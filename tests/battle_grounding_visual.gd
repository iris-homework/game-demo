extends "res://tests/drag_visual.gd"
## Stage placement and real pointer regression. Fixtures never write adventure saves.
# Native cursor movement on macOS arrives asynchronously; establish the point before clicks.
func motion(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_viewport().get_final_transform() * pos
	event.global_position = event.position
	Input.warp_mouse(event.position)
	await settle(0.08)
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame
	if app != null and app.view.get_global_mouse_position().distance_to(pos) > 3.0:
		push_error("Pointer placement failed: requested %s, actual %s" % [pos,app.view.get_global_mouse_position()])
		get_tree().quit(1)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://battle_grounding_qa_checkpoint.json"
	Game.meta_path = "user://battle_grounding_qa_meta.json"
	var folder := "res://artifacts/qa/battle-grounding-2026-10-12/" + str(DisplayServer.window_get_size().x)
	DirAccess.make_dir_recursive_absolute(folder)
	output = folder + "/"
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle(0.4)
	for id in ["B04", "B12", "B11", "B05A"]:
		Game.start_training(id)
		await idle()
		await motion(Vector2(720,100))
		await settle(0.3)
		var view = app.view
		var extra: float = {"B04":20.0,"B12":40.0,"B11":80.0,"B05A":0.0}[id]
		verify(view.player_portrait.position.is_equal_approx(Vector2(90,239+extra)), id + " player placement")
		verify(view.enemy_position(0).is_equal_approx(Vector2(791,253+extra)), id + " enemy placement")
		var target_rect: Rect2 = view.targets[0].get_global_rect()
		verify(is_equal_approx(target_rect.position.y,283+extra), id + " target follows stage exactly once")
		verify(target_rect.end.y < view.end_button.position.y, id + " target stays above hand controls")
		if id == "B12":
			verify(view.enemy_portraits[0].position.is_equal_approx(view.enemy_position(0)), "mech uses calibrated position")
			var shadow_found := false
			for child in view.get_children():
				if child.get_script() == load("res://scripts/combat/arena_fx.gd"):
					shadow_found = child.contact_points.has(view.enemy_position(0)+Vector2(230,307))
			verify(shadow_found, "enemy contact patch follows feet")
		await shot(id + "_grounded")
		# A foot-area point below the OLD target bottom detects stale invisible hit boxes.
		var target_point := Vector2(target_rect.get_center().x,570+extra*0.5) if extra > 0 else target_rect.get_center()
		var uid: String = view.model.hand[0]
		await left_edge(view.cards[uid].home+Vector2(90,100),true)
		verify(view.held_card_uid == uid, id + " mouse-down starts drag")
		await motion(target_point)
		verify(view.aim.locked, id + " new lower target area locks")
		verify(view.aim.target_center.is_equal_approx(view.enemy_position(0)+Vector2(230,150)), id + " arrow follows actor")
		await shot(id + "_aim")
		await left_edge(target_point,false)
		await idle()
		verify(view.model.enemies[0].hp == 2, id + " release in moved target plays once")
		var impact_found := false
		for number in get_tree().get_nodes_in_group("combat_damage_numbers"):
			if number.get_parent() == view:
				impact_found = impact_found or number.anchor.is_equal_approx(view.enemy_position(0)+Vector2(230,150))
		verify(impact_found, id + " impact uses moved actor anchor")
		uid = view.model.hand[0]
		await left_edge(view.cards[uid].home+Vector2(90,100),true)
		await click(target_point,MOUSE_BUTTON_RIGHT)
		await left_edge(target_point,false)
		verify(view.selected_uid.is_empty() and view.model.enemies[0].hp == 2, id + " cancel prevents release attack")
		await click(view.cards[uid].home+Vector2(90,100))
		await click(target_point)
		await idle()
		verify(view.model.enemies[0].hp == 1, id + " click-to-play still works")
		print("TURN BEFORE ", id, " busy=", Game.battle_busy, " disabled=", view.end_button.disabled, " rect=", view.end_button.get_global_rect())
		await click(view.end_button.position+view.end_button.size/2)
		print("TURN CLICK ", id, " pointer=", view.get_global_mouse_position(), " busy=", Game.battle_busy, " down=", Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
		await idle()
		verify(view.model.player_hp == 99 and view.model.turn == 2 and view.cards.size() == 5, id + " turn control remains usable")
		await motion(Vector2(720,100))
		await shot(id + "_turn2")
		view.finish("surrender")
		await idle()
		verify(Game.page == "menu", id + " exit restores training state")
		await settle(4.1) # Let the exit toast expire before the next scene capture.
	print("BATTLE GROUNDING: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
