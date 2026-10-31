extends Node
## Run only from a project copy with a distinct custom_user_dir_name.
## Headless: contracts and integration. Windowed: same checks plus GPU-rendered
## screenshots and CPU frame-interval samples (not GPU execution-time claims).
const Atmosphere = preload("res://scripts/combat/battle_atmosphere.gd")
const PLACES := ["port", "hotel", "pump", "block5", "power", "church", "tower", "garden", "hive", "hospital", "junkyard", "bar", "alley"]
const CAPTURE_PLACES := ["pump", "garden", "hive", "church", "hospital", "hotel", "bar", "power", "alley"]
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var samples: Dictionary = {}
var output := ""
var app: Control
var original_battle: Dictionary
var rendered := false

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func clock_value(material: ShaderMaterial) -> float:
	return float(material.get_shader_parameter("atmosphere_time"))

func fingerprint(material: ShaderMaterial) -> String:
	var values: Dictionary = {}
	# Dummy rendering does not expose shader introspection; explicit parameters
	# are available on both headless and GPU backends.
	for key in Atmosphere.DEFAULTS.keys() + ["ground_start", "art_aspect"]:
		if key in ["atmosphere_time", "motion_enabled"]: continue
		values[key] = str(material.get_shader_parameter(key))
	return JSON.stringify(values)

func frames(count: int = 2) -> void:
	for _i in count:
		await get_tree().process_frame

