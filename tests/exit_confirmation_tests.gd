extends Node
## Run only in a copy with an isolated custom_user_dir_name containing
## "exit-confirmation"; all input is injected into the headless viewport.
var app: Control
var output_dir := ""
var mode := "input"
var checks := 0
var failures := 0
var records: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message, "passed":ok})
	if not ok:
		failures += 1
		push_error("EXIT CONFIRMATION: " + message)

func settle(seconds: float = 0.08) -> void:
	await get_tree().create_timer(seconds).timeout

func idle() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while Game.battle_busy or Game.transition_locked:
		if Time.get_ticks_msec() >= deadline:
			check(false, "Page transition and battle animation finish")
			return
		await get_tree().process_frame
	await settle()

func key(code: Key, shift: bool = false, ctrl: bool = false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		event.shift_pressed = shift
		event.ctrl_pressed = ctrl
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await settle()

func click_at(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	get_viewport().push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await settle()

func click(control: Control) -> void:
	if not is_instance_valid(control):
		check(false, "Required clickable control exists")
		return
	await click_at(control.get_global_rect().get_center())

func menu_button() -> Button:
	for node in app.view.find_children("*", "Button", true, false):
		if node.text in ["菜单", "退出演练"]: return node
	return null

func modal_open() -> bool:
	return is_instance_valid(app.exit_dialog)

func modal_text() -> String:
	var text := ""
	if not modal_open(): return text
	for node in app.exit_dialog.find_children("*", "Label", true, false):
		text += node.text + "\n"
	return text

func stage_map() -> void:
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.page = "map"
	Game.changed.emit()
	await idle()

func write_result() -> void:
	var file := FileAccess.open(output_dir.path_join(mode + "-result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks":checks, "failures":failures, "records":records, "userDataDirectory":OS.get_user_data_dir(), "savePath":Game.save_path, "mode":mode}, "\t"))
	print("EXIT CONFIRMATION %s: %d checks, %d failures" % [mode, checks, failures])

func _ready() -> void:
	get_tree().create_timer(80).timeout.connect(func(): push_error("EXIT CONFIRMATION timeout"); get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "quit": mode = "quit"
		if args[i] == "--output-dir" and i + 1 < args.size(): output_dir = args[i + 1]
	if output_dir.is_empty() or not "exit-confirmation" in OS.get_user_data_dir():
		push_error("Requires --output-dir and an isolated custom user directory containing exit-confirmation")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	Game.save_enabled = false
	Game.save_path = output_dir.path_join(mode + "-checkpoint.json")
	Game.meta_path = output_dir.path_join(mode + "-meta.json")
	for path in [Game.save_path, Game.meta_path]:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	Game.state = {}
	Game.page = "menu"
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle(0.5)
	if mode == "quit":
		await quit_suite()
		return
	await menu_suite()
	await map_and_dialogue_suite()
	await battle_suite()
	await training_suite()
	write_result()
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

func menu_suite() -> void:
	var menu = app.view
	var quit_button := menu.find_child("quit_game", true, false) as Button
	check(is_instance_valid(quit_button) and quit_button.text == "退出游戏", "Main menu exposes exit game button")
	check(menu.continue_button.disabled, "Continue stays disabled without a save")
	if not is_instance_valid(quit_button): return
	check(get_viewport().get_visible_rect().encloses(quit_button.get_global_rect()), "Exit button remains within the menu canvas")
	check(quit_button.get_combined_minimum_size().x <= 165 and quit_button.get_combined_minimum_size().y <= 44 and quit_button.size == Vector2(165, 44), "Exit label fits the bottom-row button size")
	check(menu.motion_button.get_combined_minimum_size().x <= 165 and menu.motion_button.get_combined_minimum_size().y <= 44 and menu.motion_button.size == Vector2(165, 44), "Motion label fits the bottom-row button size")
	check(not quit_button.get_global_rect().intersects(menu.motion_button.get_global_rect()), "Bottom-row motion and exit buttons do not overlap")
	var version_found := false
	for node in menu.ui_layer.find_children("*", "Label", true, false):
		if node.text.begins_with("v"):
			version_found = true
			check(get_viewport().get_visible_rect().encloses(node.get_global_rect()), "Version label remains inside the canvas")
	check(version_found, "Menu still shows its version label")
	menu._set_training_open(true)
	for node in menu.training_container.find_children("*", "Button", true, false):
		check(not quit_button.get_global_rect().intersects(node.get_global_rect()), "Exit does not overlap expanded training button " + str(node.name))
	Game.request_quit()
	check(not modal_open() and menu.training_open, "Unified practice modal blocks exit confirmation stacking")
	await key(KEY_F1)
	await key(KEY_A, true, true)
	check(not is_instance_valid(app.debug_panel) and not is_instance_valid(app.card_console), "Practice modal blocks developer keyboard shortcuts")
	await key(KEY_ESCAPE)
	check(not menu.training_open and Game.page == "menu", "Escape closes unified practice before global navigation")
	Game.transition_locked = true
	Game.request_quit()
	check(not modal_open(), "Transition lock blocks opening exit-game confirmation")
	Game.transition_locked = false
	await click(quit_button)
	check(modal_open() and app.exit_action == "quit", "Exit click opens confirmation without quitting")
	if not modal_open(): return
	check(get_viewport().gui_get_focus_owner() == app.exit_cancel, "Exit confirmation defaults to cancel")
	check(menu.process_mode == Node.PROCESS_MODE_DISABLED, "Exit confirmation suspends underlying menu input")
	var original_dialog = app.exit_dialog
	Game.request_quit()
	check(app.exit_dialog == original_dialog, "Repeated exit requests do not stack confirmations")
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == app.exit_ok, "Tab reaches the confirm button")
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == app.exit_cancel, "Tab wraps within confirmation")
	await key(KEY_TAB, true)
	check(get_viewport().gui_get_focus_owner() == app.exit_ok, "Shift Tab wraps within confirmation")
	for code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		var previous := get_viewport().gui_get_focus_owner()
		await key(code)
		var expected = app.exit_cancel if previous == app.exit_ok else app.exit_ok
		check(get_viewport().gui_get_focus_owner() == expected, "Direction key stays inside confirmation: " + OS.get_keycode_string(code))
	await key(KEY_F1)
	await key(KEY_A, true, true)
	check(not is_instance_valid(app.debug_panel) and not is_instance_valid(app.card_console), "Exit confirmation blocks developer shortcuts")
	await click_at(Vector2(40, 40))
	check(modal_open() and Game.page == "menu", "Backdrop click does not exit or dismiss confirmation")
	await key(KEY_ESCAPE)
	check(not modal_open() and app.view == menu, "Escape cancels exit and keeps the same menu")
	check(menu.continue_button.disabled and not quit_button.disabled and menu.process_mode != Node.PROCESS_MODE_DISABLED, "Cancel restores original disabled and processing states")
	check(Game.state.is_empty() and not FileAccess.file_exists(Game.save_path), "Exit cancellation does not create a game or save")
	await click(quit_button)
	await key(KEY_ENTER)
	check(not modal_open() and Game.page == "menu", "Enter on initial focus cancels exit safely")
	await key(KEY_TAB, true)
	check(get_viewport().gui_get_focus_owner() == quit_button, "Shift Tab after cancellation reaches the exit button")
	get_viewport().gui_release_focus()
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() != null, "Keyboard navigation can re-enter the menu after cancellation")

