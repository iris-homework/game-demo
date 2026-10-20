extends "res://tests/noren_cards_visual.gd"
## Program-driven battle rendering; no physical-input or subjective acceptance claim.
const Laser = preload("res://scripts/combat/palm_laser_fx.gd")
var contacts := 0
var captured: Dictionary = {}
var frames := 0
var record_frames := false
var presentation_snapshot: Dictionary = {}
var snapshot_unchanged := true
var observed_widths: Array[float] = []
var widest := 0.0
var frame_images: Array[Image] = []
var sample_images: Dictionary = {}

func observe_phase(value: String, view: Control) -> void:
	if value == "laser_charge":
		presentation_snapshot = view.model.snapshot().duplicate(true)
		record_frames = true

func monitor(view: Control) -> void:
	var start_time := Time.get_ticks_msec()
	while Game.battle_busy:
		await get_tree().process_frame
		if not presentation_snapshot.is_empty():
			snapshot_unchanged = snapshot_unchanged and view.model.snapshot() == presentation_snapshot
		for fx in get_tree().get_nodes_in_group("palm_laser_fx"):
			var width: float = fx.width_at(fx.elapsed)
			observed_widths.append(width)
			widest = maxf(widest, width)
			check(width <= fx.max_width + 0.001, "Animated beam including glow stays inside palm diameter")
			var label := ""
			if fx.elapsed < Laser.CHARGE_TIME and not captured.has("01-thin"): label = "01-thin"
			elif fx.elapsed > Laser.CHARGE_TIME + 0.08 and fx.elapsed < Laser.CHARGE_TIME + Laser.GROW_TIME - 0.02 and not captured.has("02-growing"): label = "02-growing"
			elif fx.elapsed > Laser.CHARGE_TIME + Laser.GROW_TIME and fx.elapsed < Laser.CHARGE_TIME + Laser.GROW_TIME + Laser.HOLD_TIME and not captured.has("03-full"): label = "03-full"
			if not label.is_empty():
				captured[label] = width
				await RenderingServer.frame_post_draw
				sample_images[label] = get_viewport().get_texture().get_image()
		if record_frames and frames < 28:
			await RenderingServer.frame_post_draw
			frame_images.append(get_viewport().get_texture().get_image())
			frames += 1
		if Time.get_ticks_msec() - start_time > 20000:
			check(false, "Real turn completes before timeout")
			break
	await idle()
	for label in sample_images: sample_images[label].save_png(output + label + ".png")
	for i in frame_images.size(): frame_images[i].save_png(output + "frame-%02d.png" % i)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://robot_laser_visual_unused.json"
	Game.meta_path = "user://robot_laser_visual_meta_unused.json"
	output = "res://artifacts/qa/robot-laser-2026-10-20/visual-1280/"
	var args := OS.get_cmdline_user_args()
	if args.has("--output-dir"): output = args[args.find("--output-dir") + 1].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state = Game.initial_state()
	var adventure: Dictionary = Game.state.duplicate(true)
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	await idle()
	var menu = app.view
	menu.training_toggle.pressed.emit()
	var entrance: Button = menu.find_child("training_B02", true, false)
	check(is_instance_valid(entrance) and entrance.is_visible_in_tree(), "Expanded menu exposes robot test entrance")
	check(menu.training_container.get_global_rect().encloses(entrance.get_global_rect()), "Robot entrance fits the expanded training menu")
	check(not entrance.get_global_rect().intersects(menu.motion_button.get_global_rect()), "Robot entrance clears the motion setting below")
	await shot("menu-entry")
	entrance.pressed.emit()
	await idle()
	var view = app.view
	var stage = view.stage
	var robot = stage.enemies[0]
	check(robot.kind == "robot" and robot.attack_style_override == "laser", "B02 resolves the dedicated robot visual")
	check(robot.sprite.texture.resource_path.ends_with("robot_idle.png"), "Robot enters with its authored idle pose")
	check(view.model.enemy_intent_text(view.model.enemies[0]) == "攻击 10", "Displayed intent is attack10")
	check(view.target_at_point(stage.contact(robot)) == 0, "Robot torso remains targetable")
	await shot("00-idle")
	var origin: Vector2 = robot.position
	var hp_before: int = view.model.player_hp
	stage.phase_changed.connect(func(value): observe_phase(value,view))
	view.end_turn_pressed()
	await monitor(view)
	check(view.model.player_hp == hp_before - 10 and view.shown_player_hp == view.model.player_hp, "One real turn applies and displays exactly 10 damage")
	check(view.model.turn == 2 and view.model.enemy_intent_text(view.model.enemies[0]) == "攻击 10", "Next player turn keeps the same intent")
	check(snapshot_unchanged, "Animation does not mutate the already settled model")
	check(captured.size() == 3 and captured.get("01-thin",99) < captured.get("02-growing",0) and captured.get("02-growing",99) < captured.get("03-full",0), "Rendered samples progress thin to medium to full")
	check(robot.position.is_equal_approx(origin) and robot.pose == "idle" and not Game.battle_busy, "Robot stays planted and the turn unlocks")
	check(get_tree().get_nodes_in_group("palm_laser_fx").is_empty(), "Transient beam releases at the end of the real turn")
	await shot("04-returned")
	# Left and right firing, full block and lethal: callback once, no extra model damage.
	var snapshot: Dictionary = view.model.snapshot().duplicate(true)
	for reversed in [false, true]:
		robot.position = Vector2(410 if reversed else 1021, stage.floor_y - 75)
		stage.player.position = Vector2(1020 if reversed else 405, stage.floor_y - 30)
		stage.player.alive = true
		stage.player.modulate = Color.WHITE
		await stage.attack(robot, stage.player, "pierce", [{"damage":0 if not reversed else 10,"blocked":10 if not reversed else 0,"killed":reversed}], func(_hit,_index):
			contacts += 1
			var beams := get_tree().get_nodes_in_group("palm_laser_fx")
			check(beams.size() == 1, "One continuous beam at contact")
			if beams.size() == 1:
				var fx = beams[0]
				var aim: Vector2 = (fx.target - fx.start).normalized()
				check(fx.start.distance_to(fx.ray_end()) > fx.start.distance_to(fx.target) + 1400, "Beam continues far beyond the target")
				check((fx.ray_end() - fx.start).normalized().dot(aim) > 0.999, "Continuing beam passes through the target")
				check(fx.start.distance_to(stage.world.to_local(robot.sprite.to_global(robot.laser_muzzle))) < 0.01, "Emitter follows calibrated palm with either facing")
				check(fx.max_width <= robot.laser_palm_width * absf(robot.sprite.scale.y * robot.scale.y) + 0.001, "Width cap follows the scaled palm")
			check(robot.pose == "laser", "Firing pose holds through contact"))
		check(stage.player.alive != reversed, "Block survives; lethal result retires target once")
	check(contacts == 2 and view.model.snapshot() == snapshot, "Preview contact callbacks never apply additional damage")
	check(get_tree().get_nodes_in_group("palm_laser_fx").is_empty(), "No beam remains after blocked or lethal attack")
	# Invalid authoring cannot reach the actor.
	var resolver := EnemyVisualResolver.new()
	var valid: Dictionary = resolver.catalog.robot.duplicate(true)
	for field in ["laserMuzzle", "laserPalmWidth"]:
		var bad := valid.duplicate(true)
		bad.id = "bad_robot"
		bad.erase(field)
		resolver.catalog.bad_robot = bad
		check(resolver.resolve({"combatVisualId":"bad_robot"},{}).id == "finn", "Missing laser calibration rejects profile: " + field)
	var curve := Laser.new()
	curve.max_width = 13.5
	check(curve.width_at(Laser.CHARGE_TIME) < curve.width_at(Laser.CHARGE_TIME + Laser.GROW_TIME * 0.5) and curve.width_at(Laser.CHARGE_TIME + Laser.GROW_TIME * 0.5) < curve.width_at(Laser.CHARGE_TIME + Laser.GROW_TIME), "Width grows progressively during firing")
	check(curve.width_at(Laser.DURATION) == 0.0 and curve.width_at(Laser.DURATION - 0.05) < curve.max_width, "Tail narrows to zero")
	curve.free()
	Game.menu()
	await idle()
	check(Game.state == adventure and not Game.training_mode, "Leaving B02 restores the original adventure")
	var result := {"checks":checks,"failures":failures,"capturedWidths":captured,"largestObservedWidth":widest,"recordedFrames":frames,"windowSize":DisplayServer.window_get_size(),"modelUnchangedDuringAnimation":snapshot_unchanged}
	var file := FileAccess.open(output + "result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("ROBOT LASER VISUAL: %d checks, %d failures" % [checks,failures])
	app.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
