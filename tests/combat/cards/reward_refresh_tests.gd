extends Node
## Real result routing and timed UI values; headless, no system pointer or player saves.
const Cleanup = preload("res://scripts/combat/audio_cleanup.gd")
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var app: Control
var offers: Array[String] = []
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message, "passed":ok})
	if not ok:
		failures.append(message)
		push_error("REWARD REFRESH: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func remove_app() -> void:
	if not is_instance_valid(app): return
	if is_instance_valid(app.audio_hooks): app.audio_hooks.attach(null)
	await Cleanup.release(app, get_tree())
	app.queue_free()
	await settle()

func fixture(source: String, money_chip: bool = false) -> void:
	Game.save_enabled = false
	Game.save_path = output.path_join("checkpoint-" + source + ".json")
	Game.meta_path = output.path_join("meta.json")
	Game.pending_save_kind = ""
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.state = Game.initial_state()
	var event_reward := source == "event"
	var boss := source == "boss"
	Game.state.activeEventId = "E01R" if event_reward else "E16" if boss else "E02"
	Game.state.activeNodeId = "finish"
	Game.state.currentPlaceId = "bar" if event_reward else Game.battles["B16" if boss else "B02"].placeId
	Game.state.battleId = "" if event_reward else "B16" if boss else "B02"
	Game.state.currentScene = "result"
	Game.state.currentDay = 7 if boss else 4
	Game.state.result = "win"
	Game.state.completedEventIds = ["E01", "E02", "E04", "E11"]
	if event_reward: Game.state.completedEventIds.append("E01R")
	else:
		Game.state.battleHistory = [{"battleId":Game.state.battleId, "result":"win"}]
		if boss: Game.state.completedEventIds.append("E16")
	if money_chip:
		Game.state.ownedCyberwareIds = ["money_chip"]
		Game.state.equippedCyberwareIds = ["money_chip"]
		var claim_id: String = Game.state.activeEventId + ":" + Game.state.battleId + ":passive_victory"
		Game.state.claimedRewardIds.append(claim_id)
		Game.state.battlePassiveReward = {"claimId":claim_id, "eventId":Game.state.activeEventId,
			"battleId":Game.state.battleId, "credits":30, "healing":0, "creditsStatus":"pending"}
	Game.prepare_battle_reward()
	Game.state.battleReward.options = offers.duplicate()
	Game.page = "result"
	Game.revision += 1
	check(Game.valid_save(Game.state), source + " reward checkpoint is valid")

func stage(source: String, money_chip: bool = false) -> void:
	await remove_app()
	fixture(source, money_chip)
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(0.25).timeout
	check(is_equal_approx(app.view.reward_view.modulate.a, 1.0), source + " initial page fade finishes before claims")

func same_view(result_id: int, reward_id: int) -> bool:
	return is_instance_valid(app.view) and app.view.get_instance_id() == result_id and is_instance_valid(app.view.reward_view) and app.view.reward_view.get_instance_id() == reward_id

func check_counter(source: String, before: int, target: int, result_id: int, reward_id: int) -> void:
	var values: Array[int] = []
	var opaque := true
	var stable := true
	for index in range(12):
		await get_tree().create_timer(0.08).timeout
		stable = stable and same_view(result_id, reward_id)
		var reward: Control = app.view.reward_view
		opaque = opaque and is_equal_approx(reward.modulate.a, 1.0)
		values.append(int(reward.credits_label.text))
	var monotone := true
	var previous := before
	for value in values:
		monotone = monotone and value >= previous and value <= target
		previous = value
	check(stable and opaque, source + " all sampled claim frames retain the same fully opaque result and reward nodes")
	check(values.any(func(value): return value > before and value < target), source + " balance visibly passes through intermediate integers")
	check(monotone and values[-1] == target, source + " displayed balance increases monotonically and lands exactly on committed balance")
	check(Game.state.credits == target, source + " display animation never modifies committed credits")

func test_credit_claim(source: String, money_chip: bool = false) -> void:
	await stage(source, money_chip)
	var reward: Control = app.view.reward_view
	var result_id: int = app.view.get_instance_id()
	var reward_id: int = reward.get_instance_id()
	var before: int = Game.state.credits
	var amount: int = Game.reward_credit_amount()
	var base_amount: int = Game.state.battleReward.credits
	check(base_amount >= 40 and base_amount <= 60 and amount == base_amount + (30 if money_chip else 0), source + " counter target uses frozen random base plus optional chip")
	var revision: int = Game.revision
	var card_button_id: int = reward.card_reward_button.get_instance_id()
	check(int(reward.credits_label.text) == before, source + " initial balance is shown immediately without replaying an increase")
	reward.credits_reward_button.pressed.emit()
	check(same_view(result_id, reward_id) and is_equal_approx(app.view.reward_view.modulate.a, 1.0), source + " claim updates in place without restarting full-screen fade")
	reward = app.view.reward_view
	check(Game.state.credits == before + amount and Game.reward_credits_status() == "claimed", source + " claim commits base and optional chip credits once")
	check(reward.expected_revision == Game.revision and Game.revision == revision + 1, source + " retained controls advance to the successful claim revision")
	check(not reward.credits_reward_button.visible and reward.credits_reward_button.disabled, source + " paid credit action is hidden and cannot receive focus or clicks")
	check(reward.card_reward_button.get_instance_id() == card_button_id and not reward.card_reward_button.disabled, source + " unclaimed card control is retained and usable")
	check(reward.exit_button.text == "放弃卡牌并返回  →", source + " exit caption only warns about the remaining card")
	if money_chip: check(Game.state.battlePassiveReward.creditsStatus == "claimed", "chip receipt settles with its base credit claim")
	reward.claim_credits()
	check(not Game.claim_reward_credits(revision) and not Game.claim_reward_credits(Game.revision) and Game.state.credits == before + amount, source + " stale and repeated claims cannot pay again during animation")
	await check_counter(source, before, before + amount, result_id, reward_id)
	# Use the surviving button to open and settle a card after the credit claim.
	reward.card_reward_button.pressed.emit()
	await settle()
	check(is_instance_valid(reward.picker), source + " card picker still opens after credit revision changes")
	await get_tree().create_timer(0.6).timeout
	reward.picker.option_buttons[0].pressed.emit()
	await settle()
	check(same_view(result_id, reward_id) and not is_instance_valid(reward.picker), source + " card settlement closes its modal without rebuilding the background")
	check(Game.state.deck.count(offers[0]) == 1 and reward.exit_button.text == "返回地图  →", source + " card is granted once and fully claimed exit caption refreshes")
	var credits_label_ref: WeakRef = weakref(reward.credits_label)
	reward.exit_button.pressed.emit()
	await settle()
	check(Game.page == "map" and credits_label_ref.get_ref() == null, source + " ordinary exit routes to map and releases the old counter")

func test_failure_and_card_first() -> void:
	await stage("battle")
	var reward: Control = app.view.reward_view
	var result_id: int = app.view.get_instance_id()
	var reward_id: int = reward.get_instance_id()
	var before: int = Game.state.credits
	var amount: int = Game.reward_credit_amount()
	check(Game.save_game(), "failure fixture creates a test-only checkpoint")
	var good_path: String = Game.save_path
	var saved_bytes := FileAccess.get_file_as_bytes(good_path)
	Game.save_enabled = true
	Game.save_path = good_path.path_join("blocked.json")
	var before_state: Dictionary = Game.state.duplicate(true)
	var revision: int = Game.revision
	reward.credits_reward_button.pressed.emit()
	await get_tree().create_timer(0.25).timeout
	check(Game.state == before_state and Game.revision == revision, "failed credit save rolls back balance and receipt")
	check(same_view(result_id, reward_id) and int(reward.credits_label.text) == before and is_equal_approx(reward.modulate.a, 1.0), "failed credit save neither rebuilds the page nor animates an unearned increase")
	check(reward.credits_reward_button.visible and not reward.credits_reward_button.disabled and FileAccess.get_file_as_bytes(good_path) == saved_bytes, "failed save preserves a usable retry and original checkpoint bytes")
	Game.save_path = good_path
	reward.card_reward_button.pressed.emit()
	await settle()
	await get_tree().create_timer(0.6).timeout
	reward.picker.option_buttons[1].pressed.emit()
	await settle()
	check(same_view(result_id, reward_id) and reward.expected_revision == Game.revision, "card-first choice refreshes revision without replacing the reward view")
	check(Game.state.deck == [offers[1]] and Game.reward_credits_status() == "pending" and reward.credits_reward_button.visible and not reward.credits_reward_button.disabled, "card-first choice leaves unpaid credit action available")
	reward.credits_reward_button.pressed.emit()
	await check_counter("card-first retry", before, before + amount, result_id, reward_id)
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(good_path))
	check(disk.credits == before + amount and disk.battleReward.creditsStatus == "claimed" and disk.deck == [offers[1]], "successful retry persists exact credit amount and the earlier card together")
	Game.save_enabled = false

