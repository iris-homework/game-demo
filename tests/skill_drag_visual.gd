extends "res://tests/noren_cards_visual.gd"

var test_buttons := 0
var last_pointer := Vector2.ZERO

# Let the OS pointer move settle before injecting the button event used by the battle view.
func pointer(position: Vector2, pressed: int = -1) -> void:
	var event: InputEventMouse
	if pressed < 0:
		event = InputEventMouseMotion.new()
		event.relative = position-last_pointer
	else:
		if pressed == 1: test_buttons |= MOUSE_BUTTON_MASK_LEFT
		else: test_buttons &= ~MOUSE_BUTTON_MASK_LEFT
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed == 1
	event.position = get_viewport().get_final_transform()*position
	event.global_position = event.position
	event.button_mask = test_buttons
	last_pointer = position
	Input.warp_mouse(event.position)
	await get_tree().create_timer(0.06).timeout
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame

func check(ok: bool, title: String) -> void:
	if not ok and is_instance_valid(app) and is_instance_valid(app.view):
		var view=app.view
		print("INPUT DIAGNOSTIC: ",{"title":title,"pointer":view.get_global_mouse_position(),"selected":view.selected_uid,"held":view.held_card_uid,"enemies":view.model.enemies})
		for uid in view.cards:
			var card: CombatCard=view.cards[uid]
			if card.selected or uid=="card_000": print(uid," pos=",card.position," home=",card.home," selected=",card.selected," follow=",card.dragging," hover=",card.hovered)
	super.check(ok,title)

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
	output = "res://artifacts/qa/card-release-priority-2026-10-16/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suffix="): output += arg.trim_prefix("--suffix=")+"-"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	var deadline := Time.get_ticks_msec()+5000
	while not get_window().has_focus() and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	Game.start_training("B04")
	await idle()
	await install_hand([2,3,7,23,1])
	var view = app.view
	var before: Dictionary = view.model.snapshot()
	await start_drag()
	check(view.selected_uid=="card_000", "Press selects the intended skill")
	await pointer(Vector2(720,420))
	check(view.cards["card_000"].dragging and release_overlay_absent(view) and not view.aim.visible, "Skill follows with no release rectangle or instruction")
	check((view.cards["card_000"].global_position+view.cards["card_000"].pivot_offset).distance_to(Vector2(720,420))<3, "Dragged card follows pointer in logical coordinates")
	check(view.model.snapshot()==before, "Holding skill over center does not spend resources")
	await shot("held-skill")
	await pointer(Vector2(720,420),0)
	await idle()
	check(view.model.block==5 and view.model.energy==2 and not view.model.hand.has("card_000"), "Center release casts skill once without a button")
	check(release_overlay_absent(view), "No release overlay remains after casting")
	before=view.model.snapshot()
	await pointer(Vector2(720,420),0)
	check(view.model.snapshot()==before, "Duplicate release cannot cast again")
	await shot("released-skill")

	for point in [Vector2(60,420),Vector2(720,50),Vector2(720,760),Vector2(1310,740)]:
		await install_hand([2,1]);view=app.view
		await start_drag();await pointer(point);await pointer(point,0);await idle()
		check(view.model.block==5 and view.model.energy==2 and not view.cards.has("card_000"), "Non-attack release works beyond the former center bounds: "+str(point))
		check(view.model.turn==1 and not is_instance_valid(view.pile_overlay), "Drag release cannot trigger another button: "+str(point))
	for point in [Vector2(60,650),Vector2(50,840),Vector2(1380,840),Vector2(1300,175),Vector2(1300,40),Vector2(1310,740),Vector2(790,875)]:
		await install_hand([2,1]);view=app.view
		var first: Vector2=view.cards["card_000"].home+Vector2(68,110)
		await pointer(first,1);await pointer(first,0)
		await pointer(point,1);await pointer(point,0);await idle()
		check(app.view==view and Game.page=="battle", "Selected skill consumes button/card click without leaving battle: "+str(point))
		if app.view!=view:
			get_tree().quit(1)
			return
		check(view.model.block==5 and view.model.energy==2 and view.model.turn==1 and not is_instance_valid(view.pile_overlay) and not view.cards.has("card_000"), "Click casts exactly once instead of activating UI or changing selection: "+str(point))
	await install_hand([34,1]);view=app.view;before=view.model.snapshot()
	var skill_home: Vector2=view.cards["card_000"].home+Vector2(68,110)
	await pointer(skill_home,1);await pointer(skill_home,0)
	await pointer(Vector2(1310,740),1);await pointer(Vector2(1310,740),0)
	check(view.selected_uid=="card_000" and view.model.snapshot()==before and not is_instance_valid(view.pile_overlay), "Targeted non-attack consumes invalid button click but still requires an enemy")
	await key(KEY_ESCAPE)
	await pointer(view.DRAW_POS+view.PILE_SIZE/2,1);await pointer(view.DRAW_POS+view.PILE_SIZE/2,0)
	check(is_instance_valid(view.pile_overlay), "Explicit cancellation restores normal pile-button clicks")
	await key(KEY_ESCAPE)
	for point in [Vector2(215,100),Vector2(1225,100),Vector2(215,705),Vector2(1225,705)]:
		await install_hand([2,1]);view=app.view
		await start_drag();await pointer(point);await pointer(point,0);await idle()
		check(view.model.block==5 and view.model.energy==2 and not view.model.hand.has("card_000"), "Expanded release zone accepts its newly added corner: "+str(point))
	await install_hand([2,1])
	view=app.view;before=view.model.snapshot()
	var rest: Vector2=view.cards["card_000"].home+Vector2(68,110)
	await pointer(rest,1);await pointer(rest,0)
	check(view.model.snapshot()==before and view.selected_uid=="card_000", "Click selects a skill without spending it on initial release")
	await pointer(Vector2(560,400))
	check(view.cards["card_000"].dragging and (view.cards["card_000"].global_position+view.cards["card_000"].pivot_offset).distance_to(Vector2(560,400))<3, "Released selection keeps following the pointer without a held button")
	check(view.held_card_uid.is_empty() and release_overlay_absent(view), "Click selection has no release rectangle or instruction")
	check(view.model.snapshot()==before, "Moving a selected skill into the release zone does not cast it")
	await shot("click-follow-skill")
	await pointer(Vector2(560,400),1);await pointer(Vector2(560,400),0);await idle()
	check(view.model.block==5 and view.model.energy==2 and not view.model.hand.has("card_000"), "Second click in release zone casts selected skill exactly once")
	before=view.model.snapshot()
	await pointer(Vector2(560,400),0)
	check(view.model.snapshot()==before, "Extra release after click confirmation cannot duplicate a cast")
	await install_hand([2,1]);view=app.view;before=view.model.snapshot()
	await start_drag();await pointer(Vector2(720,420));await key(KEY_ESCAPE)
	await pointer(Vector2(720,420),0)
	check(view.model.snapshot()==before and release_overlay_absent(view), "Escape cancels a held skill before release")
	await start_drag();await pointer(Vector2(720,420))
	var cancel:=InputEventMouseButton.new()
	cancel.button_index=MOUSE_BUTTON_RIGHT;cancel.pressed=true
	cancel.position=get_viewport().get_final_transform()*Vector2(720,420)
	cancel.button_mask=test_buttons | MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(cancel)
	await get_tree().process_frame
	cancel=cancel.duplicate();cancel.pressed=false;cancel.button_mask=test_buttons;Input.parse_input_event(cancel)
	await pointer(Vector2(720,420),0)
	check(view.model.snapshot()==before and not view.cards["card_000"].dragging, "Right click cancels a held skill")
	await start_drag();await pointer(view.cards["card_000"].home+Vector2(68,110),0)
	await pointer(Vector2(560,400));await key(KEY_ESCAPE);await pointer(Vector2(720,200))
	await get_tree().create_timer(0.2).timeout
	check(view.selected_uid.is_empty() and not view.cards["card_000"].dragging and view.cards["card_000"].position.is_equal_approx(view.cards["card_000"].home), "Escape returns a click-selected skill to its original hand pose")
	check(view.model.snapshot()==before, "Cancelling a click-selected skill spends nothing")
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
	await install_hand([34,1]);view=app.view;before=view.model.snapshot()
	rest=view.cards["card_000"].home+Vector2(68,110)
	await pointer(rest,1);await pointer(rest,0)
	target_point=view.stage.target_rect(0).get_center()
	await pointer(target_point)
	check(view.cards["card_000"].dragging and (view.cards["card_000"].global_position+view.cards["card_000"].pivot_offset).distance_to(target_point)<3, "Enemy-targeted non-attack skill also follows the pointer")
	check(view.model.snapshot()==before, "Hovering a selected skill over an enemy does not cast it")
	await pointer(target_point,1);await pointer(target_point,0);await idle()
	check(view.model.enemies[0].bleed==2 and not view.cards.has("card_000"), "Following skill does not swallow enemy confirmation clicks")

	await install_hand([1,2,3,23,1,1,1,1,1,1]);view=app.view;before=view.model.snapshot()
	rest=view.cards["card_000"].home+Vector2(68,110)
	await pointer(rest,1);await pointer(rest,0)
	await get_tree().create_timer(0.2).timeout
	var attack: CombatCard=view.cards["card_000"]
	var centered: Vector2=attack.position
	check(view.selected_uid=="card_000" and absf((attack.get_global_transform()*attack.pivot_offset).x-720)<1 and is_equal_approx(attack.position.y,646), "Selected attack stays centered close to the bottom edge")
	check(is_zero_approx(attack.rotation) and is_equal_approx(attack.scale.x,1.12), "Centered attack is upright and fully enlarged")
	var bottom: float=(attack.get_global_transform()*Vector2(90,230)).y
	check(bottom>=888 and bottom<=892, "Selected attack remains fully visible with about ten pixels below it")
	check(view.model.snapshot()==before, "Centering an attack does not change cards or resources")
	await pointer(view.cards["card_009"].home+Vector2(68,110))
	check(attack.position.is_equal_approx(centered) and not attack.dragging, "Attack stays centered while the mouse moves across other cards")
	check(view.cards.values().all(func(card):return card==attack or card.z_index<attack.z_index), "Selected attack stays above every other hand card, including hover")
	await shot("attack-centered-top")
	await pointer(attack.global_position+Vector2(90,200),1)
	await pointer(attack.global_position+Vector2(90,200),0)
	check(view.selected_uid.is_empty() and view.model.snapshot()==before, "Clicking centered top card cancels it instead of selecting a card underneath")
	await pointer(Vector2(720,200));await get_tree().create_timer(0.2).timeout
	check(attack.position.is_equal_approx(attack.home) and is_equal_approx(attack.rotation,attack.home_rotation) and attack.z_index==attack.home_z, "Cancelled attack restores original fan position, rotation and layer")
	await start_drag();await pointer(rest,0)
	target_point=view.stage.target_rect(0).get_center()
	await pointer(target_point,1);await pointer(target_point,0);await idle()
	check(view.model.enemies[0].hp==114 and not view.cards.has("card_000"), "Centered attack still supports click-to-confirm on an enemy")

	await install_hand([38,1],"ranged");view=app.view
	await start_drag();await pointer(Vector2(720,420))
	await get_tree().create_timer(0.2).timeout
	check(not view.cards["card_000"].dragging and absf((view.cards["card_000"].get_global_transform()*view.cards["card_000"].pivot_offset).x-720)<1, "Area attack remains centered because presentation follows card type, not target type")
	await pointer(Vector2(720,420),0);await idle()
	check(view.model.enemies.all(func(enemy):return enemy.hp==114), "Centered area attack keeps center drag-release targeting")
	await install_hand([23,1]);view=app.view
	rest=view.cards["card_000"].home+Vector2(68,110)
	await pointer(rest,1);await pointer(rest,0);await pointer(Vector2(550,390))
	check(view.cards["card_000"].dragging and (view.cards["card_000"].global_position+view.cards["card_000"].pivot_offset).distance_to(Vector2(550,390))<3, "Power card also follows after click selection")
	before=view.model.snapshot()
	await pointer(view.DRAW_POS+view.PILE_SIZE/2,1);await pointer(view.DRAW_POS+view.PILE_SIZE/2,0)
	await idle()
	check(not is_instance_valid(view.pile_overlay) and view.selected_uid.is_empty() and not view.cards.has("card_000"), "Power card consumes a pile-button click without opening the pile")
	check(view.model.powers==["high_pressure"] and "card_000" in view.model.exhaust_pile and view.model.turn==1, "Power resolves normally when confirmed over a button")
	await install_hand([2,1]);view=app.view;before=view.model.snapshot()
	await key(KEY_A,true,true)
	await center_drop()
	check(view.model.snapshot()==before, "Console modal blocks skill drag")
	await key(KEY_A,true,true)
	await shot("final")
	print("SKILL DRAG: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
