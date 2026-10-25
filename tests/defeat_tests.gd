extends Node
## Headless flow/UI contract checks. Require an isolated copied project; no mouse events.
const OUTPUT := "res://artifacts/qa/defeat-2026-10-23/"
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var terminal_fixture: Dictionary = {}
var pending_fixture: Dictionary = {}
var adventure_fixture: Dictionary = {}
var app: Control

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message, "passed":ok})
	if not ok:
		failures.append(message)
		push_error("DEFEAT: " + message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func read_checkpoint() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	return parsed if parsed is Dictionary else {}

func write_fixture(path: String, value) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Open isolated fixture " + path.get_file())
	if file != null:
		file.store_string(JSON.stringify(value, "\t"))
		file.close()

func setup_case(label: String) -> void:
	Game.save_enabled = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.training_backup.clear()
	Game.save_path = OUTPUT + label + "-checkpoint.json"
	Game.meta_path = OUTPUT + label + "-meta.json"
	for path in [Game.save_path, Game.meta_path]:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	Game.state = Game.initial_state()
	Game.page = Game.state.currentScene

func begin_battle(label: String, battle_id: String, hp: int = 1) -> CombatModel:
	setup_case(label)
	Game.state.currentHp = hp
	Game.state.targetId = "richard"
	Game.state.activeEventId = Game.battles[battle_id].eventId
	Game.state.currentPlaceId = Game.battles[battle_id].placeId
	Game.save_enabled = true
	Game.enter_node("battle")
	check(Game.state.currentScene == "battle" and Game.state.battleId == battle_id, label + ": battle entered")
	check(not Game.state.battleStart.is_empty(), label + ": opening snapshot exists")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	return model

func lose_naturally(model: CombatModel, label: String) -> void:
	model.draw_cards()
	var turns := 0
	while model.outcome.is_empty() and turns < 24:
		model.end_turn()
		Game.commit_combat(model)
		turns += 1
	check(model.outcome == "lose" and model.player_hp == 0, label + ": actual enemy/status damage is lethal")
	check(turns < 24, label + ": lethal round reached within bounded fixture")
	check(Game.state.currentHp == 0 and Game.state.combat.outcome == "lose", label + ": actual terminal model committed")

func assert_ended(label: String) -> void:
	check(Game.state.currentScene == "defeat" and Game.page == "defeat" and Game.state.result == "lose", label + ": dedicated defeat page")
	check(Game.state.battleStart.is_empty() and Game.state.battleReward.is_empty(), label + ": no restart snapshot or card reward")
	check(Game.is_run_over() and not Game.can_continue(), label + ": run over and continue unavailable")

func test_all_battles() -> void:
	check(Game.battles.size() == 7 and Game.battles.has("B16"), "Fixture covers six normal battles and the day-seven Boss")
	for battle_id in Game.battles:
		var label := "loss-" + str(battle_id)
		var model := begin_battle(label, battle_id)
		var original := Game.state.duplicate(true)
		lose_naturally(model, label)
		check(Game.is_run_over() and not Game.can_continue(), label + ": lethal playback interval cannot continue")
		var projected := read_checkpoint()
		check(projected.currentScene == "defeat" and projected.result == "lose" and projected.battleStart.is_empty() and projected.battleReward.is_empty(), label + ": lethal commit projects terminal disk state before animation exits")
		check(projected.currentHp == 0 and same(projected.combat, model.snapshot()), label + ": projected terminal disk keeps actual lethal combat")
		check(projected.battleHistory.size() == original.battleHistory.size() + 1, label + ": projected terminal disk records one loss")
		check(Game.state.currentScene == "battle" and Game.state.result.is_empty() and Game.state.battleHistory == original.battleHistory and not Game.state.battleStart.is_empty(), label + ": terminal save projection preserves live playback state")
		if battle_id == "B02": pending_fixture = Game.state.duplicate(true)
		var request_revision := Game.revision
		var before := Game.state.duplicate(true)
		check(not Game.battle_exit("win", request_revision) and same(Game.state, before), label + ": lethal snapshot cannot forge a victory")
		check(not Game.battle_exit("lose", request_revision - 1) and same(Game.state, before), label + ": stale revision is rejected atomically")
		Game.battle_busy = true
		check(not Game.battle_exit("lose", request_revision), label + ": animation lock blocks premature exit")
		Game.battle_busy = false
		Game.transition_locked = true
		check(not Game.battle_exit("lose", request_revision), label + ": transition lock blocks exit")
		Game.transition_locked = false
		check(Game.battle_exit("lose", request_revision), label + ": loss commits successfully")
		assert_ended(label)
		check(Game.state.battleHistory.size() == original.battleHistory.size() + 1 and Game.state.battleHistory.back() == {"battleId":battle_id, "result":"lose"}, label + ": battle history records exactly one loss")
		check(Game.state.dialogueHistory == original.dialogueHistory and Game.state.activeNodeId != "lose", label + ": authored loss dialogue is never entered or logged")
		check(Game.state.credits == original.credits and Game.state.deck == original.deck and Game.state.claimedRewardIds == original.claimedRewardIds, label + ": loss gives no credits or cards")
		check(Game.state.currentDay == original.currentDay and Game.state.completedEventIds == original.completedEventIds, label + ": loss does not complete event or advance day")
		var ended := Game.state.duplicate(true)
		check(not Game.battle_exit("lose", Game.revision) and not Game.battle_exit("lose", request_revision), label + ": duplicate loss commits rejected")
		check(same(Game.state, ended), label + ": duplicates do not alter terminal state")
		check(Game.valid_save(read_checkpoint()), label + ": defeat checkpoint validates")
		check(same(read_checkpoint(), ended), label + ": terminal checkpoint saves exact state")
		if battle_id == "B02": terminal_fixture = ended.duplicate(true)
		Game.menu()
		check(Game.page == "menu" and same(Game.state, ended), label + ": menu keeps terminal state")
		Game.resume()
		assert_ended(label + " warm resume")
		Game.state = {}
		check(not Game.can_continue(), label + ": disk-only terminal cannot continue")
		check(Game.load_game(), label + ": terminal save remains readable")
		assert_ended(label + " cold load")

func assert_navigation_blocked(subject: Dictionary, label: String) -> void:
	Game.state = subject.duplicate(true)
	Game.page = Game.state.currentScene
	Game.state.completedEventIds = ["E01"]
	Game.state.refreshedEventIds = ["E02"]
	var before := Game.state.duplicate(true)
	var revision := Game.revision
	Game.go_map()
	check(same(Game.state, before) and Game.revision == revision, label + ": go_map cannot revive run")
	Game.visit("bar")
	check(same(Game.state, before) and Game.revision == revision, label + ": visit cannot bypass terminal state")
	var candidate := "E02" if not "E02" in before.completedEventIds else "E04"
	check(not Game.start_event(candidate) and same(Game.state, before), label + ": start_event rejects terminal run")
	for node_id in ["@map", "intro_01", "lose", "battle", "finish"]:
		Game.enter_node(node_id)
		check(same(Game.state, before) and Game.revision == revision, label + ": enter_node blocks " + node_id)
	check(not Game.choose(0, Game.revision), label + ": no loss choice can return to map")
	check(not Game.claim_rewards(Game.revision), label + ": cannot claim result rewards")
	check(not Game.choose_reward_card("noren_01", Game.revision), label + ": cannot claim cards")

func test_terminal_detection_and_navigation() -> void:
	setup_case("navigation")
	for subject in [terminal_fixture, pending_fixture]:
		assert_navigation_blocked(subject, "committed" if subject.currentScene == "defeat" else "pending lethal")
	for fixture in [{"currentScene":"defeat"}, {"currentScene":"map", "result":"lose"}, {"currentScene":"battle", "combat":{"outcome":"lose"}}]:
		check(Game.is_run_over(fixture), "Terminal predicate detects " + JSON.stringify(fixture))
	for fixture in [{"currentScene":"map"}, {"currentScene":"battle", "combat":{"outcome":""}}, {"currentScene":"result", "result":"win"}]:
		check(not Game.is_run_over(fixture), "Terminal predicate excludes " + JSON.stringify(fixture))

func test_pending_navigation() -> void:
	for route in ["menu", "resume"]:
		setup_case("pending-" + route)
		Game.state = pending_fixture.duplicate(true)
		Game.page = "battle"
		var previous_count: int = Game.state.battleHistory.size()
		if route == "menu":
			Game.menu()
			check(Game.page == "menu" and Game.state.currentScene == "defeat", "Pending lethal menu return canonicalizes terminal state")
		Game.resume()
		assert_ended("pending " + route)
		check(Game.state.currentHp == 0 and Game.state.battleHistory.size() == previous_count + 1, "Pending " + route + " never restores opening HP or duplicates history")
		Game.menu()
		Game.resume()
		check(Game.state.battleHistory.size() == previous_count + 1, "Repeated pending " + route + " is idempotent")

func test_pending_load_and_migration() -> void:
	setup_case("migration")
	var legacy_dialogue := terminal_fixture.duplicate(true)
	legacy_dialogue.currentScene = "dialogue"
	legacy_dialogue.activeNodeId = "lose"
	var legacy_map := legacy_dialogue.duplicate(true)
	legacy_map.currentScene = "map"
	for fixture in [pending_fixture, legacy_dialogue, legacy_map, terminal_fixture]:
		var before: Dictionary = fixture.duplicate(true)
		var migrated: Dictionary = Game.migrate_save(fixture)
		check(same(fixture, before), "Loss migration leaves source fixture unchanged")
		check(migrated.currentScene == "defeat" and migrated.result == "lose" and migrated.battleStart.is_empty() and migrated.battleReward.is_empty(), "Loss migration normalizes battle/dialogue/page to defeat")
		check(Game.valid_save(migrated), "Migrated terminal checkpoint validates")
		check(same(Game.migrate_save(migrated), migrated), "Terminal migration is idempotent")
		write_fixture(Game.save_path, fixture)
		Game.state = {}
		Game.page = "menu"
		check(not Game.can_continue(), "Disk legacy/terminal save cannot continue")
		Game.resume()
		assert_ended("legacy cold resume")
		check(Game.state.combat.outcome == "lose" and Game.state.currentHp == 0, "Loading pending lethal save never restarts its opening HP")
		var count: int = Game.state.battleHistory.size()
		Game.menu()
		Game.resume()
		check(Game.state.battleHistory.size() == count, "Repeated legacy resume never appends duplicate loss history")

func test_can_continue() -> void:
	setup_case("can-continue")
	Game.state = {}
	check(not Game.can_continue(), "No memory and no disk cannot continue")
	write_fixture(Game.save_path, {"broken":true})
	check(Game.can_continue(), "Damaged file preserves existing continue-to-error behavior")
	Game.state = Game.initial_state()
	check(Game.can_continue(), "Fresh active adventure can continue")
	adventure_fixture = Game.state.duplicate(true)
	write_fixture(Game.save_path, adventure_fixture)
	Game.state = {}
	check(Game.can_continue(), "Valid disk-only active adventure can continue")
	write_fixture(Game.save_path, terminal_fixture)
	write_fixture(Game.save_path + ".bak", adventure_fixture)
	check(not Game.can_continue(), "Terminal primary is authoritative over an older active backup")
	check(Game.state.is_empty(), "Disk eligibility query never loads adventure into memory")
	Game.state = terminal_fixture.duplicate(true)
	write_fixture(Game.save_path, adventure_fixture)
	check(not Game.can_continue(), "Terminal memory cannot be overridden by an older active disk save")

func finish_story() -> void:
	var steps := 0
	while Game.state.currentScene == "dialogue" and Game.node_data().has("next") and steps < 100:
		Game.advance(Game.revision)
		steps += 1
	check(steps < 100, "Victory story terminates")

func test_victory_training_new_game() -> void:
	var model := begin_battle("victory", "B02", 63)
	check(model.enemies[0].maxHp == 40, "Victory fixture uses the current authored robot")
	model.draw_cards()
	var rounds := 0
	while model.outcome.is_empty() and rounds < 20:
		for uid in model.hand.duplicate():
			if model.outcome.is_empty() and model.card(uid).type == "attack": model.play_card(uid, 0)
		for uid in model.hand.duplicate():
			if model.outcome.is_empty() and model.card(uid).id == "noren_02": model.play_card(uid, -1)
		if model.outcome.is_empty(): model.end_turn()
		rounds += 1
	check(model.outcome == "win" and rounds < 20, "Victory regression reaches real B02 win through legal turns")
	Game.commit_combat(model)
	check(not Game.is_run_over() and Game.can_continue(), "Winning battle is resumable")
	check(Game.battle_exit("win", Game.revision) and Game.state.currentScene == "dialogue", "Victory retains authored post-battle story")
	finish_story()
	check(Game.page == "result" and Game.has_battle_reward() and Game.state.credits == int(Game.config.initialCredits) and Game.reward_credits_status() == "pending", "Victory still offers unpaid credits and cards")
	var credit_amount: int = Game.reward_credit_amount()
	check(credit_amount >= 40 and credit_amount <= 60, "Victory reward base stays within 40–60")
	check(Game.claim_reward_credits(Game.revision) and Game.state.credits == int(Game.config.initialCredits) + credit_amount, "Victory credits remain manually claimable")
	var options: Array = Game.state.battleReward.options.duplicate()
	check(Game.choose_reward_card(options[0], Game.revision), "Victory card remains claimable")
	check(not Game.choose_reward_card(options[1], Game.revision), "Victory rewards still claimed once")
	setup_case("training")
	Game.state = adventure_fixture.duplicate(true)
	Game.save_enabled = true
	check(Game.save_game(), "Persist active adventure before training")
	var original := Game.state.duplicate(true)
	var disk_before := FileAccess.get_file_as_bytes(Game.save_path)
	Game.start_training("B02")
	var practice := CombatModel.new()
	practice.restore(Game.state.combat)
	lose_naturally(practice, "training")
	check(Game.battle_exit("lose", Game.revision), "Training accepts actual lethal result")
	check(not Game.training_mode and Game.page == "menu" and same(Game.state, original), "Training loss restores exact adventure to menu")
	check(Game.can_continue() and FileAccess.get_file_as_bytes(Game.save_path) == disk_before, "Training loss leaves resumable adventure disk unchanged")
	Game.state = terminal_fixture.duplicate(true)
	Game.page = "defeat"
	Game.new_game()
	check(not Game.is_run_over() and Game.can_continue(), "New game resets defeat and re-enables continue")
	check(Game.page == "dialogue" and Game.state.activeEventId == "E01" and Game.state.currentHp == Game.state.maxHp, "New game starts full HP intro")
	check(Game.state.result.is_empty() and Game.state.battleHistory.is_empty() and Game.state.battleStart.is_empty() and Game.state.battleReward.is_empty(), "New game clears all terminal history and battle data")
	check(Game.valid_save(read_checkpoint()), "New game overwrites terminal checkpoint with valid adventure")

func key(code: Key, shift: bool = false, ctrl: bool = false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		event.shift_pressed = shift
		event.ctrl_pressed = ctrl
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await get_tree().process_frame

func check_layout(defeat: Control) -> void:
	for window_size in [Vector2i(1280, 800), Vector2i(1600, 1000)]:
		get_window().size = window_size
		await get_tree().process_frame
		await get_tree().process_frame
		var canvas := Rect2(Vector2.ZERO, Vector2(1440, 900))
		for node_name in ["game_over_label", "defeat_title", "defeat_message", "defeat_hint", "return_to_menu", "defeat_context"]:
			var control := defeat.find_child(node_name, true, false) as Control
			check(is_instance_valid(control), "Layout control exists: " + node_name)
			if not is_instance_valid(control): continue
			check(canvas.encloses(control.get_global_rect()), "%s stays inside logical 1440x900 at %s" % [node_name, window_size])
			var minimum := control.get_combined_minimum_size()
			check(minimum.x <= control.size.x and minimum.y <= control.size.y, "%s content minimum fits at %s" % [node_name, window_size])
			if control is Button: check(control.size.y >= 48, "Return button retains at least 48 logical pixels height")

func test_ui() -> void:
	setup_case("ui")
	Game.state = terminal_fixture.duplicate(true)
	Game.page = "defeat"
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	await get_tree().process_frame
	check(app.shown_page == "defeat" and app.view is DemoUI, "Main route renders dedicated DemoUI defeat scene")
	var defeat: Control = app.view
	var buttons: Array[Node] = defeat.find_children("*", "BaseButton", true, false)
	check(buttons.size() == 1, "Defeat UI exposes exactly one button")
	var back := defeat.find_child("return_to_menu", true, false) as Button
	check(is_instance_valid(back) and back.text.begins_with("返回主菜单"), "Defeat sole action is return_to_menu")
	check(defeat.hp_fill == null and defeat.hp_label == null and defeat.credits_label == null, "Defeat scene omits HP/credit status bar")
	await check_layout(defeat)
	if is_instance_valid(back):
		check(not back.disabled and back.focus_mode == Control.FOCUS_ALL and get_viewport().gui_get_focus_owner() == back, "Return button starts enabled and keyboard focused")
		for shift in [false, true]:
			await key(KEY_TAB, shift)
			check(get_viewport().gui_get_focus_owner() == back, "Tab stays on sole return button, shift=" + str(shift))
		await key(KEY_F1)
		await key(KEY_A, true, true)
		check(not is_instance_valid(app.debug_panel) and not is_instance_valid(app.card_console), "Defeat blocks developer menu and card console shortcuts")
		await key(KEY_ENTER)
		check(Game.page == "menu" and not is_instance_valid(app.exit_dialog), "Keyboard return goes directly to menu without confirmation")
		check(app.view.continue_button.disabled and app.view.continue_button.focus_mode == Control.FOCUS_NONE, "Menu disables terminal continue and removes its keyboard focus")
		check(get_viewport().gui_get_focus_owner() == app.view.new_button, "Menu focuses new commission after defeat")
		await key(KEY_ESCAPE)
		check(Game.page == "menu" and not is_instance_valid(app.exit_dialog), "Menu Escape cannot resume terminal run")
		Game.state = terminal_fixture.duplicate(true)
		Game.page = "defeat"
		Game.changed.emit()
		await get_tree().process_frame
		await key(KEY_ESCAPE)
		check(Game.page == "menu" and not is_instance_valid(app.exit_dialog) and Game.state.currentScene == "defeat", "Defeat Escape returns directly to menu without confirmation")
		Game.state = {}
		write_fixture(Game.save_path, terminal_fixture)
		Game.changed.emit()
		await get_tree().process_frame
		check(app.view.continue_button.disabled, "Disk-only terminal save disables menu continue")
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _ready() -> void:
	if not "defeat-2026-10-23" in OS.get_user_data_dir():
		push_error("Run only in an isolated copied project with defeat-2026-10-23 custom user directory")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	Game.save_enabled = false
	Game.save_path = OUTPUT + "unused-checkpoint.json"
	Game.meta_path = OUTPUT + "unused-meta.json"
	get_tree().create_timer(60).timeout.connect(func(): push_error("DEFEAT timeout"); get_tree().quit(2))
	seed(20261023)
	test_all_battles()
	test_terminal_detection_and_navigation()
	test_pending_navigation()
	test_pending_load_and_migration()
	test_can_continue()
	test_victory_training_new_game()
	await test_ui()
	Game.save_enabled = false
	var report := {"checks":checks, "failures":failures, "records":records, "userDataDirectory":OS.get_user_data_dir(), "savePath":Game.save_path, "scope":"isolated headless model/flow/persistence and synthetic keyboard focus; no visible window, mouse movement, screenshots, physical-input or visual acceptance"}
	var file := FileAccess.open(OUTPUT + "defeat-results.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	print("DEFEAT TESTS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
