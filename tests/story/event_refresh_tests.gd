extends Node

var checks := 0
var failures := 0
var authored_events: Dictionary
var qa_dir := "res://artifacts/qa/event-refresh-2026-10-23"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("EVENT REFRESH: " + message)

func ids(values: Array) -> Array:
	return values.map(func(e): return str(e.id))

func reset_authored() -> void:
	Game.events = authored_events.duplicate(true)
	Game.state = Game.initial_state()
	Game.page = Game.state.currentScene

func fixture_state() -> void:
	reset_authored()
	Game.state.currentScene = "map"
	Game.page = "map"
	Game.state.completedEventIds = Game.events.keys()
	Game.state.refreshedEventIds = []
	for index in range(6):
		var id := "REFRESH_%02d" % index
		var event: Dictionary = authored_events.E01.duplicate(true)
		event.id = id
		event.placeId = "bar" if index % 2 == 0 else "pump"
		event.unlockCondition = {"flag":"fixtureGate"}
		event.refreshTimeRange = {"startDay":null, "endDay":null}
		Game.events[id] = event
	Game.state.flags = {"fixtureGate":true}
	Game.refresh_event_pool()

func step_to_stop() -> void:
	var guard := 0
	while Game.state.currentScene == "dialogue" and Game.node_data().has("next") and guard < 80:
		Game.advance(Game.revision)
		guard += 1
	check(guard < 80, "dialogue terminates")

func start_contract() -> void:
	reset_authored()
	Game.new_game()
	step_to_stop()
	check(Game.choose(0, Game.revision), "E01 contract chosen")
	step_to_stop()
	check("E01" in Game.state.completedEventIds and Game.state.currentDay == 1, "E01 first completion keeps day one")
	Game.claim_rewards(Game.revision)
	Game.state.refreshedEventIds = ["E02", "E04"]
	Game.refresh_event_pool()

func test_opening_date() -> void:
	for choice in [0, 1, 2]:
		for skip in [false, true]:
			reset_authored()
			Game.new_game()
			if skip: Game.skip_dialogue(Game.revision)
			else: step_to_stop()
			check(Game.state.activeNodeId == "contract" and Game.state.currentDay == 1, "opening reaches choice on day one")
			check(Game.choose(choice, Game.revision), "opening support choice accepted")
			if skip: Game.skip_dialogue(Game.revision)
			else: step_to_stop()
			check(Game.state.currentScene == "result" and Game.state.completedEventIds == ["E01"] and Game.state.currentDay == 1, "all opening branches finish without spending time, skip=" + str(skip))
			check(Game.state.targetId.is_empty() and Game.state.flags.get("openingSupportChipId") == ["money_chip", "healing_chip", "swift_chip"][choice], "opening records selected support without selecting a target")
			check(Game.claim_rewards(Game.revision) and Game.state.currentScene == "map" and Game.state.currentDay == 1, "opening returns to map on day one")
			check(not "E01" in Game.state.refreshedEventIds, "completed opening leaves the event pool")
			check(Game.save_game(), "day one opening checkpoint saves")
			Game.state = {}
			check(Game.load_game() and Game.state.currentDay == 1 and "E01" in Game.state.completedEventIds, "completed opening reloads on day one")

func all_text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button or node is RichTextLabel:
		result += str(node.text) + "\n"
	for child in node.get_children(): result += all_text(child)
	return result

