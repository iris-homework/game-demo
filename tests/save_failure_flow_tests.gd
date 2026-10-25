extends Node
## Run headlessly in an isolated project/user directory only.
var checks := 0
var failures := 0
var messages: Array[String] = []
var changed_count := 0
const SAVE := "user://save-failure-flow.json"
const BLOCKED := "user://save-failure-blocker/checkpoint.json"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func same(a, b) -> bool:
	return JSON.stringify(a) == JSON.stringify(b)

func fresh() -> void:
	Game.save_enabled = false
	Game.pending_save_kind = ""
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.save_path = SAVE
	Game.meta_path = "user://save-failure-meta.json"
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.page = "map"
	messages.clear()
	changed_count = 0

func block_writes() -> void:
	Game.save_path = BLOCKED
	Game.save_enabled = true
	messages.clear()
	changed_count = 0

func retry() -> bool:
	Game.save_path = SAVE
	return Game.retry_pending_save()

func test_heal() -> void:
	fresh()
	Game.state.currentHp = 40
	Game.state.credits = 300
	check(Game.save_game(), "Healing baseline saves")
	var disk := FileAccess.get_file_as_string(SAVE)
	var healed_hp := 40 + roundi(Game.state.maxHp * 0.3)
	block_writes()
	check(not Game.heal_at("clinic"), "Failed healing checkpoint does not report success")
	check(Game.pending_save_kind == "scene" and Game.state.currentHp == healed_hp and Game.state.credits == 150, "One healing payment and effect retained for retry")
	check(changed_count == 0 and not messages.any(func(m): return "生命恢复" in m), "No page or success message before persistence")
	check(FileAccess.get_file_as_string(SAVE) == disk, "Failed write preserves old disk checkpoint")
	check(not Game.heal_at("clinic"), "Pending healing cannot be repeated")
	Game.visit("bar")
	Game.new_game()
	Game.menu()
	check(Game.state.currentHp == healed_hp and Game.state.credits == 150 and Game.page == "map", "Navigation and new game cannot discard unsaved effects")
	check(not Game.retry_pending_save() and Game.pending_save_kind == "scene", "Repeated storage failure retains pending operation")
	check(retry(), "Healing retry succeeds after storage recovery")
	check(changed_count == 1 and Game.pending_save_kind.is_empty(), "Successful retry publishes one refreshed page")
	check(Game.state.currentHp == healed_hp and Game.state.credits == 150, "Retry never repeats charge or healing")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	check(saved.currentHp == healed_hp and saved.credits == 150 and Game.valid_save(saved), "Recovered healing persists a valid checkpoint")
	check(not Game.retry_pending_save(), "Duplicate retry is a no-op")

func test_dialogue_reward() -> void:
	fresh()
	Game.state.activeEventId = "E02"
	Game.state.currentPlaceId = "junkyard"
	Game.state.battleId = "B02"
	Game.state.result = "win"
	Game.state.battleHistory = [{"battleId":"B02", "result":"win"}]
	for node in Game.events.E02.nodes.values():
		if node.get("next", "") == "finish": Game.state.activeNodeId = node.id
	Game.state.currentScene = "dialogue"
	Game.page = "dialogue"
	var credits: int = Game.state.credits
	var day: int = Game.state.currentDay
	block_writes()
	Game.skip_dialogue(Game.revision)
	check(Game.pending_save_kind == "scene" and Game.page == "dialogue", "Failed finish stays behind the save gate")
	check(Game.state.currentScene == "result" and Game.state.currentDay == day + 1 and Game.state.credits == credits and Game.reward_credits_status() == "pending", "Completion/day and unpaid reward resolve exactly once")
	var pending := Game.state.duplicate(true)
	Game.skip_dialogue(Game.revision)
	Game.claim_rewards(Game.revision)
	check(not Game.claim_reward_credits(Game.revision), "Pending completion save also blocks credit claim")
	check(same(Game.state,pending), "Skip/claim cannot bypass failed completion checkpoint")
	check(retry() and Game.page == "result", "Retry resumes the reward page")
	check(same(Game.state,pending), "Retry preserves original card offers, day and money")
	check(Game.valid_save(JSON.parse_string(FileAccess.get_file_as_string(SAVE))), "Recovered reward checkpoint validates")

