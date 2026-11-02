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
	var deadline := Time.get_ticks_msec()+5000
	while battle.get_node_or_null("NossPhaseDialogue") == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var dialogue: Control = battle.get_node_or_null("NossPhaseDialogue")
	check(dialogue != null and dialogue.eye_wall_background,"phase dialogue retains the opened eye wall")
	await shot("eyes_dialogue")
	await settle()
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
	var clock_before: float = wall.ambient_time
	wall.hide()
	await get_tree().create_timer(0.15).timeout
	check(is_equal_approx(wall.ambient_time,clock_before),"hidden eye wall freezes its animation clock")
	wall.show()
	await get_tree().create_timer(0.15).timeout
	check(wall.ambient_time > clock_before,"visible eye wall resumes ambient animation")
	await battle.stage.camera_to(1040,1.45,0.15).finished
	await get_tree().process_frame
	check(wall.scale.x > 1.0 and wall.position.x <= 0.01 and wall.position.x+1440.0*wall.scale.x >= 1439.99,"eye wall follows the combat camera without exposing an edge (x=%.4f, scale=%.4f)" % [wall.position.x,wall.scale.x])
	await battle.stage.wide()
	var saved_horizon: float = wall.floor_horizon
	var saved: Dictionary = battle.model.snapshot()
	Game.state.combat = saved.duplicate(true)
	app.swap_view()
	await settle()
	battle = app.view
	check(is_instance_valid(battle.stage.noss_eye_wall) and battle.stage.noss_eye_wall.visible,"restoring phase two directly restores the eye wall")
	check(battle.stage.scenery.visible and battle.stage.noss_eye_wall.floor_horizon == saved_horizon,"restoring phase two also restores its calibrated floor boundary")
	check(battle.get_node_or_null("NossPhaseEyes") == null and battle.get_node_or_null("NossPhaseDialogue") == null,"restored phase two does not replay the interlude")
	check(JSON.stringify(battle.model.snapshot()) == JSON.stringify(saved),"phase-two restore preserves all combat data")
	await shot("phase2_restored")
	await turn(battle,"first eye-wall battle turn")
	Game.start_training("B02")
	await settle()
	check(not is_instance_valid(app.view.stage.noss_eye_wall),"ordinary robot battle does not inherit Noss eyes")
	Game.restore_training()
	await settle()
	Engine.time_scale = 1.0
	await preload("res://scripts/combat/audio_cleanup.gd").release(app,get_tree())
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	finished = true
	report()
	print("NOSS EYE WALL: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
