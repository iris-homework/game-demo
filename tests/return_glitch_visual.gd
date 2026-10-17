extends "res://tests/noren_cards_visual.gd"
## Real battle return flow; also runs headless. Saves disabled, no physical input.
const Ghost = preload("res://scripts/combat/return_ghost_fx.gd")
var cycle := ""
var seen: Array[String] = []
var expected_survivors := 3
var stationary_player := false
var snapshot: Dictionary = {}

func ghosts() -> Array:
	return app.view.stage.world.get_children().filter(func(node): return node.get_script() == Ghost)

func capture(name: String) -> void:
	if DisplayServer.get_name() != "headless": await shot(name)

func on_phase(value: String) -> void:
	seen.append(value)
	var view = app.view
	if value == "return_light":
		snapshot = view.model.snapshot()
		if stationary_player:
			check(view.stage.player.position == view.stage.player.home,"Player did not move before end-of-turn return")
	if value == "home_glitch":
		check(ghosts().size() == expected_survivors,"Every survivor gets a ghost, including stationary actors")
		check(Game.battle_busy,"Input remains locked during return")
		for actor in view.stage.actors_root.get_children():
			if not actor.alive: continue
			check(actor.position == actor.home and is_zero_approx(actor.modulate.a),"Survivor hidden at exact home")
			check(actor.facing == (1.0 if actor == view.stage.player else -1.0),"Facing restored before ghost reveal")
		check(view.model.snapshot() == snapshot,"Return does not mutate the combat model")
		await get_tree().create_timer(0.10).timeout
		await capture(cycle+"-ghost")
	if value == "home_reveal":
		await get_tree().create_timer(0.12).timeout
		for actor in view.stage.actors_root.get_children():
			if actor.alive: check(actor.modulate.a > 0 and actor.modulate.a < 1,"Survivor gradually reappears")
		await capture(cycle+"-reveal")

func verify_return() -> void:
	# queue_free releases temporary ghosts at the end of the current frame.
	await get_tree().process_frame
	var stage = app.view.stage
	check(seen.count("home_glitch") == 1 and seen.count("home_reveal") == 1,"One shared ghost/reveal sequence")
	check(ghosts().is_empty() and stage.phase == "idle","Temporary ghosts released and stage idle")
	for actor in stage.actors_root.get_children():
		if not actor.alive: continue
		check(actor.position == actor.home and actor.modulate == Color.WHITE,"Survivor ends at home with normal visibility")
		check(actor.facing == (1.0 if actor == stage.player else -1.0),"Player faces right; enemy faces left")
		check(actor.pose == ("gun_idle" if actor == stage.player and actor.combat_stance == "ranged" else "idle"),"Return preserves stance-specific idle")
	check(is_equal_approx(stage.zoom,1.0),"Wide camera restored")

func _ready() -> void:
	output = "res://artifacts/qa/always-return-2026-10-17/"+("headless/" if DisplayServer.get_name() == "headless" else "render/")
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = "user://always_return_unused.json"
	Game.meta_path = "user://always_return_meta_unused.json"
	Game.state = Game.initial_state()
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B11")
	await idle()
	var view = app.view
	view.stage.phase_changed.connect(on_phase)
	# No cards played: defender stays home while fish attack / apply pollution.
	cycle = "melee-turn"
	stationary_player = true
	await view.end_turn_pressed()
	await verify_return()
	check(view.model.player_hp == 94 and view.model.turn == 2 and view.model.hand.size() == 5,"Actual enemy turn damages and draws exactly once")
	check(not Game.battle_busy and view.cards.size() == 5,"Next hand opens after return")
	await capture(cycle+"-complete")
	# All actors stay at home, but face the wrong way after a hit / turn.
	cycle = "stationary-ranged"
	seen.clear()
	view.stage.player.set_combat_stance("ranged")
	for actor in view.stage.actors_root.get_children():
		actor.face_toward(actor.position+Vector2(-100 if actor == view.stage.player else 100,0))
	view.set_busy(true)
	await capture(cycle+"-before")
	await view.stage.return_home()
	await verify_return()
	check(view.model.snapshot() == snapshot,"Stationary return keeps model snapshot unchanged")
	view.set_busy(false)
	await capture(cycle+"-complete")
	# Subpixel displacement, normal displacement, and a dead actor in one pass.
	cycle = "mixed"
	seen.clear()
	stationary_player = false
	expected_survivors = 2
	view.stage.player.position += Vector2(0.5,0)
	view.stage.enemies[0].position += Vector2(-160,20)
	var dead = view.stage.enemies[1]
	dead.alive = false
	dead.modulate.a = 0
	dead.position += Vector2(-80,30)
	var dead_position: Vector2 = dead.position
	view.set_busy(true)
	await view.stage.return_home()
	await verify_return()
	check(dead.position == dead_position and dead.modulate.a == 0 and not dead.alive,"Dead actor neither returns nor reappears")
	check(view.model.snapshot() == snapshot,"Mixed return keeps model snapshot unchanged")
	view.set_busy(false)
	await capture(cycle+"-complete")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false},"\t"))
	print("RETURN GLITCH: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
