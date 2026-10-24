extends Node
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func step_to_stop() -> void:
	var guard := 0
	while Game.state.currentScene == "dialogue" and Game.node_data().has("next") and guard < 80:
		Game.advance(Game.revision)
		guard += 1
	check(guard < 80, "Dialogue terminates")

func offer_event(id: String) -> void:
	Game.state.refreshedEventIds = [id]
	Game.refresh_event_pool()

func complete_event(id: String, outcome: String = "win", choice: int = 0) -> void:
	offer_event(id)
	check(Game.start_event(id), "Start " + id)
	step_to_stop()
	if Game.state.currentScene == "battle":
		check(Game.battle_exit(outcome, Game.revision), "Battle returns " + id + " / " + outcome)
		step_to_stop()
	if Game.state.currentScene == "dialogue" and Game.node_data().has("choices"):
		check(Game.choose(choice, Game.revision), "Choice " + id)
		step_to_stop()
	if Game.state.currentScene == "result": Game.claim_rewards(Game.revision)

func start_contract(index: int) -> void:
	Game.new_game()
	step_to_stop()
	check(Game.choose(index, Game.revision), "Select contract")
	step_to_stop()
	Game.claim_rewards(Game.revision)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://automated_test_checkpoint.json"
	Game.meta_path = "user://automated_test_meta.json"
	# Validate authored references, including legacy saved result nodes.
	check(Game.places.size() == 17, "17 places including church")
	check(Game.events.size() == 8 and Game.events.has("E01R"), "opening, six commissions, and gated return reward event")
	for e in Game.events.values():
		check(not Game.place_data(e.placeId).is_empty(), e.id + " place exists")
		for n in e.nodes.values():
			if n.has("speakerId") and n.speakerId != "": check(Game.characters.has(Game.resolve_character_id(n.speakerId)), "Known character " + n.speakerId)
			if n.has("next"): check(n.next == "@map" or e.nodes.has(n.next), e.id + " next exists")
			for c in n.get("choices", []): check(c.next == "@map" or e.nodes.has(c.next), "Choice target exists")
		for id in e.rewardIds: check(Game.rewards.has(id), "Reward exists")
	for b in Game.battles.values():
		for result in ["win", "lose", "surrender"]:
			check(Game.events[b.eventId].nodes.has(b.returnNodeByResult[result]), b.id + " return " + result)
	# Payment rejection is atomic; payment is committed once even under duplicate click.
	preload("res://tests/fixtures/payment_choice.gd").install(Game)
	start_contract(0)
	check(Game.events.E04.unlockCondition.is_empty(), "E04 no longer requires a clue")
	offer_event("QA_PAYMENT")
	Game.start_event("QA_PAYMENT")
	step_to_stop()
	var rev := Game.revision
	var credits_before := int(Game.state.credits)
	check(not Game.choose(0, rev), "Insufficient credits rejected")
	check(Game.state.credits == credits_before and not Game.state.flags.has("alleyClue"), "No clue or charge on rejected payment")
	Game.state.credits = 300
	check(Game.choose(0, rev), "Payment succeeds")
	check(not Game.choose(0, rev), "Double click rejected")
	check(Game.state.credits == 0 and not Game.state.flags.has("alleyClue"), "Payment applied once without a retired clue")
	step_to_stop()
	check("QA_PAYMENT" in Game.state.completedEventIds, "Payment finishes QA_PAYMENT")
	preload("res://tests/fixtures/payment_choice.gd").uninstall(Game)
	# All three support choices allow completing every independent commission.
	for support in [0,1,2]:
		start_contract(support)
		complete_event("E02")
		complete_event("E04")
		check(not Game.state.has("faction"), "No allegiance after contract completion")
		for removed in ["E03", "E05A", "E05B", "E06", "E07", "E08", "E09", "E10", "E12"]:
			check(not Game.start_event(removed), "Removed event cannot start " + removed)
		complete_event("E11")
		check(Game.state.completedEventIds.size() == 4 and Game.state.currentDay == 4, "Opening and three commissions complete exactly once; only three commissions spend a day")
		check(Game.state.currentWeek == 1, "No empty future week")
		check(not Game.start_event("E11"), "Completed event cannot repeat")
	# Disk roundtrip preserves victory story or the terminal defeat page.
	for b in Game.battles.values():
		for result in ["win", "lose"]:
			Game.state = Game.initial_state()
			Game.state.targetId = "richard"
			Game.state.activeEventId = b.eventId
			Game.state.currentPlaceId = Game.events[b.eventId].placeId
			Game.enter_node("battle")
			check(Game.save_game(), "Save battle")
			Game.state = {}
			check(Game.load_game(), "Restore battle")
			var before_rejected := Game.state.duplicate(true)
			var battle_rev := Game.revision
			check(not Game.battle_exit("surrender", battle_rev), "Surrender rejected " + b.id)
			check(Game.state == before_rejected and Game.revision == battle_rev and Game.page == "battle", "Rejected surrender preserves battle")
			check(Game.battle_exit(result,battle_rev), b.id + " " + result)
			check(not Game.battle_exit(result,battle_rev), "Duplicate battle result rejected")
			check(Game.state.activeNodeId == b.returnNodeByResult.win if result == "win" else Game.page == "defeat" and Game.state.currentScene == "defeat", "Exact victory node or terminal defeat page")
			if result != "win":
				check(Game.state.completedEventIds.is_empty(), "Failure not completed")
				check(Game.state.flags.is_empty(), "Failure grants no clues")
				check(Game.is_run_over() and not Game.can_continue(), "Failure ends the adventure")
				var failed := Game.state.duplicate(true)
				Game.go_map()
				check(Game.state == failed and Game.page == "defeat", "Failure cannot return to map")
			check(Game.save_game() and Game.load_game(), "Restore result node")
	# Legacy result checkpoints still return to the map; new training cannot surrender.
	Game.state = Game.initial_state()
	Game.state.targetId = "richard"
	Game.state.activeEventId = "E02"
	Game.state.currentPlaceId = "junkyard"
	Game.state.result = "surrender"
	Game.enter_node("surrender")
	check(Game.save_game() and Game.load_game(), "Legacy surrender dialogue still loads")
	check(Game.choose(0, Game.revision) and Game.page == "map", "Legacy surrender can return to map")
	var adventure := Game.state.duplicate(true)
	Game.start_training("B02")
	var training := Game.state.duplicate(true)
	var training_revision := Game.revision
	check(not Game.battle_exit("surrender", Game.revision), "Training battle exit rejects surrender")
	Game.finish_training("surrender")
	check(Game.training_mode and Game.state == training and Game.revision == training_revision and Game.page == "battle", "Direct training surrender leaves battle intact")
	Game.finish_training("lose")
	check(not Game.training_mode and Game.page == "menu" and Game.state == adventure, "Training defeat restores adventure")
	# Configured rewards are claimed atomically and idempotently.
	check(Game.events.E01.rewardIds.is_empty(), "Opening chip support does not invent a configured credit reward")
	Game.rewards["test"] = {"type":"credits","amount":20,"name":"test"}
	Game.state = Game.initial_state()
	var expected_credits := int(Game.state.credits) + 20
	check(Game.apply_actions([{"op":"grantReward","id":"test"}]), "Configured reward applies")
	check(Game.apply_actions([{"op":"grantReward","id":"test"}]), "Repeated reward is safe")
	check(Game.state.credits == expected_credits and Game.state.claimedRewardIds.size() == 1, "Reward exactly once")
	check(not Game.apply_actions([{"op":"addCredits","amount":10},{"op":"spendCredits","amount":500}]), "Invalid action batch rejected")
	check(Game.state.credits == expected_credits, "Invalid batch has no partial effects")
	Game.rewards.erase("test")
	# Corrupt current checkpoint, recover the previous backup.
	Game.save_game(); Game.save_game()
	var file := FileAccess.open(Game.save_path,FileAccess.WRITE)
	file.store_string("corrupt"); file.close()
	check(Game.load_game(), "Backup recovers corrupt checkpoint")
	check(Game.state.credits == expected_credits and Game.state.claimedRewardIds.size() == 1, "Claim state persists")
	for path in [Game.save_path,Game.save_path+".bak",Game.save_path+".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("TEST RESULTS: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: print(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