func test_pool() -> void:
	fixture_state()
	check(Game.eligible_events().size() == 6, "all six eligible candidates remain discoverable")
	check(ids(Game.eligible_events()) == ["REFRESH_00", "REFRESH_01", "REFRESH_02", "REFRESH_03", "REFRESH_04", "REFRESH_05"], "eligible candidates use stable ID order")
	check(Game.state.refreshedEventIds.size() == 3 and Game.available_events().size() == 3, "global pool caps six eligible candidates at three")
	var union: Array = []
	for place in Game.places: union.append_array(ids(Game.available_events(place.id)))
	union.sort()
	check(union == ids(Game.available_events()), "place queries partition the same global pool")
	check(ids(Game.map_target_events()) == ids(Game.available_events()), "map targets include every refreshed event")
	check(not Game.map_place_state("bar").has("main_events") and not Game.map_place_state("bar").has("optional_events"), "map state has no removed event categories")
	var before := JSON.stringify(Game.state)
	for index in range(4):
		Game.available_events(); Game.available_events("bar"); Game.map_target_events(); Game.map_place_state("pump"); Game.objective(); Game.eligible_events()
	check(before == JSON.stringify(Game.state), "repeated availability and map queries are read only")
	check(Game.objective() == "3 个可进行的事件", "objective uses unified event count")
	var hidden := ""
	for event in Game.eligible_events():
		if not event.id in Game.state.refreshedEventIds: hidden = event.id; break
	check(not hidden.is_empty() and not Game.start_event(hidden), "eligible but unrefreshed event cannot bypass pool")
	check(before == JSON.stringify(Game.state), "rejected hidden event leaves state unchanged")
	var retained: Array = Game.state.refreshedEventIds.duplicate()
	for index in range(8): Game.refresh_event_pool()
	check(Game.state.refreshedEventIds == retained, "refresh preserves all still eligible entries without reroll")
	var saved_pool: Array = Game.state.refreshedEventIds.duplicate()
	check(Game.save_game(), "six-candidate random pool checkpoint saves")
	Game.state = {}
	check(Game.load_game() and Game.state.refreshedEventIds == saved_pool, "random subset survives roundtrip without reroll")
	var removed: String = retained.pop_front()
	check(Game.apply_actions([{"op":"completeEvent", "id":removed}]), "pooled fixture completion commits")
	Game.checkpoint()
	check(Game.state.refreshedEventIds.size() == 3 and not removed in Game.state.refreshedEventIds, "checkpoint fills vacancy after completion")
	for id in retained: check(id in Game.state.refreshedEventIds, "completion preserves remaining pooled event " + id)
	Game.state.flags.fixtureGate = false
	Game.refresh_event_pool()
	check(Game.state.refreshedEventIds.is_empty(), "events leaving prerequisites are removed")
	Game.state.flags.fixtureGate = true
	Game.checkpoint()
	check(Game.state.refreshedEventIds.size() == 3, "checkpoint fills newly eligible entries")
	var subject := Game.state.duplicate(true)
	subject.currentDay = 9
	var global_before := JSON.stringify(Game.state)
	Game.refresh_event_pool(subject)
	check(subject.refreshedEventIds.size() == 3 and JSON.stringify(Game.state) == global_before, "explicit subject refresh does not modify live adventure")

func test_ranges() -> void:
	fixture_state()
	var sample: Dictionary = Game.events.REFRESH_00
	check(Game.event_refresh_time_label(sample) == "随时", "open range is displayed as anytime")
	for day in [1, 7, 8, 999]:
		var subject := Game.state.duplicate(true)
		subject.currentDay = day
		check(Game.event_in_refresh_range(sample, subject), "open range includes day %d" % day)
	sample.refreshTimeRange = {"startDay":3, "endDay":5}
	check(Game.event_refresh_time_label(sample) == "第3—5天", "closed range is displayed with both boundaries")
	for day in [2, 3, 5, 6]:
		var subject := Game.state.duplicate(true)
		subject.currentDay = day
		check(Game.event_in_refresh_range(sample, subject) == (day >= 3 and day <= 5), "closed range boundary day %d" % day)
	sample.refreshTimeRange = {"startDay":3, "endDay":null}
	check(not Game.event_in_refresh_range(sample, {"currentDay":2}) and Game.event_in_refresh_range(sample, {"currentDay":99}), "open end preserves start boundary")
	sample.refreshTimeRange = {"startDay":null, "endDay":5}
	check(Game.event_in_refresh_range(sample, {"currentDay":1}) and not Game.event_in_refresh_range(sample, {"currentDay":6}), "open start preserves end boundary")
	for invalid in [{"startDay":0,"endDay":5}, {"startDay":-1,"endDay":5}, {"startDay":"3","endDay":5}, {"startDay":3.5,"endDay":5}, {"startDay":6,"endDay":3}]:
		sample.refreshTimeRange = invalid
		check(not Game.event_in_refresh_range(sample, {"currentDay":4}), "invalid range rejected " + JSON.stringify(invalid))
		Game.refresh_event_pool()
		check(not "REFRESH_00" in ids(Game.eligible_events()) and not "REFRESH_00" in Game.state.refreshedEventIds, "invalid range never enters candidates or refreshed pool")
	# Expiring a refreshed event must immediately hide it, even before next checkpoint.
	var expiring: String = Game.state.refreshedEventIds[0]
	Game.events[expiring].refreshTimeRange = {"startDay":1, "endDay":1}
	Game.state.currentDay = 2
	check(not expiring in ids(Game.available_events()) and not Game.start_event(expiring), "expired event is hidden and cannot start")
	Game.checkpoint()
	check(Game.state.refreshedEventIds.size() == 3 and not expiring in Game.state.refreshedEventIds, "expired pool entry is replaced at checkpoint")

