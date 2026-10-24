extends Node
var checks := 0
var failures := 0
var output := "res://artifacts/qa/opening-support-2026-10-24/return"
var save_file := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("COMMISSION RETURN: " + message)

func fresh() -> void:
	Game.save_enabled = false
	Game.save_path = save_file
	Game.meta_path = output.path_join("meta.json")
	Game.new_game()
	Game.skip_dialogue(Game.revision)
	check(Game.choose(0, Game.revision), "take money chip")
	Game.skip_dialogue(Game.revision)
	Game.claim_rewards(Game.revision)

func finish_commission(id: String) -> void:
	Game.state.refreshedEventIds = [id]
	Game.refresh_event_pool()
	check(Game.start_event(id), "start " + id)
	Game.skip_dialogue(Game.revision)
	if Game.state.currentScene == "battle":
		check(Game.battle_exit("win", Game.revision), "finish real battle route " + id)
		Game.skip_dialogue(Game.revision)
	check(id in Game.state.completedEventIds, "commission complete " + id)
	check(Game.claim_rewards(Game.revision), "leave commission " + id)

func texts(node: Node) -> String:
	var result := ""
	if node is Label or node is Button or node is RichTextLabel: result += str(node.text) + "\n"
	for child in node.get_children(): result += texts(child)
	return result

func test_unlock() -> void:
	for last in ["E02", "E04", "E11"]:
		fresh()
		check(not Game.start_event("E01R"), "return unavailable before three commissions")
		var others := ["E02", "E04", "E11"]
		others.erase(last)
		Game.state.completedEventIds.append_array(others.slice(0, 2))
		Game.refresh_event_pool()
		check(not "E01R" in Game.state.refreshedEventIds, "opening plus two does not count as three")
		Game.state.completedEventIds.append(last)
		Game.refresh_event_pool()
		check("E01R" in Game.state.refreshedEventIds and Game.available_events("bar").size() == 1, "all three remaining unique commissions unlock return")
		check(Game.start_event("E01R"), "return can start")
	fresh()
	Game.state.completedEventIds = ["E01", "E02", "E02", "E02"]
	check(not Game.meets(Game.events.E01R.unlockCondition), "duplicates cannot satisfy count")
	Game.state.completedEventIds = ["E02", "E04", "E11"]
	check(not Game.meets(Game.events.E01R.unlockCondition), "opening agreement is required")
	Game.state.completedEventIds.append("E01")
	Game.state.refreshedEventIds = ["E11"]
	var migrated: Dictionary = Game.migrate_save(Game.state)
	check("E01R" in migrated.refreshedEventIds and migrated.currentDay == 1, "eligible old save gains return without retroactive days or prizes")

