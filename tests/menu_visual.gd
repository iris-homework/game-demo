extends Node
## 实际主菜单输入与环境采样，所有保存写入测试专用目录。
## 原生 PNG 与局部 shader；核对纹理尺寸、动作时钟、灯牌、开关和资源释放。
## 归一坐标由审核帧源 1672x941 的灯牌多边形中心换算；映射到画布约为 (654,411) 与 (1396,325)。
const NOREN_FEET := Vector2(0.225, 0.92)
const LEFT_BOTTLE_SIGN := Vector2(0.458, 0.455)
const RIGHT_BOTTLE_SIGN := Vector2(0.925, 0.359)
var app: Control
var output_dir := ""
var suite := "capture"
var checks := 0
var failures := 0
var records: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message,"passed":ok,"page":Game.page})
	if not ok:
		failures += 1
		push_error("MENU QA: " + message)

func art_point(env: Control, normalized: Vector2) -> Vector2:
	# 审核帧源的归一坐标映射到画布，用于核对双脚与灯牌仍在可视范围。
	return env.global_position + env.artwork_rect.position + normalized * env.artwork_rect.size

func clock_frame(env: Control) -> int:
	# 使用实际播放倍率核对审核帧序，不改变源帧的 80ms 时间。
	return int(fmod(env.animation_time * env.playback_speed, env.loop_duration) / env.frame_duration)

func frame_observation(env: Control, elapsed: float) -> Dictionary:
	var texture: Texture2D = env.source_texture
	return {
		"elapsedSeconds": elapsed,
		"environmentClock": env.animation_time,
		"playbackSpeed": env.playback_speed,
		"effectiveLoopSeconds": env.loop_duration / env.playback_speed,
		"frameIndex": env.frame_index,
		"framePath": texture.resource_path,
		"artSource": str(env.get_script().get_script_constant_map().get("SOURCE_ART", "")),
		"sourceSize": str(texture.get_size()),
		"currentTextureId": texture.get_instance_id(),
		"environmentFrameResources": (1 if env.source_texture != null else 0),
		"textureMemoryBytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
	}

func settle(seconds: float = 0.16) -> void:
	await get_tree().create_timer(seconds).timeout

func button(name_text: String) -> Button:
	return app.view.find_child(name_text, true, false) as Button

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle(0.08)

func click(node: Control) -> void:
	if node == null:
		check(false,"required button exists")
		return
	# Avoid sampling a button during a scene-cover transition.
	while Game.transition_locked or Game.battle_busy:
		await settle(0.1)
	var point := get_viewport().get_final_transform() * node.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.warp_mouse(point)
	Input.parse_input_event(motion)
	await get_tree().process_frame
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle()

func shot(name_text: String) -> void:
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output_dir.path_join(name_text + ".png")) == OK,"save screenshot " + name_text)