func test_days_and_failures() -> void:
	start_contract()
	var before := int(Game.state.currentDay)
	check(Game.apply_actions([{"op":"completeEvent", "id":"E01"}, {"op":"completeEvent", "id":"E01"}]), "repeated completion is accepted idempotently")
	check(Game.state.currentDay == before, "duplicate completion does not spend another day")
	check(not Game.apply_actions([{"op":"completeEvent", "id":"E02"}, {"op":"spendCredits", "amount":999999}]), "rejected completion batch stays atomic")
	check(Game.state.currentDay == before and not "E02" in Game.state.completedEventIds, "rejected batch consumes no date or completion")
	preload("res://tests/fixtures/payment_choice.gd").install(Game)
	Game.state.refreshedEventIds = ["QA_PAYMENT"]
	check(Game.start_event("QA_PAYMENT"), "payment fixture available after E01")
	step_to_stop()
	var rev := Game.revision
	check(not Game.choose(0, rev) and Game.state.currentDay == before, "failed payment spends no time")
	Game.state.credits = 300
	check(Game.choose(0, rev), "paid fixture route commits")
	step_to_stop()
	check(Game.state.currentDay == before + 1 and "QA_PAYMENT" in Game.state.completedEventIds, "paid fixture completion spends one day")
	Game.claim_rewards(Game.revision)
	check(Game.state.currentDay == before + 1, "noncombat reward exit does not add date")
	preload("res://tests/fixtures/payment_choice.gd").uninstall(Game)
	start_contract()
	before = int(Game.state.currentDay)
	check(Game.start_event("E02"), "start real battle event")
	step_to_stop()
	check(Game.state.currentScene == "battle" and Game.state.currentDay == before, "starting battle consumes no date")
	check(Game.battle_exit("lose", Game.revision), "battle defeat returns")
	check(not Game.choose(0, Game.revision) and Game.page == "defeat", "defeat cannot choose the old map exit")
	check(Game.state.currentDay == before and not "E02" in Game.state.completedEventIds, "defeat spends no time and does not complete the event")
	check(not Game.start_event("E02"), "defeated adventure cannot retry an event")
	start_contract()
	before = int(Game.state.currentDay)
	check(Game.start_event("E02"), "new adventure can start the battle event")
	step_to_stop()
	check(Game.battle_exit("win", Game.revision), "battle victory returns")
	check(Game.state.currentDay == before, "victory before finish does not spend time")
	step_to_stop()
	check(Game.state.currentDay == before + 1 and "E02" in Game.state.completedEventIds, "battle event spends one day at finish")
	if Game.state.battleReward.get("status", "") == "pending":
		var option: String = Game.state.battleReward.options[0]
		check(Game.choose_reward_card(option, Game.revision), "reward choice succeeds")
		check(Game.state.currentDay == before + 1, "reward choice consumes no time")
	Game.claim_rewards(Game.revision)
	Game.visit("hospital")
	Game.state.currentHp = 50
	check(Game.heal_at("hospital"), "healing succeeds")
	check(Game.state.currentDay == before + 1, "movement and healing consume no time")
	check(Game.apply_actions([{"op":"advanceDay", "days":20}]), "explicit day advancement succeeds")
	check(Game.state.currentDay == 7 and Game.state.currentWeek == 1, "explicit advancement caps at seven without switching weeks")
	check(Game.valid_save(Game.state), "day seven adventure remains valid")
	check(Game.apply_actions([{"op":"completeEvent", "id":"E11"}]) and Game.state.currentDay == 7, "new completion at day seven stays capped")
	for invalid_day in [0, 8, 8.5]:
		var invalid := Game.state.duplicate(true)
		invalid.currentDay = invalid_day
		check(not Game.valid_save(invalid), "out of range date rejected: " + str(invalid_day))
	var fractional := Game.state.duplicate(true)
	fractional.currentDay = 6.5
	check(not Game.valid_save(fractional), "fractional dates remain invalid")
	var adventure := Game.state.duplicate(true)
	Game.start_training("B02")
	Game.finish_training("win")
	check(not Game.training_mode and Game.state == adventure, "training victory restores exact date and refreshed pool")
	Game.start_training("B02")
	Game.finish_training("lose")
	check(not Game.training_mode and Game.state == adventure, "training defeat restores exact date and refreshed pool")

