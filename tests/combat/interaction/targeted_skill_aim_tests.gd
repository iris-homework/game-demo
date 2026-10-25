extends "res://tests/combat/cards/noren_cards_visual.gd"
## Headless synthetic viewport input only: no desktop pointer, rendering or user saves.
var buttons := 0

func pointer(position: Vector2, pressed: int = -1) -> void:
	if pressed >= 0: await pointer(position)
	var event: InputEventMouse
	if pressed < 0:
		event = InputEventMouseMotion.new()
	else:
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed == 1
		buttons = MOUSE_BUTTON_MASK_LEFT if pressed == 1 else 0
	event.position = position
	event.global_position = position
	event.button_mask = buttons
	if event is InputEventMouseMotion:
		event.position = get_viewport().get_final_transform() * position
		event.global_position = event.position
		Input.parse_input_event(event)
	else: get_viewport().push_input(event, true)
	await get_tree().process_frame
	await get_tree().process_frame

func click_at(point: Vector2) -> void:
	await pointer(point, 1)
	await pointer(point, 0)

func card_point(uid: String = "card_000") -> Vector2:
	return app.view.cards[uid].home + Vector2(68,110)

func wait_pose() -> void:
	await get_tree().create_timer(0.18).timeout

func cancel_right() -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = down
		event.position = app.view.get_global_mouse_position()
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func test_skill(number: int, form: String) -> void:
	await install_hand([number,1,2], form)
	var view = app.view
	if number == 39: view.model.buffs.apply(view.model, "bleed", 3, 1)
	var before: Dictionary = view.model.snapshot()
	var target: Vector2 = view.targets[1].get_global_rect().get_center()
	check(view.target_at_point(target) == 1, "Fixture can select the second living enemy")
	await pointer(card_point(), 1)
	check(view.selected_uid == "card_000" and view.held_card_uid == "card_000", "%s %d mouse-down selects without waiting for release" % [form,number])
	check(view.aim.visible and view.cards.card_000.center_on_selection and not view.cards.card_000.dragging, "%s %d uses attack-style stationary aim" % [form,number])
	await pointer(target)
	await wait_pose()
	var pose: Vector2 = view.cards.card_000.position
	check(view.aim.locked and view.hovered_target == 1, "%s %d locks aimed second enemy" % [form,number])
	check(pose.is_equal_approx(view.cards.card_000.selection_home + Vector2(0,-150)), "%s %d selected card occupies the centered attack pose" % [form,number])
	check(view.model.snapshot() == before, "%s %d aiming does not spend or resolve skill" % [form,number])
	await pointer(target, 0)
	await idle()
	check(not view.model.hand.has("card_000") and view.model.energy == 3-int(Game.card_catalog["noren_%02d" % number].cost), "%s %d release commits exactly one card and cost" % [form,number])
	match number:
		11:
			check(view.model.block == 8 and view.model.buffs.count(view.model,"weak",1) == 1, "Ranged steady footing blocks and weakens the chosen enemy")
		30,34:
			check(view.model.buffs.count(view.model,"bleed",1) == (2 if form == "ranged" else 3) and view.model.buffs.count(view.model,"bleed",0) == 0 and view.model.buffs.count(view.model,"bleed",2) == 0, "%s %d bleed affects only chosen second enemy" % [form,number])
			if number == 34: check("card_000" in view.model.exhaust_pile, "Mark follows its original exhaust rule")
		39:
			check(view.model.hand.size() == before.hand.size()-1+3 and view.model.buffs.count(view.model,"bleed",1) == 3, "%s blood trail draws three from chosen wounded enemy without changing bleed" % form)
	var paid: Dictionary = view.model.snapshot()
	await pointer(target, 0)
	check(view.model.snapshot() == paid, "%s %d duplicate release cannot resolve twice" % [form,number])