func test_real_flow() -> void:
	fresh()
	finish_commission("E02")
	finish_commission("E04")
	check(not "E01R" in Game.state.refreshedEventIds, "two actual completions are insufficient")
	finish_commission("E11")
	check(Game.state.currentDay == 4 and "E01R" in Game.state.refreshedEventIds, "third remaining commission reveals return")
	Game.state.currentHp = 42
	var history: Array = Game.state.battleHistory.duplicate(true)
	var credits: int = Game.state.credits
	check(Game.start_event("E01R"), "start return dialogue")
	Game.skip_dialogue(Game.revision)
	check(Game.state.activeNodeId == "collect" and Game.state.credits == credits, "skip stops before claiming reward")
	var before := Game.state.duplicate(true)
	var rev := Game.revision
	check(Game.save_game(), "pre-claim checkpoint saves")
	Game.save_path = save_file.path_join("blocked.json")
	Game.save_enabled = true
	check(not Game.choose(0, rev) and Game.state == before and Game.revision == rev, "failed reward save rolls back completion, credits and options")
	Game.save_path = save_file
	check(Game.choose(0, Game.revision), "reward succeeds after restoring save path")
	Game.save_enabled = false
	check(Game.state.currentDay == 4 and Game.state.currentHp == 42 and Game.state.battleHistory == history, "reward spends no day and triggers no victory chip or fake battle")
	check(Game.state.credits == credits + 1000 and Game.state.battleReward.source == "event" and Game.state.battleReward.battleType == "normal", "return uses ordinary battle credit and rarity rules")
	check(Game.state.battleReward.options.size() == 3 and Game.state.battleReward.options.all(func(id): return Game.card_catalog[id].rarity in ["B", "A", "S"]), "three non-starting card options")
	check(Game.state.claimedRewardIds.count("E01R:commission") == 1 and Game.valid_save(Game.state), "reward receipt is valid and unique")
	var pending = JSON.parse_string(JSON.stringify(Game.state.battleReward))
	Game.state = {}
	check(Game.load_game() and JSON.parse_string(JSON.stringify(Game.state.battleReward)) == pending, "reward reload preserves choices and receipt")
	check(not Game.choose(0, rev), "stale collection cannot repeat")
	Game.prepare_battle_reward()
	check(Game.state.credits == credits + 1000 and JSON.parse_string(JSON.stringify(Game.state.battleReward)) == pending, "re-entry never regrants or rerolls")
	var view = load("res://scripts/reward.gd").new()
	add_child(view)
	check("约定的回礼" in texts(view) and "领奖不消耗时间" in texts(view) and not "战斗胜利" in texts(view), "reward UI describes a return visit")
	view.open_picker()
	check(view.option_buttons.size() == 3, "existing reward picker offers three cards")
	view.free()
	var card: String = Game.state.battleReward.options[0]
	var count: int = int(Game.owned_card_counts().get(card, 0))
	before = Game.state.duplicate(true)
	Game.save_enabled = true
	Game.save_path = save_file.path_join("blocked.json")
	check(not Game.choose_reward_card(card, Game.revision) and Game.state == before, "card save failure rolls back acquisition")
	Game.save_path = save_file
	check(Game.choose_reward_card(card, Game.revision), "card reward claim succeeds")
	Game.save_enabled = false
	check(int(Game.owned_card_counts().get(card, 0)) == count + 1 and not Game.choose_reward_card(card, Game.revision), "card grants exactly one copy")
	check(Game.save_game() and Game.load_game() and Game.state.battleReward.status == "claimed", "claimed card persists")
	var bad := Game.state.duplicate(true)
	bad.battleReward.source = "unknown"
	check(not Game.valid_save(bad), "unknown reward source rejected")
	bad = Game.state.duplicate(true)
	bad.battleReward.erase("battleType")
	check(not Game.valid_save(bad), "event reward without its configured type is rejected")
	bad = Game.state.duplicate(true)
	bad.completedEventIds.erase("E01R")
	check(not Game.valid_save(bad), "return receipt requires its own completion record")
	check(Game.claim_rewards(Game.revision), "leave return reward")
	check(not Game.start_event("E01R") and not "E01R" in Game.state.refreshedEventIds, "return cannot be farmed")

func test_skip_card() -> void:
	fresh()
	Game.state.completedEventIds.append_array(["E02", "E04", "E11"])
	Game.refresh_event_pool()
	check(Game.start_event("E01R"), "start skip-card return")
	Game.skip_dialogue(Game.revision)
	check(Game.choose(0, Game.revision), "collect skip-card return")
	var credits: int = Game.state.credits
	var cards: Array = Game.state.deck.duplicate()
	var options: Array = Game.state.battleReward.options.duplicate()
	check(Game.claim_rewards(Game.revision) and Game.state.battleReward.status == "skipped", "leaving without a card records skipped")
	check(Game.save_game() and Game.load_game(), "skipped return roundtrips")
	check(Game.state.credits == credits and Game.state.deck == cards and not Game.choose_reward_card(options[0], Game.revision), "skipped card cannot be reclaimed after reload")