func test_card_during_counter() -> void:
	await stage("battle")
	var reward: Control = app.view.reward_view
	var result_id: int = app.view.get_instance_id()
	var reward_id: int = reward.get_instance_id()
	var before: int = Game.state.credits
	var amount: int = Game.reward_credit_amount()
	reward.credits_reward_button.pressed.emit()
	await get_tree().create_timer(0.1).timeout
	var intermediate := int(reward.credits_label.text)
	check(intermediate > before and intermediate < before + amount, "counter is active before selecting a card")
	reward.card_reward_button.pressed.emit()
	await settle()
	await get_tree().create_timer(0.6).timeout
	reward.picker.option_buttons[2].pressed.emit()
	await settle()
	check(same_view(result_id, reward_id) and int(reward.credits_label.text) >= intermediate, "card selection during credit animation retains counter progress")
	await get_tree().create_timer(1.0).timeout
	check(int(reward.credits_label.text) == before + amount and Game.state.credits == before + amount and Game.state.deck == [offers[2]], "concurrent card selection finishes the exact counter without duplicate model rewards")
	# A different receipt must still replace the result, even on the same page name.
	fixture("event")
	Game.changed.emit()
	await settle()
	check(app.view.get_instance_id() != result_id and app.view.reward_view.get_instance_id() != reward_id, "different reward identity rebuilds the result instead of reusing stale event content")
	check(app.view.reward_view.expected_revision == Game.revision and Game.state.activeEventId == "E01R", "replacement reward uses its current claim revision")

