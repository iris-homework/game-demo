extends "res://tests/interaction_visual.gd"

func verify(ok: bool, message: String) -> void:
	print("CHECK: ", message)
	super.verify(ok, message)

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame

func check_hand_views(view, message: String) -> void:
	verify(view.cards.size() == view.model.hand.size(), message + ": visible card count matches hand")
	for uid in view.model.hand:
		verify(view.cards.has(uid) and is_instance_valid(view.cards.get(uid)) and view.cards[uid].visible, message + ": live view for " + str(uid))

func check_committed(view, before: Dictionary, message: String) -> void:
	verify(view.model.snapshot() == before and Game.state.combat == before, message + ": presentation never repeats model effects")
	check_hand_views(view, message)

func open_technology(view) -> void:
	await click(view.cyberware_button.get_rect().get_center())
	verify(is_instance_valid(view.pile_overlay), "Technology button opens overlay")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://technology_effects_visual_checkpoint.json"
	Game.meta_path = "user://technology_effects_visual_meta.json"
	var requested_size := Vector2i(1280, 800)
	for arg in OS.get_cmdline_user_args():
		if arg == "--large": requested_size = Vector2i(1600, 1000)
	output = "res://artifacts/qa/technology-effects-2026-10-23/visual-%d/" % requested_size.x
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle(0.3)
	get_window().size = requested_size
	await settle(0.3)
	Game.start_training("B04")
	await idle()
	var view = app.view
	verify(view.cyberware_button.text.contains("3/3"), "HUD starts with three ready technologies")
	await open_technology(view)
	var overlay = view.pile_overlay
	verify(overlay.card_buttons.size() == 3, "Exactly three authored technologies are visible")
	for i in 3:
		var b: Button = overlay.card_buttons[i]
		verify(b.tooltip_text.contains(["异次元口袋", "加速时钟", "后备能源"][i]), "Configured name and order: %d" % i)
		verify(b.tooltip_text.contains("冷却 %d 回合" % [3,999,3][i]), "Tooltip shows authored cooldown: %d" % i)
		verify(Rect2(64,34,1312,828).encloses(b.get_global_rect()), "Whole technology card stays inside panel")
		for child in b.get_children():
			if child is Label: verify(Rect2(Vector2.ZERO,b.size).encloses(child.get_rect()), "Card label bounds: " + child.text)
	var before: Dictionary = view.model.snapshot()
	await key(KEY_4)
	verify(view.model.snapshot() == before, "Unassigned fourth shortcut does nothing")
	await shot("01-three-technologies")
	await click(overlay.card_buttons[2].get_global_rect().get_center())
	var committed: Dictionary = view.model.snapshot()
	await idle()
	verify(not is_instance_valid(view.pile_overlay) and view.model.energy == 4, "Clicking backup energy closes overlay and restores one energy")
	verify(view.energy_value.text == "4 / 3" and view.energy_panel.is_overclocked(), "Energy HUD shows 4 / 3 overclocked state")
	check_committed(view, committed, "Energy activation")
	await shot("02-backup-energy")
	await open_technology(view)
	await key(KEY_1)
	committed = view.model.snapshot()
	view.end_turn_pressed()
	view.show_cyberware()
	verify(view.model.snapshot() == committed and not is_instance_valid(view.pile_overlay), "Stance animation blocks turn end and reopening")
	await idle()
	verify(view.model.stance == "ranged" and view.stage.player.combat_stance == "ranged", "Pocket synchronizes ranged model and actor")
	check_committed(view, committed, "Ranged pocket")
	await open_technology(view)
	var old_hand: Array = view.model.hand.duplicate()
	var old_views: Array = view.cards.values().duplicate()
	await key(KEY_2)
	committed = view.model.snapshot()
	await idle()
	verify(view.model.hand.size() == old_hand.size() and view.model.discard_pile == old_hand, "Clock swaps the entire displayed hand at equal count")
	for card in old_views: verify(not is_instance_valid(card) or not card.visible, "Old hand card is retired after clock")
	check_committed(view, committed, "Clock activation")
	verify(view.cyberware_button.text.contains("0/3"), "HUD shows all three cooling")
	await open_technology(view)
	for i in 3:
		verify(view.pile_overlay.card_buttons[i].disabled, "Cooling card is disabled: %d" % i)
		verify(view.pile_overlay.state_labels[i].text.contains(str([3,999,3][i])), "Remaining cooldown is visible: %d" % i)
	before = view.model.snapshot()
	await key(KEY_1)
	await key(KEY_2)
	await key(KEY_3)
	verify(view.model.snapshot() == before, "All cooling keyboard shortcuts are inert")
	await shot("03-all-cooling")
	await key(KEY_ESCAPE)
	for index in 3:
		print("TECHNOLOGY VISUAL: end turn ", index + 1)
		view.end_turn_pressed()
		await idle()
	verify(view.model.turn == 4 and view.cyberware_button.text.contains("2/3"), "Turn four releases pocket and energy while clock remains cooling")
	await open_technology(view)
	verify(view.pile_overlay.state_labels[1].text.contains("996"), "Long cooldown correctly ticks to 996")
	var hand_count: int = view.model.hand.size()
	await key(KEY_1)
	committed = view.model.snapshot()
	await idle()
	verify(view.model.stance == "melee" and view.stage.player.combat_stance == "melee", "Second pocket switches back to melee")
	verify(view.model.hand.size() == hand_count + 2, "Melee switch draws two extra cards")
	check_committed(view, committed, "Melee pocket draw")
	await shot("04-pocket-melee-draw")
	# Force recycling so the clock redraws the same UIDs; old views must be retired.
	Game.menu()
	await idle()
	Game.start_training("B04")
	await idle()
	view = app.view
	view.model.draw_cards(100)
	view.commit()
	await view.deal_hand(true)
	view.arrange_hand()
	view.refresh_counts()
	await open_technology(view)
	old_hand = view.model.hand.duplicate()
	old_views = view.cards.values().duplicate()
	await key(KEY_2)
	committed = view.model.snapshot()
	await idle()
	verify(view.model.hand.size() == old_hand.size() and view.model.discard_pile.is_empty(), "Clock recycles all ten discarded cards when draw pile is empty")
	for card in old_views: verify(not is_instance_valid(card) or not card.visible, "Recycled UID old view is retired")
	check_committed(view, committed, "Recycled clock")
	await shot("05-clock-recycled-hand")
	print("TECHNOLOGY EFFECTS VISUAL: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
