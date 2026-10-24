extends Node

var checks := 0
var failures := 0
const REMOVED_EVENTS := ["E03", "E05A", "E05B", "E08", "E12"]
const REMOVED_BATTLES := ["B03", "B05A", "B05B", "B08", "B12"]

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("REMOVED EVENTS: " + message)

func ids(values: Array) -> Array:
	return values.map(func(e): return str(e.id))

func test_catalog() -> void:
	Game.state = Game.initial_state()
	var event_ids: Array = Game.events.keys()
	event_ids.sort()
	check(event_ids == ["E01", "E01R", "E02", "E04", "E11"], "four retained events plus the gated return reward are authored")
	check(Game.battles.keys() == ["B02", "B04", "B11"], "only three retained battles are authored")
	check(Game.read_data("weeks/week1/week.json").eventIds == Game.events.keys(), "week index matches event catalog")
	check(ids(Game.eligible_events()) == ["E01", "E02", "E04", "E11"], "four original events remain eligible before E01, but return reward is gated")
	for event in Game.events.values():
		if event.id == "E01R":
			check(not event.unlockCondition.is_empty(), "return reward requires completed commissions")
		else:
			check(event.unlockCondition.is_empty(), "no event prerequisite " + event.id)
		check(event.refreshTimeRange == {"startDay":null, "endDay":null}, "anytime range " + event.id)
		check(event.nodes.has(event.startNodeId), "valid start node " + event.id)
		for node in event.nodes.values():
			if node.has("next"): check(event.nodes.has(node.next), "valid next node " + event.id)
			for choice in node.get("choices", []):
				check(choice.next == "@map" or event.nodes.has(choice.next), "valid choice route " + event.id)
			if node.get("type") == "battle":
				check(Game.battles.has(node.battleId) and Game.battles[node.battleId].eventId == event.id, "battle ownership " + event.id)
	for removed in REMOVED_EVENTS: check(not Game.start_event(removed), "removed event rejected " + removed)
	for removed in REMOVED_BATTLES:
		var before := Game.state.duplicate(true)
		Game.start_training(removed)
		check(not Game.training_mode and Game.state == before, "removed battle cannot train " + removed)
	check(Game.render_text("你见过{目标姓名}吗？") == "你见过委托目标吗？", "empty target renders safely before E01")
	for target in ["richard", "lumina"]:
		Game.state.targetId = target
		check(Game.render_text("{目标姓名}") == Game.display_name(target), "selected target still renders " + target)
	Game.state.targetId = ""
	check(Game.available_events().size() == 3, "ungated catalog still has three-event cap")
	Game.state.refreshedEventIds = ["E11", "E02", "E04"]
	check(Game.start_event("E11"), "fish event can start without E01 or a target")
	check(not "E01" in Game.state.completedEventIds, "starting fish did not silently complete E01")
	Game.state = Game.initial_state()
	check(Game.available_events("hive").is_empty(), "retired hive commission no longer appears at its location")
	var before := Game.state.duplicate(true)
	check(not Game.start_event("E03") and Game.state == before, "direct entry cannot restore retired payment event")