func stage(state: Dictionary = {}) -> void:
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.training_backup.clear()
	Game.state = state.duplicate(true)
	Game.page = "menu"
	Game.changed.emit()
	await settle(0.5)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--output-dir" and i + 1 < args.size(): output_dir = args[i+1]
		if args[i] == "--suite" and i + 1 < args.size(): suite = args[i+1]
	if output_dir.is_empty():
		push_error("Menu test requires an explicit isolated output directory")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	Game.save_enabled = false
	Game.save_path = output_dir.path_join("test-checkpoint.json")
	Game.meta_path = output_dir.path_join("test-meta.json")
	# Re-running this dedicated suite resets only its explicitly named fixtures.
	for fixture in [Game.save_path,Game.meta_path]:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(fixture + suffix): DirAccess.remove_absolute(fixture + suffix)
	Game.state.clear()
	Game.page = "menu"
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle(0.6)
	var metadata := {"window":str(DisplayServer.window_get_size()),"logicalCanvas":str(get_viewport().get_visible_rect().size),"captureSize":str(get_viewport().get_texture().get_image().get_size()),"renderer":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"engine":Engine.get_version_info().string,"userDataDirectory":OS.get_user_data_dir(),"checkpoint":Game.save_path,"meta":Game.meta_path,"autoSave":Game.save_enabled}
	write_json("environment.json",metadata)
	check("artifacts/qa/menu-gif-2026-10-07/engine-userdata" in OS.get_user_data_dir().replace("\\","/"),"autoload user directory is isolated from formal saves")
	check(button("continue_commission").disabled,"no save disables continue")
	check(app.view.progress_summary.text == "暂无委托记录","no save summary is honest")
	var env: Control = app.view.environment
	check(env.source_texture.get_size() == Vector2(1672,941),"native artwork retains full 1672x941 resolution")
	check(env.source_texture.resource_path == "res://assets/menu/noren-bar-seated-v1.png","menu samples original full-color PNG")
	check(env.background.material is ShaderMaterial and env.artwork_material == env.background.material,"local motion shader is connected")
	check(not ResourceLoader.has_cached("res://assets/menu/noren_idle_frames/frame_000.png"),"low-resolution GIF frames are not loaded")
	check(is_equal_approx(env.frame_duration,0.08) and is_equal_approx(env.loop_duration,4.8) and is_equal_approx(env.playback_speed,1.5),"original animation timing retains the requested 1.5x speed")
	check(is_equal_approx(env.loop_duration / env.playback_speed,3.2),"effective loop duration is 3.2 seconds")
	check(env.background is TextureRect and env.background.name == "tavern_art","background exposes the tavern_art texture node")
	check(env.background.position.is_equal_approx(Vector2(-80.0,0.0)) and env.background.size.is_equal_approx(Vector2(1600.0,900.0)),"background keeps the approved -80,0 / 1600x900 mapping")
	check(env.artwork_rect.size.x > 0.0 and absf(env.artwork_rect.position.x - env.background.position.x) <= 0.5 and absf(env.artwork_rect.size.x - env.background.size.x) <= 0.5,"artwork rect is measured from the frame source")
	for legacy in ["noren_original","window_rain","neon_glow","commission_terminal"]:
		check(app.view.environment.find_child(legacy,true,false) == null,"legacy environment node removed " + legacy)
	var canvas_rect: Rect2 = get_viewport().get_visible_rect()
	for key in [["诺伦双脚",NOREN_FEET],["左瓶形灯牌",LEFT_BOTTLE_SIGN],["右瓶形灯牌",RIGHT_BOTTLE_SIGN]]:
		check(canvas_rect.has_point(art_point(env,key[1])),"artwork keypoint inside canvas " + key[0])
	var right_sign_center: Vector2 = art_point(env,RIGHT_BOTTLE_SIGN)
	for node in app.view.ui_layer.find_children("*","Button",true,false):
		if node.is_visible_in_tree():
			check(not node.get_global_rect().has_point(right_sign_center),"right button keeps clear of the right bottle sign " + str(node.name))
	for node in app.view.find_children("*","Label",true,false):
		if node.is_visible_in_tree(): check(get_viewport().get_visible_rect().encloses(node.get_global_rect()),"label inside canvas " + node.text)
	for node in app.view.find_children("*","Button",true,false):
		if node.is_visible_in_tree():
			check(get_viewport().get_visible_rect().encloses(node.get_global_rect()),"button inside canvas " + str(node.name))
	await shot("01-menu-no-save")
	if suite == "input": await input_suite()
	elif suite == "performance": await performance_suite()
	elif suite == "native_art": await native_art_suite()
	else:
		var state := Game.initial_state()
		state.currentScene = "map"
		state.completedEventIds = ["E01"]
		state.faction = "company"
		await stage(state)
		await shot("02-menu-progress")
		app.view._set_training_open(true)
		await shot("03-training-menu")
	write_json("checks.json",records)
	print("MENU QA: %d checks, %d failures; %s" % [checks,failures,output_dir])
	app.queue_free()
	app = null
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().call_deferred("quit",0 if failures == 0 else 1)

