extends Node
## Copy-only QA: synthetic viewport input, no system pointer or production saves.
const Cleanup := preload("res://scripts/combat/audio_cleanup.gd")
var app: Control
var output := ""
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var statuses: Array[bool] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message,"passed":ok})
	if not ok:
		failures.append(message)
		push_error("SETTINGS QA: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func wait_ready(condition: Callable, seconds := 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if not Game.transition_locked and not Game.battle_busy and condition.call():
			await settle()
			return true
		await get_tree().create_timer(0.02).timeout
	return false

func key_event(code: Key, down := true, ctrl := false, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = down
	event.ctrl_pressed = ctrl
	event.echo = echo
	return event

func key(code: Key, shift := false, ctrl := false) -> void:
	for down in [true,false]:
		var event := key_event(code,down,ctrl)
		event.shift_pressed = shift
		get_viewport().push_input(event,true)
		await settle()

func click(control: Control, button_index := MOUSE_BUTTON_LEFT) -> void:
	if not is_instance_valid(control):
		check(false,"required clickable control exists")
		return
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion,true)
	await settle()
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button_index
		event.pressed = down
		get_viewport().push_input(event,true)
		await settle()

func file_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func test_storage() -> void:
	check(PlayerSettings.reset_defaults(),"defaults automatically save to isolated settings file")
	check(FileAccess.file_exists(PlayerSettings.settings_path),"settings file exists without an explicit Save action")
	check(is_equal_approx(PlayerSettings.master_volume,1.0) and is_equal_approx(PlayerSettings.sfx_volume,1.0) and PlayerSettings.sfx_enabled,"default sound retains full user volume and enabled effects")
	check(PlayerSettings.bindings == PlayerSettings.DEFAULT_BINDINGS,"default key bindings match published defaults")
	var last_text := file_text(PlayerSettings.settings_path)
	check(PlayerSettings.set_master_volume(0.37),"master volume setter saves successfully")
	check(file_text(PlayerSettings.settings_path) != last_text,"master volume change immediately reaches disk")
	last_text = file_text(PlayerSettings.settings_path)
	check(PlayerSettings.set_sfx_volume(0.63),"effects volume setter saves successfully")
	check(file_text(PlayerSettings.settings_path) != last_text,"effects volume change immediately reaches disk")
	check(PlayerSettings.set_sfx_enabled(false),"effects toggle saves successfully")
	check(PlayerSettings.bind_key("hand_1",KEY_Z).is_empty(),"valid rebind automatically saves")
	PlayerSettings.master_volume = 0.99
	PlayerSettings.sfx_volume = 0.99
	PlayerSettings.sfx_enabled = true
	PlayerSettings.bindings = PlayerSettings.DEFAULT_BINDINGS.duplicate()
	PlayerSettings.reload_settings()
	check(is_equal_approx(PlayerSettings.master_volume,0.37) and is_equal_approx(PlayerSettings.sfx_volume,0.63) and not PlayerSettings.sfx_enabled,"reload restores saved sound settings")
	check(PlayerSettings.bindings.hand_1 == KEY_Z,"reload restores saved key binding")
	var master := AudioServer.get_bus_index("Master")
	var sfx := AudioServer.get_bus_index("SFX")
	check(master >= 0 and sfx >= 0,"settings creates Master and SFX audio paths")
	if sfx >= 0:
		check(AudioServer.get_bus_send(sfx) == &"Master","effects bus feeds global master volume")
		check(AudioServer.is_bus_mute(sfx),"disabled effects mute the bus")
		check(is_equal_approx(AudioServer.get_bus_volume_linear(sfx),0.63),"effects volume applies to audio bus")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(master),0.37),"master volume applies to audio bus")
	PlayerSettings.set_master_volume(0.0)
	check(AudioServer.is_bus_mute(master) or AudioServer.get_bus_volume_linear(master) <= 0.00001,"zero master volume is silent")
	PlayerSettings.set_sfx_enabled(true)
	if sfx >= 0: check(not AudioServer.is_bus_mute(sfx),"effects switch restores audio bus")
	var saved_path: String = PlayerSettings.settings_path
	PlayerSettings.settings_path = output.path_join("absent-parent/settings.cfg")
	check(not PlayerSettings.set_master_volume(0.45),"unwritable settings path reports save failure")
	check(not statuses.is_empty() and not statuses.back(),"save failure signal can drive visible panel status")
	check(not FileAccess.file_exists(PlayerSettings.settings_path),"save failure does not claim a disk settings file")
	check(PlayerSettings.pending_save and is_equal_approx(PlayerSettings.master_volume,0.45),"save failure keeps immediate setting and schedules automatic retry")
	PlayerSettings.settings_path = saved_path
	PlayerSettings._process(2.1)
	check(not PlayerSettings.pending_save,"automatic retry clears pending save once storage is available")
	PlayerSettings.reload_settings()
	check(is_equal_approx(PlayerSettings.master_volume,0.45),"automatic retry persists retained in-memory setting")
	check(PlayerSettings.set_master_volume(0.54),"next valid change recovers automatic saving")
	check(not statuses.is_empty() and statuses.back(),"successful retry reports recovered saving")
	PlayerSettings.reset_defaults()