func map_and_dialogue_suite() -> void:
	await stage_map()
	check(Game.save_game(), "Create isolated adventure checkpoint")
	var saved := FileAccess.get_file_as_bytes(Game.save_path)
	var original := Game.state.duplicate(true)
	var revision := Game.revision
	var map = app.view
	Game.transition_locked = true
	Game.request_menu()
	check(not modal_open(), "Transition lock blocks return-to-menu confirmation")
	Game.transition_locked = false
	await click(menu_button())
	check(modal_open() and app.exit_action == "menu" and Game.page == "map", "Adventure menu button asks before returning")
	if not modal_open(): return
	await click(map.get_node("current_deck_button"))
	check(not is_instance_valid(app.deck_browser) and modal_open(), "Confirmation blocks underlying current-deck button")
	await key(KEY_ESCAPE)
	check(not modal_open() and app.view == map, "Cancel retains the original map")
	check(Game.state == original and Game.revision == revision and FileAccess.get_file_as_bytes(Game.save_path) == saved, "Map cancellation preserves state revision and checkpoint bytes")
	await key(KEY_ESCAPE)
	check(modal_open(), "Adventure Escape opens return-to-menu confirmation")
	if not modal_open(): return
	await click(app.exit_ok)
	await idle()
	check(Game.page == "menu" and not modal_open(), "Confirm returns to main menu")
	check(Game.state == original and FileAccess.get_file_as_bytes(Game.save_path) == saved, "Confirmed map return preserves adventure and checkpoint")
	app.view.request_new()
	check(is_instance_valid(app.view.confirm_dialog) and app.view.confirm_dialog.visible, "Existing progress still opens new-commission confirmation")
	Game.request_quit()
	check(not modal_open(), "New-commission confirmation blocks nested exit confirmation")
	await key(KEY_ESCAPE)
	check(Game.page == "menu" and not app.view.confirm_dialog.visible, "Escape closes new-commission confirmation without resuming")
	await key(KEY_ESCAPE)
	await idle()
	check(Game.page == "map" and not modal_open(), "Main menu Escape retains existing resume behavior")
	Game.state = Game.initial_state()
	Game.page = "dialogue"
	Game.changed.emit()
	await settle()
	var dialogue = app.view
	var dialogue_state := Game.state.duplicate(true)
	await click(menu_button())
	check(modal_open(), "Dialogue menu opens confirmation")
	if not modal_open(): return
	var visible: int = dialogue.text_label.visible_characters
	await settle(0.2)
	await click_at(Vector2(800, 750))
	check(dialogue.text_label.visible_characters == visible and Game.state == dialogue_state, "Return confirmation pauses dialogue reveal and blocks advance clicks")
	await click(app.exit_cancel)
	check(app.view == dialogue and not modal_open(), "Cancel returns to the same dialogue sentence")
	# Menu-only archive and library pages keep their lightweight close behavior.
	Game.menu()
	await idle()
	Game.open_card_library()
	await idle()
	await key(KEY_ESCAPE)
	check(Game.page == "menu" and not modal_open(), "Closing the menu card library does not ask to leave an adventure")
	Game.open_cyberware()
	await idle()
	await key(KEY_ESCAPE)
	check(Game.page == "menu" and not modal_open(), "Closing the menu technology archive stays direct")