func test_historical_return_receipts() -> void:
	for status in ["pending", "claimed", "skipped"]:
		fresh()
		Game.state.completedEventIds.append_array(["E02", "E04", "E11"])
		Game.refresh_event_pool()
		check(Game.start_event("E01R"), "prepare historical return reward")
		Game.skip_dialogue(Game.revision)
		check(Game.choose(0, Game.revision), "generate historical return reward receipt")
		var card: String = Game.state.battleReward.options[0]
		if status == "claimed": check(Game.choose_reward_card(card, Game.revision), "historical card already claimed")
		elif status == "skipped": check(Game.claim_rewards(Game.revision), "historical card already skipped")
		# This reward was earned when E03 counted. E11 was not completed then.
		Game.state.completedEventIds = ["E01", "E02", "E03", "E04", "E01R"]
		var old := Game.state.duplicate(true)
		var migrated: Dictionary = Game.migrate_save(old)
		check(Game.valid_save(migrated) and not "E03" in migrated.completedEventIds and not "E11" in migrated.completedEventIds, "historical return stays valid without newly required third commission: " + status)
		check(migrated.credits == old.credits and migrated.deck == old.deck and migrated.battleReward == old.battleReward and migrated.claimedRewardIds == old.claimedRewardIds, "historical return assets, receipt and options remain exact: " + status)
		var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(old)); file.close()
		check(Game.load_game() and Game.state.battleReward.status == status, "historical return loads from old disk checkpoint: " + status)
		var credits: int = Game.state.credits
		var cards: Array = Game.state.deck.duplicate()
		var options: Array = Game.state.battleReward.options.duplicate()
		Game.prepare_battle_reward()
		check(Game.state.credits == credits and Game.state.deck == cards and Game.state.battleReward.options == options, "historical receipt prevents new credits or option reroll: " + status)
		if status == "pending":
			check(Game.choose_reward_card(card, Game.revision), "historical pending card remains claimable once")
			check(not Game.choose_reward_card(card, Game.revision), "historical pending card cannot be claimed twice")
		else:
			check(not Game.choose_reward_card(card, Game.revision) and Game.state.deck == cards, "historical finished card cannot be reclaimed: " + status)
		check(not Game.start_event("E01R"), "historical completed return cannot restart")

func test_uncollected_old_return_dialogue() -> void:
	for node_id in ["return_01", "return_02", "collect"]:
		fresh()
		Game.state.completedEventIds = ["E01", "E02", "E03", "E04"]
		Game.state.activeEventId = "E01R"
		Game.state.activeNodeId = node_id
		Game.state.currentPlaceId = "bar"
		Game.state.currentScene = "dialogue"
		Game.state.currentDay = 4
		var old := Game.state.duplicate(true)
		var migrated: Dictionary = Game.migrate_save(old)
		check(Game.valid_save(migrated) and migrated.activeEventId == "E01" and migrated.activeNodeId == "finish" and migrated.currentScene == "map" and migrated.currentPlaceId == "bar", "uncollected old return returns safely to map: " + node_id)
		for field in ["credits", "deck", "currentDay", "dialogueHistory", "ownedCyberwareIds", "equippedCyberwareIds"]:
			check(migrated[field] == old[field], "uncollected return migration preserves " + field + ": " + node_id)
		check(not "E01R" in migrated.completedEventIds and not "E01R:commission" in migrated.claimedRewardIds and migrated.battleReward.is_empty(), "uncollected return grants no premature reward: " + node_id)
		check("E11" in migrated.refreshedEventIds and not "E01R" in migrated.refreshedEventIds, "remaining pump commission is available before return can unlock: " + node_id)
		var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(old)); file.close()
		check(Game.load_game() and Game.page == "map" and Game.start_event("E11"), "old return disk load allows continuing the remaining commission: " + node_id)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	save_file = output.path_join("checkpoint.json")
	test_unlock()
	test_real_flow()
	test_skip_card()
	test_historical_return_receipts()
	test_uncollected_old_return_dialogue()
	print("COMMISSION RETURN: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
