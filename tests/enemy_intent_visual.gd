extends "res://tests/noren_cards_visual.gd"
## Rendered intent integration, isolated fixtures and direct view calls; no save writes.

func verify_intents(view: Control) -> void:
	var before: Dictionary = view.model.snapshot().duplicate(true)
	view.refresh_enemy_hud()
	view.update_target_rects()
	for i in view.enemy_intents.size():
		var intent: Control = view.enemy_intents[i]
		check(intent.mouse_filter == Control.MOUSE_FILTER_IGNORE and intent.value_label.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Intent and number preserve targeting input")
		check(intent.find_children("*","Panel",true,false).is_empty(),"Intent has no background panel")
		check(intent.size == Vector2(96,66) and intent.scale == Vector2.ONE,"Icon and value keep screen-space size")
	check(view.model.snapshot() == before,"Rebuilding intent HUD does not change combat state")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://enemy_intent_visual_unused.json"
	Game.meta_path = "user://enemy_intent_visual_meta_unused.json"
	output = "res://artifacts/qa/enemy-intent-icons-2026-10-20/1280/"
	var args := OS.get_cmdline_user_args()
	if args.has("--output-dir"): output = args[args.find("--output-dir")+1].trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	var view = app.view
	verify_intents(view)
	check(view.enemy_intents[0].value_label.text == "4" and view.enemy_intents[2].value_label.text == "+1","Gang attack and ally reinforcement show their quantities")
	await shot("01-gang")
	# Isolated multi-hit preview includes strength, weak rounding and player vulnerable decay.
	view.model.enemies[0].intent = {"type":"attack","amount":4,"hits":5}
	view.model.enemies[0].buffs = {"strength":2}
	view.model.enemies[0].weak = 1
	view.model.buff_state.vulnerable = 2
	view.shown_enemies = view.model.enemies.duplicate(true)
	verify_intents(view)
	check(view.enemy_intents[0].value_label.text == "8×5","Multi-hit shows per-hit damage after strength, weak and post-decay vulnerable")
	await shot("02-multihit-buffed")
	var actor: Node2D = view.stage.enemies[0]
	var origin: Vector2 = actor.position
	var previous: Vector2 = view.enemy_intents[0].global_position
	var snapshot: Dictionary = view.model.snapshot().duplicate(true)
	await view.stage.move_actor(actor,origin+Vector2(-80,0),0.1)
	view.update_target_rects()
	check(view.enemy_intents[0].global_position.distance_to(previous)>20,"Intent follows a moving actor")
	check(view.model.snapshot() == snapshot,"Intent movement leaves model unchanged")
	await view.stage.move_actor(actor,origin,0.1)
	actor.alive = false
	view.update_enemy_plates()
	check(not view.enemy_intents[0].visible,"Dead enemy intent is hidden")
	actor.alive = true
	Game.menu()
	await idle()
	Game.start_training("B11")
	await idle()
	view = app.view
	verify_intents(view)
	check(view.enemy_intents[1].kind == "pollution" and view.enemy_intents[1].value_label.text == "3","Fish pollution intent shows three layers")
	await shot("03-fish")
	view.model.enemies[0].intent = {"type":"vulnerable","amount":2}
	view.shown_enemies = view.model.enemies.duplicate(true)
	verify_intents(view)
	check(view.enemy_intents[0].kind == "vulnerable" and view.enemy_intents[0].value_label.text == "2","Vulnerable intent shows two layers")
	await shot("04-vulnerable-fixture")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false},"\t"))
	print("ENEMY INTENT VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