func test_retired_checkpoints() -> void:
	var retired_events := ["E03", "E05A", "E05B", "E06", "E07", "E08", "E09", "E10", "E12"]
	var retired_battles := ["B03", "B05A", "B05B", "B09", "B10", "B08", "B09", "B10", "B12"]
	for index in retired_events.size():
		var event_id: String = retired_events[index]
		var battle_id: String = retired_battles[index]
		for scene in ["dialogue", "battle", "result", "defeat"]:
			var old := Game.initial_state()
			old.activeEventId = event_id
			old.activeNodeId = "lose" if scene == "defeat" else "win_01"
			old.currentPlaceId = "hive" if event_id == "E03" else "port"
			old.currentScene = scene
			old.battleId = battle_id
			old.result = "lose" if scene == "defeat" else "win"
			old.currentDay = 4
			old.currentHp = 38
			old.credits = 4321
			old.deck = ["noren_01", "noren_01"]
			old.faction = "company"
			old.completedEventIds = ["E02", event_id]
			old.refreshedEventIds = ["E04", event_id, "E11"]
			old.flags = {"week1Complete":true, "alleyClue":true}
			old.claimedRewardIds = [event_id + ":" + battle_id + ":victory"]
			old.choiceHistory = {"E01:contract":"richard", event_id + ":join":"accept"}
			old.dialogueHistory = [{"eventId":event_id, "title":"历史事件", "speaker":"场景", "text":"保留历史对白", "kind":"dialogue"}]
			old.battleHistory = [{"battleId":battle_id, "result":old.result}]
			old.combat = {"outcome":old.result}
			old.battleStart = {"legacy":true}
			old.battleReward = {"eventId":event_id, "battleId":battle_id, "status":"pending"}
			var frozen := old.duplicate(true)
			var migrated: Dictionary = Game.migrate_save(old)
			var label: String = event_id + "/" + scene
			check(old == frozen, "migration is read only " + label)
			check(Game.valid_save(migrated), "retired checkpoint remains loadable " + label)
			check(migrated.activeEventId == "E01" and migrated.activeNodeId == "finish", "safe retained anchor " + label)
			check(migrated.currentScene == ("defeat" if scene == "defeat" else "map"), "preserves terminal defeat " + label)
			for key in ["credits", "deck", "currentDay", "currentHp", "claimedRewardIds", "dialogueHistory", "battleHistory"]:
				check(migrated[key] == frozen[key], "preserves " + key + " " + label)
			check(not migrated.has("faction") and not migrated.flags.has("week1Complete"), "cleans retired allegiance and finale flag " + label)
			check(migrated.completedEventIds == ["E02"], "filters retired completion without completing E01 " + label)
			if event_id == "E03":
				check(migrated.refreshedEventIds.size() == 3 and migrated.refreshedEventIds.all(func(id): return id in ["E01", "E04", "E11"]), "retiring Ike refills its removed pool slot " + label)
			else:
				check(migrated.refreshedEventIds == ["E04", "E11"], "unrelated retired migration preserves retained pool " + label)
			check(migrated.choiceHistory == {"E01:contract":"richard"}, "retains only live choices " + label)
			check(migrated.combat.is_empty() and migrated.battleStart.is_empty() and migrated.battleReward.is_empty(), "closes retired encounter and unchosen offer " + label)
			check(Game.migrate_save(migrated) == migrated, "migration is idempotent " + label)
	# A lethal saved snapshot may precede the battle-exit UI callback.
	var lethal := Game.initial_state()
	lethal.activeEventId = "E08"
	lethal.activeNodeId = "battle"
	lethal.battleId = "B08"
	lethal.currentScene = "battle"
	lethal.combat = {"outcome":"lose"}
	lethal.currentHp = 0
	var ended: Dictionary = Game.migrate_save(lethal)
	check(ended.currentScene == "defeat" and ended.result == "lose" and Game.valid_save(ended), "pending lethal retired encounter remains a failed run")
	Game.state = ended
	check(not Game.can_continue(), "retirement cannot revive a failed adventure")
	var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(lethal))
	file.close()
	Game.state = {}
	check(Game.load_game() and Game.page == "defeat" and not Game.can_continue(), "retired failure survives actual disk load")
	# Retiring unrelated event history must preserve an active retained battle.
	Game.state = Game.initial_state()
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.enter_node("battle")
	var live := Game.state.duplicate(true)
	live.completedEventIds = ["E02", "E05A"]
	live.refreshedEventIds = ["E04", "E05A"]
	var kept: Dictionary = Game.migrate_save(live)
	check(kept.combat == live.combat and kept.battleStart == live.battleStart and kept.activeEventId == "E04", "retained encounter keeps its frozen rules and opening")
	check(Game.valid_save(kept), "retained encounter still validates")
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.state.refreshedEventIds = ["E04", "E11", "E05A"]
	var old_file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(Game.state))
	old_file.close()
	Game.state = {}
	check(Game.load_game() and Game.state.refreshedEventIds.size() == 3 and "E04" in Game.state.refreshedEventIds and "E11" in Game.state.refreshedEventIds, "disk migration keeps live pool entries and refills retired slot")
	var pool: Array = Game.state.refreshedEventIds.duplicate()
	check(Game.save_game() and Game.load_game() and Game.state.refreshedEventIds == pool, "migrated pool persists without reroll")

func test_retired_ike_nodes() -> void:
	var nodes := ["intro_01", "intro_02", "payment", "paid_01", "paid_02", "paid_03", "refuse_01", "refuse_02", "refuse_03", "win_01", "win_02", "battle", "lose", "surrender", "finish"]
	for node_id in nodes:
		var old := Game.initial_state()
		old.activeEventId = "E03"
		old.activeNodeId = node_id
		old.currentPlaceId = "hive"
		old.currentScene = "battle" if node_id == "battle" else ("result" if node_id == "finish" else "dialogue")
		old.battleId = "B03" if node_id in ["battle", "win_01", "win_02", "lose", "surrender", "finish"] else ""
		old.result = "lose" if node_id == "lose" else ""
		old.credits = 4321
		old.deck = ["noren_01"]
		old.claimedRewardIds = ["E03:B03:victory"]
		old.completedEventIds = ["E01", "E03"]
		old.choiceHistory = {"E03:payment":"pay"}
		old.dialogueHistory = [{"eventId":"E03", "title":"旧艾克事件", "speaker":"艾克", "text":"历史对白", "kind":"dialogue"}]
		var migrated: Dictionary = Game.migrate_save(old)
		check(Game.valid_save(migrated), "each retired Ike node remains loadable: " + node_id)
		check(migrated.activeEventId == "E01" and migrated.activeNodeId == "finish" and migrated.currentScene == ("defeat" if node_id == "lose" else "map"), "retired Ike node returns to safe map or terminal defeat: " + node_id)
		check(migrated.credits == old.credits and migrated.deck == old.deck and migrated.claimedRewardIds == old.claimedRewardIds and migrated.dialogueHistory == old.dialogueHistory, "retiring Ike preserves already awarded assets and history: " + node_id)
		check(not "E03" in migrated.completedEventIds and not migrated.choiceHistory.has("E03:payment"), "retired Ike IDs cannot count toward new commissions: " + node_id)
		Game.state = migrated
		check(Game.save_game() and Game.load_game(), "retired Ike node survives actual isolated save load: " + node_id)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://removed-events-test-checkpoint.json"
	Game.meta_path = "user://removed-events-test-meta.json"
	test_catalog()
	test_retired_checkpoints()
	test_retired_ike_nodes()
	print("REMOVED EVENTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
