extends "res://tests/combat/presentation/noss_intents_presentation_tests.gd"
## Real B23 transition, snapshot restoration and ordinary-battle isolation.

func wait_for_eyes(battle: Control, progress: float) -> Node2D:
	var deadline := Time.get_ticks_msec()+20000
	while Time.get_ticks_msec() < deadline:
		var eyes := battle.get_node_or_null("NossPhaseEyes")
		if eyes != null and eyes.reveal_progress >= progress: return eyes
		await get_tree().process_frame
	check(false,"eye reveal reaches %.2f within twenty seconds" % progress)
	return null

func check_gaze_binding(battle: Control, label: String) -> void:
	var wall: Node2D = battle.stage.noss_eye_wall
	var expected: Vector2 = wall.to_local(battle.stage.player.to_global(Vector2(0,-80)))
	check(wall.gaze_target.distance_to(expected) < 0.1,label+" gaze follows the player's body in wall-local coordinates")
	var material: ShaderMaterial = wall.get_node("CachedEyes").material
	var shader_gaze: Vector2 = material.get_shader_parameter("gaze_position")
	check(shader_gaze.distance_to(wall.gaze_position) < 0.1,label+" shader receives the smoothed gaze rather than the immediate target")
	var summary: Control = battle.enemy_summary
	for item in [["summary_region",summary],["intent_region",battle.enemy_intents[0]]]:
		var rect: Rect2 = item[1].get_global_rect()
		var local_origin: Vector2 = wall.to_local(rect.position)
		var local_end: Vector2 = wall.to_local(rect.end)
		var region: Vector4 = material.get_shader_parameter(item[0])
		check(Vector2(region.x,region.y).distance_to(local_origin) < 0.1 and Vector2(region.z,region.w).distance_to(local_end-local_origin) < 0.1,label+" "+str(item[0])+" tracks the actual HUD rectangle through camera transforms")

func wait_for_gaze(wall: Node2D) -> void:
	var deadline := Time.get_ticks_msec()+8000
	while wall.gaze_position.distance_to(wall.gaze_target) > 3.0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(wall.gaze_position.distance_to(wall.gaze_target) <= 3.0,"gaze settles near its target within eight wall-clock seconds")

