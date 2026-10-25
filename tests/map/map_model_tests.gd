extends Node

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MAP MODEL: " + message)

func reset_map() -> void:
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.state.completedEventIds = ["E01", "E11", "E13", "E14", "E15", "E01R"]
	Game.state.targetId = "richard"
	Game.state.credits = 300
	Game.page = "map"
	Game.refresh_event_pool()

func target_ids() -> Array:
	return Game.map_target_events().map(func(e): return e.id)

func finish_event(id: String, choice: int = 0) -> void:
	check(Game.start_event(id), "event starts " + id)
	var guard := 0
	while Game.state.currentScene == "dialogue" and guard < 90:
		guard += 1
		if Game.node_data().has("choices"): Game.choose(choice, Game.revision)
		elif Game.node_data().has("next"): Game.advance(Game.revision)
		else: break
	if Game.state.currentScene == "battle":
		check(Game.battle_exit("win", Game.revision), "battle result " + id)
		while Game.state.currentScene == "dialogue" and guard < 90:
			guard += 1
			if Game.node_data().has("choices"): Game.choose(choice, Game.revision)
			elif Game.node_data().has("next"): Game.advance(Game.revision)
			else: break
	check(guard < 90, "event terminates " + id)
	check(id in Game.state.completedEventIds, "event complete " + id)
	if Game.state.currentScene == "result": Game.claim_rewards(Game.revision)

