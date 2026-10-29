extends Node
## Run only in a copy with a QA user directory. GPU mode also captures keyframes.
const MAIN := preload("res://scenes/main.tscn")
const CLEANUP := preload("res://scripts/combat/audio_cleanup.gd")
var app: Control
var output := ""
var records: Array[Dictionary] = []
var failures: Array[String] = []
var slash_count := 0
var audio_count := 0

func check(ok: bool, label: String) -> void:
	records.append({"check": label, "passed": ok})
	if not ok:
		failures.append(label)
		push_error("STARTUP QA: " + label)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func key(code: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	get_viewport().push_input(event, true)

func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = app.view.new_button.get_global_rect().get_center()
	event.global_position = event.position
	get_viewport().push_input(event, true)

func new_app(fresh_session := true) -> void:
	if fresh_session and get_tree().root.has_meta("startup_splash_played"): get_tree().root.remove_meta("startup_splash_played")
	app = MAIN.instantiate()
	# Root parenting exercises the same startup gate as the actual main scene.
	get_tree().root.add_child(app)
	if is_instance_valid(app.startup_splash): app.startup_splash.set_process(false)
	await settle()

func dispose_app() -> void:
	if is_instance_valid(app.audio_hooks): app.audio_hooks.attach(null)
	await CLEANUP.release(app, get_tree())
	app.queue_free()
	await settle()

func screenshot(label: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)

func test_natural_finish() -> void:
	await new_app()
	var splash: Control = app.startup_splash
	check(is_instance_valid(splash), "fresh application starts splash automatically")
	check(app.view.process_mode == Node.PROCESS_MODE_DISABLED, "menu disabled behind splash")
	check(get_viewport().gui_get_focus_owner() == null, "hidden menu does not own focus")
	check(app.view.ui_layer.modulate.a == 0.0, "menu controls wait until reveal")
	check(splash.source_viewport.size == Vector2i(2880, 1800), "intro uses a 2x title render target")
	check(splash.title.logo_font.base_font.oversampling == 4.0, "title glyphs use private high resolution font sampling")
	var before: Dictionary = Game.state.duplicate(true)
	key(KEY_TAB, true)
	key(KEY_TAB, false)
	check(get_viewport().gui_get_focus_owner() == null, "Tab cannot focus hidden menu")
	key(KEY_F1, true)
	key(KEY_F1, false)
	check(not is_instance_valid(app.debug_panel), "debug shortcut blocked during splash")
	splash.slash_started.connect(func(): slash_count += 1)
	app.audio_player.cue_played.connect(func(cue: String, _path: String):
		if cue == "parry": audio_count += 1)
	if DisplayServer.get_name() != "headless":
		for point in [[0.0,"00-black"],[0.65,"01-ignite"],[1.4,"02-title"],[1.58,"03-slash"],[1.92,"04-split"],[2.45,"05-reveal"],[2.85,"06-open"]]:
			splash.set_timeline(float(point[0]))
			await screenshot(point[1])
		if OS.get_environment("QA_CAPTURE_SEQUENCE") == "1":
			DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
			for frame in 61:
				splash.set_timeline(float(frame) / 20.0)
				await settle()
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(output.path_join("frames/%03d.png" % frame))
	check(slash_count == 0 and audio_count == 0, "timeline seeking never emits slash or sound")
	splash.set_timeline(0.0)
	# Deterministically advance the actual runtime path, including signal crossings.
	for frame in 185: splash._process(1.0 / 60.0)
	await settle()
	check(not is_instance_valid(app.startup_splash), "natural finish removes overlay")
	check(not is_instance_valid(splash), "SubViewport owner freed after completion")
	check(slash_count == 1 and audio_count == 1, "natural play emits exactly one slash and sound")
	check(app.view.process_mode == Node.PROCESS_MODE_INHERIT, "menu processing restored")
	check(get_viewport().gui_get_focus_owner() == app.view.new_button, "normal menu entry receives focus")
	await get_tree().create_timer(0.5).timeout
	check(is_equal_approx(app.view.ui_layer.modulate.a, 1.0), "menu controls finish fading in")
	check(Game.state == before and Game.page == "menu", "intro never changes adventure state")
	if DisplayServer.get_name() != "headless": await screenshot("07-menu")
	app.view.library_button.pressed.emit()
	await settle()
	check(Game.page == "card_library", "menu entry works after intro")
	Game.menu()
	await settle()
	check(not is_instance_valid(app.startup_splash) and Game.page == "menu", "return to menu does not replay intro")
	await dispose_app()
	await new_app(false)
	check(not is_instance_valid(app.startup_splash), "recreating main in same session does not replay intro")
	await dispose_app()

func test_skip() -> void:
	for code in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]:
		await new_app()
		var before: Dictionary = Game.state.duplicate(true)
		key(code, true)
		await settle()
		check(not is_instance_valid(app.startup_splash), "skip key dismisses intro: " + str(code))
		key(code, true, true)
		key(code, false)
		await settle()
		check(Game.state == before and Game.page == "menu" and not is_instance_valid(app.view.confirm_dialog), "skip press/repeat/release never activates menu: " + str(code))
		await dispose_app()
	await new_app()
	mouse(true)
	await settle()
	mouse(false)
	await settle()
	check(not is_instance_valid(app.startup_splash) and Game.page == "menu" and not is_instance_valid(app.view.confirm_dialog), "skip click over New Commission cannot click through")
	key(KEY_ENTER, true)
	key(KEY_ENTER, false)
	await settle()
	check(Game.page != "menu" or is_instance_valid(app.view.confirm_dialog), "fresh confirm gesture works after skip")
	await dispose_app()

func _ready() -> void:
	if not OS.get_user_data_dir().to_lower().contains("startup-settings-qa"):
		push_error("Requires a copied project with startup-settings-qa in its custom user directory")
		get_tree().quit(2)
		return
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty() or not output.is_absolute_path():
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	PlayerSettings.settings_path = output.path_join("unused-settings.cfg")
	Game.state = {}
	Game.page = "menu"
	# A deferred entry allows adding a root child after the scene tree finishes setup.
	call_deferred("run")

func run() -> void:
	if OS.get_environment("QA_REALTIME") == "1":
		await new_app()
		var start := Time.get_ticks_msec()
		app.startup_splash.set_process(true)
		while is_instance_valid(app.startup_splash) and Time.get_ticks_msec() - start < 6000:
			await get_tree().process_frame
		var seconds := float(Time.get_ticks_msec() - start) / 1000.0
		check(not is_instance_valid(app.startup_splash), "real-time playback completes without manual seeking")
		check(seconds >= 2.8 and seconds < 4.5, "real-time startup duration within 2.8-4.5 seconds: " + str(seconds))
		await dispose_app()
	else:
		await test_natural_finish()
		await test_skip()
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path) and not FileAccess.file_exists(PlayerSettings.settings_path), "startup and skip do not write saves or preferences")
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":records.size(),"failures":failures,"records":records,"user_data":OS.get_user_data_dir(),"renderer":DisplayServer.get_name()},"\t"))
	file.close()
	print("STARTUP SPLASH: %d checks, %d failures" % [records.size(),failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