func test_invalid_file() -> void:
	var config := ConfigFile.new()
	config.set_value("audio","master_volume",-3.0)
	config.set_value("audio","sfx_volume",3.0)
	config.set_value("audio","sfx_enabled","false")
	config.set_value("keys","hand_1",KEY_ESCAPE)
	config.set_value("keys","hand_2","Z")
	check(config.save(PlayerSettings.settings_path) == OK,"malformed-value fixture writes only isolated settings")
	PlayerSettings.reload_settings()
	check(is_equal_approx(PlayerSettings.master_volume,0.0) and is_equal_approx(PlayerSettings.sfx_volume,1.0),"finite out-of-range volume values clamp safely")
	check(PlayerSettings.sfx_enabled,"wrong-type enabled value falls back to true")
	check(PlayerSettings.bindings.hand_1 == KEY_1 and PlayerSettings.bindings.hand_2 == KEY_2,"reserved and wrong-type saved keys fall back to defaults")
	config.set_value("audio","master_volume","very loud")
	config.set_value("audio","sfx_volume",false)
	config.set_value("keys","hand_1",KEY_2)
	config.save(PlayerSettings.settings_path)
	PlayerSettings.reload_settings()
	check(is_equal_approx(PlayerSettings.master_volume,1.0) and is_equal_approx(PlayerSettings.sfx_volume,1.0),"wrong-type volume values restore safe defaults")
	check(PlayerSettings.bindings == PlayerSettings.DEFAULT_BINDINGS,"conflicting saved map falls back to usable default keys")
	var broken := FileAccess.open(PlayerSettings.settings_path,FileAccess.WRITE)
	broken.store_string("[broken\nthis is not a config file")
	broken.close()
	PlayerSettings.reload_settings()
	check(PlayerSettings.bindings == PlayerSettings.DEFAULT_BINDINGS and PlayerSettings.sfx_enabled and is_equal_approx(PlayerSettings.master_volume,1.0),"unparseable settings file does not block boot and restores defaults")
	PlayerSettings.reset_defaults()

