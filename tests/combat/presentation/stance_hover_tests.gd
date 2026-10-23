extends "res://tests/combat/cards/noren_cards_visual.gd"
## Viewport input only; no desktop windows, pointer warps or player saves.

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://stance_hover_unused.json"
	Game.meta_path = "user://stance_hover_meta_unused.json"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	for form in ["melee","ranged"]:
		await install_hand([2,1],form)
		var view = app.view
		view.update_target_rects()
		var hover = view.player_hover
		var before: Dictionary = view.model.snapshot()
		check(hover.visible and hover.stance == form,"Character hover follows current stance: "+form)
		check(hover.mouse_filter == Control.MOUSE_FILTER_PASS and hover.focus_mode == Control.FOCUS_NONE,"Inspection region passes events and cannot take keyboard focus")
		var motion := InputEventMouseMotion.new()
		motion.position = hover.get_global_rect().get_center()
		motion.global_position = motion.position
		get_viewport().push_input(motion,true)
		await get_tree().process_frame
		await get_tree().process_frame
		if get_viewport().gui_get_hovered_control() != hover:
			print("HOVER DIAGNOSTIC: ", {"event":motion.position,"pointer":view.get_global_mouse_position(),"rect":hover.get_global_rect(),"hover":get_viewport().gui_get_hovered_control(),"transform":get_viewport().get_final_transform()})
		check(get_viewport().gui_get_hovered_control() == hover,"Viewport hover reaches the character inspection region")
		var tip: Control = hover._make_custom_tooltip(hover.tooltip_text)
		add_child(tip)
		var text := ""
		for line in tip.find_children("*","Label",true,false): text += line.text+"\n"
		check(text.contains("每实际打出一段攻击恢复 1 发弹药") and text.contains("抽 2 张牌"),"Tooltip explains both melee mechanics")
		check(text.contains("消耗 1 发弹药") and text.contains("1.5 倍") and text.contains("能量费用 -1"),"Tooltip explains ranged spending, damage and stance reward")
		check(hover.tooltip_data.value == ("近战" if form == "melee" else "远程"),"Tooltip highlights the current stance")
		tip.queue_free()
		var old_rect: Rect2 = hover.get_global_rect()
		view.stage.player.position.x += 40
		view.stage.zoom = 1.1
		view.stage._update_camera()
		view.update_target_rects()
		var expected: Rect2 = (view.stage.player.get_global_transform() * view.stage.player.target_bounds).intersection(view.stage.get_global_rect())
		check(hover.get_global_rect().is_equal_approx(expected) and not hover.get_global_rect().is_equal_approx(old_rect),"Hover region follows movement and camera zoom")
		view.select_card("card_000",false)
		view.update_target_rects()
		check(not hover.visible,"Selecting a card hides character inspection")
		view.cancel_selection()
		view.set_busy(true)
		view.update_target_rects()
		check(not hover.visible,"Busy combat hides inspection")
		view.set_busy(false)
		view.show_cyberware()
		view.update_target_rects()
		check(not hover.visible,"Modal panels suppress character inspection")
		view.close_pile()
		view.update_target_rects()
		check(hover.visible,"Closing a panel restores character inspection")
		check(view.model.snapshot() == before,"Inspection and its bounds do not mutate combat")
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("STANCE HOVER: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
