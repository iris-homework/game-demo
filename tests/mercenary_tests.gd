extends Node

const OUTPUT := "res://artifacts/qa/free-mercenary-2026-10-15/"
const BEFORE := OUTPUT + "before/data/"
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MERCENARY: " + message)

func read_fixture(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(BEFORE + path))

func check_condition(condition: Dictionary) -> void:
	for key in condition:
		check(key != "faction", "No live allegiance condition")
		if key in ["all", "any"]:
			for child in condition[key]: check_condition(child)
		elif key == "completed": check(Game.events.has(condition[key]), "Completion dependency exists")

func advance_to_result() -> void:
	var guard := 0
	while Game.state.currentScene == "dialogue" and Game.node_data().has("next") and guard < 80:
		Game.advance(Game.revision)
		guard += 1
	check(guard < 80 and Game.state.currentScene == "result", "Migrated port dialogue reaches settlement")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = OUTPUT + "migration-checkpoint.json"
	Game.meta_path = OUTPUT + "migration-meta.json"
	check(not Game.initial_state().has("faction"), "New game has no allegiance")
	check(Game.read_data("weeks/week1/week.json").eventIds == Game.events.keys(), "Week index matches active events")
	for p in Game.places: check_condition(p.unlockCondition)
	for e in Game.events.values():
		check_condition(e.unlockCondition)
		check(not e.nodes.has("join"), "No recruitment choice")
		for n in e.nodes.values():
			for a in n.get("effects", []): check(a.op != "setFaction", "No allegiance action")
	for id in ["E06", "E07", "E09", "E10"]: check(not Game.events.has(id), "Retired event removed")
	for id in ["B09", "B10"]: check(not Game.battles.has(id), "Retired encounter removed")
	var current_events := Game.events
	var current_battles := Game.battles
	var current_enemies := Game.enemy_catalog
	var legacy_events: Dictionary = read_fixture("weeks/week1/events.json")
	var legacy_battles: Dictionary = read_fixture("battles.json")
	var legacy_enemies: Dictionary = read_fixture("enemies/enemies.json")
	# Exercise every authored checkpoint in the changed/removed stories, including combat.
	for event_id in ["E05A", "E05B", "E06", "E07", "E09", "E10"]:
		for node_id in legacy_events[event_id].nodes:
			var node: Dictionary = legacy_events[event_id].nodes[node_id]
			Game.state = Game.initial_state()
			Game.state.faction = "company" if event_id in ["E05A", "E06", "E09"] else "resistance"
			Game.state.targetId = "richard" if Game.state.faction == "company" else "lumina"
			Game.state.activeEventId = event_id
			Game.state.activeNodeId = node_id
			Game.state.currentPlaceId = legacy_events[event_id].placeId
			Game.state.currentScene = "dialogue"
			Game.state.completedEventIds = ["E01", "E03", "E04"]
			Game.state.flags = {"alleyClue":true, "portClue":true}
			Game.state.credits = 4321
			Game.state.currentHp = 61
			Game.state.currentDay = 4
			Game.state.deck = ["test_reward_01"]
			Game.state.choiceHistory = {"E01:contract":Game.state.targetId, "E05A:join":"accept", "E05B:join":"refuse"}
			Game.state.portraits = {"left":"@player", "right":"fitz"}
			if node.get("type", "") == "battle":
				Game.events = legacy_events
				Game.battles = legacy_battles
				Game.enemy_catalog = legacy_enemies
				Game.enter_node(node_id)
				Game.events = current_events
				Game.battles = current_battles
				Game.enemy_catalog = current_enemies
			elif node.get("type", "") == "finish":
				Game.state.currentScene = "result"
				Game.state.completedEventIds.append(event_id)
			var legacy := Game.state.duplicate(true)
			var migrated: Dictionary = Game.migrate_save(legacy)
			var label: String = event_id + ":" + node_id
			check(Game.valid_save(migrated), "Valid migration " + label)
			check(legacy.has("faction") and not migrated.has("faction"), "Migration does not mutate source " + label)
			check(Game.migrate_save(migrated) == migrated, "Migration is idempotent " + label)
			for key in ["currentHp", "maxHp", "currentDay", "credits", "deck", "claimedRewardIds", "flags", "playerCharacterId"]:
				check(migrated[key] == legacy[key], "Preserves " + key + " " + label)
			Game.state = migrated
			check(Game.save_game() and Game.load_game(), "Disk roundtrip " + label)
			if event_id in ["E06", "E07", "E09", "E10"]:
				check(Game.page == "map" and Game.state.currentPlaceId == "port", "Retired checkpoint returns to port " + label)
				check(Game.map_target_events().map(func(e): return e.id) == ["E12"], "Finale reachable after migration " + label)
			elif Game.state.currentScene == "dialogue" and node_id != "intro_01" and (node_id.begins_with("win_") or node_id.begins_with("accept_") or node_id.begins_with("refuse_") or node_id == "join"):
				advance_to_result()
	# Old selected and pending rewards on retired encounters never duplicate credits/cards.
	for bid in ["B09", "B10"]:
		for reward_status in ["pending", "claimed", "skipped"]:
			var old := Game.initial_state()
			old.faction = "company"
			old.targetId = "richard" if bid == "B09" else "lumina"
			old.currentScene = "result"
			old.activeEventId = legacy_battles[bid].eventId
			old.activeNodeId = "finish"
			old.battleId = bid
			old.credits = 7654
			old.deck = ["test_reward_02"] if reward_status == "claimed" else []
			var claim: String = old.activeEventId + ":" + bid + ":victory"
			old.claimedRewardIds = [claim]
			old.battleReward = {"eventId":old.activeEventId, "battleId":bid, "claimId":claim, "credits":1000, "options":Game.reward_rules.cards.keys(), "selectedCardId":"test_reward_02" if reward_status == "claimed" else "", "status":reward_status}
			var migrated: Dictionary = Game.migrate_save(old)
			check(Game.valid_save(migrated) and migrated.battleReward.is_empty(), "Retired reward cleared " + bid + reward_status)
			check(migrated.credits == old.credits and migrated.deck == old.deck and migrated.claimedRewardIds == old.claimedRewardIds, "Retired earnings preserved")
	# Port victory pending rewards remain available and can only be claimed once.
	Game.state = Game.initial_state()
	Game.state.activeEventId = "E05B"
	Game.state.targetId = "lumina"
	Game.state.currentPlaceId = "port"
	Game.enter_node("battle")
	Game.battle_exit("win", Game.revision)
	Game.state.activeNodeId = "join"
	Game.state.faction = "resistance"
	Game.state = Game.migrate_save(Game.state)
	advance_to_result()
	check(Game.state.credits == 1000 and Game.has_battle_reward(), "Migrated recruitment settles port reward")
	Game.state.faction = "resistance"
	Game.state = Game.migrate_save(Game.state)
	check(Game.choose_reward_card("test_reward_01", Game.revision), "Existing port pending card remains claimable")
	Game.enter_node("finish")
	check(Game.state.credits == 1000 and Game.state.deck == ["test_reward_01"], "Port reward remains exactly once")
	# A retained battle snapshot must be bit-for-bit stable.
	Game.state = Game.initial_state()
	Game.state.activeEventId = "E12"
	Game.enter_node("battle")
	var combat: Dictionary = Game.state.combat.duplicate(true)
	Game.state.faction = "company"
	var retained: Dictionary = Game.migrate_save(Game.state)
	check(Game.valid_save(retained) and retained.combat == combat, "Retained combat unchanged")
	# Check copies of the actual user saves, never reading or writing the live paths.
	for name in ["checkpoint.json", "checkpoint.json.bak"]:
		var path: String = OUTPUT + "save-backup/" + name
		if FileAccess.file_exists(path):
			var old = JSON.parse_string(FileAccess.get_file_as_string(path))
			check(Game.valid_save(Game.migrate_save(old)), "Actual checkpoint copy remains loadable " + name)
	print("MERCENARY: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
