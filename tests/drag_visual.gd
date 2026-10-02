extends "res://tests/interaction_visual.gd"

func left_edge(pos: Vector2, down: bool) -> void:
	await motion(pos)
	var event := InputEventMouseButton.new()
	event.position = get_viewport().get_final_transform() * pos
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	Input.parse_input_event(event)
	await get_tree().process_frame

func _ready() -> void:
	Game.save_enabled = false
	output = OS.get_temp_dir().path_join("midnight_drag_")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.start_training("B12")
	await idle()
	var view = app.view
	var uid: String = view.model.hand[0]
	await left_edge(view.cards[uid].home+Vector2(90,100),true)
	verify(view.selected_uid == uid and view.aim.visible,"Mouse-down immediately selects and displays the line, before release")
	verify(view.held_card_uid == uid,"Mouse-down arms a held-card gesture")
	await motion(Vector2(1020,380))
	verify(view.aim.locked and view.model.enemies[0].hp == 3,"Holding over enemy aims without playing early")
	await shot("held_target")
	await left_edge(Vector2(1020,380),false)
	verify(view.model.enemies[0].hp == 2 and view.model.hand.size() == 2,"Releasing over target plays the held card")
	await left_edge(Vector2(1020,380),false)
	verify(view.model.enemies[0].hp == 2,"Duplicate release does not play twice")
	await idle()
	uid = view.model.hand[0]
	await left_edge(view.cards[uid].home+Vector2(90,100),true)
	await click(Vector2(1020,380),MOUSE_BUTTON_RIGHT)
	await left_edge(Vector2(1020,380),false)
	verify(view.selected_uid.is_empty() and view.model.enemies[0].hp == 2,"Right-cancel while held prevents an attack on release")
	await left_edge(view.cards[uid].home+Vector2(90,100),true)
	await left_edge(Vector2(720,430),false)
	verify(view.selected_uid == uid and view.model.hand.size() == 2,"Release over empty space preserves selection without consuming a card")
	await click(Vector2(1020,380))
	await idle()
	verify(view.model.enemies[0].hp == 1,"Click-to-confirm remains available after releasing over empty space")
	uid = view.model.hand[0]
	await click(view.cards[uid].home+Vector2(90,100))
	verify(view.selected_uid == uid,"Click-release on the same card keeps it selected")
	await click(view.cards[uid].home+Vector2(90,100))
	verify(view.selected_uid.is_empty(),"Second click deselects without release toggling it again")
	await left_edge(view.cards[uid].home+Vector2(90,100),true)
	await left_edge(Vector2(1020,380),false)
	await idle()
	verify(Game.page == "menu","Final drag attack completes battle normally")
	print("DRAG VISUAL: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