func settle_battle() -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while Game.battle_busy or Game.transition_locked or not app.view.initialized:
		if Time.get_ticks_msec() > deadline:
			verify(false, "Battle presentation settles within 20 seconds")
			return false
		await get_tree().process_frame
	# Entry banners and hand tweens can finish after the combat busy flag clears.
	# Move only the viewport's synthetic pointer away from cards for clean captures.
	var pointer := InputEventMouseMotion.new()
	pointer.position = Vector2(16,16)
	pointer.global_position = pointer.position
	get_viewport().push_input(pointer, true)
	await get_tree().create_timer(0.7).timeout
	verify(not Game.battle_busy and not Game.transition_locked, "Battle is settled after entry animation")
	return not Game.battle_busy and not Game.transition_locked

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "user://battle-atmosphere-qa"
	DirAccess.make_dir_recursive_absolute(output)
	rendered = DisplayServer.get_name() != "headless"
	# Fail early rather than accidentally read/write a player's user directory.
	verify(str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")) != "MidnightCommissionDemo", "QA project uses an isolated custom user directory")
	if not failures.is_empty():
		finish()
		return
	Game.save_enabled = false
	Game.save_path = "user://atmosphere-unused-checkpoint.json"
	Game.meta_path = "user://atmosphere-unused-meta.json"
	PlayerSettings.settings_path = "user://atmosphere-unused-settings.cfg"
	await check_material_contract()
	original_battle = Game.battles["B04"].duplicate(true)
	Game.start_training("B04")
	app = preload("res://scenes/main.tscn").instantiate()
	app.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(app)
	await frames()
	if not await settle_battle():
		finish()
		return
	for place_id in PLACES:
		await check_place(place_id)
	await check_lifecycle()
	Game.battles["B04"] = original_battle
	Game.restore_training()
	verify(not Game.save_enabled, "Rendering and scene switches never enable saving")
	finish()

func check_material_contract() -> void:
	var texture := GradientTexture2D.new()
	texture.width = 144
	texture.height = 90
	var holder := Control.new()
	add_child(holder)
	var scenery := TextureRect.new()
	scenery.texture = texture
	holder.add_child(scenery)
	var seen: Dictionary = {}
	var previous_material: ShaderMaterial
	for place_id in PLACES:
		var material: ShaderMaterial = Atmosphere.apply_to(scenery, place_id, 0.5)
		verify(material != null and scenery.material == material, "Material attaches to original background: " + place_id)
		if material == null: continue
		verify(material != previous_material, "Scene owns a separate material: " + place_id)
		verify(is_zero_approx(clock_value(material)), "Each scene starts its own clock: " + place_id)
		verify(bool(material.get_shader_parameter("motion_enabled")), "Motion defaults on: " + place_id)
		seen[fingerprint(material)] = true
		previous_material = material
	verify(seen.size() >= 7, "Environment profiles are meaningfully differentiated")
	var material: ShaderMaterial = Atmosphere.apply_to(scenery, "unknown_qa_location", 0.5)
	for key in ["fog_strength", "dust_strength", "light_strength", "ray_strength", "water_strength", "flicker_strength", "stream_strength"]:
		verify(is_zero_approx(float(material.get_shader_parameter(key))), "Unknown location preserves original artwork: " + key)
	material = Atmosphere.apply_to(scenery, "hive", 0.5)
	Atmosphere.advance(scenery, 0.04)
	verify(is_equal_approx(clock_value(material), 0.04), "Visible atmosphere advances with delta")
	Atmosphere.advance(scenery, 10.0)
	verify(is_equal_approx(clock_value(material), 0.14), "Long frames are clamped to 0.1 seconds")
	var frozen := clock_value(material)
	scenery.hide()
	Atmosphere.advance(scenery, 0.08)
	verify(is_equal_approx(clock_value(material), frozen), "Hidden background stops its clock")
	scenery.show()
	holder.hide()
	Atmosphere.advance(scenery, 0.08)
	verify(is_equal_approx(clock_value(material), frozen), "Hidden ancestor stops its background clock")
	holder.show()
	material.set_shader_parameter("motion_enabled", false)
	Atmosphere.advance(scenery, 0.08)
	verify(is_equal_approx(clock_value(material), frozen), "Disabled motion stops its clock")
	material.set_shader_parameter("motion_enabled", true)
	get_tree().paused = true
	Atmosphere.advance(scenery, 0.08)
	verify(is_equal_approx(clock_value(material), frozen), "Paused scene tree stops the atmosphere clock")
	get_tree().paused = false
	holder.queue_free()
	await frames()

func covers_canvas(stage: Control) -> bool:
	var bounds: Rect2 = stage.scenery.get_global_rect()
	return bounds.position.x <= 0.1 and bounds.position.y <= 0.1 and bounds.end.x >= 1439.9 and bounds.end.y >= 899.9

func check_place(place_id: String) -> void:
	var before: Dictionary = app.view.model.snapshot()
	var old_scenery: WeakRef = weakref(app.view.stage.scenery)
	var battle := original_battle.duplicate(true)
	battle.placeId = place_id
	Game.battles["B04"] = battle
	app.swap_view()
	await frames(3)
	if not await settle_battle(): return
	verify(old_scenery.get_ref() == null, "Old sibling background is released: " + place_id)
	var stage: Control = app.view.stage
	verify(app.view.model.snapshot() == before, "Changing atmosphere preserves the combat snapshot: " + place_id)
	verify(is_instance_valid(stage.scenery), "Battle has its original textured background: " + place_id)
	if not is_instance_valid(stage.scenery): return
	var material := stage.scenery.material as ShaderMaterial
	verify(material != null, "Real battle integrates atmosphere: " + place_id)
	if material == null: return
	verify(stage.scenery.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Atmosphere does not intercept battle input: " + place_id)
	verify(covers_canvas(stage), "Wide scenery covers the whole canvas: " + place_id)
	verify(stage.scenery.get_parent() == stage.get_parent(), "Atmosphere preserves full-canvas sibling layering: " + place_id)
	var expected := TextureRect.new()
	add_child(expected)
	var asset_id: String = Game.assets[Game.place_data(place_id).backgroundAssetId].battleAssetId
	var ground_start := float(Game.assets[asset_id].get("groundStart", 0.5))
	expected.texture = stage.scenery.texture
	var expected_material: ShaderMaterial = Atmosphere.apply_to(expected, place_id, ground_start)
	verify(fingerprint(material) == fingerprint(expected_material), "Battle passes the correct location profile: " + place_id)
	expected.queue_free()
	var wide: Rect2 = stage.scenery.get_global_rect()
	stage.zoom = 1.28
	stage.focus_x = 960.0
	stage.kick_camera(1.0, 16.0)
	verify(covers_canvas(stage), "Zoom and shake leave no exposed background edges: " + place_id)
	verify(stage.scenery.get_global_rect() != wide, "Atmosphere follows combat camera framing: " + place_id)
	stage.zoom = 1.0
	stage.focus_x = 720.0
	stage.shake_duration = 0.0
	await frames()
	verify(app.view.model.snapshot() == before, "Camera and atmosphere never mutate combat: " + place_id)
	if rendered and place_id in CAPTURE_PLACES:
		if not await settle_battle(): return
		await capture_pair(stage, place_id)
		await shot(place_id + "-battle")
		if place_id == "pump" and OS.get_environment("QA_CAPTURE_MOTION") == "1":
			await capture_motion(stage)
		if place_id == "hive":
			samples["motion_on"] = await frame_intervals(material, true)
			samples["motion_off"] = await frame_intervals(material, false)
			material.set_shader_parameter("motion_enabled", true)

func capture_pair(stage: Control, place_id: String) -> void:
	var overlay := TextureRect.new()
	overlay.texture = stage.scenery.texture
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	overlay.size = Vector2(1440, 900)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 100
	overlay.material = stage.scenery.material.duplicate()
	add_child(overlay)
	var material := overlay.material as ShaderMaterial
	material.set_shader_parameter("atmosphere_time", 0.0)
	await shot(place_id + "-art-t0")
	material.set_shader_parameter("atmosphere_time", 6.0)
	await shot(place_id + "-art-t6")
	var first := Image.load_from_file(output.path_join(place_id + "-art-t0.png"))
	var second := Image.load_from_file(output.path_join(place_id + "-art-t6.png"))
	var changed := 0
	var sampled := 0
	for y in range(0, first.get_height(), 8):
		for x in range(0, first.get_width(), 8):
			sampled += 1
			if first.get_pixel(x, y) != second.get_pixel(x, y): changed += 1
	verify(changed > 20, "Rendered atmosphere actually changes between times: " + place_id)
	samples[place_id + "_pixel_change"] = {"sampledPixels": sampled, "changedPixels": changed, "timeSeconds": [0, 6]}
	if Atmosphere.LIGHT_BOXES.has(place_id):
		material.set_shader_parameter("atmosphere_time", 1.6)
		await shot(place_id + "-art-lamp-off")
		var dim := Image.load_from_file(output.path_join(place_id + "-art-lamp-off.png"))
		var box: Vector4 = Atmosphere.LIGHT_BOXES[place_id][0]
		var on_energy := 0.0
		var off_energy := 0.0
		var lit_pixels := 0
		for y in range(int(box.y * first.get_height()), int(box.w * first.get_height())):
			for x in range(int(box.x * first.get_width()), int(box.z * first.get_width())):
				var light := first.get_pixel(x,y)
				if maxf(light.r,maxf(light.g,light.b)) < 0.4: continue
				on_energy += light.r + light.g + light.b
				var dark := dim.get_pixel(x,y)
				off_energy += dark.r + dark.g + dark.b
				lit_pixels += 1
		verify(lit_pixels > 5 and off_energy < on_energy * 0.85, "Selected lamp visibly dims at least 15 percent: " + place_id)
		samples[place_id + "_lamp_dimming"] = {"litPixels":lit_pixels,"offOnRatio":off_energy/maxf(on_energy,0.001)}
	overlay.queue_free()
	await frames()

func capture_motion(stage: Control) -> void:
	var material := stage.scenery.material as ShaderMaterial
	var prior_time := clock_value(material)
	var was_processing := stage.is_processing()
	stage.set_process(false)
	var saved := true
	for frame in 60:
		material.set_shader_parameter("atmosphere_time", float(frame) / 12.0)
		await RenderingServer.frame_post_draw
		var path := output.path_join("motion-%03d.png" % frame)
		if get_viewport().get_texture().get_image().save_png(path) != OK: saved = false
	material.set_shader_parameter("atmosphere_time", prior_time)
	stage.set_process(was_processing)
	verify(saved, "Optional 60-frame pump battle motion preview saved")
	samples["motionCapture"] = {"pathPattern": output.path_join("motion-%03d.png"), "frames": 60, "fps": 12, "durationSeconds": 5, "scene": "pump", "backgroundClockControlled": true}

func shot(id: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output.path_join(id + ".png")
	verify(get_viewport().get_texture().get_image().save_png(path) == OK, "Rendered screenshot saved: " + id)
	captures.append(path)

func frame_intervals(material: ShaderMaterial, enabled: bool) -> Dictionary:
	material.set_shader_parameter("motion_enabled", enabled)
	await frames(12)
	var intervals: Array[float] = []
	var prior := Time.get_ticks_usec()
	for _i in 90:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - prior) / 1000.0)
		prior = now
	intervals.sort()
	var total := 0.0
	for interval in intervals: total += interval
	return {"samples": intervals.size(), "meanCpuFrameIntervalMs": total / intervals.size(), "p95CpuFrameIntervalMs": intervals[85], "scope": "CPU frame intervals, includes pacing and all battle rendering; not GPU time"}

func check_lifecycle() -> void:
	var material := app.view.stage.scenery.material as ShaderMaterial
	var frozen := clock_value(material)
	app.hide()
	await frames(5)
	verify(is_equal_approx(clock_value(material), frozen), "Hidden battle stops atmosphere in the real scene")
	app.show()
	get_tree().paused = true
	await frames(5)
	verify(is_equal_approx(clock_value(material), frozen), "Paused battle stops atmosphere in the real scene")
	get_tree().paused = false
	await frames(5)
	verify(clock_value(material) > frozen, "Atmosphere resumes after pause")
	var background: WeakRef = weakref(app.view.stage.scenery)
	await preload("res://scripts/combat/audio_cleanup.gd").release(app, get_tree())
	app.queue_free()
	await frames(3)
	verify(background.get_ref() == null, "Leaving battle releases its sibling background and effect")

func finish() -> void:
	var result := {"checks": checks, "failures": failures.size(), "failureMessages": failures, "rendered": rendered, "screenshots": captures, "frameSamples": samples, "programDriven": true, "physicalInput": false}
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("BATTLE ATMOSPHERE: %d checks, %d failures; %s" % [checks, failures.size(), output])
	get_tree().quit(0 if failures.is_empty() else 1)