func test_early_exit_and_boss() -> void:
	await stage("battle")
	var reward: Control = app.view.reward_view
	var before: int = Game.state.credits
	var amount: int = Game.reward_credit_amount()
	reward.credits_reward_button.pressed.emit()
	await get_tree().create_timer(0.08).timeout
	var counter: WeakRef = weakref(reward.credits_label)
	reward.exit_button.pressed.emit()
	await settle()
	check(Game.page == "map" and counter.get_ref() == null and Game.state.credits == before + amount, "leaving mid-animation releases the counter while retaining already committed credits")
	await get_tree().create_timer(0.9).timeout
	check(Game.state.credits == before + amount and Game.state.battleReward.status == "skipped", "released animation cannot award more credits or claim an abandoned card")
	await stage("boss")
	reward = app.view.reward_view
	var result_id: int = app.view.get_instance_id()
	var reward_id: int = reward.get_instance_id()
	before = Game.state.credits
	amount = Game.reward_credit_amount()
	reward.credits_reward_button.pressed.emit()
	check(same_view(result_id, reward_id) and not Game.is_week_complete(), "Boss credit claim preserves the reward page and waits for explicit exit")
	check(reward.exit_button.text == "放弃卡牌并结束第一周 →", "Boss claim refresh retains the first-week exit action")
	reward.exit_button.pressed.emit()
	await settle()
	check(Game.is_week_complete() and Game.page == "result" and app.view.get_instance_id() != result_id, "Boss exit replaces same-name result route with week completion")
	check(is_instance_valid(app.view.week_end_view) and Game.state.credits == before + amount, "Boss completion shows the terminal view and retains claimed credits")

func _ready() -> void:
	if OS.get_user_data_dir().ends_with("/MidnightCommissionDemo"):
		push_error("Run reward refresh QA only in an isolated copied project/user directory")
		get_tree().quit(2)
		return
	get_tree().create_timer(90).timeout.connect(func(): push_error("REWARD REFRESH timeout");get_tree().quit(2))
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "user://reward-refresh-qa"
	DirAccess.make_dir_recursive_absolute(output)
	for rarity in ["B", "A", "S"]:
		for id in Game.card_catalog:
			if Game.card_catalog[id].get("rarity") == rarity:
				offers.append(id)
				break
	check(offers.size() == 3, "fixture uses three real reward cards")
	await test_credit_claim("battle")
	await test_credit_claim("event")
	await test_credit_claim("battle", true)
	await test_failure_and_card_first()
	await test_card_during_counter()
	await test_early_exit_and_boss()
	await remove_app()
	var file := FileAccess.open(output.path_join("reward-refresh-results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures, "records":records,
		"scope":"isolated headless UI identity, opacity, timed counter values and real reward callbacks; no GPU pixels or physical input"}, "\t"))
	file.close()
	print("REWARD REFRESH TESTS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
