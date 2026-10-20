extends Node
## Real viewport input coverage for aiming, cancellation and rapid card plays.
var app: Control
var failures := 0
var checks := 0
var output := OS.get_temp_dir().path_join("midnight_ui_")

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle(seconds: float = 0.2) -> void:
	await get_tree().create_timer(seconds).timeout

func idle() -> void:
	var start := Time.get_ticks_msec()
	while Game.transition_locked or Game.battle_busy:
		await get_tree().process_frame
		if Time.get_ticks_msec() - start > 6000:
			push_error("Timed out waiting for combat")
			get_tree().quit(1)
			return
	await get_tree().process_frame

func motion(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_viewport().get_final_transform() * pos
	event.global_position = event.position
	Input.warp_mouse(event.position)
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame

func click(pos: Vector2, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await motion(pos)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = get_viewport().get_final_transform() * pos
		event.global_position = event.position
		event.button_index = which
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame

func shot(id: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+id+".png")

func _ready() -> void:
	Game.save_enabled = false
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle()
	await motion(Vector2(417,707))
	await settle()
	await shot("button_hover")
	Game.start_training("B12")
	await idle()
	var view = app.view
	var uid: String = view.model.hand[0]
	var card: CombatCard = view.cards[uid]
	await click(card.home + Vector2(90,100))
	verify(view.selected_uid == uid,"Mouse click selects a card")
	await motion(Vector2(750,420))
	verify(view.aim.visible and not view.aim.locked,"Free pointer displays unlocked aiming line")
	verify(view.aim.tip.distance_to(Vector2(750,420)) < 2,"Arrow follows the pointer in stretched viewport coordinates")
	await settle()
	await shot("free_aim")
	await motion(Vector2(1020,380))
	await settle()
	verify(view.aim.locked,"Hovering the enemy locks targeting feedback")
	await shot("target_lock")
	await click(Vector2(1020,380), MOUSE_BUTTON_RIGHT)
	verify(view.selected_uid.is_empty() and not view.aim.visible,"Right click cancels without damage")
	verify(view.model.enemies[0].hp == 3,"Cancel preserves enemy HP")
	await click(card.home + Vector2(90,100))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	verify(Game.page == "battle" and view.selected_uid.is_empty(),"Escape cancels selection before navigating to menu")
	await click(card.home + Vector2(90,100))
	view.play_selected(99)
	verify(view.model.enemies[0].hp == 3 and view.model.hand.size() == 5,"Invalid target consumes neither card nor HP")
	var start := Time.get_ticks_msec()
	await click(Vector2(1020,380))
	view.play_selected(0)
	await idle()
	verify(Time.get_ticks_msec()-start < 450,"Next card is available before impact and discard tails finish")
	verify(view.model.enemies[0].hp == 2 and view.model.hand.size() == 4,"Rapid duplicate target click only plays one card")
	await shot("impact")
	uid = view.model.hand[0]
	await click(view.cards[uid].home + Vector2(90,100))
	verify(view.selected_uid == uid,"Next card selectable during previous impact")
	await click(Vector2(1020,380))
	await idle()
	verify(view.model.enemies[0].hp == 1,"Consecutive cards resolve in order")
	await view.end_turn_pressed()
	verify(view.model.player_hp == 99 and view.cards.size() == 5,"End turn safely recycles while visual tails finish")
	view.select_card(view.model.hand[0])
	view.show_pile("抽牌堆",view.model.draw_pile)
	verify(view.selected_uid.is_empty() and is_instance_valid(view.pile_overlay),"Pile dialog clears targeting")
	view.select_card(view.model.hand[0])
	verify(view.selected_uid.is_empty(),"Modal pile view blocks card selection")
	view.close_pile()
	await settle()
	view.select_card(view.model.hand[0])
	await view.play_selected(0)
	await idle()
	verify(Game.page == "menu","Lethal hit completes battle after the final impact")
	print("INTERACTION VISUAL: %d checks, %d failures; %s" % [checks, failures, output])
	get_tree().quit(0 if failures == 0 else 1)
