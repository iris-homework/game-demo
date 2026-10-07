extends "res://tests/drag_visual.gd"
## Ten-card fixtures stay in memory; the prototype still starts with five cards.
func _ready() -> void:
	Game.save_enabled = false
	output = OS.get_temp_dir().path_join("midnight_fan_"+str(DisplayServer.window_get_size().x)+"_")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.start_training("B04")
	await idle()
	await motion(Vector2(720,100))
	await settle(0.3)
	await shot("five")
	var view = app.view
	await motion(view.cards[view.model.hand[2]].home+Vector2(90,100))
	await settle(0.3)
	await shot("five_hover")
	await motion(Vector2(720,100))
	await settle(0.3)
	verify(view.cards.values().all(func(card): return not card.hovered and card.position.is_equal_approx(card.home) and card.scale.is_equal_approx(Vector2.ONE*card.home_scale)),"Leaving the hand returns cards to submerged resting pose")
	for card in view.cards.values(): card.queue_free()
	view.cards.clear()
	view.model.profile.handSize = 10
	view.model.enemies[0].hp = 100
	view.model.enemies[0].maxHp = 100
	for i in range(view.model.hand.size(),10):
		var uid := "fan_%02d" % i
		view.model.instances[uid] = "test_attack"
		view.model.draw_pile.append(uid)
	view.refresh_enemy_hud()
	view.model.draw_cards()
	view.set_busy(true)
	await view.deal_hand(true)
	view.set_busy(false)
	await settle(0.3)
	verify(view.cards.size() == 10,"Ten cards dealt into fan")
	for uid in view.model.hand:
		var card: CombatCard = view.cards[uid]
		verify(card.scale.is_equal_approx(Vector2.ONE*0.75) and is_equal_approx(card.rotation,card.home_rotation),"Draw animation restores fan pose")
		for corner in [Vector2.ZERO,Vector2(180,0),Vector2(180,230),Vector2(0,230)]:
			verify(Rect2(205,620,1030,420).has_point(card.get_global_transform()*corner),"Resting cards stay horizontally between side controls within the bottom tray")
		verify((card.get_global_transform()*Vector2(90,230)).y > 900.0 and (card.get_global_transform()*Vector2(90,0)).y < 900.0,"Resting card is partially submerged below screen")
	await shot("ten")
	for i in 10:
		var uid: String = view.model.hand[i]
		var card: CombatCard = view.cards[uid]
		await motion(card.home+card.pivot_offset)
		await settle(0.3)
		verify(card.hovered and card.scale.x > 1.0 and absf(card.rotation)<0.01,"Every card enlarges upright on hover")
		for corner in [Vector2.ZERO,Vector2(180,0),Vector2(180,230),Vector2(0,230)]:
			verify(Rect2(0,0,1440,900).has_point(card.get_global_transform()*corner),"Hovered card is fully visible above bottom edge")
		var hovered_count := 0
		for other in view.cards.values():
			if other.hovered: hovered_count += 1
		verify(hovered_count == 1,"Only one hovered card in overlapping fan")
		await click(card.home+card.pivot_offset)
		verify(view.selected_uid == uid,"Overlapping card click selects intended instance")
		await click(Vector2(720,400),MOUSE_BUTTON_RIGHT)
	await motion(view.cards[view.model.hand[4]].home+Vector2(90,115))
	await settle(0.3)
	await shot("hover")
	var uid: String = view.model.hand[0]
	await left_edge(view.cards[uid].home+Vector2(90,115),true)
	await left_edge(Vector2(1020,380),false)
	await idle()
	verify(view.model.hand.size() == 9 and view.model.enemies[0].hp == 99,"Drag from ten-card fan plays once")
	await motion(Vector2(720,100))
	await settle(0.4)
	for i in 9:
		verify(view.cards[view.model.hand[i]].home.is_equal_approx(view.hand_position(i,9)),"Remaining cards reflow after play")
	await click(view.DRAW_POS+view.PILE_SIZE/2)
	verify(is_instance_valid(view.pile_overlay),"Corner draw pile opens")
	view.close_pile()
	await click(view.DISCARD_POS+view.PILE_SIZE/2)
	verify(is_instance_valid(view.pile_overlay),"Corner discard pile opens")
	view.close_pile()
	await click(view.end_button.position+view.end_button.size/2)
	await idle()
	verify(view.model.turn == 2 and view.cards.size() == 10,"Ten-card cleanup and redraw complete normally")
	await motion(Vector2(720,100))
	await settle(0.4)
	await shot("redraw")
	print("HAND FAN VISUAL: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
