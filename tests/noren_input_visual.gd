extends "res://tests/noren_cards_visual.gd"
func _ready() -> void:
	Game.save_enabled=false
	Game.save_path="user://noren_input_unused.json"
	Game.meta_path="user://noren_input_meta_unused.json"
	output += "input-"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	app=preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(0.5).timeout
	Game.start_training("B04")
	await idle()
	var view
	await install_hand([1,4,1,2,3])
	view=app.view
	var rest: Vector2=view.cards["card_000"].home+Vector2(68,110)
	await pointer(rest)
	await pointer(rest,1)
	print("INPUT POSITION: ", rest, " actual: ",view.get_global_mouse_position()," hover: ",view.hand_at_pointer()," selected: ",view.selected_uid," transform: ",get_viewport().get_final_transform())
	check(view.selected_uid=="card_000" and view.aim.visible,"Mouse-down immediately starts attack aim")
	if failures > 0:
		get_tree().quit(1)
		return
	await pointer(view.stage.target_rect(0).get_center())
	await pointer(view.stage.target_rect(0).get_center(),0)
	await idle()
	check(view.model.enemies[0].hp==114 and not view.cards.has("card_000"),"Drag-release attack resolves once")
	rest=view.cards["card_002"].home+Vector2(90,80)
	await pointer(rest,1)
	await key(KEY_ESCAPE)
	await pointer(view.stage.target_rect(0).get_center(),0)
	check(view.model.enemies[0].hp==114,"Cancelled drag release does not play")
	await pointer(view.cards["card_001"].home+Vector2(68,110),1)
	await pointer(Vector2(720,420))
	await pointer(Vector2(720,420),0)
	await idle()
	# Place the actor close only in this visual fixture to exercise the authored retreat branch.
	view.stage.player.position=view.stage.enemies[0].position-Vector2(130,0)
	var phases: Array=[]
	view.stage.phase_changed.connect(func(phase):
		phases.append(phase)
		if phase=="shoot": shot.call_deferred("shoot-pose")
		elif phase=="retreat": shot.call_deferred("retreat-pose"))
	view.select_card("card_002");view.play_selected(0);await idle()
	check("retreat" in phases and "shoot" in phases,"Close ranged attack hops back before firing")
	await key(KEY_A,true,true)
	var frozen_battle: Dictionary=view.model.snapshot()
	await pointer(Vector2(1310,740),1);await pointer(Vector2(1310,740),0)
	check(view.model.snapshot()==frozen_battle,"Console blocks underlying end-turn click")
	await key(KEY_A,true,true)
	check(not is_instance_valid(app.card_console),"Ctrl+Shift+A closes battle console")

	print("NOREN INPUT: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