func test_confirm_switch_cancel() -> void:
	await install_hand([34,30,1])
	var view = app.view
	var before: Dictionary = view.model.snapshot()
	await click_at(card_point())
	await pointer(Vector2(600,300))
	check(view.selected_uid == "card_000" and view.aim.visible and not view.cards.card_000.dragging and view.model.snapshot() == before, "Click selection keeps stationary aim without casting")
	await pointer(card_point("card_002"), 1)
	await pointer(Vector2(500,300), 0)
	check(view.selected_uid == "card_002" and view.model.snapshot() == before, "Targeted skill permits switching directly to another hand card")
	view.cancel_selection()
	await pointer(card_point(), 1)
	await pointer(Vector2(600,300), 0)
	check(view.selected_uid == "card_000" and view.model.snapshot() == before, "Release over empty space preserves selection and resources")
	await click_at(view.targets[2].get_global_rect().get_center())
	await idle()
	check(view.model.buffs.count(view.model,"bleed",2) == 3 and view.model.buffs.count(view.model,"bleed",1) == 0, "Subsequent enemy click confirms skill on a different target")
	await install_hand([34,1]);view=app.view;before=view.model.snapshot()
	await click_at(card_point())
	await wait_pose()
	await click_at(view.cards.card_000.get_global_transform()*Vector2(90,110))
	check(view.selected_uid.is_empty() and view.model.snapshot() == before, "Clicking selected centered card again cancels just as attack")
	for cancel in ["escape","right"]:
		await pointer(card_point(), 1)
		await pointer(view.targets[0].get_global_rect().get_center())
		if cancel == "escape": await key(KEY_ESCAPE)
		else: await cancel_right()
		await pointer(view.targets[0].get_global_rect().get_center(), 0)
		check(view.selected_uid.is_empty() and view.model.snapshot() == before, cancel+" cancels held skill before release without spending")
	await click_at(card_point())
	await click_at(view.DRAW_POS+view.PILE_SIZE/2)
	check(is_instance_valid(view.pile_overlay) and view.model.snapshot() == before, "Targeted skill allows pile button rather than consuming invalid UI clicks")
	await key(KEY_ESCAPE)

func test_invalid_and_forms() -> void:
	await install_hand([30,11,1])
	var view = app.view
	view.model.enemies[0].hp = 0
	view.refresh_enemy_hud()
	var before: Dictionary = view.model.snapshot()
	await pointer(card_point(), 1)
	await pointer(view.targets[0].get_global_rect().get_center(), 0)
	check(view.model.snapshot() == before and view.selected_uid == "card_000", "Dead enemy release cannot resolve targeted skill")
	await key(KEY_ESCAPE)
	view.model.energy = 0
	before = view.model.snapshot()
	await pointer(card_point(), 1)
	await pointer(view.targets[1].get_global_rect().get_center(), 0)
	check(view.selected_uid.is_empty() and view.model.snapshot() == before, "Insufficient energy prevents selection and targeted release")
	await install_hand([11,1]);view=app.view;before=view.model.snapshot()
	view.select_card("card_000",false)
	check(not view.cards.card_000.center_on_selection and view.cards.card_000.dragging and not view.aim.visible, "Melee steady footing retains self-skill following input")
	view.cancel_selection()
	view.model.stance = "ranged"
	view.select_card("card_000",false)
	check(view.cards.card_000.center_on_selection and not view.cards.card_000.dragging and view.aim.visible, "Same existing hand changes to enemy aim after stance becomes ranged")
	view.cancel_selection()
	view.model.stance = "melee"
	view.select_card("card_000",false)
	check(not view.cards.card_000.center_on_selection and view.cards.card_000.dragging and not view.aim.visible, "Same hand returns to self-skill following after stance becomes melee")
	await key(KEY_ESCAPE)
	await click_at(card_point())
	await click_at(Vector2(60,420))
	await idle()
	check(view.model.block == 8 and view.model.ammo == int(before.norenState.ammo)+1 and not view.model.hand.has("card_000"), "Melee steady footing still casts in whole-view self release area")
	for all_target in [false,true]:
		await install_hand([2,1]);view=app.view
		if all_target: view.model.card_catalog.noren_02.target = "all"
		view.select_card("card_000",false)
		await pointer(Vector2(60,420))
		check(not view.cards.card_000.center_on_selection and view.cards.card_000.dragging and not view.aim.visible, "Self/all nonattack keeps following pose: "+str(all_target))
		await click_at(Vector2(60,420));await idle()
		check(view.model.block == 5 and not view.model.hand.has("card_000"), "Self/all nonattack keeps whole-view cast: "+str(all_target))
	await install_hand([1,2]);view=app.view
	await pointer(card_point(),1)
	await pointer(view.targets[1].get_global_rect().get_center(),0)
	await idle()
	check(view.model.enemies[1].hp == 114 and not view.model.hand.has("card_000"), "Original attack drag still damages chosen enemy exactly once")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://targeted_skill_aim_unused.json"
	Game.meta_path = "user://targeted_skill_aim_meta_unused.json"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.start_training("B04")
	await idle()
	for form in ["melee","ranged"]:
		for number in [30,34,39]: await test_skill(number,form)
	await test_skill(11,"ranged")
	await test_confirm_switch_cancel()
	await test_invalid_and_forms()
	await preload("res://scripts/combat/audio_cleanup.gd").release(app,get_tree())
	app.queue_free()
	await get_tree().process_frame
	print("TARGETED SKILL AIM: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
