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

func modified_key(code: Key, modifier: String = "", repeat: bool = false, down: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = down
	event.echo = repeat
	event.ctrl_pressed = modifier == "ctrl"
	event.alt_pressed = modifier == "alt"
	event.meta_pressed = modifier == "meta"
	event.shift_pressed = modifier == "shift"
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	await get_tree().process_frame

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://hand_number_keys_unused.json"
	Game.meta_path = "user://hand_number_keys_meta_unused.json"
	Game.state = Game.initial_state()
	output = "res://artifacts/qa/hand-number-keys-2026-10-19/window/"
	DirAccess.make_dir_recursive_absolute(output)
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	await install_hand([1,2,3,4,5,6,7,8,9,10,1])
	var view = app.view
	view.model.energy = 99
	view.model.ammo = 10
	view.refresh_resources()
	view.commit()
	var before: Dictionary = view.model.snapshot()
	var adventure: Dictionary = Game.state.duplicate(true)
	var top := [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8,KEY_9,KEY_0]
	var keypad := [KEY_KP_1,KEY_KP_2,KEY_KP_3,KEY_KP_4,KEY_KP_5,KEY_KP_6,KEY_KP_7,KEY_KP_8,KEY_KP_9,KEY_KP_0]
	for keys in [top,keypad]:
		for i in keys.size():
			await key(keys[i])
			check(view.selected_uid == view.model.hand[i] and view.cards[view.model.hand[i]].selected, "Digit selects current hand slot %d" % (i+1))
			check(view.cards.values().filter(func(card): return card.selected).size() == 1, "Only one card is selected")
	check(view.model.snapshot() == before and Game.state == adventure, "Selection never plays a card, spends resources, reorders hand or saves")
	await key(KEY_0)
	check(view.selected_uid == view.model.hand[9], "Repeated digit keeps its card selected")
	await modified_key(KEY_1, "", true)
	await modified_key(KEY_1, "", false, false)
	check(view.selected_uid == view.model.hand[9], "Echo and release events cannot select")
	for modifier in ["ctrl","alt","meta","shift"]:
		await modified_key(KEY_1, modifier)
		check(view.selected_uid == view.model.hand[9], "Modified digits are ignored: "+modifier)
	await shot("ten-selected")
	view.cancel_selection()
	Game.battle_busy = true
	await key(KEY_1)
	check(view.selected_uid.is_empty(), "Animation lock blocks digit selection")
	Game.battle_busy = false
	Game.transition_locked = true
	await key(KEY_1)
	check(view.selected_uid.is_empty(), "Transition blocks digit selection")
	Game.transition_locked = false
	view.initialized = false
	await key(KEY_1)
	check(view.selected_uid.is_empty(), "Entry setup blocks digit selection")
	view.initialized = true
	view.model.outcome = "win"
	await key(KEY_1)
	check(view.selected_uid.is_empty(), "Finished battle blocks digit selection")
	view.model.outcome = ""
	await key(KEY_1)
	view.model.energy = 0
	await key(KEY_2)
	check(view.selected_uid == view.model.hand[0], "Unaffordable card keeps existing selection and original play-error path")
	view.model.energy = 99
	view.cancel_selection()
	for kind in ["pile","technology","choice","deck","console","debug"]:
		match kind:
			"pile": view.show_pile("抽牌堆",view.model.draw_pile)
			"technology": view.show_cyberware()
			"choice": view.show_card_choice("测试选择",[{"text":"测试选项","value":0}],func(_value): pass)
			"deck": app.open_current_deck()
			"console": app.open_card_console()
			"debug": app.toggle_debug()
		await get_tree().process_frame
		await key(KEY_1)
		check(view.selected_uid.is_empty(), "Modal blocks underlying selection: "+kind)
		if kind == "technology":
			check(view.model.used_cyberware == ["test_cyberware_01"] and view.model.next_attack_bonus == 1, "Technology popup retains its own existing digit1 activation")
			before = view.model.snapshot()
			adventure = Game.state.duplicate(true)
		match kind:
			"pile","technology","choice": view.close_pile()
			"deck": app.close_current_deck()
			"console": app.close_card_console()
			"debug": app.toggle_debug()
		await get_tree().process_frame
	check(view.model.snapshot() == before and Game.state == adventure, "Blocked shortcuts and modal browsing preserve combat and adventure")
	await install_hand([1,2,1])
	view = app.view
	await key(KEY_1)
	await key(KEY_0)
	await key(KEY_4)
	check(view.selected_uid == "card_000", "Missing hand slots do nothing")
	await pointer(view.stage.target_rect(0).get_center(),1)
	await pointer(view.stage.target_rect(0).get_center(),0)
	await idle()
	check(view.model.enemies[0].hp == 114 and view.model.hand == ["card_001","card_002"], "Digit-selected attack uses existing mouse target confirmation exactly once")
	await key(KEY_1)
	check(view.selected_uid == "card_001", "After playing, digit1 selects new first card")
	var block_before: int = view.model.block
	check(block_before == 0, "Digit-selected skill does not auto-play")
	await pointer(Vector2(720,420),1)
	await pointer(Vector2(720,420),0)
	await idle()
	check(view.model.block == 5 and view.model.energy == 1 and view.model.hand == ["card_002"], "Digit-selected skill uses ordinary click-to-play once")
	await key(KEY_1)
	await key(KEY_ESCAPE)
	check(view.selected_uid.is_empty() and Game.page == "battle", "Escape cancels keyboard selection without leaving battle")
	await key(KEY_1)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	get_viewport().push_input(right,true)
	await get_tree().process_frame
	check(view.selected_uid.is_empty(), "Right click cancels keyboard selection")
	await shot("after-play-new-first")
	Game.finish_training("lose")
	await idle()
	check(not Game.training_mode and Game.state == Game.initial_state(), "Training restores original adventure")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false},"\t"))
	print("HAND NUMBER KEYS: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