func test_display_storage() -> void:
	PlayerSettings.reset_defaults()
	check(PlayerSettings.display_mode == "windowed" and PlayerSettings.display_window_mode() == DisplayServer.WINDOW_MODE_WINDOWED,"display defaults to a normal window")
	var actual_mode := DisplayServer.window_get_mode()
	var modes := [["windowed",DisplayServer.WINDOW_MODE_WINDOWED],["borderless",DisplayServer.WINDOW_MODE_FULLSCREEN],["exclusive",DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]]
	for choice in modes:
		check(PlayerSettings.set_display_mode(choice[0]),"display mode automatically saves: " + str(choice[0]))
		check(PlayerSettings.display_mode == choice[0] and PlayerSettings.display_window_mode() == choice[1],"display mode maps to expected native enum: " + str(choice[0]))
		var saved := ConfigFile.new()
		check(saved.load(PlayerSettings.settings_path) == OK and saved.get_value("display","mode","") == choice[0],"display mode immediately reaches config: " + str(choice[0]))
		PlayerSettings.display_mode = "temporary-invalid-memory-value"
		PlayerSettings.reload_settings()
		check(PlayerSettings.display_mode == choice[0] and PlayerSettings.display_window_mode() == choice[1],"display mode survives reload: " + str(choice[0]))
	check(PlayerSettings.DISPLAY_MODES["exclusive"] == 4 and PlayerSettings.DISPLAY_MODES["exclusive"] != DisplayServer.WINDOW_MODE_MAXIMIZED,"true fullscreen uses exclusive enum 4 rather than maximized")
	if DisplayServer.get_name() == "headless":
		check(DisplayServer.window_get_mode() == actual_mode,"headless display settings do not attempt real window mode changes")
	var before_text := file_text(PlayerSettings.settings_path)
	check(not PlayerSettings.set_display_mode("maximized") and PlayerSettings.display_mode == "exclusive","unsupported display mode is rejected without replacing valid preference")
	check(file_text(PlayerSettings.settings_path) == before_text,"invalid display mode does not overwrite saved settings")
	PlayerSettings.set_master_volume(0.42)
	PlayerSettings.set_sfx_volume(0.61)
	PlayerSettings.set_sfx_enabled(false)
	PlayerSettings.bind_key("hand_1",KEY_Z)
	PlayerSettings.reload_settings()
	check(PlayerSettings.display_mode == "exclusive","sound and hotkey writes retain selected display mode")
	check(is_equal_approx(PlayerSettings.master_volume,0.42) and is_equal_approx(PlayerSettings.sfx_volume,0.61) and not PlayerSettings.sfx_enabled and PlayerSettings.bindings.hand_1 == KEY_Z,"display mode shares config safely with sound and hotkeys")
	var config := ConfigFile.new()
	config.set_value("audio","master_volume",0.36)
	config.set_value("keys","hand_1",KEY_Z)
	config.save(PlayerSettings.settings_path)
	PlayerSettings.display_mode = "exclusive"
	PlayerSettings.reload_settings()
	check(PlayerSettings.display_mode == "windowed","legacy config without display section defaults to a window")
	check(is_equal_approx(PlayerSettings.master_volume,0.36) and PlayerSettings.bindings.hand_1 == KEY_Z,"legacy display default preserves existing sound and hotkeys")
	for invalid in ["maximized",17,false]:
		config.set_value("display","mode",invalid)
		config.save(PlayerSettings.settings_path)
		PlayerSettings.display_mode = "exclusive"
		PlayerSettings.reload_settings()
		check(PlayerSettings.display_mode == "windowed" and PlayerSettings.display_window_mode() == DisplayServer.WINDOW_MODE_WINDOWED,"unknown or wrong-type saved display mode falls back safely: " + str(invalid))
	var good_path: String = PlayerSettings.settings_path
	PlayerSettings.settings_path = output.path_join("absent-display-parent/settings.cfg")
	check(not PlayerSettings.set_display_mode("exclusive"),"display change reports save failure on unavailable storage")
	check(PlayerSettings.display_mode == "exclusive" and PlayerSettings.pending_save,"failed display save retains selected mode and schedules automatic retry")
	PlayerSettings.settings_path = good_path
	PlayerSettings._process(2.1)
	PlayerSettings.reload_settings()
	check(PlayerSettings.display_mode == "exclusive" and not PlayerSettings.pending_save,"automatic retry persists the retained display mode")
	PlayerSettings.reset_defaults()
	PlayerSettings.display_mode = "exclusive"
	PlayerSettings.reload_settings()
	check(PlayerSettings.display_mode == "windowed","Restore Defaults automatically persists windowed display mode")

