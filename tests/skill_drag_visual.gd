extends "res://tests/noren_cards_visual.gd"

func start_drag(uid: String = "card_000") -> void:
	await pointer(app.view.cards[uid].home+Vector2(68,110),1)

func center_drop(uid: String = "card_000") -> void:
	await start_drag(uid)
	await pointer(Vector2(720,420))
	await pointer(Vector2(720,420),0)
	await idle()

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://skill_drag_visual_unused.json"
	Game.meta_path = "user://skill_drag_visual_meta_unused.json"
	output = "res://artifacts/qa/skill-drag-2026-10-16/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suffix="): output += arg.trim_prefix("--suffix=")+"-"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(0.4).timeout
	Game.start_training("B04")
	await idle()
	await install_hand([2,3,7,23,1])
	var view = app.view
	var before: Dictionary = view.model.snapshot()
	await start_drag()
	check(view.selected_uid=="card_000", "Press selects the intended skill")
	await pointer(Vector2(720,420))
	check(view.cards["card_000"].dragging and view.drop_zone.visible and not view.aim.visible, "Skill follows drag with a center release cue")
	check((view.cards["card_000"].global_position+view.cards["card_000"].pivot_offset).distance_to(Vector2(720,420))<3, "Dragged card follows pointer in logical coordinates")
	check(view.model.snapshot()==before, "Holding skill over center does not spend resources")
	await shot("held-skill")
	await pointer(Vector2(720,420),0)
	await idle()
	check(view.model.block==5 and view.model.energy==2 and not view.model.hand.has("card_000"), "Center release casts skill once without a button")
	check(not view.drop_zone.visible, "Release removes the drop cue")
	before=view.model.snapshot()
	await pointer(Vector2(720,420),0)
	check(view.model.snapshot()==before, "Duplicate release cannot cast again")
	await shot("released-skill")

	for point in [Vector2(60,420),Vector2(720,120),Vector2(720,760),Vector2(1310,740)]:
		await install_hand([2,1])
		view=app.view;before=view.model.snapshot()
		await start_drag()
		await pointer(point)
		await pointer(point,0)
		check(view.model.snapshot()==before, "Release outside center does not cast or end turn: "+str(point))
		check(view.selected_uid.is_empty() and not view.cards["card_000"].dragging and not view.drop_zone.visible, "Invalid release returns skill to hand")
	await install_hand([2,1])
	view=app.view;before=view.model.snapshot()
	var rest: Vector2=view.cards["card_000"].home+Vector2(68,110)
	await pointer(rest,1);await pointer(rest,0)
	check(view.model.snapshot()==before and view.selected_uid.is_empty(), "Click without dragging never casts a skill")
	await start_drag();await pointer(Vector2(720,420));await key(KEY_ESCAPE)
	await pointer(Vector2(720,420),0)
	check(view.model.snapshot()==before and not view.drop_zone.visible, "Escape cancels a held skill before release")
	await start_drag();await pointer(Vector2(720,420))
	var cancel:=InputEventMouseButton.new()
	cancel.button_index=MOUSE_BUTTON_RIGHT;cancel.pressed=true
	cancel.position=get_viewport().get_final_transform()*Vector2(720,420)
	Input.parse_input_event(cancel)
	await get_tree().process_frame
	cancel=cancel.duplicate();cancel.pressed=false;Input.parse_input_event(cancel)
	await pointer(Vector2(720,420),0)
	check(view.model.snapshot()==before and not view.cards["card_000"].dragging, "Right click cancels a held skill")
	view.model.energy=0;before=view.model.snapshot()
	await center_drop()
	check(view.model.snapshot()==before, "Insufficient energy cannot cast by dragging")

	await install_hand([23,1]);view=app.view
	await center_drop()
	check(view.model.powers==["high_pressure"] and "card_000" in view.model.exhaust_pile, "Ability casts from center and enters exhaust")
	await install_hand([38,1],"ranged");view=app.view
	await center_drop()
	check(view.model.enemies.all(func(enemy):return enemy.hp==114) and view.model.ammo==1, "Area attack hits all targets from center with one ammo")
	await install_hand([7,1]);view=app.view
	await center_drop()
	check(view.model.hand.size()==3 and view.cards.size()==3, "Draw skill creates live hand cards after center release")
	await install_hand([12,1,2]);view=app.view;before=view.model.snapshot()
	await center_drop()
	check(is_instance_valid(view.pile_overlay) and view.model.snapshot()==before, "Dismantle drag opens its required choice without early spend")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(view.pile_overlay) and view.model.snapshot()==before, "Cancel required choice leaves skill and resources unchanged")
	await center_drop()
	check(is_instance_valid(view.pile_overlay), "Skill can be dragged again immediately after cancelling its choice")
	if not is_instance_valid(view.pile_overlay):
		get_tree().quit(1)
		return
	view.pile_overlay.picked.emit("card_001")
	await idle()
	check(view.model.ammo==4 and "card_001" in view.model.discard_pile and "card_000" in view.model.exhaust_pile, "Dismantle resolves only after selecting the exact attack")
	await install_hand([34,1]);view=app.view;before=view.model.snapshot()
	var empty_point:=Vector2(720,300)
	check(view.target_at_point(empty_point)==-1, "Targeted skill sample uses empty central space")
	await start_drag();await pointer(empty_point);await pointer(empty_point,0)
	check(view.model.snapshot()==before, "Targeted skill still requires an enemy")
	view.cancel_selection()
	await start_drag()
	var target_point: Vector2=view.stage.target_rect(0).get_center()
	await pointer(target_point);await pointer(target_point,0);await idle()
	check(view.model.enemies[0].bleed==2, "Targeted skill casts by releasing over its enemy")
	await install_hand([2,1]);view=app.view;before=view.model.snapshot()
	await key(KEY_F2)
	await center_drop()
	check(view.model.snapshot()==before, "Console modal blocks skill drag")
	await key(KEY_F2)
	await shot("final")
	print("SKILL DRAG: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