func test_gaze(battle: Control) -> void:
	var wall: Node2D = battle.stage.noss_eye_wall
	var material: ShaderMaterial = wall.get_node("CachedEyes").material
	var frames: Variant = material.get_shader_parameter("tracking_frames")
	check(wall.eye_count == 82,"gaze and hierarchy preserve the authored 82-eye layout")
	check(frames != null and frames.size() == 5,"only five main eyes receive tracking frames")
	if frames != null and frames.size() == 5:
		var aligned := true
		for i in 5:
			var eye: Dictionary = wall._eyes[i]
			var frame: Vector4 = frames[i]
			aligned = aligned and Vector2(frame.x,frame.y).distance_to(eye.center) < 0.01
			aligned = aligned and Vector2(frame.z,frame.w).distance_to(Vector2(cos(eye.angle),sin(eye.angle))) < 0.01
		check(aligned,"five tracking frames retain the authored eye centers and rotated local axes")
	check_gaze_binding(battle,"wide camera")
	var state_before: String = JSON.stringify(battle.model.snapshot())
	var player: Node2D = battle.stage.player
	var original_position: Vector2 = player.position
	# Presentation-only fixtures: no card is played and no model position is changed.
	player.position.x = 220.0
	await get_tree().process_frame
	await get_tree().process_frame
	await wait_for_gaze(wall)
	wall.set_process(false)
	wall.ambient_time = 2.0
	await shot("phase2_gaze_left")
	wall.set_process(true)
	var previous: Vector2 = wall.gaze_position
	player.position.x = 940.0
	await get_tree().process_frame
	await get_tree().process_frame
	var shifted_target: Vector2 = wall.gaze_target
	check(wall.gaze_position.distance_to(previous) > 0.01 and wall.gaze_position.distance_to(shifted_target) > 20.0,"moving the real actor starts a delayed gaze shift instead of snapping")
	check(wall.gaze_position.distance_to(shifted_target) < previous.distance_to(shifted_target),"delayed gaze moves toward the new actor location")
	await wait_for_gaze(wall)
	wall.set_process(false)
	wall.ambient_time = 2.0
	await shot("phase2_gaze_right")
	wall.set_process(true)
	player.position = original_position
	await get_tree().process_frame
	await get_tree().process_frame
	var gaze_before_pause: Vector2 = wall.gaze_position
	var clock_before_pause: float = wall.ambient_time
	get_tree().paused = true
	await get_tree().create_timer(0.12,true).timeout
	check(wall.gaze_position.is_equal_approx(gaze_before_pause) and is_equal_approx(wall.ambient_time,clock_before_pause),"scene pause freezes gaze and the eye clock together")
	get_tree().paused = false
	player.position = original_position
	await get_tree().process_frame
	await get_tree().process_frame
	await wait_for_gaze(wall)
	check(JSON.stringify(battle.model.snapshot()) == state_before,"gaze motion and presentation fixtures leave every combat snapshot field unchanged")

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in output.to_lower() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("NOSS EYE WALL: requires a copied project and QA user directory/output")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused_checkpoint.json")
	Game.meta_path = output.path_join("unused_meta.json")
	capture = OS.get_environment("QA_CAPTURE") == "1"
	started = Time.get_ticks_msec()
	Engine.time_scale = 1.0 if capture else 6.0
	var battle: Control = await open_boss()
	check(not is_instance_valid(battle.stage.noss_eye_wall),"phase one retains its original scenery")
	await shot("phase1_original")
	battle.model.enemies[2].hp = 1
	battle.model.enemies[2].block = 0
	battle.shown_enemies = battle.model.enemies.duplicate(true)
	battle.refresh_enemy_hud()
	var uid: String = battle.model.hand[0]
	battle.model.instances[uid] = "noren_01"
	battle.select_card(uid)
	battle.play_selected(2)
	var eyes := await wait_for_eyes(battle,0.0)
	if eyes == null:
		report()
		get_tree().quit(2)
		return
	check(eyes.reveal_progress < 0.15,"transition begins in darkness before opening the eyes")
	var reveal_gaze: Vector2 = eyes.gaze_position
	eyes.gaze_target = Vector2(1100,500)
	check(Game.battle_busy and battle.get_node("NossPhaseBlackout").mouse_filter == Control.MOUSE_FILTER_STOP,"blackout blocks battle input for the interlude")
	var committed: String = JSON.stringify(battle.model.snapshot())
	await shot("blackout")
	await wait_for_eyes(battle,0.23)
	check(eyes.reveal_progress < 0.8,"early reveal precedes the complete eye wall")
	check(battle.get_node_or_null("NossPhaseDialogue") == null,"eyes open before the phase dialogue")
	await shot("eyes_early")
	await wait_for_eyes(battle,0.72)
	await shot("eyes_spreading")
	await wait_for_eyes(battle,1.0)
	check(JSON.stringify(battle.model.snapshot()) == committed,"eye animation does not change the committed combat state")
	check(eyes.gaze_position.is_equal_approx(reveal_gaze),"foreground reveal keeps its gaze fixed while only the battle wall tracks the player")
	var deadline := Time.get_ticks_msec()+5000
	while battle.get_node_or_null("NossPhaseDialogue") == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var dialogue: Control = battle.get_node_or_null("NossPhaseDialogue")
	check(dialogue != null and dialogue.eye_wall_background,"phase dialogue retains the opened eye wall")
	await shot("eyes_dialogue")
	check(not is_instance_valid(app.transition),"normal wipe waits for the final dialogue line")
	var transitions_before: int = app.transition_count
	for i in 6:
		advance_phase_dialogue()
		await get_tree().process_frame
	var transition: ColorRect = app.transition
	check(is_instance_valid(transition) and app.transition_count == transitions_before+1,"last dialogue line starts exactly one shared battle transition")
	if is_instance_valid(transition):
		check(transition.material.shader.resource_path == "res://shaders/glitch.gdshader","interlude uses the existing game transition shader")
		check(Game.battle_busy and Game.transition_locked and transition.mouse_filter == Control.MOUSE_FILTER_STOP,"shared transition retains both combat and page input locks")
		check(JSON.stringify(battle.model.snapshot()) == committed,"shared transition leaves committed combat data unchanged")
		while is_instance_valid(transition) and float(transition.material.get_shader_parameter("coverage")) < 0.45:
			await get_tree().process_frame
		await shot("phase2_existing_transition")
		while is_instance_valid(eyes) and is_instance_valid(transition):
			await get_tree().process_frame
		check(not is_instance_valid(eyes) and is_instance_valid(transition),"foreground is removed under full cover before the shared wipe fades")
	await settle()
	check(not is_instance_valid(app.transition) and not Game.transition_locked and app.view == battle,"shared transition cleans up without rebuilding the active battle")
	check(not is_instance_valid(eyes) and battle.get_node_or_null("NossPhaseBlackout") == null,"reveal and input blocker clean up after dialogue")
	check(phase_lines_advanced == 6,"all six authored dialogue lines are preserved")
	var wall: Node2D = battle.stage.noss_eye_wall
	check(is_instance_valid(wall) and wall.wall_mode and wall.reveal_progress == 1.0,"phase two keeps the fully opened battle eye wall")
	check(battle.stage.scenery.visible,"phase-two wall preserves the original artwork floor underneath")
	check(wall.floor_horizon < battle.stage.position.y+battle.stage.player.home.y and wall.floor_horizon < battle.stage.position.y+battle.stage.enemies[0].home.y,"both actors stand below the wall-to-floor boundary")
	check(wall.get_node("EyeWallEnvironment").mouse_filter == Control.MOUSE_FILTER_IGNORE,"environment and glitch strips do not intercept combat input")
	check(wall.eye_count >= 40,"wall is densely populated with eyes")
	check(battle.model.encounter_phase == 2 and battle.model.enemies[0].hp == 160,"phase-two boss starts with correct committed health")
	var active_samples := 0
	for i in 520:
		if wall.glitch_envelope_at(i*0.02) > 0.0: active_samples += 1
	check(active_samples > 0 and active_samples < 78,"neon glitches appear in brief bursts with long quiet intervals")
	var environment_state: String = JSON.stringify(battle.model.snapshot())
	wall.set_process(false)
	wall.ambient_time = 2.0
	check(wall.glitch_strength == 0.0,"quiet interval has no neon strips")
	await shot("phase2_eye_wall")
	wall.ambient_time = 0.81
	check(wall.glitch_strength > 0.5,"burst interval enables neon strips")
	await shot("phase2_neon_glitch")
	check(JSON.stringify(battle.model.snapshot()) == environment_state,"glitch and floor rendering leave combat state unchanged")
	wall.set_process(true)
	await test_gaze(battle)
	var clock_before: float = wall.ambient_time
	var gaze_before: Vector2 = wall.gaze_position
	var player_position: Vector2 = battle.stage.player.position
	wall.hide()
	battle.stage.player.position.x += 100.0
	await get_tree().create_timer(0.15).timeout
	check(is_equal_approx(wall.ambient_time,clock_before),"hidden eye wall freezes its animation clock")
	check(wall.gaze_position.is_equal_approx(gaze_before),"hidden eye wall also freezes gaze despite actor movement")
	wall.show()
	await get_tree().create_timer(0.15).timeout
	check(wall.ambient_time > clock_before,"visible eye wall resumes ambient animation")
	check(wall.gaze_position.distance_to(gaze_before) > 0.01,"showing the eye wall resumes delayed tracking")
	battle.stage.player.position = player_position
	await battle.stage.camera_to(1040,1.45,0.15).finished
	await get_tree().process_frame
	check(wall.scale.x > 1.0 and wall.position.x <= 0.01 and wall.position.x+1440.0*wall.scale.x >= 1439.99,"eye wall follows the combat camera without exposing an edge (x=%.4f, scale=%.4f)" % [wall.position.x,wall.scale.x])
	check_gaze_binding(battle,"close camera")
	await battle.stage.wide()
	var saved_horizon: float = wall.floor_horizon
	var saved: Dictionary = battle.model.snapshot()
	Game.state.combat = saved.duplicate(true)
	app.swap_view()
	await settle()
	battle = app.view
	check(is_instance_valid(battle.stage.noss_eye_wall) and battle.stage.noss_eye_wall.visible,"restoring phase two directly restores the eye wall")
	check(battle.stage.scenery.visible and battle.stage.noss_eye_wall.floor_horizon == saved_horizon,"restoring phase two also restores its calibrated floor boundary")
	check(battle.get_node_or_null("NossPhaseEyes") == null and battle.get_node_or_null("NossPhaseDialogue") == null and battle.get_node_or_null("NossPhaseNeonTransition") == null,"restored phase two does not replay the interlude or neon reveal")
	check(JSON.stringify(battle.model.snapshot()) == JSON.stringify(saved),"phase-two restore preserves all combat data")
	check_gaze_binding(battle,"restored phase two")
	await shot("phase2_restored")
	await turn(battle,"first eye-wall battle turn")
	Game.start_training("B02")
	await settle()
	check(not is_instance_valid(app.view.stage.noss_eye_wall),"ordinary robot battle does not inherit Noss eyes")
	Game.restore_training()
	await settle()
	var outgoing: Control = app.view
	var page_transitions_before: int = app.transition_count
	Game.menu()
	check(Game.transition_locked and app.view == outgoing,"default shared transition keeps the outgoing battle during cover")
	await settle()
	check(app.shown_page == "menu" and app.view != outgoing and app.transition_count == page_transitions_before+1 and not Game.transition_locked,"default shared transition still swaps pages and unlocks normally")
	Engine.time_scale = 1.0
	await preload("res://scripts/combat/audio_cleanup.gd").release(app,get_tree())
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	finished = true
	report()
	print("NOSS EYE WALL: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func shot(name: String) -> void:
	if not capture or DisplayServer.get_name() == "headless": return
	for resolution in [Vector2i(1280,800),Vector2i(1600,1000)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		var filename := name+"_%dx%d.png" % [resolution.x,resolution.y]
		var error := get_viewport().get_texture().get_image().save_png(output.path_join(filename))
		check(error == OK,"GPU screenshot saved: "+filename)
		if error == OK: screenshots.append(filename)
