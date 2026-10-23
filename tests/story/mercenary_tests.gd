extends Node

const OUTPUT := "res://artifacts/qa/free-mercenary-2026-10-15/"
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MERCENARY: " + message)

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
	for p in Game.places: check(not p.has("unlockCondition"), "Places have no unlock conditions")
	for e in Game.events.values():
		check_condition(e.unlockCondition)
		check(not e.nodes.has("join"), "No recruitment choice")
		for n in e.nodes.values():
			for a in n.get("effects", []): check(a.op != "setFaction", "No allegiance action")
	for id in ["E05A", "E05B", "E06", "E07", "E08", "E09", "E10", "E12"]: check(not Game.events.has(id), "Retired event removed")
	for id in ["B05A", "B05B", "B08", "B09", "B10", "B12"]: check(not Game.battles.has(id), "Retired encounter removed")
	# Self-contained checkpoint matrix: no dependency on untracked QA artifacts.
	var legacy_events: Dictionary = {}
	var legacy_battles := {"B09":{"eventId":"E09"}, "B10":{"eventId":"E10"}}
	var legacy_ids := {"E05A":"B05A", "E05B":"B05B", "E06":"B05A", "E07":"B05B", "E09":"B09", "E10":"B10"}
	for event_id in legacy_ids:
		legacy_events[event_id] = {"placeId":"port", "nodes":{}}
		for node_id in ["intro_01", "join", "accept_01", "refuse_01", "win_01", "lose", "surrender"]:
			legacy_events[event_id].nodes[node_id] = {}
		legacy_events[event_id].nodes.battle = {"type":"battle", "battleId":legacy_ids[event_id]}
		legacy_events[event_id].nodes.finish = {"type":"finish"}
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
				Game.state.currentScene = "battle"
				Game.state.battleId = node.battleId
				Game.state.combat = {"battleId":node.battleId}
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
			check(Game.state.activeEventId == "E01" and Game.state.currentPlaceId == "bar", "Retired checkpoint uses safe retained anchor " + label)
			if node_id == "lose":
				check(Game.page == "defeat" and not Game.can_continue(), "Legacy failure remains terminal " + label)
			else:
				check(Game.page == "map" and Game.map_target_events().map(func(e): return e.id) == ["E02", "E11"], "Retired checkpoint resumes remaining ungated events " + label)
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
	# Newly retired port/finale rewards preserve paid earnings and selected cards.
	for pair in [["E05A", "B05A"], ["E05B", "B05B"], ["E08", "B08"], ["E12", "B12"]]:
		for status in ["pending", "claimed", "skipped"]:
			var old := Game.initial_state()
			old.activeEventId = pair[0]
			old.activeNodeId = "finish"
			old.currentScene = "result"
			old.battleId = pair[1]
			old.credits = 6543
			old.currentDay = 5
			old.deck = ["test_reward_01"] if status == "claimed" else []
			old.battleReward = {"eventId":pair[0], "battleId":pair[1], "status":status}
			var migrated: Dictionary = Game.migrate_save(old)
			check(Game.valid_save(migrated) and migrated.battleReward.is_empty(), "Removed pending offer cannot be claimed " + pair[0] + status)
			check(migrated.credits == old.credits and migrated.deck == old.deck and migrated.currentDay == old.currentDay, "Removed reward keeps paid earnings and date")
	# A retained battle snapshot must be bit-for-bit stable.
	Game.state = Game.initial_state()
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
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
