extends "res://tests/combat/cards/noren_cards_visual.gd"
## Real battle playback and isolated presentation controls; no desktop input or capture.
const Stage = preload("res://scripts/combat/test_stage.gd")
var phase_two_snapshot: Dictionary = {}

func faces(actor: Node2D, target: Node2D) -> bool:
	return is_equal_approx(actor.facing, 1.0 if target.position.x >= actor.position.x else -1.0)

func check_survivor(view: Control, survivor: int, title: String) -> void:
	check(view.stage.player.alive and view.stage.enemies[survivor].alive, title+" retains living combatants")
	check(not view.stage.enemies[1-survivor].alive, title+" retired dancer stays dead")
	check(faces(view.stage.player,view.stage.enemies[survivor]), title+" player faces surviving dancer")
	check(faces(view.stage.enemies[survivor],view.stage.player), title+" surviving dancer faces player")

func prepare_duet(form: String = "melee", dead: int = -1) -> Control:
	await idle()
	var model := CombatModel.new()
	model.restore(phase_two_snapshot)
	model.instances[model.hand[0]] = "noren_01"
	model.stance = form
	model.ammo = 2
	model.energy = 3
	if dead >= 0: model.enemies[dead].hp = 0
	check(Game.commit_combat(model), "phase-two fixture commits without saving")
	app.swap_view()
	await idle()
	check(app.view.stage.dancer_duet and app.view.stage.enemies.size() == 2, "fixture restores true duet stage")
	return app.view

func test_card_death(form: String) -> void:
	var view: Control = await prepare_duet(form)
	view.model.enemies[0].hp = 1
	view.shown_enemies[0].hp = 1
	var uid: String = view.model.hand[0]
	view.select_card(uid)
	view.play_selected(0)
	await idle()
	check(view.model.enemies[0].hp == 0 and view.model.enemies[1].hp > 0, form+" card kills black only")
	check(uid in view.model.discard_pile and not uid in view.model.hand, form+" lethal card resolves once")
	check_survivor(view,1,form+" death playback")
	view.end_turn_pressed()
	await idle()
	check_survivor(view,1,form+" next player round")
	check(view.stage.player.position.is_equal_approx(view.stage.player.home), form+" player returns home")
	check(view.stage.enemies[1].position.is_equal_approx(view.stage.enemies[1].home), form+" white returns home")
	var saved_snapshot: Dictionary = view.model.snapshot()
	check(Game.commit_combat(view.model), form+" survivor snapshot commits")
	app.swap_view()
	await idle()
	check(app.view.model.snapshot() == saved_snapshot, form+" restore leaves model snapshot unchanged")
	check_survivor(app.view,1,form+" restored survivor snapshot")

func test_retirement_and_restore() -> void:
	var view: Control = await prepare_duet()
	check(view.stage.player.facing == 1.0, "both living dancers retain initial right facing")
	var snapshot: Dictionary = view.model.snapshot()
	await view.stage.retire_actor(view.stage.enemies[0])
	check_survivor(view,1,"shared retirement entry")
	check(view.model.snapshot() == snapshot, "presentation retirement does not mutate model")
	await view.stage.return_home()
	check_survivor(view,1,"shared retirement return")
	view = await prepare_duet("melee",0)
	check_survivor(view,1,"direct black-dead restore")
	view = await prepare_duet("melee",1)
	check_survivor(view,0,"direct white-dead restore")
	await view.stage.return_home()
	check_survivor(view,0,"black-only return")
	view = await prepare_duet()
	await view.stage.retire_actor(view.stage.enemies[1])
	check_survivor(view,0,"white-first retirement")
	var facing_before: float = view.stage.player.facing
	await view.stage.retire_actor(view.stage.enemies[0])
	check(view.stage.player.facing == facing_before, "last dancer death does not turn toward a corpse")

func test_ordinary_stage(count: int) -> void:
	var resolver := EnemyVisualResolver.new()
	var visuals: Array[EnemyVisualResolver.Visual] = []
	for i in count: visuals.append(resolver.resolve({"combatVisualId":"dancer_black"},{}))
	var stage = Stage.new()
	add_child(stage)
	stage.setup(577.0,visuals)
	check(not stage.dancer_duet, "ordinary %d-enemy fixture does not opt into duet" % count)
	stage.player.face_toward(stage.player.position-Vector2(100,0))
	if count > 1:
		# A living opponent on the left catches accidental generic survivor retargeting.
		stage.enemies[1].position.x = stage.player.position.x-200
	await stage.retire_actor(stage.enemies[0])
	check(stage.player.facing == -1.0, "ordinary %d-enemy death preserves existing facing" % count)
	await stage.return_home()
	check(stage.player.facing == 1.0, "ordinary %d-enemy return retains default player right facing" % count)
	for i in range(1,count):
		check(stage.enemies[i].facing == -1.0, "ordinary survivor retains default enemy left facing")
	check(not stage.enemies[0].alive and stage.enemies[0].modulate.a == 0.0, "ordinary dead actor stays hidden after return")
	stage.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://dancer_survivor_facing_unused.json"
	Game.meta_path = "user://dancer_survivor_facing_meta_unused.json"
	output = "/tmp/midnight-dancer-survivor-facing-qa"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not "qa" in OS.get_user_data_dir().to_lower():
		push_error("Dancer survivor facing tests require an isolated QA user directory")
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
	check(model.advance_encounter_phase(), "fixture crosses real Boss phase boundary")
	phase_two_snapshot = model.snapshot()
	await test_card_death("melee")
	await test_card_death("ranged")
	await test_retirement_and_restore()
	await test_ordinary_stage(1)
	await test_ordinary_stage(2)
	await test_ordinary_stage(3)
	Game.finish_training("lose")
	await idle()
	DirAccess.make_dir_recursive_absolute(output)
	var summary := {"checks":checks,"failures":failures,"actualCardPlayback":true,"headlessFacing":true,"ordinaryEnemyCounts":[1,2,3],"physicalInput":false,"pixelValidation":false}
	var file := FileAccess.open(output.path_join("summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(summary,"\t"))
	file.close()
	print("DANCER SURVIVOR FACING: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