func test_bindings() -> void:
	for i in 10:
		var action := "hand_%d" % (i + 1)
		var code: int = [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8,KEY_9,KEY_0][i]
		var keypad: int = [KEY_KP_1,KEY_KP_2,KEY_KP_3,KEY_KP_4,KEY_KP_5,KEY_KP_6,KEY_KP_7,KEY_KP_8,KEY_KP_9,KEY_KP_0][i]
		check(PlayerSettings.matches(key_event(code),action),"default number selects " + action)
		check(PlayerSettings.matches(key_event(keypad),action),"default keypad selects " + action)
	check(PlayerSettings.matches(key_event(KEY_ENTER),"advance") and PlayerSettings.matches(key_event(KEY_SPACE),"advance"),"default dialogue accepts Space and Enter")
	check(not PlayerSettings.matches(key_event(KEY_1,false),"hand_1"),"key release does not trigger action")
	check(not PlayerSettings.matches(key_event(KEY_1,true,false,true),"hand_1"),"key echo does not trigger action")
	check(not PlayerSettings.matches(key_event(KEY_1,true,true),"hand_1"),"modifier combinations do not trigger action")
	for code in [KEY_ESCAPE,KEY_TAB,KEY_ENTER,KEY_F1,KEY_F5,KEY_F6,KEY_F7,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_SHIFT,KEY_CTRL,KEY_ALT,KEY_META]:
		check(not PlayerSettings.bind_key("hand_1",code).is_empty(),"reserved or modifier key rejected: " + OS.get_keycode_string(code))
	var before: Dictionary = PlayerSettings.bindings.duplicate()
	check(not PlayerSettings.bind_key("hand_1",KEY_2).is_empty() and PlayerSettings.bindings == before,"battle binding conflict is rejected without mutation")
	check(not PlayerSettings.bind_key("missing_action",KEY_Z).is_empty(),"unknown binding action is rejected")
	check(PlayerSettings.bind_key("hand_1",KEY_Z).is_empty(),"hand hotkey can change to Z")
	check(PlayerSettings.matches(key_event(KEY_Z),"hand_1") and not PlayerSettings.matches(key_event(KEY_1),"hand_1") and not PlayerSettings.matches(key_event(KEY_KP_1),"hand_1"),"rebound hand action replaces both default aliases")
	check(PlayerSettings.bind_key("advance",KEY_Z).is_empty(),"dialogue and battle may share a key in separate contexts")
	check(PlayerSettings.matches(key_event(KEY_Z),"advance") and not PlayerSettings.matches(key_event(KEY_ENTER),"advance") and not PlayerSettings.matches(key_event(KEY_SPACE),"advance"),"rebound dialogue action replaces default aliases")
	PlayerSettings.reset_defaults()

func test_panel() -> bool:
	var menu = app.view
	var state_before: Dictionary = Game.state.duplicate(true)
	var revision_before: int = Game.revision
	menu.open_settings()
	await settle()
	check(is_instance_valid(menu.settings_dialog),"menu settings opens an embedded panel")
	if not is_instance_valid(menu.settings_dialog): return false
	var settings = menu.settings_dialog
	check(menu.new_button.focus_mode == Control.FOCUS_NONE,"underlying menu cannot receive keyboard focus")
	check(menu.new_button.disabled and menu.quit_button.disabled,"settings modal disables background menu buttons")
	check(settings.is_ancestor_of(get_viewport().gui_get_focus_owner()),"opening panel places keyboard focus inside settings")
	var save_buttons := 0
	for control in settings.find_children("*","Button",true,false):
		if "保存" in control.text: save_buttons += 1
	check(save_buttons == 0,"settings has no separate Save button")
	for i in settings.binding_buttons.size() + 8:
		await key(KEY_TAB)
		check(settings.is_ancestor_of(get_viewport().gui_get_focus_owner()),"Tab stays in settings modal at step %d" % i)
	await key(KEY_TAB,true)
	check(settings.is_ancestor_of(get_viewport().gui_get_focus_owner()),"Shift Tab stays in settings modal")
	settings.master_slider.value = 28
	settings.sfx_slider.value = 46
	await settle()
	# Sliders expose percentages; persistence exposes normalized volume.
	check(is_equal_approx(PlayerSettings.master_volume,0.28) and is_equal_approx(PlayerSettings.sfx_volume,0.46),"slider changes apply normalized sound volumes immediately")
	PlayerSettings.reload_settings()
	check(is_equal_approx(PlayerSettings.master_volume,0.28) and is_equal_approx(PlayerSettings.sfx_volume,0.46),"slider changes survive reload without closing panel")
	var enabled_before: bool = PlayerSettings.sfx_enabled
	await click(settings.sfx_toggle)
	check(PlayerSettings.sfx_enabled != enabled_before,"effects switch toggles live setting through GUI")
	settings.begin_rebind("hand_1")
	await key(KEY_Z)
	check(PlayerSettings.bindings.hand_1 == KEY_Z and settings.listening_action.is_empty(),"listening captures one valid hotkey and exits capture")
	settings.begin_rebind("hand_1")
	await key(KEY_2)
	check(PlayerSettings.bindings.hand_1 == KEY_Z,"conflicting capture preserves previous hotkey")
	check(not settings.status_label.text.is_empty(),"conflicting capture shows player feedback")
	await key(KEY_ESCAPE)
	check(is_instance_valid(menu.settings_dialog) and settings.listening_action.is_empty(),"first Esc cancels hotkey capture without closing settings")
	for code in [KEY_F1,KEY_F5,KEY_1]: await key(code)
	await key(KEY_A,false,true)
	check(Game.page == "menu" and Game.state == state_before and Game.revision == revision_before and not is_instance_valid(app.debug_panel) and not is_instance_valid(app.card_console),"settings blocks game and debug shortcuts without changing adventure")
	var good_path: String = PlayerSettings.settings_path
	PlayerSettings.settings_path = output.path_join("absent-panel-parent/settings.cfg")
	settings.master_slider.value = 29
	check("失败" in settings.status_label.text and PlayerSettings.pending_save,"panel visibly reports save failure while retaining automatic retry")
	PlayerSettings.settings_path = good_path
	PlayerSettings._process(2.1)
	check(not PlayerSettings.pending_save and "已自动保存" in settings.status_label.text,"panel reports successful automatic retry without Save button")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(menu.settings_dialog),"next Esc closes settings")
	check(not menu.new_button.disabled and not menu.quit_button.disabled,"closing settings restores original background button states")
	menu.open_settings()
	await settle()
	settings = menu.settings_dialog
	await click(settings.reset_button)
	check(PlayerSettings.bindings == PlayerSettings.DEFAULT_BINDINGS and is_equal_approx(PlayerSettings.master_volume,1.0) and is_equal_approx(PlayerSettings.sfx_volume,1.0) and PlayerSettings.sfx_enabled,"Restore Defaults applies and automatically saves all settings")
	await click(settings.close_button)
	check(not is_instance_valid(menu.settings_dialog),"close button returns to main menu")
	menu.open_settings()
	await settle()
	settings = menu.settings_dialog
	var bindings_before: Dictionary = PlayerSettings.bindings.duplicate()
	var saved_before := file_text(PlayerSettings.settings_path)
	settings.begin_rebind("hand_1")
	await click(settings.binding_buttons.hand_1,MOUSE_BUTTON_RIGHT)
	check(is_instance_valid(menu.settings_dialog) and settings.listening_action.is_empty(),"right click cancels key capture without closing settings")
	check(PlayerSettings.bindings == bindings_before and file_text(PlayerSettings.settings_path) == saved_before,"canceling capture by right click preserves bindings and saved preferences")
	await click(settings.close_button,MOUSE_BUTTON_RIGHT)
	check(not is_instance_valid(menu.settings_dialog),"next right click closes settings")
	check(not menu.new_button.disabled and not menu.quit_button.disabled,"right click restores background menu buttons")
	check(Game.page == "menu" and Game.state == state_before and Game.revision == revision_before,"right click returns without changing adventure or triggering the underlying menu")
	return true

