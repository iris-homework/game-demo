extends "res://tests/interaction_visual.gd"

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame

func _ready() -> void:
	Game.save_enabled = false
	output = OS.get_temp_dir().path_join("midnight_cyberware_")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.start_training("B12")
	await idle()
	var view = app.view
	view.model.enemies[0].hp = 20
	view.model.enemies[0].maxHp = 20
	view.commit()
	view.refresh_enemy_hud()
	view.select_card(view.model.hand[0])
	await click(view.cyberware_button.get_rect().get_center())
	verify(is_instance_valid(view.pile_overlay) and view.selected_uid.is_empty(),"Button opens cyberware and clears targeting")
	var overlay = view.pile_overlay
	verify(overlay.card_buttons.size() == 6,"Six cards are displayed")
	await key(KEY_7)
	await key(KEY_8)
	verify(view.model.next_attack_bonus == 0,"Removed seventh and eighth shortcuts do nothing")
	for b in overlay.card_buttons:
		verify(Rect2(64,34,1312,828).encloses(b.get_global_rect()),"Entire cyberware card is visible")
	await motion(Vector2(80,180))
	await shot("six_cards")
	var turn: int = view.model.turn
	view.end_turn_pressed()
	view.show_pile("抽牌堆",view.model.draw_pile)
	view.finish("surrender")
	await key(KEY_F1)
	verify(view.model.turn == turn and Game.page == "battle" and view.pile_overlay == overlay and not is_instance_valid(app.debug_panel),"Modal blocks turn, pile, surrender and debug shortcuts")
	await click(overlay.card_buttons[0].get_global_rect().get_center())
	verify(view.model.next_attack_bonus == 1 and overlay.card_buttons[0].disabled,"Click activates and marks card used")
	await click(overlay.card_buttons[0].get_global_rect().get_center())
	verify(view.model.next_attack_bonus == 1,"Clicking used card never doubles effect")
	await key(KEY_1)
	verify(view.model.next_attack_bonus == 1,"Keyboard cannot bypass cooldown")
	verify(overlay.state_labels[0].text.contains("冷却中") and not overlay.card_buttons[1].disabled,"Only activated card enters cooldown")
	await key(KEY_2)
	verify(view.model.next_attack_bonus == 2 and Game.state.combat.nextAttackBonus == 2,"Keyboard activation stacks and commits")
	await shot("activated")
	await key(KEY_ESCAPE)
	verify(Game.page == "battle" and not is_instance_valid(view.pile_overlay),"Escape closes only overlay")
	verify(view.cyberware_status.text.contains("+2"),"Battle HUD shows pending bonus")
	await shot("battle_bonus")
	view.select_card(view.model.hand[0])
	view.play_selected(99)
	verify(view.model.next_attack_bonus == 2,"Invalid UI target preserves effect")
	await click(Vector2(1020,380))
	await idle()
	verify(view.model.enemies[0].hp == 17 and view.model.next_attack_bonus == 0,"Real attack receives +2 once")
	view.select_card(view.model.hand[0])
	await click(Vector2(1020,380))
	await idle()
	verify(view.model.enemies[0].hp == 16,"Following attack has normal damage")
	await click(view.cyberware_button.get_rect().get_center())
	verify(view.pile_overlay.card_buttons[0].disabled and view.pile_overlay.card_buttons[1].disabled,"Reopening preserves used-card state")
	await click(Vector2(700,740),MOUSE_BUTTON_RIGHT)
	verify(not is_instance_valid(view.pile_overlay) and Game.page == "battle","Right-click closes without leaving battle")
	await click(view.end_button.get_rect().get_center())
	await idle()
	verify(view.model.turn == turn+1 and view.cyberware_button.text.contains("6/6"),"Next turn restores all six activations in HUD")
	await click(view.cyberware_button.get_rect().get_center())
	overlay = view.pile_overlay
	verify(not overlay.card_buttons[0].disabled and overlay.state_labels[0].text.contains("点击激活"),"Next-turn card is available again")
	await motion(Vector2(80,180))
	await shot("cooldown_ready")
	await click(overlay.card_buttons[0].get_global_rect().get_center())
	verify(view.model.next_attack_bonus == 1 and overlay.card_buttons[0].disabled,"Same card can reactivate and enters cooldown again")
	await motion(Vector2(80,180))
	await shot("cooldown_gray")
	print("CYBERWARE VISUAL: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
