extends Node
## Actual menu callbacks and battle entry; only an isolated QA adventure is used.
const CASES := [["warden_shield","B17",[85]],["chip_broker","B18",[72]],["mutant_mouse","B19",[42,42]],["luggage_lurker","B20",[45,45]],["penitent_ascetic","B21",[80]],["scavenger_hooker","B22",[78]]]
var checks := 0
var failures: Array[String] = []
var shots: Array[String] = []
var output := ""
var app: Control
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("WEEK2 TRAINING MENU: "+message)
func same(a,b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))
func settle() -> void:
	var deadline := Time.get_ticks_msec()+15000
	await get_tree().process_frame
	while Game.transition_locked or Game.battle_busy:
		await get_tree().process_frame
		if Time.get_ticks_msec() > deadline:
			check(false,"actual UI transition completes within fifteen seconds")
			get_tree().quit(2)
			return
	await get_tree().process_frame
	await get_tree().process_frame
func shot(name: String, size: Vector2i = Vector2i(1280,800)) -> void:
	if DisplayServer.get_name() == "headless": return
	get_window().size = size
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var filename := name+"_%dx%d.png" % [size.x,size.y]
	check(get_viewport().get_texture().get_image().save_png(output.path_join(filename)) == OK,"save screenshot "+filename)
	shots.append(filename)
func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in OS.get_user_data_dir().to_lower():get_tree().quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused.json")
	Game.meta_path = output.path_join("unused-meta.json")
	Game.state = Game.initial_state("noren","advanced")
	Game.state.currentWeek = 2
	Game.state.currentDay = 4
	Game.state.currentScene = "map"
	Game.state.currentHp = 47
	Game.state.credits = 321
	Game.state.deck = ["noren_35"]
	Game.page = "menu"
	var original := Game.state.duplicate(true)
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	Engine.time_scale = 6.0
	await settle()
	var menu: Control = app.view
	menu.training_toggle.pressed.emit()
	await get_tree().process_frame
	check(menu.training_open and menu.training_container.find_children("enemy_choice_*","Button",true,false).size() == 14,"all fourteen groups appear in the actual modal")
	for c in CASES:
		var button: Button = menu.training_container.find_child("enemy_choice_"+c[0],true,false)
		check(button != null and button.is_visible_in_tree() and not button.disabled,"new encounter visible and enabled: "+c[0])
	await shot("all_training",Vector2i(1280,800))
	await shot("all_training",Vector2i(1600,1000))
	menu.training_cancel.pressed.emit()
	for c in CASES:
		menu = app.view
		menu.training_toggle.pressed.emit()
		var button: Button = menu.training_container.find_child("enemy_choice_"+c[0],true,false)
		button.pressed.emit()
		await settle()
		check(Game.training_mode and Game.page == "battle" and Game.state.battleId == "training_"+c[0],"real menu starts selected practice: "+c[0])
		var battle: Control = app.view
		check(battle.initialized and battle.stage.enemies.size() == c[2].size() and battle.targets.size() == c[2].size(),"actual actor and target counts: "+c[0])
		check(battle.model.enemies.map(func(e): return e.maxHp) == c[2] and battle.model.profile.difficulty == "normal","practice uses formal base HP despite advanced adventure: "+c[0])
		check(battle.model.enemies.map(func(e): return e.id) == Game.battles[c[1]].enemyIds,"full formal formation: "+c[0])
		check(battle.model.enemies.all(func(e): return same(e.intentSequence,Game.enemy_catalog[e.id].intentSequence)),"formal intent sequences retained: "+c[0])
		check(battle.stage.enemies.all(func(actor): return actor.sprite.texture != null and actor.pipeline_diagnostics.is_empty()),"published visuals load: "+c[0])
		await shot(c[0])
		Game.menu()
		await settle()
		check(not Game.training_mode and Game.page == "menu" and same(Game.state,original),"leaving actual practice restores complete adventure: "+c[0])
	Engine.time_scale = 1.0
	await preload("res://scripts/combat/audio_cleanup.gd").release(app,get_tree())
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":shots},"\t"))
	print("WEEK2 TRAINING MENU: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
