extends "res://tests/combat/cards/noren_cards_visual.gd"
## Actual melee playback and projected hit areas; no desktop pointer or screenshots.
const Stage = preload("res://scripts/combat/test_stage.gd")
var phase_two_snapshot: Dictionary = {}
var samples := 0
var all_visible := true
var peak_shake_seen := false

func full_target(_stage: Control, actor: Node2D) -> Rect2:
	return actor.get_global_transform() * actor.target_bounds

func visible_targets(view: Control) -> bool:
	for actor in view.stage.enemies:
		if actor.alive and not view.stage.get_global_rect().encloses(full_target(view.stage,actor)):
			return false
	return true

func check_targets(view: Control, title: String) -> void:
	view.stage._update_camera()
	view.update_target_rects()
	for i in view.stage.enemies.size():
		var full := full_target(view.stage,view.stage.enemies[i])
		check(view.stage.get_global_rect().encloses(full),title+" complete enemy hit area visible: "+str(i))
		check(view.stage.target_rect(i).has_area(),title+" clipped hit area remains nonempty: "+str(i))
		check(view.target_at_point(full.get_center()) == i,title+" enemy independently targetable: "+str(i))

func prepare_duet() -> Control:
	await idle()
	var model := CombatModel.new()
	model.restore(phase_two_snapshot)
	# Keep a valid, existing pair of instances and force two identical melee cards.
	for i in 2:
		model.instances[model.hand[i]] = "noren_01"
	model.stance = "melee"
	model.energy = 3
	Game.commit_combat(model)
	app.swap_view()
	await idle()
	check(app.view.stage.dancer_duet and app.view.stage.enemies.size() == 2,"restored phase-two fixture has both dancers")
	return app.view

func play_and_observe(view: Control, uid: String, target: int) -> void:
	var hp_before: int = view.model.enemies[target].hp
	view.select_card(uid)
	view.play_selected(target)
	var deadline := Time.get_ticks_msec()+20000
	while Game.battle_busy or Game.transition_locked:
		await get_tree().process_frame
		view.stage.update_depth()
		view.stage._update_camera()
		view.update_target_rects()
		samples += 1
		all_visible = all_visible and visible_targets(view)
		peak_shake_seen = peak_shake_seen or view.stage.impact_zoom > 1.02
		if Time.get_ticks_msec() > deadline:
			check(false,"melee playback timed out")
			get_tree().quit(2)
			return
	await idle()
	check(view.model.enemies[target].hp == hp_before-6,"melee hits requested dancer exactly once: "+str(target))
	check(uid in view.model.discard_pile and not uid in view.model.hand,"played melee card retires exactly once")
	check_targets(view,"after melee against "+str(target))

func test_order(first: int) -> void:
	var view: Control = await prepare_duet()
	var hand: Array = view.model.hand.duplicate()
	samples = 0
	all_visible = true
	peak_shake_seen = false
	await play_and_observe(view,str(hand[0]),first)
	# The next target is obtained through the actual projected selection area.
	var other := 1-first
	var next_target: int = view.target_at_point(full_target(view.stage,view.stage.enemies[other]).get_center())
	check(next_target == other,"can switch to opposite dancer from close camera")
	if next_target == other:
		await play_and_observe(view,str(hand[1]),next_target)
	check(samples > 10 and all_visible,"both dancers stay visible throughout consecutive melee approaches and camera movement")
	check(peak_shake_seen,"actual hit-stop camera impulse was observed")
	for direction in [-1.0,1.0]:
		view.stage.kick_camera(direction,8.0)
		check_targets(view,"peak impulse "+str(direction))
	view.stage.shake_time = 0.0
	view.stage.shake = Vector2.ZERO
	view.stage.impact_zoom = 1.0
	view.stage._update_camera()

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://dancer_camera_unused.json"
	Game.meta_path = "user://dancer_camera_meta_unused.json"
	output = "/tmp/midnight-dancer-camera-qa"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not "qa" in OS.get_user_data_dir().to_lower():
		push_error("Dancer camera tests require an isolated QA user directory")
		get_tree().quit(2)
		return
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B16")
	await idle()
	var model: CombatModel = app.view.model
	model.enemies[0].hp = 0
	model.outcome = "win"
	check(model.advance_encounter_phase(),"fixture advances through real Boss phase boundary")
	phase_two_snapshot = model.snapshot()
	await test_order(0)
	await test_order(1)
	var resolver := EnemyVisualResolver.new()
	var visuals: Array[EnemyVisualResolver.Visual] = [resolver.resolve({"combatVisualId":"dancer_black"},{})]
	var single = Stage.new()
	add_child(single)
	single.setup(577.0,visuals)
	var destination: Vector2 = single.attack_destination(single.player,single.enemies[0],86.0)
	single.frame_attack(single.player,single.enemies[0],destination)
	await single.camera_tween.finished
	check(is_equal_approx(single.zoom,1.485),"single-enemy melee retains existing close zoom")
	single.queue_free()
	await get_tree().process_frame
	Game.finish_training("lose")
	await idle()
	DirAccess.make_dir_recursive_absolute(output)
	var summary := {"checks":checks,"failures":failures,"headlessGeometry":true,"actualMeleePlayback":true,"physicalInput":false,"pixelValidation":false}
	var file := FileAccess.open(output.path_join("summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(summary,"\t"))
	file.close()
	print("DANCER CAMERA: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