func test_display_panel() -> void:
	var menu = app.view
	var state_before: Dictionary = Game.state.duplicate(true)
	var revision_before: int = Game.revision
	menu.open_settings()
	await settle()
	check(is_instance_valid(menu.settings_dialog),"settings reopens for display mode controls")
	if not is_instance_valid(menu.settings_dialog): return
	var settings = menu.settings_dialog
	var picker: OptionButton = settings.display_mode_picker
	check(is_instance_valid(picker) and picker.item_count == 3,"display picker exposes three modes")
	if not is_instance_valid(picker):
		menu.handle_escape()
		return
	check(settings.focus_controls.has(picker),"display picker participates in settings keyboard focus loop")
	var labels := ["窗口","无边框全屏","独占全屏（真全屏）"]
	var ids := [DisplayServer.WINDOW_MODE_WINDOWED,DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	var names := ["windowed","borderless","exclusive"]
	for i in mini(3,picker.item_count):
		check(picker.get_item_text(i) == labels[i],"display choice has explicit player label: " + labels[i])
		check(picker.get_item_id(i) == ids[i],"display choice carries correct native enum: " + labels[i])
		picker.select(i)
		picker.item_selected.emit(i)
		await settle()
		check(PlayerSettings.display_mode == names[i],"picker selection immediately applies preference: " + names[i])
		var config := ConfigFile.new()
		check(config.load(PlayerSettings.settings_path) == OK and config.get_value("display","mode","") == names[i],"picker selection saves without separate Save action: " + names[i])
	check(picker.get_item_id(2) == 4,"true fullscreen picker option is exclusive, not maximized")
	await click(settings.close_button)
	menu.open_settings()
	await settle()
	settings = menu.settings_dialog
	check(settings.display_mode_picker.get_selected_id() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,"reopening settings reflects saved exclusive fullscreen preference")
	await click(settings.reset_button)
	check(PlayerSettings.display_mode == "windowed" and settings.display_mode_picker.get_selected_id() == DisplayServer.WINDOW_MODE_WINDOWED,"Restore Defaults updates display preference and picker together")
	await click(settings.close_button)
	check(Game.page == "menu" and Game.state == state_before and Game.revision == revision_before,"display settings do not alter adventure state or menu route")

func test_dialogue_input() -> void:
	Game.new_game()
	var ready := await wait_ready(func(): return Game.page == "dialogue" and app.view.get_script().resource_path.ends_with("/dialogue.gd"))
	check(ready,"real dialogue is ready for key rebinding")
	if not ready: return
	get_viewport().gui_release_focus()
	app.view.text_label.visible_characters = -1
	var previous_revision: int = Game.revision
	await key(KEY_SPACE)
	check(Game.revision > previous_revision,"default Space advances fully revealed real dialogue")
	await wait_ready(func(): return Game.page == "dialogue")
	check(PlayerSettings.bind_key("advance",KEY_Z).is_empty(),"dialogue key can be changed and saved")
	app.view.text_label.visible_characters = -1
	previous_revision = Game.revision
	await key(KEY_SPACE)
	await key(KEY_ENTER)
	check(Game.revision == previous_revision,"old Space and Enter no longer advance real dialogue after rebind")
	await key(KEY_Z,false,true)
	check(Game.revision == previous_revision,"modified dialogue hotkey does not advance")
	await key(KEY_Z)
	check(Game.revision > previous_revision,"new key advances real dialogue")
	await wait_ready(func(): return Game.page == "dialogue")
	PlayerSettings.reset_defaults()
	Game.menu()
	await wait_ready(func(): return Game.page == "menu")

func test_hand_input() -> void:
	Game.start_training("B02")
	var ready := await wait_ready(func(): return Game.page == "battle" and app.view.get_script().resource_path.ends_with("/battle.gd") and app.view.initialized)
	check(ready,"real training battle initializes for rebound hotkey verification")
	if not ready: return
	var battle = app.view
	battle.model.energy = 99
	battle.model.ammo = 99
	get_viewport().gui_release_focus()
	await key(KEY_1)
	check(battle.selected_uid == battle.model.hand[0],"default numeric hotkey selects first real hand card")
	battle.cancel_selection()
	check(PlayerSettings.bind_key("hand_1",KEY_Z).is_empty(),"real battle hotkey change saves")
	await key(KEY_1)
	check(battle.selected_uid.is_empty(),"old hotkey no longer selects real hand card")
	await key(KEY_Z,false,true)
	check(battle.selected_uid.is_empty(),"modified rebound key does not select real hand card")
	await key(KEY_Z)
	check(battle.selected_uid == battle.model.hand[0],"rebound key selects first real hand card")
	battle.cancel_selection()
	# Create the actor-frame voice on the same path used by authored animations.
	battle.stage.player._next_audio_player()
	for enemy in battle.stage.enemies: enemy._next_audio_player()
	battle.stage.combat_audio.play_cue("slash")
	var voices := app.find_children("*","AudioStreamPlayer",true,false)
	check(voices.size() >= 12,"real scene includes shared, stage, frame and attack audio voices")
	for voice in voices:
		check(voice.bus == &"SFX","live sound voice uses settings SFX bus: " + str(voice.get_path()))
	for action_data in [[KEY_Q,"cyberware_view.gd"],[KEY_D,"pile_view.gd"],[KEY_F,"pile_view.gd"]]:
		get_viewport().gui_release_focus()
		await key(action_data[0])
		check(is_instance_valid(battle.pile_overlay),"battle action opens modal for " + OS.get_keycode_string(action_data[0]))
		if not is_instance_valid(battle.pile_overlay): continue
		check(battle.pile_overlay.get_script().resource_path.ends_with(action_data[1]),"battle shortcut opens expected view " + action_data[1])
		if action_data[0] == KEY_D: check(battle.pile_overlay.pile_title == "抽牌堆","D opens draw pile")
		if action_data[0] == KEY_F: check(battle.pile_overlay.pile_title == "弃牌堆","F opens discard pile")
		var overlay: Control = battle.pile_overlay
		var before: Dictionary = battle.model.snapshot()
		for blocked in [KEY_E,KEY_Q,KEY_D,KEY_F,KEY_Z]: await key(blocked)
		check(battle.pile_overlay == overlay and battle.model.snapshot() == before and battle.selected_uid.is_empty(),"battle action modal blocks underlying shortcuts and state mutation")
		await key(KEY_ESCAPE)
		check(not is_instance_valid(battle.pile_overlay),"Escape closes battle shortcut modal")
	check(PlayerSettings.bind_key("draw_pile",KEY_G).is_empty(),"draw pile action can be rebound")
	get_viewport().gui_release_focus()
	await key(KEY_D)
	check(not is_instance_valid(battle.pile_overlay),"old draw pile action no longer opens modal")
	await key(KEY_G)
	check(is_instance_valid(battle.pile_overlay) and battle.pile_overlay.pile_title == "抽牌堆","new draw pile action opens real modal")
	if is_instance_valid(battle.pile_overlay): await key(KEY_ESCAPE)
	get_viewport().gui_release_focus()
	var turn_before: int = battle.model.turn
	await key(KEY_E)
	ready = await wait_ready(func(): return battle.initialized and battle.model.turn > turn_before)
	check(ready and battle.model.turn == turn_before + 1,"E executes exactly one real enemy turn and starts next player turn")
	Game.menu()
	check(Game.transition_locked and Game.page == "menu" and app.shown_page == "battle" and app.view == battle,"menu destination keeps battle view during transition cover")
	var snapshot: Dictionary = battle.model.snapshot()
	test_transition_input("battle cover")
	check(battle.model.snapshot() == snapshot,"transition input does not mutate outgoing battle")
	var deadline := Time.get_ticks_msec() + 5000
	while app.shown_page != "menu" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(app.shown_page == "menu" and Game.transition_locked,"menu view is installed while transition reveal remains locked")
	test_transition_input("menu reveal")
	await wait_ready(func(): return Game.page == "menu")
	check(app.shown_page == "menu" and not Game.transition_locked,"menu transition completes after blocked input")
	app.view.open_settings()
	check(is_instance_valid(app.view.settings_dialog),"settings still opens after battle return")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.view.settings_dialog),"Escape closes settings after transition unlocks")
	PlayerSettings.reset_defaults()

