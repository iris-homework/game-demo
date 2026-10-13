extends "res://tests/combat_stage_visual.gd"
## Actual battle return sequence, sampled during the ghost-only and reveal phases.
var ghost_frames := 0
var reveal_frames := 0
var fixed_button := Rect2()
var fixed_hp := Rect2()

func ghosts(view: Control) -> Array:
	return view.stage.world.get_children().filter(func(node): return node.get_script() == preload("res://scripts/combat/return_ghost_fx.gd"))

func on_phase(value: String) -> void:
	var view = app.view
	if value == "home_glitch":
		var copies := ghosts(view)
		verify(copies.size() == 4,"All four displaced survivors get a return silhouette")
		verify(Game.battle_busy,"Return silhouettes keep next-turn input locked")
		for actor in view.stage.actors_root.get_children():
			verify(actor.position == actor.home and is_zero_approx(actor.modulate.a),"Actor stays hidden at its home before reveal")
		await settle(0.10)
		for copy in copies:
			verify(copy.progress > 0 and copy.progress < 0.44 and copy.echoes.size() == 3,"Neon channel silhouettes animate before the real body")
		ghost_frames += 1
		await shot("02-ghost-only")
	if value == "home_reveal":
		await settle(0.12)
		for actor in view.stage.actors_root.get_children():
			verify(actor.modulate.a > 0 and actor.modulate.a < 1,"Body gradually appears while echoes fade")
		reveal_frames += 1
		await shot("03-body-reveal")

func _ready() -> void:
	output = "res://artifacts/qa/return-glitch-2026-10-14/%d/" % DisplayServer.window_get_size().x
	DirAccess.make_dir_recursive_absolute(output)
	var demo: Node = load("res://scenes/combat_stage_demo.tscn").instantiate()
	add_child(demo)
	await settle(0.5)
	app = demo.get_child(0)
	while app.shown_page != "battle" or app.view.model.enemies.size() != 3: await get_tree().process_frame
	await idle()
	var view = app.view
	fixed_button = view.end_button.get_global_rect()
	fixed_hp = view.enemy_plates[0].get_global_rect()
	view.stage.phase_changed.connect(on_phase)
	view.select_card(view.model.hand[0])
	await view.play_selected(0)
	await shot("01-before-return")
	await view.end_turn_pressed()
	await settle(0.1)
	verify(ghost_frames == 1 and reveal_frames == 1,"Return plays ghost and body stages exactly once")
	verify(ghosts(view).is_empty(),"All temporary silhouettes release after reveal")
	for actor in view.stage.actors_root.get_children():
		verify(actor.position == actor.home and actor.modulate == Color.WHITE,"Survivors finish at XY home with normal color and alpha")
	verify(view.model.player_hp == 97 and view.model.enemies[0].hp == 19 and view.model.turn == 2 and view.model.hand.size() == 5,"Existing enemy damage, round count and draw resolve exactly once")
	verify(view.end_button.get_global_rect() == fixed_button and view.enemy_plates[0].get_global_rect() == fixed_hp,"Controls and fixed enemy HP layout stay still")
	await shot("04-complete")
	view.stage.phase_changed.disconnect(on_phase)
	var snapshot: Dictionary = view.model.snapshot()
	var dead: Node2D = view.stage.enemies[2]
	dead.alive = false
	dead.modulate.a = 0
	dead.position += Vector2(-100,20)
	var dead_position := dead.position
	await view.stage.return_home()
	verify(dead.position == dead_position and dead.modulate.a == 0 and ghosts(view).is_empty(),"No ghost or resurrection for dead actors; stationary survivors skip return")
	verify(view.model.snapshot() == snapshot,"Presentation-only return never modifies the combat snapshot")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"mode":"real rendering, direct battle view calls"},"\t"))
	print("RETURN GLITCH: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