func input_suite() -> void:
	# Mouse activation plus keyboard focus/activation exercise the actual GUI dispatch.
	await click(button("motion_toggle"))
	var env: Control = app.view.environment
	var frozen: float = env.animation_time
	await settle(0.3)
	check(not env.get_motion_enabled() and env.frame_index == 0,"real static toggle shows the approved frame 0")
	check(is_equal_approx(env.animation_time,frozen),"static mode stops environment clock")
	await key(KEY_TAB)
	var focused_button := get_viewport().gui_get_focus_owner()
	check(focused_button != null and focused_button is Button and not focused_button.disabled,"Tab reaches enabled button")
	button("motion_toggle").grab_focus()
	await key(KEY_SPACE)
	check(env.get_motion_enabled(),"Space activates focused dynamic toggle")
	await settle(0.3)
	check(env.animation_time > frozen,"dynamic clock resumes the frozen original clock")
	check(absi(env.frame_index - clock_frame(env)) <= 1,"frame animation follows the environment clock")
	var advanced_frame: int = env.frame_index
	await settle(0.5)
	check(env.frame_index != advanced_frame,"frames keep advancing while the dynamic clock runs")
	await click(button("training_toggle"))
	check(app.view.training_open and button("training_B04").is_visible_in_tree(),"training group expands with actual input")
	for code in ["training_B04","training_B12"]:
		check(get_viewport().get_visible_rect().encloses(button(code).get_global_rect()),"expanded button inside canvas " + code)
	await shot("04-training-expanded")
	await key(KEY_ESCAPE)
	check(Game.page == "menu" and not app.view.training_open,"Escape closes training before navigation")
	# New game without progress routes to dialogue and the destroyed menu has no environment left.
	var old_env: WeakRef = weakref(env)
	var old_frame: WeakRef = weakref(env.source_texture)
	await click(button("new_commission"))
	check(Game.page == "dialogue" and Game.state.activeEventId == "E01","actual new click starts first event")
	await settle()
	check(old_env.get_ref() == null and get_tree().get_nodes_in_group("menu_environment").is_empty(),"leaving menu releases environment")
	check(old_frame.get_ref() == null,"leaving menu releases the native artwork texture")
	Game.go_map()
	await settle()
	Game.state.faction = "resistance"
	Game.state.currentPlaceId = "hospital"
	var adventure: Dictionary = Game.state.duplicate(true)
	Game.menu()
	await settle(0.5)
	check("医院" in app.view.progress_summary.text and "革命军" in app.view.progress_summary.text,"summary uses real location and faction")
	check(not button("continue_commission").disabled,"memory progress enables continue")
	var revision_before := Game.revision
	await settle(0.4)
	check(Game.state == adventure and Game.revision == revision_before,"menu display and animation do not mutate progress")
	await click(button("new_commission"))
	check(app.view.confirm_dialog.visible,"existing progress shows overwrite confirmation")
	check(get_viewport().gui_get_focus_owner() == app.view.confirm_cancel,"confirmation defaults to safe cancel focus")
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == app.view.confirm_ok,"Tab stays in confirmation")
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == app.view.confirm_cancel,"confirmation focus loops inside modal")
	await click(button("continue_commission"))
	check(Game.page == "menu" and Game.state == adventure and app.view.confirm_dialog.visible,"modal blocks underlying menu input")
	await shot("05-new-confirm")
	await key(KEY_ESCAPE)
	check(Game.page == "menu" and Game.state == adventure and not app.view.confirm_dialog.visible,"Escape dismisses confirmation without resuming or overwriting")
	await click(button("new_commission"))
	await click(app.view.confirm_cancel)
	check(Game.page == "menu" and Game.state == adventure and not app.view.confirm_dialog.visible,"cancel button closes modal and preserves progress")
	await click(button("continue_commission"))
	check(Game.page == "map" and Game.state == adventure,"actual continue restores correct scene")
	Game.menu()
	await settle(0.5)
	await click(button("cyberware_archive"))
	check(Game.page == "cyberware" and Game.state == adventure,"archive keeps adventure state")
	for node in app.view.find_children("*","Button",true,false):
		if "返回主菜单" in node.text: await click(node)
	check(Game.page == "menu","archive return button returns to menu")
	await click(button("motion_toggle"))
	check(not app.view.environment.get_motion_enabled(),"static choice switched off")
	for battle_id in ["B04","B12"]:
		await click(button("training_toggle"))
		await click(button("training_" + battle_id))
		await wait_unlocked()
		check(Game.page == "battle" and Game.training_mode and Game.state.battleId == battle_id,"real training entrance " + battle_id)
		# Existing outcome API ends the exercise; this is not a full combat playthrough.
		Game.finish_training("surrender")
		await wait_unlocked()
		await settle(0.5)
		check(Game.page == "menu" and Game.state == adventure and not Game.training_mode,"training restores adventure " + battle_id)
		check(not app.view.environment.get_motion_enabled(),"static mode persists on menu rebuild")
		check(get_tree().get_nodes_in_group("menu_environment").size() == 1,"only one environment remains after return")
	# Only disk checkpoint: the menu can report existence without loading it.
	check(Game.save_game(),"write isolated checkpoint")
	await stage()
	check(app.view.progress_summary.text == "已有检查点" and Game.state.is_empty(),"disk summary does not restore state")
	button("continue_commission").grab_focus()
	await key(KEY_ENTER)
	check(Game.page == "map" and Game.state.currentPlaceId == "hospital","Enter continues isolated disk checkpoint")
	# Invalid disk checkpoint must produce the existing error and stay on menu.
	var corrupt := FileAccess.open(Game.save_path,FileAccess.WRITE)
	corrupt.store_string("broken checkpoint fixture")
	corrupt.close()
	if FileAccess.file_exists(Game.save_path + ".bak"): DirAccess.remove_absolute(Game.save_path + ".bak")
	await stage()
	await click(button("continue_commission"))
	check(Game.page == "menu" and Game.state.is_empty() and not Game.last_error.is_empty(),"corrupt checkpoint stays on menu with error")
	var kept := FileAccess.get_file_as_string(Game.save_path)
	await click(button("new_commission"))
	await click(app.view.confirm_cancel)
	check(FileAccess.get_file_as_string(Game.save_path) == kept,"cancel preserves corrupt file for recovery")
	await click(button("new_commission"))
	await click(app.view.confirm_ok)
	check(Game.page == "dialogue" and Game.state.activeEventId == "E01","confirmed new game replaces in-memory progress intentionally")
	check(FileAccess.get_file_as_string(Game.save_path) == kept,"auto save disabled does not overwrite fixture")
	# Actual window minimization sends focus-out; restore before further pointer tests.
	await stage(adventure)
	if not app.view.environment.get_motion_enabled(): await click(button("motion_toggle"))
	await settle(0.2)
	check(app.view.environment.get_motion_enabled(),"dynamic mode enabled before window pause test")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	await settle(0.4)
	var paused: float = app.view.environment.animation_time
	var paused_frame: int = app.view.environment.frame_index
	await settle(0.3)
	check(not app.view.environment.focused and is_equal_approx(paused,app.view.environment.animation_time) and paused_frame == app.view.environment.frame_index,"minimized window freezes environment clock and frame through focus notification")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	# Windows may deny an app's own foreground request after minimization.
	# The external QA runner activates this process, as a user reselecting it would.
	write_json("focus-request.json", {"reason":"restore minimized QA window"})
	for attempt in 30:
		if app.view.environment.focused and app.view.environment.animation_time > paused: break
		await settle(0.1)
	var restored := frame_observation(app.view.environment, 0.0)
	restored["windowFocused"] = DisplayServer.window_is_focused()
	restored["windowMode"] = DisplayServer.window_get_mode()
	restored["motionEnabled"] = app.view.environment.get_motion_enabled()
	restored["pausedClock"] = paused
	write_json("restore-observation.json", restored)
	check(app.view.environment.focused and app.view.environment.animation_time > paused,"restored window resumes environment")
	# The corrupt-fixture error above uses the existing four-second notice timer.
	await settle(4.1)
	await shot("06-menu-final")
	await key(KEY_ESCAPE)
	check(Game.page == "map","global Escape still restores existing adventure")

