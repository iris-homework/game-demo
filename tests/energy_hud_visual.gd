extends "res://tests/noren_cards_visual.gd"

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://energy_hud_unused.json"
	Game.meta_path = "user://energy_hud_meta_unused.json"
	output = "res://artifacts/qa/energy-hud-2026-10-16/"
	var requested_size := Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg == "--large": requested_size = Vector2i(1600,1000)
	output += str(requested_size.x)+"-"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(0.4).timeout
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = requested_size
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().get_size() == requested_size,"Rendered size matches requested window")
	Game.start_training("B04")
	await idle()
	await install_hand([2,2,2,2,1])
	var view = app.view
	check(view.energy_panel.visible and view.energy_value.text == "3 / 3","Opening energy is full")
	check(not view.resources_label.text.contains("能量"),"Energy is shown only in its dedicated HUD")
	check(view.cyberware_button.get_rect().end.y < view.cyberware_status.position.y and view.cyberware_status.get_rect().end.y < view.energy_panel.position.y,"Technology and energy form separate vertical rows")
	check(view.energy_panel.get_rect().end.y < view.DRAW_POS.y,"Energy panel clears draw pile")
	await shot("full")
	# Exercise the moved button through viewport input, then return to battle.
	await pointer(view.cyberware_button.get_rect().get_center(),1)
	await pointer(view.cyberware_button.get_rect().get_center(),0)
	check(is_instance_valid(view.pile_overlay),"Moved technology button opens its panel")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(view.pile_overlay),"Technology panel closes normally")
	for i in 3:
		view.select_card("card_%03d" % i)
		view.play_selected(-1)
		await idle()
		check(view.model.energy == 2-i and view.energy_value.text == "%d / 3" % (2-i),"Energy HUD follows committed card spend")
		if i == 0: await shot("spent")
	await shot("empty")
	view.select_card("card_003")
	view.play_selected(-1)
	await idle()
	check(view.model.energy == 0 and view.model.hand.has("card_003"),"Rejected play preserves empty energy and card")
	view.end_turn_pressed()
	await idle()
	check(view.model.turn == 2 and view.energy_value.text == "3 / 3","Next turn refills visible energy")
	await shot("refilled")
	# Rebuild the view from an actual saved combat snapshot in memory.
	view.model.energy = 1
	view.commit()
	app.swap_view()
	await idle()
	view = app.view
	check(view.energy_value.text == "1 / 3","View reconstruction restores remaining energy")
	view.model.energy = 5
	view.refresh_resources()
	check(view.energy_value.text == "5 / 3","Bonus energy retains its exact displayed value")
	# Use a known legacy profile for compatibility, without committing it.
	view.model.profile = Game.prototype_rules.duplicate(true)
	view.refresh_resources()
	check(not view.energy_panel.visible,"Legacy combat does not show an unsupported energy display")
	print("ENERGY HUD: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