func test_transition_input(phase: String) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(700, 400)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	var console_key := key_event(KEY_A, true, true)
	console_key.shift_pressed = true
	for event in [motion, right, key_event(KEY_ESCAPE), key_event(KEY_E), key_event(KEY_1), console_key]:
		get_viewport().push_input(event, true)
		check(get_viewport().is_input_handled(),phase + " consumes " + event.as_text())
	check(Game.page == "menu" and Game.transition_locked,phase + " preserves transition destination and lock")
	check(not is_instance_valid(app.card_console) and not is_instance_valid(app.exit_dialog),phase + " does not open global dialogs")

func _ready() -> void:
	if not OS.get_user_data_dir().to_lower().contains("settings-qa"):
		push_error("Requires copied project and custom user directory containing settings-qa")
		get_tree().quit(2)
		return
	get_tree().create_timer(80).timeout.connect(func(): push_error("SETTINGS QA timeout"); get_tree().quit(2))
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "user://settings-qa-evidence"
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	Game.state = Game.initial_state()
	Game.transition_locked = false
	Game.battle_busy = false
	Game.page = "menu"
	PlayerSettings.settings_path = output.path_join("settings.cfg")
	PlayerSettings.status_changed.connect(func(success: bool): statuses.append(success))
	test_storage()
	test_invalid_file()
	test_display_storage()
	test_bindings()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	var ready := await wait_ready(func(): return Game.page == "menu" and is_instance_valid(app.view))
	check(ready,"main scene initializes menu with isolated settings")
	if ready:
		await test_panel()
		await test_display_panel()
		await test_dialogue_input()
		await test_hand_input()
	if is_instance_valid(app.audio_hooks): app.audio_hooks.attach(null)
	await Cleanup.release(app,get_tree())
	app.queue_free()
	await settle()
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path),"settings QA never writes adventure or meta save files")
	var file := FileAccess.open(output.path_join("settings-results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"userDataDirectory":OS.get_user_data_dir(),"scope":"isolated settings storage, audio buses, display mode enums and preferences, real viewport synthetic input; no physical fullscreen, pixels, listening or physical input"},"\t"))
	file.close()
	print("SETTINGS TESTS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