func _ready() -> void:
	Game.save_enabled = false
	var evidence_dir := ProjectSettings.globalize_path("res://artifacts/qa/event-refresh-2026-10-23/map-model-test-files")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	Game.save_path = evidence_dir.path_join("test-checkpoint.json")
	Game.meta_path = evidence_dir.path_join("test-meta.json")
	reset_map()
	check(Game.places.size() == 17, "16 existing places plus church")
	var catalog: Dictionary = Game.read_data("../assets/icons/map/locations.json")
	var seen: Array = []
	for p in Game.places:
		check(not p.id in seen, "unique place ID " + p.id)
		seen.append(p.id)
		check(p.mapAnchor[0] >= 0 and p.mapAnchor[0] <= 1 and p.mapAnchor[1] >= 0 and p.mapAnchor[1] <= 1, "normalized anchor " + p.id)
		var matching: Array = catalog.locations.filter(func(e): return e.id == p.id)
		check(matching.size() == 1 and ResourceLoader.exists("res://assets/icons/map/" + str(matching[0].icon)), "existing symbol " + p.id)
	check(Game.texture(Game.map_config.cityMapAssetId) != null, "city texture is configured")
	Game.state = Game.initial_state()
	for p in Game.places:
		check(Game.map_place_state(p.id).open, "place open before any event " + p.id)
		Game.visit(p.id)
		Game.skip_dialogue(Game.revision)
		check(Game.page == "place" and Game.state.currentPlaceId == p.id, "initial visit succeeds " + p.id)
	check(not Game.start_event("E12"), "retired event cannot be started from an open place")
	Game.state.currentHp = 50
	var clinic_expected := mini(int(Game.state.maxHp), 50 + roundi(Game.state.maxHp * 0.3))
	Game.state.credits = 150
	check(Game.heal_at("clinic") and Game.state.currentHp == clinic_expected and Game.state.credits == 0, "clinic service available before E01 at configured price")
	var last_place: String = Game.state.currentPlaceId
	Game.visit("unknown")
	check(Game.state.currentPlaceId == last_place, "unknown location still rejected")
	reset_map()
	check(Game.map_place_state("church").open and Game.available_events("church").is_empty(), "church is visitable without invented events")
	var church_before: Dictionary = Game.state.duplicate(true)
	Game.visit("church")
	check(Game.page == "place" and Game.state.currentPlaceId == "church", "church enters existing place route")
	for key in ["currentHp", "currentDay", "credits", "completedEventIds", "flags", "deck"]:
		check(Game.state[key] == church_before[key], "church visit preserves " + key)
	check(Game.save_game(), "church checkpoint saved to test path")
	Game.state = {}
	check(Game.load_game() and Game.state.currentPlaceId == "church" and Game.page == "place", "church checkpoint restores location")
	Game.go_map()
	check(Game.map_place_state("church").current and not Game.map_place_state("church").target, "church return updates avatar without changing objective")
	reset_map()
	check(target_ids() == ["E02", "E04"], "all initially refreshed events are targets")
	check(Game.map_place_state("bar").current, "current avatar at bar")
	check(Game.map_place_state("bar").completed, "bar completed and no new event")
	check(Game.map_place_state("hospital").open and Game.map_place_state("hospital").available.is_empty(), "laboratory remains open without task")
	check(Game.healing_service("hospital").is_empty(), "laboratory exposes no healing service")
	var laboratory_before := JSON.stringify(Game.state)
	var laboratory_revision := Game.revision
	check(not Game.heal_at("hospital"), "laboratory rejects healing")
	check(JSON.stringify(Game.state) == laboratory_before and Game.revision == laboratory_revision, "laboratory healing rejection preserves state and revision")
	check(Game.map_place_state("alley").target and Game.map_place_state("junkyard").target, "all refreshed places are targets")
	check(Game.map_place_state("junkyard").available.size() == 1, "unified event badge data")
	var previous := JSON.stringify(Game.state)
	Game.map_place_state("alley")
	Game.map_target_events()
	check(previous == JSON.stringify(Game.state), "queries do not mutate state")
	check(Game.map_place_state("unknown").is_empty(), "unknown place handled")
	Game.state.currentPlaceId = "alley"
	check(Game.map_place_state("alley").current and Game.map_place_state("alley").target, "same-place current and target coexist")
	Game.state.activeEventId = "E01"
	check(target_ids() == ["E02", "E04"], "completed stale active event not used as target")
	# Synthetic map combinations stay in memory and leave authored data unchanged.
	var tower: Dictionary = Game.place_data("tower")
	tower.unlockCondition = {"flag":"obsoletePlaceLock"}
	var fake_event := {"id":"MAP_LOCKED_TEST", "placeId":"tower", "refreshTimeRange":{"startDay":null,"endDay":null}, "unlockCondition":{}, "title":"Locked fixture"}
	Game.events[fake_event.id] = fake_event
	Game.refresh_event_pool()
	check(Game.available_events("tower").size() > 0, "fixture event-level condition passes")
	check(Game.map_place_state("tower").open and Game.map_place_state("tower").target and Game.map_place_state("tower").available.size() == 1, "obsolete place condition cannot hide available events or targets")
	check("MAP_LOCKED_TEST" in target_ids(), "target query ignores obsolete place condition")
	Game.visit("tower")
	check(Game.state.currentPlaceId == "tower", "visit ignores obsolete place condition")
	Game.events.erase(fake_event.id)
	Game.events["MAP_PARALLEL_TEST"] = {"id":"MAP_PARALLEL_TEST", "placeId":"bar", "refreshTimeRange":{"startDay":null,"endDay":null}, "unlockCondition":{}, "title":"Parallel fixture"}
	Game.refresh_event_pool()
	check(target_ids() == ["E02", "E04", "MAP_PARALLEL_TEST"], "all refreshed events in stable order")
	check(Game.objective() == "3 个可进行的事件", "objective counts all refreshed events")
	Game.events.erase("MAP_PARALLEL_TEST")
	tower.erase("unlockCondition")
	# Remaining events are independent of target and all historical clue flags.
	for contract in ["richard", "lumina", ""]:
		reset_map()
		Game.state.completedEventIds = ["E01"]
		Game.state.targetId = contract
		for id in ["E11", "E04", "E02"]:
			check(Game.events[id].unlockCondition.is_empty(), "no prerequisite " + id)
			Game.state.refreshedEventIds = [id]
			Game.refresh_event_pool()
			finish_event(id)
			check(not id in target_ids(), "completed event leaves targets " + id)
		check(Game.state.completedEventIds.size() == 4 and Game.state.currentDay == 4, "all remaining events complete without an ordered chain")
		check(Game.meets(Game.events.E01R.unlockCondition) and target_ids().size() == 3 and target_ids().all(func(id): return id in ["E01R", "E13", "E14", "E15"]), "earned return and new commissions share the three-slot pool without retired events")
		check(Game.map_place_state("camp").open and Game.map_place_state("tower").open, "locations remain open without allegiance")
	reset_map()
	for outcome in ["lose"]:
		Game.start_event("E04")
		var guard := 0
		while Game.state.currentScene == "dialogue" and guard < 40:
			if Game.node_data().has("choices"): Game.choose(1, Game.revision)
			elif Game.node_data().has("next"): Game.advance(Game.revision)
			else: break
			guard += 1
		check(Game.state.currentScene == "battle", "actual encounter reached for " + outcome)
		check(Game.battle_exit(outcome, Game.revision), "actual battle return " + outcome)
		check(not Game.choose(0, Game.revision) and Game.page == "defeat" and not Game.can_continue(), "defeat is terminal " + outcome)
		check(not "E04" in Game.state.completedEventIds and target_ids() == ["E02", "E04"], "unfinished events retained on " + outcome)
		reset_map()
	Game.state.currentHp = roundi(Game.state.maxHp * 0.5)
	var healed_expected := mini(int(Game.state.maxHp), int(Game.state.currentHp) + roundi(Game.state.maxHp * 0.3))
	var current: String = Game.state.currentPlaceId
	var day: int = Game.state.currentDay
	Game.state.credits = 300
	check(Game.heal_at("clinic") and Game.state.currentHp == healed_expected and Game.state.credits == 150, "clinic heals 30 percent of configured maximum for 150 credits")
	check(Game.state.currentPlaceId == current and Game.state.currentDay == day, "healing preserves place and day")
	check(Game.heal_at("clinic") and Game.state.currentHp == Game.state.maxHp and Game.state.credits == 0, "clinic healing clamps HP and charges once per treatment")
	var expected: Dictionary = Game.state.duplicate(true)
	check(Game.save_game(), "test-path checkpoint written")
	Game.state = {}
	check(Game.load_game(), "test-path checkpoint restored")
	check(Game.state.get("currentPlaceId", "") == expected.currentPlaceId and target_ids() == ["E02", "E04"], "restored place and refreshed targets derived correctly")
	check(Game.state.get("schemaVersion", 0) == 2, "save schema retained")
	for p in Game.places:
		check(Game.map_place_state(p.id).open, "restored save keeps place open " + p.id)
	print("MAP MODEL: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