func wait_unlocked() -> void:
	var count := 0
	while (Game.transition_locked or Game.battle_busy) and count < 120:
		count += 1
		await settle(0.1)
	check(not Game.transition_locked and not Game.battle_busy,"transition releases input lock")

func performance_suite() -> void:
	var data := {}
	var observations: Array = []
	for mode in [false,true]:
		app.view.environment.set_motion_enabled(mode)
		await settle(1.0)
		var samples: Array = []
		var started := Time.get_ticks_usec()
		var previous := started
		var duration := 20.0 if mode else 8.0
		var next_capture := 0.0
		var last_frame: int = app.view.environment.frame_index
		var frame_changes := 0
		while float(Time.get_ticks_usec() - started)/1000000.0 < duration:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now - previous)/1000.0)
			previous = now
			var current_frame: int = app.view.environment.frame_index
			if current_frame != last_frame:
				frame_changes += 1
				last_frame = current_frame
			var elapsed := float(now - started)/1000000.0
			if mode and elapsed >= next_capture:
				# Readback/PNG encoding stalls the render loop at large resolutions.
				# Keep timed samples free of screenshots; native_art captures poses separately.
				var observation := frame_observation(app.view.environment,elapsed)
				observations.append(observation)
				next_capture += 5.0
				previous = Time.get_ticks_usec()
		await shot("animation-end" if mode else "static-reference")
		if mode:
			var final_observation := frame_observation(app.view.environment,float(Time.get_ticks_usec()-started)/1000000.0)
			final_observation["screenshot"] = "animation-end.png"
			observations.append(final_observation)
		samples.sort()
		var total := 0.0
		for value in samples: total += float(value)
		var mean: float = total / maxf(1,samples.size())
		data["dynamic" if mode else "static"] = {"durationSeconds":duration,"sampleCount":samples.size(),"meanFrameMs":mean,"p95FrameMs":samples[int(samples.size()*0.95)],"meanFps":1000.0/maxf(0.001,mean),"clock":app.view.environment.animation_time,"frameIndex":app.view.environment.frame_index,"frameCount":app.view.environment.frame_count,"frameChanges":frame_changes,"environmentFrameResources":(1 if app.view.environment.source_texture != null else 0),"textureMemoryBytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)}
	write_json("performance.json",data)
	write_json("animation-observations.json", observations)
	check(float(data.dynamic.meanFps) >= 59.0,"dynamic mean frame rate meets 60 FPS target within timing tolerance")
	check(float(data.dynamic.p95FrameMs) <= 20.0,"dynamic 95th percentile frame time remains smooth")
	check(float(data.dynamic.clock) >= 19.0,"environment clock advances throughout observed dynamic interval")
	check(int(data.dynamic.frameChanges) >= 350,"1.5x playback advances at least 350 frames during the 20 second sample")
	check(int(data.dynamic.environmentFrameResources) == 1,"dynamic run keeps only one native artwork texture resident")
	check(int(data.dynamic.textureMemoryBytes) > 0,"rendering texture memory is read from RenderingServer, not from PNG file size")

func write_json(file_name: String, value) -> void:
	var file := FileAccess.open(output_dir.path_join(file_name),FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t"))

# Focused rendering regression: use real GPU output, not only shader parameter values.
func native_art_image(env: Control, index: int) -> Image:
	env._show_frame(index)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image.save_png(output_dir.path_join("native-%02d.png" % index)) == OK, "capture native animation pose %d" % index)
	return image

func art_region_samples(env: Control, image: Image, region: Rect2) -> PackedColorArray:
	var samples := PackedColorArray()
	for y in range(12):
		for x in range(12):
			var source_point := region.position + region.size * Vector2((x + 0.5)/12.0, (y + 0.5)/12.0)
			var logical := art_point(env, source_point / Vector2(1672,941))
			var pixel := logical / Vector2(1440,900) * Vector2(image.get_size())
			samples.append(image.get_pixel(int(pixel.x), int(pixel.y)))
	return samples

func region_delta(a: PackedColorArray, b: PackedColorArray) -> float:
	var delta := 0.0
	for i in a.size():
		delta += absf(a[i].r-b[i].r) + absf(a[i].g-b[i].g) + absf(a[i].b-b[i].b)
	return delta / float(a.size()*3)

func region_brightness(samples: PackedColorArray) -> float:
	var total := 0.0
	for color in samples: total += color.get_luminance()
	return total / float(samples.size())

func native_art_suite() -> void:
	var env: Control = app.view.environment
	env.set_process(false)
	var start := await native_art_image(env, 0)
	var moved := await native_art_image(env, 15)
	for region in [Rect2(395,350,55,90), Rect2(320,740,80,60), Rect2(450,780,60,70)]:
		check(region_delta(art_region_samples(env,start,region),art_region_samples(env,moved,region)) > 0.002,"rendered hand/boot motion changes pixels " + str(region))
	var left_dim := await native_art_image(env, 11)
	var right_dim := await native_art_image(env, 17)
	for pair in [[Rect2(750,370,30,115),left_dim],[Rect2(1530,285,35,105),right_dim]]:
		check(region_brightness(art_region_samples(env,pair[1],pair[0])) < region_brightness(art_region_samples(env,start,pair[0])) * 0.65,"rendered bottle sign dims at original keyframe " + str(pair[0]))
	await native_art_image(env,45)
	env.set_process(true)
	button("motion_toggle").grab_focus()
	await key(KEY_SPACE)
	check(not env.get_motion_enabled() and env.frame_index == 0,"keyboard dynamic toggle freezes native pose zero")
	var frozen: float = env.animation_time
	await settle(0.2)
	check(is_equal_approx(env.animation_time,frozen),"native static clock stays frozen")
	var old_env: WeakRef = weakref(env)
	var old_texture: WeakRef = weakref(env.source_texture)
	Game.open_cyberware()
	await settle(0.3)
	check(old_env.get_ref() == null and old_texture.get_ref() == null,"native menu and its single texture are released on exit")
	Game.menu()
	await settle(0.5)
	env = app.view.environment
	check(not env.get_motion_enabled() and env.frame_index == 0,"native static preference survives menu recreation")
	button("motion_toggle").grab_focus()
	await key(KEY_SPACE)
	await settle(0.3)
	check(env.get_motion_enabled() and env.animation_time > 0.0,"native animation resumes through keyboard input")
	write_json("native-observation.json",frame_observation(env,0.0))
