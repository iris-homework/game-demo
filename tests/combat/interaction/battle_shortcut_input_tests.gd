extends Node
## Copy-only regression: real main/Battle and viewport key press/release events.
## No direct input-handler calls, system pointer movement, or production saves.
const Cleanup := preload("res://scripts/combat/audio_cleanup.gd")
const USER_DIR_MARKER := "battle-shortcut-qa"
var app: Control
var output := ""
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var native_end_down := 0
var native_end_pressed := 0
var picks: Array = []

func check(ok: bool, message: String) -> bool:
	checks += 1
	records.append({"check":message, "passed":ok})
	if not ok:
		failures.append(message)
		push_error("BATTLE SHORTCUT INPUT: " + message)
	return ok

func observe(label: String) -> void:
	var view = app.view
	records.append({"event":label, "turn":view.model.turn, "selected":view.selected_uid,
		"endHasFocus":view.end_button.has_focus(), "endIsPressed":view.end_button.button_pressed,
		"nativeEndDown":native_end_down, "nativeEndPressed":native_end_pressed, "busy":Game.battle_busy})

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func wait_ready(condition: Callable, seconds := 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not Game.transition_locked and not Game.battle_busy and condition.call():
			await settle()
			if not Game.transition_locked and not Game.battle_busy: return true
		await get_tree().create_timer(0.02, true, false, true).timeout
	return false

func key_event(code: Key, down: bool, shift := false, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	event.shift_pressed = shift
	event.echo = echo
	get_viewport().push_input(event, true)
	await settle()

func key(code: Key) -> void:
	await key_event(code, true)
	await key_event(code, false)

func fresh_battle() -> bool:
	if not await wait_ready(func(): return is_instance_valid(app.view)):
		return check(false, "previous UI becomes idle before a new fixture")
	if is_instance_valid(app.exit_dialog): app.close_exit_confirmation()
	if Game.page != "menu":
		Game.menu()
		if not await wait_ready(func(): return Game.page == "menu" and is_instance_valid(app.view)):
			return check(false, "training returns to menu before reset")
	check(PlayerSettings.reset_defaults(), "fixture resets only isolated key settings")
	Game.start_training("B04")
	var ready := await wait_ready(func(): return Game.page == "battle" and is_instance_valid(app.view) and app.view.initialized)
	if not check(ready, "real B04 battle finishes initialization"): return false
	native_end_down = 0
	native_end_pressed = 0
	app.view.end_button.button_down.connect(func(): native_end_down += 1)
	app.view.end_button.pressed.connect(func(): native_end_pressed += 1)
	return check(not app.view.model.hand.is_empty(), "training supplies a real initial hand")

func focus_end_after_pile() -> bool:
	var view = app.view
	view.cancel_selection()
	view.show_pile("抽牌堆", view.model.draw_pile)
	await settle()
	if not check(is_instance_valid(view.pile_overlay), "draw pile opens through battle UI"): return false
	view.pile_overlay.close_button.pressed.emit()
	await settle()
	return check(not is_instance_valid(view.pile_overlay) and view.end_button.has_focus(), "closing pile leaves native End Turn focused")

func test_default_hand_keys() -> void:
	if not await fresh_battle() or not await focus_end_after_pile(): return
	var view = app.view
	var before: Dictionary = view.model.snapshot()
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
	var keypad := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5]
	for codes in [keys, keypad]:
		for i in mini(view.model.hand.size(), codes.size()):
			await key_event(codes[i], true)
			check(view.selected_uid == view.model.hand[i], "default hand key selects on press: " + OS.get_keycode_string(codes[i]))
			await key_event(codes[i], false)
			check(view.model.snapshot() == before and native_end_down == 0 and native_end_pressed == 0, "default hand key release never activates focused End Turn: " + OS.get_keycode_string(codes[i]))
	observe("default_hand_keys")

func test_space_select_and_missing_slot() -> void:
	if not await fresh_battle() or not await focus_end_after_pile(): return
	var view = app.view
	check(PlayerSettings.bind_key("hand_1", KEY_SPACE).is_empty(), "Space can bind to first hand slot")
	var before: Dictionary = view.model.snapshot()
	var uid: String = view.model.hand[0]
	await key_event(KEY_SPACE, true)
	check(view.selected_uid == uid and view.model.snapshot() == before, "Space selects first card on press without playing it")
	check(not view.end_button.button_pressed and native_end_down == 0, "bound Space press never arms native End Turn")
	observe("space_hand_down")
	await key_event(KEY_SPACE, true, false, true)
	check(view.selected_uid == uid and view.model.snapshot() == before and native_end_down == 0, "Space echo is consumed without GUI activation or repeated selection")
	await key_event(KEY_SPACE, false)
	await wait_ready(func(): return view.initialized)
	check(view.selected_uid == uid and view.model.snapshot() == before and native_end_pressed == 0, "Space release preserves selection and never ends the turn")
	observe("space_hand_up")
	# Use a fresh fixture so the original defect cannot contaminate later checks.
	if not await fresh_battle() or not await focus_end_after_pile(): return
	view = app.view
	check(PlayerSettings.bind_key("hand_1", KEY_SPACE).is_empty(), "Space rebind for changed-modifier release")
	before = view.model.snapshot()
	await key_event(KEY_SPACE, true)
	await key_event(KEY_SPACE, false, true)
	await wait_ready(func(): return view.initialized)
	check(view.model.snapshot() == before and native_end_down == 0 and native_end_pressed == 0, "release is consumed even when Shift was pressed after the shortcut key")
	await key(KEY_SPACE)
	check(view.selected_uid == view.model.hand[0] and view.model.snapshot() == before, "changed-modifier release does not leave a stale held shortcut")
	if not await fresh_battle() or not await focus_end_after_pile(): return
	view = app.view
	check(view.model.hand.size() < 10 and PlayerSettings.bind_key("hand_10", KEY_SPACE).is_empty(), "Space can bind to currently absent tenth hand slot")
	before = view.model.snapshot()
	await key_event(KEY_SPACE, true)
	check(view.selected_uid.is_empty() and not view.end_button.button_pressed and native_end_down == 0, "absent hand slot still consumes Space press before native GUI")
	await key_event(KEY_SPACE, false)
	await wait_ready(func(): return view.initialized)
	check(view.model.snapshot() == before and native_end_pressed == 0, "absent hand slot is a no-op on release, not End Turn")

func test_space_end_turn() -> void:
	if not await fresh_battle() or not await focus_end_after_pile(): return
	var view = app.view
	check(PlayerSettings.bind_key("end_turn", KEY_SPACE).is_empty(), "Space can explicitly bind to End Turn")
	var previous_turn: int = view.model.turn
	await key_event(KEY_SPACE, true)
	check(Game.battle_busy and not view.end_button.button_pressed and native_end_down == 0, "explicit Space shortcut starts enemy turn on press without native button arming")
	var ready := await wait_ready(func(): return view.model.turn > previous_turn)
	check(ready and view.model.turn == previous_turn + 1, "held Space executes exactly one full enemy turn")
	var after: Dictionary = view.model.snapshot()
	await key_event(KEY_SPACE, true, false, true)
	await key_event(KEY_SPACE, false)
	await wait_ready(func(): return view.initialized)
	check(view.model.snapshot() == after and native_end_pressed == 0, "echo and delayed release after animation never execute a second turn")
	observe("space_end_turn_released_after_animation")

func test_modal_confirmation() -> void:
	if not await fresh_battle(): return
	var view = app.view
	for binding in ["hand_1", "end_turn"]:
		PlayerSettings.reset_defaults()
		check(PlayerSettings.bind_key(binding, KEY_SPACE).is_empty(), "Space binding before choice modal: " + binding)
		view.cancel_selection()
		var before: Dictionary = view.model.snapshot()
		var count := picks.size()
		view.show_card_choice("快捷键隔离", [{"text":"确认候选", "value":binding}], func(value): picks.append(value))
		await settle()
		var picker = view.pile_overlay
		check(picker.option_buttons[0].has_focus(), "choice modal owns initial keyboard focus")
		await key(KEY_SPACE)
		check(picks.size() == count + 1 and picks.back() == binding and not is_instance_valid(view.pile_overlay), "Space still confirms focused modal candidate once: " + binding)
		check(view.model.snapshot() == before and view.selected_uid.is_empty() and native_end_pressed == 0, "modal confirmation never executes underlying shortcut: " + binding)
	# Main-owned confirmation pauses Battle; its native cancel button must still work.
	var before: Dictionary = view.model.snapshot()
	Game.request_menu()
	await settle()
	check(is_instance_valid(app.exit_dialog) and app.exit_cancel.has_focus(), "main exit confirmation owns focus and pauses Battle")
	await key(KEY_SPACE)
	check(not is_instance_valid(app.exit_dialog) and Game.page == "battle" and view.model.snapshot() == before, "Space cancels main modal without executing bound End Turn")

func test_release_after_modal_open() -> void:
	for action in ["draw_pile", "technology"]:
		if not await fresh_battle() or not await focus_end_after_pile(): return
		var view = app.view
		check(PlayerSettings.bind_key(action, KEY_SPACE).is_empty(), "Space binds modal-opening action: " + action)
		var before: Dictionary = view.model.snapshot()
		await key_event(KEY_SPACE, true)
		if not check(is_instance_valid(view.pile_overlay), "Space press opens expected modal: " + action):
			await key_event(KEY_SPACE, false)
			continue
		var overlay = view.pile_overlay
		check(overlay.close_button.has_focus() and not overlay.close_button.button_pressed and native_end_down == 0, "opening press cannot arm newly focused modal Close or underlying End Turn: " + action)
		await key_event(KEY_SPACE, false)
		check(is_instance_valid(overlay) and view.pile_overlay == overlay and view.model.snapshot() == before, "same key release does not confirm or close newly opened modal: " + action)
		await key(KEY_ESCAPE)
		check(not is_instance_valid(view.pile_overlay) and view.model.snapshot() == before, "modal keeps its own Escape handling: " + action)

func test_release_while_battle_paused() -> void:
	if not await fresh_battle() or not await focus_end_after_pile(): return
	var view = app.view
	check(PlayerSettings.bind_key("hand_1", KEY_SPACE).is_empty(), "Space binds hand for pause/release regression")
	var before: Dictionary = view.model.snapshot()
	await key_event(KEY_SPACE, true)
	check(view.selected_uid == view.model.hand[0], "Space press selects before Battle is paused")
	Game.request_menu()
	await settle()
	check(is_instance_valid(app.exit_dialog) and view.process_mode == Node.PROCESS_MODE_DISABLED, "main confirmation pauses the view while Space remains held")
	await key_event(KEY_SPACE, false)
	check(is_instance_valid(app.exit_dialog) and view.model.snapshot() == before, "release while paused cannot confirm a dialog that never received its press")
	await key(KEY_ENTER)
	check(not is_instance_valid(app.exit_dialog) and Game.page == "battle", "Enter cancels the main confirmation normally")
	view.end_button.grab_focus()
	await key(KEY_SPACE)
	await wait_ready(func(): return view.initialized)
	check(view.selected_uid == view.model.hand[0] and view.model.snapshot() == before and native_end_down == 0 and native_end_pressed == 0, "next Space selects normally after a release missed by the paused view")

func test_unbound_native_accept() -> void:
	for code in [KEY_SPACE, KEY_ENTER]:
		if not await fresh_battle() or not await focus_end_after_pile(): return
		var view = app.view
		var previous_turn: int = view.model.turn
		await key_event(code, true)
		check(view.end_button.button_pressed and native_end_down == 1 and not Game.battle_busy, "unbound accept retains native focused button press: " + OS.get_keycode_string(code))
		await key_event(code, false)
		var ready := await wait_ready(func(): return view.model.turn > previous_turn)
		check(ready and view.model.turn == previous_turn + 1 and native_end_pressed == 1, "unbound accept confirms native focused End Turn once: " + OS.get_keycode_string(code))

func _ready() -> void:
	var user_dir := OS.get_user_data_dir()
	var project_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	if not user_dir.to_lower().contains(USER_DIR_MARKER):
		push_error("Run only in a copied project with custom user directory containing " + USER_DIR_MARKER)
		get_tree().quit(2)
		return
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "user://battle-shortcut-input-evidence"
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(100.0, true, false, true).timeout.connect(func(): push_error("BATTLE SHORTCUT INPUT timeout"); get_tree().quit(2))
	Engine.time_scale = 6.0
	Game.save_enabled = false
	Game.save_path = output.path_join("battle-shortcut-unused-checkpoint.json")
	Game.meta_path = output.path_join("battle-shortcut-unused-meta.json")
	Game.state = Game.initial_state()
	Game.page = "menu"
	PlayerSettings.settings_path = output.path_join("battle-shortcut-settings.cfg")
	PlayerSettings.reset_defaults()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	var ready := await wait_ready(func(): return Game.page == "menu" and is_instance_valid(app.view))
	if check(ready, "real main scene opens menu in isolated user directory"):
		await test_default_hand_keys()
		await test_space_select_and_missing_slot()
		await test_space_end_turn()
		await test_modal_confirmation()
		await test_release_after_modal_open()
		await test_release_while_battle_paused()
		await test_unbound_native_accept()
	if is_instance_valid(app.audio_hooks): app.audio_hooks.attach(null)
	await Cleanup.release(app, get_tree())
	app.queue_free()
	await settle()
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "input suite never writes adventure or meta saves")
	var file := FileAccess.open(output.path_join("battle-shortcut-input-results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures, "records":records,
		"userDataDirectory":user_dir, "projectDirectory":project_dir,
		"scope":"real main/Battle, isolated settings and synthetic viewport press/release; no system pointer, physical keyboard, pixels or full playthrough"}, "\t"))
	file.close()
	print("BATTLE SHORTCUT INPUT TESTS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
