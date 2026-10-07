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
	Game.state.completedEventIds = ["E01"]
	Game.state.targetId = "richard"
	Game.state.credits = 300
	Game.page = "map"

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
	var evidence_dir := ProjectSettings.globalize_path("res://artifacts/qa/map-build-2026-10-07/model-test-files")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	Game.save_path = evidence_dir.path_join("test-checkpoint.json")
	Game.meta_path = evidence_dir.path_join("test-meta.json")
	reset_map()
	check(Game.places.size() == 16, "all 16 existing places retained")
	var catalog: Dictionary = Game.read_data("../assets/icons/map/locations.json")
	var seen: Array = []
	for p in Game.places:
		check(not p.id in seen, "unique place ID " + p.id)
		seen.append(p.id)
		check(p.mapAnchor[0] >= 0 and p.mapAnchor[0] <= 1 and p.mapAnchor[1] >= 0 and p.mapAnchor[1] <= 1, "normalized anchor " + p.id)
		var matching: Array = catalog.locations.filter(func(e): return e.id == p.id)
		check(matching.size() == 1 and ResourceLoader.exists("res://assets/icons/map/" + str(matching[0].icon)), "existing symbol " + p.id)
	check(Game.texture(Game.map_config.cityMapAssetId) != null, "city texture is configured")
	check(target_ids() == ["E03"], "initial target is hive")
	check(Game.map_place_state("bar").current, "current avatar at bar")
	check(Game.map_place_state("bar").completed, "bar completed and no new event")
	check(Game.map_place_state("hospital").open and Game.map_place_state("hospital").available.is_empty(), "open service place without task")
	check(Game.map_place_state("hive").target and not Game.map_place_state("junkyard").target, "optional does not become main target")
	check(Game.map_place_state("junkyard").optional_events.size() == 1, "optional badge data")
	var previous := JSON.stringify(Game.state)
	Game.map_place_state("hive")
	Game.map_target_events()
	check(previous == JSON.stringify(Game.state), "queries do not mutate state")
	check(Game.map_place_state("unknown").is_empty(), "unknown place handled")
	Game.state.currentPlaceId = "hive"
	check(Game.map_place_state("hive").current and Game.map_place_state("hive").target, "same-place current and target coexist")
	Game.state.activeEventId = "E01"
	check(target_ids() == ["E03"], "completed stale active event not used as target")
	# Synthetic map combinations stay in memory and leave authored data unchanged.
	var tower: Dictionary = Game.place_data("tower")
	var old_condition: Dictionary = tower.unlockCondition.duplicate(true)
	var fake_event := {"id":"MAP_LOCKED_TEST", "placeId":"tower", "optional":false, "unlockCondition":{}, "title":"Locked fixture"}
	Game.events[fake_event.id] = fake_event
	check(Game.available_events("tower").size() > 0, "fixture event-level condition passes")
	check(not Game.map_place_state("tower").open and not Game.map_place_state("tower").target and Game.map_place_state("tower").available.is_empty(), "locked place excludes available events and targets")
	Game.events.erase(fake_event.id)
	Game.events["MAP_PARALLEL_TEST"] = {"id":"MAP_PARALLEL_TEST", "placeId":"bar", "optional":false, "unlockCondition":{}, "title":"Parallel fixture"}
	check(target_ids() == ["E03", "MAP_PARALLEL_TEST"], "all simultaneous main candidates in stable order")
	check(Game.objective() == "2 个可推进的主线目标", "multiple candidates not arbitrarily reduced")
	Game.events.erase("MAP_PARALLEL_TEST")
	check(tower.unlockCondition == old_condition, "authored unlock conditions retained")
	# Actual first-week routes, including both faction branches.
	for contract in ["richard", "lumina"]:
		reset_map()
		Game.state.targetId = contract
		finish_event("E03")
		check(target_ids() == ["E04"], "alley target after hive " + contract)
		finish_event("E04")
		check(target_ids() == ["E05A" if contract == "richard" else "E05B"], "correct port branch " + contract)
		finish_event("E05A" if contract == "richard" else "E05B")
		check(target_ids() == ["E06" if contract == "richard" else "E07"], "correct faction entry " + contract)
		finish_event("E06" if contract == "richard" else "E07")
		check(target_ids() == ["E09" if contract == "richard" else "E10"], "correct power branch " + contract)
		finish_event("E09" if contract == "richard" else "E10")
		check(target_ids() == ["E12"], "hive finale " + contract)
		finish_event("E12")
		check(target_ids().is_empty(), "no false next-week target " + contract)
		check(Game.map_place_state("pump").optional_events.size() == 1, "optional remains after week completion " + contract)
	reset_map()
	for outcome in ["lose", "surrender"]:
		Game.start_event("E03")
		var guard := 0
		while Game.state.currentScene == "dialogue" and guard < 40:
			if Game.node_data().has("choices"): Game.choose(1, Game.revision)
			elif Game.node_data().has("next"): Game.advance(Game.revision)
			else: break
			guard += 1
		check(Game.state.currentScene == "battle", "actual encounter reached for " + outcome)
		check(Game.battle_exit(outcome, Game.revision), "actual battle return " + outcome)
		check(Game.choose(0, Game.revision) and Game.page == "map", "return choice reaches map " + outcome)
		check(not "E03" in Game.state.completedEventIds and target_ids() == ["E03"], "unfinished target retained on " + outcome)
		reset_map()
	Game.state.currentHp = 50
	var current: String = Game.state.currentPlaceId
	var day: int = Game.state.currentDay
	check(Game.heal_at("hospital") and Game.state.currentHp == 80, "existing healing 30 percent")
	check(Game.state.currentPlaceId == current and Game.state.currentDay == day, "healing preserves place and day")
	check(Game.heal_at("hospital") and Game.state.currentHp == 100, "healing clamps HP")
	var expected: Dictionary = Game.state.duplicate(true)
	check(Game.save_game(), "test-path checkpoint written")
	Game.state = {}
	check(Game.load_game(), "test-path checkpoint restored")
	check(Game.state.get("currentPlaceId", "") == expected.currentPlaceId and target_ids() == ["E03"], "restored place and target derived correctly")
	check(Game.state.get("schemaVersion", 0) == 2, "save schema retained")
	print("MAP MODEL: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
