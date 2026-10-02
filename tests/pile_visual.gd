extends "res://tests/interaction_visual.gd"

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame

func _ready() -> void:
	Game.save_enabled = false
	output = OS.get_temp_dir().path_join("midnight_pile_")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.start_training("B12")
	await idle()
	var view = app.view
	await click(Vector2(125,760))
	await settle()
	verify(is_instance_valid(view.pile_overlay), "Draw pile click opens full-screen browser")
	verify(view.pile_overlay.displayed_uids.is_empty(), "Empty draw pile has no invented cards")
	await shot("empty")
	await key(KEY_ESCAPE)
	verify(Game.page == "battle" and not is_instance_valid(view.pile_overlay), "Escape closes browser without leaving combat")
	for i in 2:
		view.select_card(view.model.hand[0])
		await view.play_selected(0)
	await click(Vector2(1300,760))
	await settle()
	verify(view.pile_overlay.grid.get_child_count() == 2, "Discard pile shows both complete cards")
	await shot("discard")
	await click(Vector2(1230,820))
	verify(not is_instance_valid(view.pile_overlay), "Return button closes browser")
	# Capacity fixtures only: actual game data and saves are unchanged.
	var fixture: Array = []
	for kind in 3:
		var id := "fixture_%d" % kind
		var definition: Dictionary = view.model.card_catalog.test_attack.duplicate(true)
		definition.id = id
		definition.name = ["测试卡甲", "测试卡乙", "测试卡丙"][kind]
		definition.sortOrder = 30-kind
		view.model.card_catalog[id] = definition
		for i in 10:
			var uid := "%s_%02d" % [id,i]
			view.model.instances[uid] = id
			fixture.append(uid)
	fixture.shuffle()
	for kind in 3: view.model.card_catalog["fixture_%d" % kind].erase("sortOrder")
	var default_order: Array = preload("res://scripts/combat/pile_view.gd").ordered_cards(view.model, fixture)
	verify(str(default_order[0]).begins_with("fixture_0") and str(default_order[29]).begins_with("fixture_2"), "Without sortOrder, card catalog order is the default")
	for kind in 3: view.model.card_catalog["fixture_%d" % kind].sortOrder = 30-kind
	view.model.draw_pile = fixture.duplicate()
	view.refresh_counts()
	var before: Dictionary = view.model.snapshot()
	await click(Vector2(125,760))
	await settle()
	var browser = view.pile_overlay
	var order: Array = browser.displayed_uids.duplicate()
	verify(order.size() == 30 and browser.grid.get_child_count() == 30, "All 30 cards, including duplicate copies, are displayed")
	verify(str(order[0]).begins_with("fixture_2") and str(order[29]).begins_with("fixture_0"), "Configured default order overrides arrival order")
	verify(before == view.model.snapshot(), "Browsing and sorting never mutate combat piles")
	verify(browser.scroll.get_v_scroll_bar().visible, "Overflow shows vertical scrollbar")
	await shot("capacity_top")
	var hp: int = view.model.enemies[0].hp
	await click(Vector2(200,280))
	verify(view.model.enemies[0].hp == hp and view.selected_uid.is_empty(), "Preview cards are read-only")
	var turn: int = view.model.turn
	await click(Vector2(1300,645))
	verify(view.model.turn == turn, "Full-screen browser blocks the underlying end-turn button")
	for i in 6: await click(Vector2(200,280),MOUSE_BUTTON_WHEEL_DOWN)
	verify(browser.scroll.scroll_vertical > 0, "Mouse wheel scrolls even over a card")
	await key(KEY_END)
	await settle()
	verify(browser.scroll.scroll_vertical > 900, "Last row can be reached")
	await shot("capacity_bottom")
	var last: Control = browser.grid.get_child(29)
	var card_bottom := last.global_position.y + 280
	verify(card_bottom <= browser.scroll.global_position.y + browser.scroll.size.y, "Last card is fully visible at the bottom")
	await key(KEY_F1)
	verify(not is_instance_valid(app.debug_panel), "Browser blocks underlying keyboard shortcuts")
	await key(KEY_ESCAPE)
	fixture.reverse()
	view.show_pile("弃牌堆", fixture)
	await settle()
	verify(view.pile_overlay.displayed_uids == order, "Reversed pile order produces identical default layout")
	await click(Vector2(700,450),MOUSE_BUTTON_RIGHT)
	verify(not is_instance_valid(view.pile_overlay) and Game.page == "battle", "Right click closes only the browser")
	print("PILE VISUAL: %d checks, %d failures; %s" % [checks, failures, output])
	get_tree().quit(0 if failures == 0 else 1)