func test_save() -> void:
	reset_authored()
	check(Game.eligible_events().size() == 7 and Game.state.refreshedEventIds.size() == 3, "new adventure has seven ungated candidates and three refreshed events")
	for event in Game.events.values():
		check(not event.has("optional") and event.get("refreshTimeRange") == {"startDay":null,"endDay":null}, "authored event uses anytime range and no category " + event.id)
	Game.state.currentDay = 7
	Game.state.completedEventIds = ["E01", "E02"]
	Game.state.targetId = "richard"
	Game.state.currentScene = "map"
	Game.refresh_event_pool()
	for bad_pool in ["E04", ["E04", "E04"], ["E01", "E02", "E04", "E11"], ["UNKNOWN_REFRESH_ID"]]:
		var invalid := Game.state.duplicate(true)
		invalid.refreshedEventIds = bad_pool
		check(not Game.valid_save(invalid), "invalid persisted pool rejected " + str(bad_pool))
	var pool: Array = Game.state.refreshedEventIds.duplicate()
	check(Game.save_game(), "test checkpoint saves date and pool")
	Game.state = {}
	check(Game.load_game() and Game.state.currentDay == 7 and Game.state.currentWeek == 1, "day seven survives disk roundtrip")
	check(Game.state.refreshedEventIds == pool, "disk roundtrip preserves refreshed pool without reroll")
	var legacy := Game.state.duplicate(true)
	legacy.erase("refreshedEventIds")
	legacy.currentDay = 4
	var migrated = Game.migrate_save(legacy)
	check(Game.valid_save(migrated) and migrated.currentDay == 4, "old schema two fills fields without replaying completed event dates")
	check(migrated.refreshedEventIds.size() == 3 and migrated.refreshedEventIds.all(func(id): return id in ["E04", "E11", "E13", "E14", "E15"]) and not legacy.has("refreshedEventIds"), "legacy pool initialized without modifying source")
	var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy)); file.close()
	check(Game.load_game() and Game.state.currentDay == 4 and Game.state.refreshedEventIds.size() == 3 and Game.state.refreshedEventIds.all(func(id): return id in ["E04", "E11", "E13", "E14", "E15"]), "old schema two migrates on actual load")

func test_ui() -> void:
	start_contract()
	Game.state.currentDay = 7
	Game.state.currentPlaceId = "junkyard"
	Game.state.currentScene = "place"
	var view: Node = load("res://scenes/place.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var text := all_text(view)
	check("刷新时间" in text and "随时" in text, "place view shows event refresh time")
	check("完成委托推进1天" in text and "开幕与领奖不耗时" in text, "place HUD distinguishes commission time from opening and return reward")
	check(not "主线" in text and not "可选事件" in text and not "支线" in text, "place view uses unified event terminology")
	check("第 7 天" in text, "date label displays day seven")
	check(view.find_child("day_segment_7", true, false) != null and view.find_child("day_segment_8", true, false) == null, "date HUD has exactly seven segments")
	view.queue_free()
	await get_tree().process_frame
	Game.state.currentScene = "map"
	Game.page = "map"
	var map_view: Node = load("res://scenes/map.tscn").instantiate()
	add_child(map_view)
	await get_tree().process_frame
	check("第 7 天" in all_text(map_view), "map HUD displays day seven")
	map_view.call("select_place", "junkyard")
	await get_tree().process_frame
	var map_text := all_text(map_view)
	check("刷新时间：随时" in map_text, "real map detail displays refresh time")
	check(not "主线" in map_text and not "可选事件" in map_text and not "支线" in map_text, "real map detail uses unified event terminology")
	map_view.queue_free()
	await get_tree().process_frame
	Game.state.flags.week1Complete = true
	check(Game.objective() == "第一周已完成 · 可继续探索剩余事件", "week completion objective has unified terminology")
	check(not Game.map_target_events().is_empty(), "week completion keeps remaining refreshed targets visible")

func _ready() -> void:
	Game.save_enabled = false
	var directory := ProjectSettings.globalize_path(qa_dir.path_join("test-files"))
	DirAccess.make_dir_recursive_absolute(directory)
	Game.save_path = directory.path_join("checkpoint-test.json")
	Game.meta_path = directory.path_join("meta-test.json")
	authored_events = Game.events.duplicate(true)
	test_pool()
	test_ranges()
	test_opening_date()
	test_days_and_failures()
	test_save()
	await test_ui()
	Game.events = authored_events
	print("EVENT REFRESH: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