func battle_suite() -> void:
	Game.state = Game.initial_state()
	Game.state.currentHp = 73
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.enter_node("battle")
	await idle()
	var battle = app.view
	var opening: Dictionary = battle.model.snapshot()
	var uid: String = battle.model.hand[0]
	battle.selected_uid = uid
	await battle.play_selected(0 if battle.model.card_target(uid) == "enemy" else -1)
	await idle()
	check(battle.model.snapshot() != opening, "Battle fixture has played a real card")
	var progressed: Dictionary = battle.model.snapshot()
	var state := Game.state.duplicate(true)
	var revision := Game.revision
	Game.battle_busy = true
	Game.request_menu()
	check(not modal_open(), "Busy battle rejects opening return confirmation")
	Game.battle_busy = false
	await click(menu_button())
	check(modal_open() and Game.page == "battle", "Battle menu asks before returning")
	if not modal_open(): return
	check("开局" in modal_text(), "Battle confirmation explains restart from the opening")
	await key(KEY_1)
	await key(KEY_F6)
	await click(battle.end_button)
	check(battle.model.snapshot() == progressed and not Game.battle_busy and battle.selected_uid.is_empty(), "Modal blocks battle card shortcuts previews and end turn")
	await key(KEY_ESCAPE)
	check(app.view == battle and not modal_open(), "Battle cancel keeps the existing view")
	check(battle.model.snapshot() == progressed and Game.state == state and Game.revision == revision, "Battle cancel preserves exact live snapshot and revision")
	await key(KEY_ESCAPE)
	check(modal_open(), "Battle Escape with no selection asks before returning")
	if not modal_open(): return
	await click(app.exit_ok)
	await idle()
	check(Game.page == "menu" and Game.state.combat == Game.state.battleStart, "Confirmed battle return applies the existing opening restart rule")
	await click(app.view.continue_button)
	await idle()
	check(Game.page == "battle" and app.view.model.snapshot() == opening, "Continue after confirmed return restores exact original opening")
	Game.menu()
	await idle()

func training_suite() -> void:
	await stage_map()
	var adventure := Game.state.duplicate(true)
	Game.menu()
	await idle()
	Game.start_training("B04")
	await idle()
	var battle = app.view
	var training_state := Game.state.duplicate(true)
	await click(menu_button())
	check(modal_open() and Game.training_mode, "Exit training asks before restoring adventure")
	if not modal_open(): return
	await click(app.exit_cancel)
	check(Game.training_mode and Game.state == training_state and app.view == battle, "Cancelling training exit preserves training snapshot")
	await click(menu_button())
	if not modal_open():
		check(false, "Training exit can reopen confirmation")
		return
	await click(app.exit_ok)
	await idle()
	check(Game.page == "menu" and not Game.training_mode and Game.state == adventure and Game.training_backup.is_empty(), "Confirmed training exit restores exact adventure state")

func quit_suite() -> void:
	await click(app.view.find_child("quit_game", true, false))
	check(modal_open() and app.exit_action == "quit", "Real quit mode opens confirmation")
	if not modal_open():
		write_result()
		get_tree().quit(1)
		return
	check(get_viewport().gui_get_focus_owner() == app.exit_cancel, "Real quit mode initially focuses cancel")
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == app.exit_ok, "Real quit mode can explicitly select exit")
	write_result()
	if failures > 0:
		get_tree().quit(1)
		return
	print("EXIT CONFIRMATION: dispatching explicit quit; process must exit with code 0")
	# Do not call SceneTree.quit here: production confirmation must terminate us.
	await key(KEY_ENTER)
	await settle(1.0)
	push_error("Explicit exit confirmation did not terminate the process")
	get_tree().quit(1)
