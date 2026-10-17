extends "res://tests/noren_cards_visual.gd"
## Real viewport and synthetic pointer checks; isolated save paths, no adventure writes.
var observed: Array[String] = []
var fish_hits := 0
var watching: Control
var captured: Array[String] = []

func _process(_delta: float) -> void:
	if not is_instance_valid(watching): return
	var fish = watching.stage.enemies[0]
	if fish.kind != "fish": return
	if not fish.pose in observed: observed.append(fish.pose)
	if fish.pose in ["move","bite","bite_close","damaged"] and not fish.pose in captured:
		captured.append(fish.pose)
		shot.call_deferred(fish.pose)

func on_phase(phase: String) -> void:
	if phase != "impact" or watching.stage.active_attacker.kind != "fish": return
	fish_hits += 1
	check(watching.stage.enemies[0].pose == "bite_close","Fish closes its jaws at the impact callback")
	check(get_tree().get_nodes_in_group("bite_hit_fx").size() == 1,"Exactly one bite imprint at each impact")
	check(watching.shown_player_hp == watching.model.player_hp,"Displayed HP follows the model at bite contact")
	shot.call_deferred("bite-impact-%d" % fish_hits)

func click_at(point: Vector2) -> void:
	await pointer(point)
	await get_tree().create_timer(0.15).timeout
	print("FISH POINTER requested=",point," actual=",app.view.get_global_mouse_position()," hovered=",get_viewport().gui_get_hovered_control())
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = get_viewport().get_final_transform()*point
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame
	await get_tree().create_timer(0.12).timeout

func install_fish_hand() -> void:
	var view = app.view
	var uid := ""
	for candidate in view.model.instances:
		if view.model.instances[candidate] == "noren_01":
			uid = candidate
			break
	check(not uid.is_empty(),"Existing training deck contains a normal attack")
	if not uid in view.model.hand:
		view.model.draw_pile.erase(uid)
		view.model.discard_pile.erase(uid)
		view.model.hand.append(uid)
	view.commit()
	app.swap_view()
	await idle()
	watching = app.view
	watching.stage.phase_changed.connect(on_phase)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://fish_visual_unused.json"
	Game.meta_path = "user://fish_visual_meta_unused.json"
	output = "res://artifacts/qa/fish-enemy-2026-10-17/%d/" % DisplayServer.window_get_size().x
	var args := OS.get_cmdline_user_args()
	if args.has("--output-dir") and args.find("--output-dir")+1 < args.size():
		output = args[args.find("--output-dir")+1].trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state = Game.initial_state()
	Game.state.credits = 321
	var adventure := Game.state.duplicate(true)
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(0.6).timeout
	var toggle: Button = app.view.find_child("training_toggle",true,false)
	await click_at(toggle.get_global_rect().get_center())
	var entrance: Button = app.view.find_child("training_B11",true,false)
	check(entrance != null and entrance.text == "敌人测试" and entrance.is_visible_in_tree(),"Menu exposes the renamed enemy test")
	check(app.view.find_child("training_B12",true,false) == null,"Old mech training button is replaced")
	await shot("menu")
	await click_at(entrance.get_global_rect().get_center())
	await idle()
	check(Game.training_mode and Game.state.battleId == "B11","Menu click enters the existing fish training battle")
	if failures > 0:
		get_tree().quit(1)
		return
	check(app.view.model.enemies[0].id == "fish" and app.view.model.enemies[0].maxHp == 100,"Fish identity with training-only 100 HP")
	check(app.view.targets[0].tooltip_text.contains("变异的鱼"),"Target tooltip uses the fish name")
	await install_fish_hand()
	var view = app.view
	var fish = view.stage.enemies[0]
	check(fish.kind == "fish" and fish.pose == "idle","Fish idle loads on battle entry")
	for pose in ["idle","move","bite","bite_close","damaged"]:
		check(fish.poses[pose] != null and fish.poses[pose].get_size() == Vector2(1254,1254),"Imported pose texture: "+pose)
	check(view.target_at_point(view.stage.contact(fish)) == 0,"Fish torso remains targetable")
	check(view.stage.get_global_rect().encloses(view.stage.target_rect(0)),"Fish target remains inside battlefield")
	await shot("idle")
	var uid := ""
	for candidate in view.model.hand:
		if view.model.instances[candidate] == "noren_01": uid = candidate; break
	var hp_before: int = view.model.enemies[0].hp
	var hand_before: int = view.model.hand.size()
	await click_at(view.cards[uid].home+Vector2(68,110))
	await click_at(view.stage.contact(fish))
	await idle()
	check(view.model.enemies[0].hp == hp_before-6 and view.model.hand.size() == hand_before-1,"Pointer attack damages fish once and consumes one card")
	check("damaged" in observed and fish.pose == "idle","Fish uses hurt art then returns to idle")
	var player_hp: int = view.model.player_hp
	await view.end_turn_pressed()
	await idle()
	check(fish_hits == 1 and view.model.player_hp == player_hp-1,"Fish bite applies the original one damage exactly once")
	check("bite" in observed and "bite_close" in observed,"Enemy attack displays open then closed jaws")
	check(view.model.turn == 2 and view.model.hand.size() == 5,"Next turn starts after bite and return")
	check(fish.position == fish.home and fish.pose == "idle" and view.stage.player.position == view.stage.player.home,"Both actors return to their own feet anchors")
	check(get_tree().get_nodes_in_group("bite_hit_fx").is_empty(),"Bite effect is freed after recovery")
	await shot("returned")
	# Exercise a full guard with the existing model; art cannot apply extra damage.
	view.model.block = 20
	view.shown_player_block = 20
	view.refresh_player_plate()
	view.commit()
	player_hp = view.model.player_hp
	await view.end_turn_pressed()
	await idle()
	check(view.model.player_hp == player_hp and fish_hits == 2,"Full guard preserves HP while still showing a bite")
	check("move" in observed,"Fish advancement art is used when approaching from home")
	check(get_tree().get_nodes_in_group("bite_hit_fx").is_empty(),"Blocked bite effect also cleans up")
	var snapshot: Dictionary = view.model.snapshot()
	watching = null
	app.swap_view()
	await idle()
	check(app.view.model.snapshot() == snapshot and app.view.stage.enemies[0].kind == "fish","View rebuild preserves snapshot and fish identity")
	Game.menu()
	await idle()
	check(Game.state == adventure and not Game.training_mode,"Exiting enemy test restores the full adventure")
	for battle_id in ["B04","B12"]:
		Game.start_training(battle_id)
		await idle()
		check(app.view.stage.enemies[0].kind == "finn","Other battle keeps its existing presentation: "+battle_id)
		Game.finish_training("lose")
		await idle()
		check(Game.state == adventure,"Other training still restores adventure: "+battle_id)
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"poses":observed,"fishHits":fish_hits,"physicalInput":false},"\t"))
	print("FISH ENEMY: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
