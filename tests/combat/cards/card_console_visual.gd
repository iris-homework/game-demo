extends Node
var app: Control
var failures := 0
var checks := 0
var output := "user://"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func key(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.ctrl_pressed = ctrl
		event.shift_pressed = shift
		event.keycode = code
		event.pressed = down
		get_viewport().push_input(event,true)
		await settle()

func click(button: Button) -> void:
	var pos := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	get_viewport().push_input(motion,true)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event,true)
		await settle()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output+name+".png") == OK,"Screenshot saved")

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	Game.save_path = "user://console_click_qa.json"
	Game.meta_path = "user://console_click_meta_qa.json"
	Game.save_enabled = false
	Game.state = Game.initial_state()
	Game.page = "card_library"
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle()
	await key(KEY_F2)
	await key(KEY_A)
	await key(KEY_A,true,false)
	await key(KEY_A,false,true)
	check(not is_instance_valid(app.card_console),"Old F2 and incomplete chords do not open console")
	await key(KEY_A,true,true)
	var console = app.card_console
	check(is_instance_valid(console),"Ctrl+Shift+A opens console")
	console.entry.text = "owned"
	await key(KEY_A,true,false)
	check(is_instance_valid(app.card_console) and console.entry.text == "owned","Ctrl+A retains input and does not close console")
	await key(KEY_F2)
	check(is_instance_valid(app.card_console),"Old F2 does not close console")
	var held := InputEventKey.new()
	held.keycode = KEY_A
	held.ctrl_pressed = true
	held.shift_pressed = true
	held.pressed = true
	held.echo = true
	get_viewport().push_input(held,true)
	await settle()
	check(is_instance_valid(app.card_console),"Holding shortcut does not toggle repeatedly")
	console.entry.clear()
	check(console.card_buttons.size() == Game.card_catalog.size(),"All definitions immediately listed")
	for id in console.card_buttons:
		var button: Button = console.card_buttons[id]
		check(console.card_scroll.get_global_rect().encloses(button.get_global_rect()),"Card visible without scrolling: "+id)
	check(console.owned_labels.noren_01.text == "已有 4","Initial copies counted")
	await shot("open")
	Game.save_enabled = true
	await click(console.card_buttons.noren_01)
	await click(console.card_buttons.noren_01)
	await click(console.card_buttons.noren_40)
	check(Game.state.deck == ["noren_01","noren_01","noren_40"],"Each real GUI click adds exactly one copy, including last card")
	check(console.owned_labels.noren_01.text == "已有 6" and console.owned_labels.noren_40.text == "已有 1","Counts refresh after repeated clicks")
	check(console.output.get_parsed_text().contains("已添加"),"Addition feedback visible")
	if failures > 0:
		get_tree().quit(1)
		return
	Game.state = {}
	check(Game.load_game() and Game.state.deck == ["noren_01","noren_01","noren_40"],"Clicked additions survive disk reload")
	Game.page = "card_library"
	Game.changed.emit()
	await settle()
	await key(KEY_A,true,true)
	console = app.card_console
	var path := Game.save_path
	Game.save_path = "user://missing_console_click_directory/save.json"
	await click(console.card_buttons.noren_23)
	check(Game.state.deck.size() == 3 and console.owned_labels.noren_23.text == "已有 0" and console.output.get_parsed_text().contains("添加失败"),"Failed save rolls back click and count")
	Game.save_path = path
	console.submit("addcard 23 2")
	check(console.owned_labels.noren_23.text == "已有 2","Text commands still work and refresh counts")
	await shot("added")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.card_console) and app.view.process_mode != Node.PROCESS_MODE_DISABLED,"Esc closes and restores underlying page")
	check(app.view.card_views.size() == 6,"Owned library refreshes after close")
	await key(KEY_A,true,true)
	console = app.card_console
	await get_tree().create_timer(0.1).timeout
	check(console.owned_labels.noren_23.text == "已有 2","Reopening reflects current ownership")
	var frozen: Array = Game.state.deck.duplicate()
	Game.training_mode = true
	await click(console.card_buttons.noren_23)
	check(Game.state.deck == frozen and console.output.get_parsed_text().contains("请先进入演练战斗"),"Training click cannot mutate permanent deck")
	Game.training_mode = false
	Game.state = {}
	await click(console.card_buttons.noren_23)
	check(Game.state.is_empty() and console.output.get_parsed_text().contains("请先开始"),"No-adventure click cannot create a deck")
	await key(KEY_A,true,true)
	check(not is_instance_valid(app.card_console),"Ctrl+Shift+A closes console")
	Game.save_enabled = false
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("CARD CONSOLE VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
