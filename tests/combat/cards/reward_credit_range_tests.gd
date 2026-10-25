extends Node
## Generation and frozen receipts only; never uses the player's save directory.
var checks := 0
var failures: Array[String] = []
var observed: Dictionary = {}
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func stage(source: String) -> void:
	Game.state = Game.initial_state()
	Game.state.activeEventId = "E01R" if source == "event" else "E02"
	Game.state.activeNodeId = "finish"
	Game.state.currentPlaceId = "bar" if source == "event" else "junkyard"
	Game.state.battleId = "" if source == "event" else "B02"
	Game.state.currentScene = "result"
	Game.state.result = "win"
	Game.state.completedEventIds = ["E01", "E02", "E04", "E11", "E01R"]
	if source != "event": Game.state.battleHistory = [{"battleId":"B02", "result":"win"}]
	Game.page = "result"
	Game.revision += 1
	Game.prepare_battle_reward()

func _ready() -> void:
	if OS.get_user_data_dir().ends_with("/MidnightCommissionDemo"):
		push_error("Run credit range QA in an isolated copied project/user directory")
		get_tree().quit(2)
		return
	Game.save_enabled = false
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "user://reward-credit-range-qa"
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_path = output.path_join("range-checkpoint.json")
	Game.meta_path = output.path_join("range-meta.json")
	check(Game.reward_rules.creditsMin == 40 and Game.reward_rules.creditsMax == 60, "Configured reward is an inclusive 40–60 range")
	var original_type: String = Game.battles.B02.battleType
	for source in ["normal", "elite", "boss", "event"]:
		if source != "event": Game.battles.B02.battleType = source
		var amounts: Array[int] = []
		for index in range(64):
			stage(source)
			var amount := Game.reward_credit_amount()
			amounts.append(amount)
			check(amount >= 40 and amount <= 60 and Game.valid_save(Game.state), source + " generated valid integer reward %d" % index)
			var frozen: Dictionary = Game.state.battleReward.duplicate(true)
			var balance: int = Game.state.credits
			Game.prepare_battle_reward()
			check(Game.state.battleReward == frozen and Game.state.credits == balance, source + " repeated preparation never rerolls or pays %d" % index)
		var unique: Dictionary = {}
		for amount in amounts: unique[amount] = true
		check(unique.size() > 1, source + " repeated new rewards vary instead of staying at fifty")
		observed[source] = amounts
		# JSON loads numbers as floats; compare the full receipt in that same form.
		var frozen: Dictionary = JSON.parse_string(JSON.stringify(Game.state.battleReward))
		check(Game.save_game(), source + " pending random receipt saves")
		Game.state = {}
		check(Game.load_game() and Game.state.battleReward == frozen, source + " pending random receipt reloads without rerolling")
		var amount := Game.reward_credit_amount()
		var balance: int = Game.state.credits
		check(Game.claim_reward_credits(Game.revision) and Game.state.credits == balance + amount, source + " claim pays exactly the frozen random amount")
		check(Game.save_game() and Game.load_game() and Game.state.credits == balance + amount and not Game.claim_reward_credits(Game.revision), source + " paid random receipt survives reload and cannot pay twice")
	Game.battles.B02.battleType = original_type
	stage("normal")
	for amount in [40, 50, 60, 1000]:
		var valid: Dictionary = Game.state.duplicate(true)
		valid.battleReward.credits = amount
		check(Game.valid_save(valid), "Inclusive range edge / legacy receipt accepted: " + str(amount))
	for amount in [39, 61, -1, 0, 40.5, 59.5, INF, NAN, "50", true]:
		var invalid: Dictionary = Game.state.duplicate(true)
		invalid.battleReward.credits = amount
		check(not Game.valid_save(invalid), "Out-of-range / malformed receipt rejected: " + str(amount))
	var file := FileAccess.open(output.path_join("reward-credit-range-results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures, "observed":observed,
		"scope":"isolated headless generation, frozen amounts, exact claims and save compatibility"}, "\t"))
	file.close()
	print("REWARD CREDIT RANGE TESTS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
