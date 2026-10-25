extends Node
## Headless scene checks; use a copied project and independent test user directory.
const OUT := "res://artifacts/qa/task-entry-2026-10-25/"
var checks := 0
var failures: Array[String] = []

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		push_error("TASK ENTRY: " + detail)

func fresh(ids: Array = ["E02", "E04", "E11"]) -> void:
	Game.save_enabled = false
	Game.save_path = OUT + "checkpoint.json"
	Game.meta_path = OUT + "meta.json"
	Game.pending_save_kind = ""
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.state.completedEventIds = ["E01"]
	Game.state.refreshedEventIds = ids.duplicate()
	Game.page = "map"

func make_view(scene: String) -> Control:
	var view: Control = load("res://scenes/" + scene + ".tscn").instantiate()
	add_child(view)
	view.set_process(false)
	return view

func discard(view: Node) -> void:
	remove_child(view)
	view.queue_free()
	await get_tree().process_frame

func all_labels(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	if node is Label: found.append(node)
	for child in node.get_children(): found.append_array(all_labels(child))
	return found

func test_map_entries() -> void:
	fresh()
	var view := make_view("map")
	for place in Game.places:
		view.select_place(place.id)
		var resident: bool = place.get("mapDisplay", {}).get("resident", false)
		var available := Game.available_events(place.id)
		var enter: Button = view.get_detail_button("enter_place")
		check((enter != null) == (resident or not available.is_empty()), place.id + " entry only for resident or available task")
		check(view.get_detail_button("heal_place") == null, place.id + " map has no service shortcut")
		for event in available:
			check(view.get_detail_button("event_" + event.id) == null, place.id + " map cannot start event directly")
			var leaked := false
			for text in all_labels(view.detail):
				if text.text.contains(event.description): leaked = true
			check(not leaked, place.id + " task description appears after entry only")
		if enter != null and not resident:
			check(enter.text.contains("进入地点"), place.id + " single entry label")
	view.select_place("junkyard")
	var before := Game.state.duplicate(true)
	view.get_detail_button("enter_place").pressed.emit()
	check(Game.page == "place" and Game.state.currentPlaceId == "junkyard", "map entry opens place briefing")
	for field in ["activeEventId", "activeNodeId", "currentDay", "credits", "completedEventIds"]:
		check(Game.state[field] == before[field], "entry preserves " + field)
	await discard(view)

func test_briefing(event_id: String) -> void:
	fresh([event_id])
	var event: Dictionary = Game.events[event_id]
	Game.visit(event.placeId)
	var before := Game.state.duplicate(true)
	var view := make_view("place")
	var info: Label = view.find_child("task_info_" + event_id, true, false)
	var start: Button = view.find_child("event_" + event_id, true, false)
	check(info != null and start != null, event_id + " has briefing and start action")
	if info == null or start == null:
		await discard(view)
		return
	check(info.text.contains(event.title) and info.text.contains(event.description), event_id + " shows authored title and description")
	check(not info.text.contains("刷新时间"), event_id + " task description omits refresh time")
	check(info.visible_characters == 0 and start.disabled, event_id + " begins typing with action disabled")
	check(start.text.contains("开始任务"), event_id + " start task wording")
	var before_disabled_click := Game.state.duplicate(true)
	start.pressed.emit()
	check(Game.state == before_disabled_click, event_id + " rejects start while typing")
	view._process(0.05)
	check(info.visible_characters > 0 and info.visible_characters < info.text.length(), event_id + " partial typewriter progress")
	check(start.disabled and Game.state == before, event_id + " typing does not start or mutate task")
	view._process(10.0)
	check(info.visible_characters == -1 or info.visible_characters >= info.get_total_character_count(), event_id + " reveals full information")
	check(not start.disabled and Game.state == before, event_id + " enables start without automatically accepting")
	await get_tree().process_frame
	await get_tree().process_frame
	check(info.size.y > 60 and start.size.y >= 60, event_id + " briefing and button reserve usable height")
	check(not info.get_global_rect().intersects(start.get_global_rect()), event_id + " information does not overlap start button")
	var return_button: Button = view.find_child("return_map", true, false)
	check(return_button != null, event_id + " briefing can return to map")
	if return_button != null:
		return_button.pressed.emit()
		check(Game.page == "map" and Game.state.activeEventId == before.activeEventId, event_id + " leaving briefing never starts event")
	await discard(view)
	Game.visit(event.placeId)
	view = make_view("place")
	view._process(10.0)
	start = view.find_child("event_" + event_id, true, false)
	start.pressed.emit()
	check(Game.state.activeEventId == event_id and Game.page == "dialogue", event_id + " start opens authored dialogue")
	check(Game.state.activeNodeId == event.startNodeId, event_id + " starts at authored first node")
	var accepted := Game.state.duplicate(true)
	var accepted_revision := Game.revision
	start.pressed.emit()
	check(Game.state == accepted and Game.revision == accepted_revision, event_id + " repeated start does not restart event")
	await discard(view)

func test_multiple_tasks() -> void:
	fresh(["E02", "E11"])
	var old_place: String = Game.events.E11.placeId
	Game.events.E11.placeId = Game.events.E02.placeId
	Game.visit(Game.events.E02.placeId)
	var view := make_view("place")
	for id in ["E02", "E11"]:
		check(view.find_child("task_info_" + id, true, false) != null, id + " co-located task is listed")
		check(view.find_child("event_" + id, true, false) != null, id + " co-located task has own action")
	view._process(10.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var first: Button = view.find_child("event_E02", true, false)
	var second: Button = view.find_child("event_E11", true, false)
	if first != null and second != null:
		check(not first.get_global_rect().intersects(second.get_global_rect()), "multiple task buttons do not overlap")
		var scroll: ScrollContainer = view.find_child("task_scroll", true, false)
		check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y, "multiple tasks retain vertical scroll access")
	if second != null: second.pressed.emit()
	check(Game.state.activeEventId == "E11", "second task action routes to its own event")
	Game.events.E11.placeId = old_place
	await discard(view)

func test_stale_and_locked_start() -> void:
	fresh(["E02"])
	Game.visit("junkyard")
	var view := make_view("place")
	view._process(10.0)
	var start: Button = view.find_child("event_E02", true, false)
	var before := Game.state.duplicate(true)
	Game.transition_locked = true
	start.pressed.emit()
	check(Game.state == before and not start.disabled, "transition rejection restores ready start button")
	Game.transition_locked = false
	Game.revision += 1
	start.pressed.emit()
	check(Game.state == before, "stale briefing revision cannot start task")
	await discard(view)
	fresh(["E02"])
	Game.visit("junkyard")
	view = make_view("place")
	view._process(10.0)
	start = view.find_child("event_E02", true, false)
	Game.go_map()
	before = Game.state.duplicate(true)
	start.pressed.emit()
	check(Game.state == before, "old briefing action cannot start after leaving page")
	await discard(view)

func test_services_and_resume() -> void:
	fresh()
	Game.state.currentHp = 20
	Game.state.credits = 150
	Game.visit("clinic")
	var view := make_view("place")
	check(view.find_child("task_info_*", true, false) == null, "clinic bypasses task briefing")
	var heal: Button = view.find_child("heal_place", true, false)
	check(heal != null and not heal.disabled, "clinic opens treatment directly")
	if heal != null: heal.pressed.emit()
	check(Game.state.currentHp == 41 and Game.state.credits == 0, "clinic retains paid 30 percent healing")
	await discard(view)
	for place_id in ["market", "mall"]:
		fresh()
		var map_view := make_view("map")
		map_view.select_place(place_id)
		map_view.get_detail_button("enter_place").pressed.emit()
		check(Game.page == "dialogue" and Game.state.get("placeDialogue", {}).get("placeId") == place_id, place_id + " preserves first-visit dialogue")
		await discard(map_view)
		Game.skip_dialogue(Game.revision)
		check(Game.page == "place", place_id + " introductory dialogue leads to service")
		Game.go_map()
		Game.visit(place_id)
		check(Game.page == "place" and not Game.state.has("placeDialogue"), place_id + " repeat visit enters service directly")
	fresh(["E02"])
	Game.visit("junkyard")
	check(Game.save_game(), "briefing checkpoint saves to isolated path")
	Game.state = {}
	check(Game.load_game() and Game.page == "place", "briefing checkpoint restores place")
	view = make_view("place")
	check(view.find_child("task_info_E02", true, false) != null, "restored place still shows available task")
	check(Game.state.activeEventId == "E01", "restoring briefing does not accept task")
	await discard(view)

func _ready() -> void:
	if not "test" in str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).to_lower():
		push_error("Run task entry tests only in an isolated project with a test user directory")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await test_map_entries()
	for id in ["E02", "E04", "E11", "E13", "E14", "E15"]:
		await test_briefing(id)
	await test_multiple_tasks()
	await test_stale_and_locked_start()
	await test_services_and_resume()
	var report := {"checks":checks, "failures":failures, "scope":"headless UI nodes and signals; no GPU pixels or physical input"}
	var file := FileAccess.open(OUT + "result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TASK ENTRY: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
