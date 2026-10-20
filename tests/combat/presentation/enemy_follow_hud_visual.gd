extends "res://tests/combat/presentation/combat_stage_visual.gd"
## Real rendering and direct view actions; no physical-input claim.
func check_plates(view: Control, label_text: String) -> void:
	view.update_target_rects()
	for i in view.enemy_plates.size():
		var plate: Control = view.enemy_plates[i]
		var actor: Node2D = view.stage.enemies[i]
		var intent: Control = view.enemy_intents[i]
		verify(plate.get_global_rect().position.is_equal_approx(Vector2(1216,280+i*58)),label_text+": HP row fixed at top right")
		verify(plate.size.is_equal_approx(Vector2(194,48)) and plate.scale.is_equal_approx(Vector2.ONE),label_text+": stable HP row size")
		verify(plate.mouse_filter == Control.MOUSE_FILTER_IGNORE and intent.mouse_filter == Control.MOUSE_FILTER_IGNORE,label_text+": labels do not intercept cards")
		if intent.visible:
			var head := actor.to_global(Vector2(0,-130))
			verify(absf(intent.global_position.x+63-head.x) < 0.1,label_text+": intent tracks its own head X")
			verify(absf(intent.global_position.y+36-head.y) < 0.1,label_text+": intent stays above its own head")
			verify(intent.size.is_equal_approx(Vector2(126,28)) and intent.scale.is_equal_approx(Vector2.ONE),label_text+": intent stays readable at either zoom")

func _ready() -> void:
	output = "res://artifacts/qa/enemy-follow-hud-2026-10-14/split-%d/" % DisplayServer.window_get_size().x
	DirAccess.make_dir_recursive_absolute(output)
	var demo: Node = load("res://scenes/combat_stage_demo.tscn").instantiate()
	add_child(demo)
	await settle(0.5)
	app = demo.get_child(0)
	while app.shown_page != "battle" or app.view.model.enemies.size() != 3: await get_tree().process_frame
	await idle()
	await settle(3.0)
	var view = app.view
	var end_rect: Rect2 = view.end_button.get_global_rect()
	var cyber_rect: Rect2 = view.cyberware_button.get_global_rect()
	var hp_rect: Rect2 = view.hp_label.get_global_rect()
	var before: Vector2 = view.enemy_intents[0].global_position
	check_plates(view,"Wide")
	await shot("01-wide-follow")
	view.select_card(view.model.hand[0])
	await view.play_selected(0)
	await settle(0.3)
	check_plates(view,"Near")
	verify(view.enemy_intents[0].global_position.distance_to(before) > 30,"Intent follows camera projection while HP stays fixed")
	verify(view.shown_enemies[0].hp == 19,"Shown HP still refreshes on hit")
	await shot("02-near-follow")
	# Sample a moving actor without changing the combat model.
	var actor: Node2D = view.stage.enemies[1]
	var origin: Vector2 = actor.position
	var snapshot: Dictionary = view.model.snapshot()
	await view.stage.move_actor(actor,origin+Vector2(-130,30),0.20)
	await settle(0.05)
	check_plates(view,"Moved")
	await shot("03-moved-follow")
	await view.stage.move_actor(actor,origin,0.20)
	verify(view.model.snapshot() == snapshot,"Position tracking has no model side effects")
	await view.end_turn_pressed()
	check_plates(view,"Returned")
	await shot("04-return-follow")
	verify(view.end_button.get_global_rect() == end_rect and view.cyberware_button.get_global_rect() == cyber_rect and view.hp_label.get_global_rect() == hp_rect,"Buttons and player HUD retain their geometry")
	view.model.enemies[2].hp = 1
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.select_card(view.model.hand[0])
	await view.play_selected(2)
	await settle(0.1)
	verify(view.enemy_plates[2].visible and is_equal_approx(view.enemy_plates[2].modulate.a,0.4) and not view.enemy_intents[2].visible,"Dead enemy retains a dimmed HP slot but loses its intent")
	await shot("05-dead-hidden")
	Game.finish_training("lose")
	await idle()
	Game.start_training("B04")
	await idle()
	view = app.view
	check_plates(view,"Single")
	await shot("06-single-follow")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"mode":"rendered view calls"},"\t"))
	print("FOLLOW HUD: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