func test_new_and_defeat() -> void:
	fresh()
	Game.page = "menu"
	block_writes()
	Game.new_game()
	check(Game.pending_save_kind == "scene" and Game.page == "menu", "New adventure waits for its first checkpoint")
	var opening := Game.state.duplicate(true)
	Game.new_game()
	check(same(Game.state, opening), "Repeated new-game input cannot reroll the pending adventure")
	check(retry() and Game.page == "dialogue", "First checkpoint retry enters the authored introduction")
	var previous_node: String = Game.state.activeNodeId
	block_writes()
	Game.advance(Game.revision)
	check(Game.pending_save_kind == "scene" and Game.state.activeNodeId != previous_node, "Ordinary dialogue advances once and stops at failed checkpoint")
	var advanced := Game.state.duplicate(true)
	Game.advance(Game.revision)
	check(same(Game.state, advanced), "Repeated dialogue input cannot run ahead of a failed save")
	check(retry() and same(Game.state, advanced), "Dialogue retry keeps the exact node and history")
	fresh()
	Game.state.activeEventId = "E02"
	Game.state.currentPlaceId = "junkyard"
	Game.enter_node("battle")
	block_writes()
	check(not Game.battle_exit("lose", Game.revision), "Defeat checkpoint failure is returned to caller")
	check(Game.is_run_over() and Game.pending_save_kind == "scene", "Failed save cannot revive a defeated run")
	check(retry() and Game.page == "defeat" and not Game.can_continue(), "Retry persists the terminal defeat and displays its page")
	check(Game.state.battleHistory.size() == 1 and Game.valid_save(JSON.parse_string(FileAccess.get_file_as_string(SAVE))), "Defeat history is recorded once and saved validly")

func test_real_modal_and_combat() -> void:
	fresh()
	var main := preload("res://scripts/main.gd").new()
	add_child(main)
	Game.state.currentHp = 40
	Game.state.credits = 150
	block_writes()
	Game.heal_at("clinic")
	check(is_instance_valid(main.save_dialog) and main.view.process_mode == Node.PROCESS_MODE_DISABLED, "Real main view opens blocking save modal and suspends background")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	main._input(escape)
	check(is_instance_valid(main.save_dialog), "Escape cannot silently dismiss a failed save")
	main.save_retry.pressed.emit()
	check(is_instance_valid(main.save_dialog), "Retry failure keeps modal visible")
	Game.save_path = SAVE
	main.save_retry.pressed.emit()
	check(main.save_dialog == null and main.view.process_mode != Node.PROCESS_MODE_DISABLED, "Retry success closes modal and restores page processing")
	remove_child(main)
	main.free()
	fresh()
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.enter_node("battle")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	model.draw_cards(10)
	Game.commit_combat(model)
	main = preload("res://scripts/main.gd").new()
	add_child(main)
	var view = main.view
	for i in 300:
		if view.initialized and not Game.battle_busy: break
		await get_tree().process_frame
	check(view.initialized and not Game.battle_busy, "Real battle view becomes ready headlessly")
	var uid := ""
	for candidate in view.model.hand:
		if view.model.card(candidate).type == "attack" and view.model.play_error(candidate).is_empty():
			uid = candidate
			break
	check(not uid.is_empty(), "Fixture has playable attack")
	if not uid.is_empty():
		var hp_before: int = view.model.enemies[0].hp
		block_writes()
		view.selected_uid = uid
		view.play_selected(0)
		check(Game.pending_save_kind == "combat" and is_instance_valid(main.save_dialog), "Combat commit failure opens same save gate")
		var resolved = view.model.snapshot()
		check(view.model.enemies[0].hp < hp_before and Game.battle_busy, "Attack resolves once and waits before presentation")
		await get_tree().create_timer(0.1).timeout
		check(same(view.model.snapshot(),resolved) and Game.pending_save_kind == "combat", "Waiting does not repeat damage or proceed to another action")
		Game.save_path = SAVE
		main.save_retry.pressed.emit()
		for i in 1200:
			if not Game.battle_busy: break
			await get_tree().process_frame
		check(Game.pending_save_kind.is_empty() and main.save_dialog == null and not Game.battle_busy, "Successful retry resumes and completes the suspended animation")
		check(same(view.model.snapshot(),resolved), "Presentation after retry does not replay model action")
		check(Game.valid_save(JSON.parse_string(FileAccess.get_file_as_string(SAVE))), "Combat retry persists a valid opening recovery checkpoint")
	Game.save_enabled = false
	check(await preload("res://scripts/combat/audio_cleanup.gd").release(main, get_tree()), "Stopped combat audio is released before shutdown")
	remove_child(main)
	main.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	Game.notice.connect(func(message): messages.append(message))
	Game.changed.connect(func(): changed_count += 1)
	var blocker := FileAccess.open("user://save-failure-blocker", FileAccess.WRITE)
	blocker.store_string("deterministic write failure")
	blocker.close()
	test_heal()
	test_dialogue_reward()
	test_new_and_defeat()
	await test_real_modal_and_combat()
	print("SAVE FAILURE FLOW: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
