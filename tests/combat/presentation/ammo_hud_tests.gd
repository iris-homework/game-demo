extends "res://tests/combat/cards/noren_cards_visual.gd"
## Headless checks only: no screenshots, window changes or physical pointer input.

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://ammo_hud_tests_unused.json"
	Game.meta_path = "user://ammo_hud_tests_meta_unused.json"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	await install_hand([1,1],"ranged")
	var view = app.view
	var hud = view.ammo_panel
	check(hud.get_rect().end.y < view.cyberware_button.position.y,"Ammo HUD sits above technology with a gap")
	check(view.resources_label.get_parent() == hud,"Old actor-following text has moved into the ammo HUD")
	check(view.resources_label.get_theme_color("font_color") == hud.ORANGE,"Ammo title uses orange text")
	check(not view.find_children("*","Label",true,false).any(func(line): return line.text == "战斗科技 / 点击查看"),"Technology helper text has been removed")
	check(hud.SLOT_COUNT == 10 and hud.COLUMNS == 5,"Ten bullet slots form two rows of five")
	check(hud.slot_origin(0).y == hud.slot_origin(4).y and hud.slot_origin(5).y == hud.slot_origin(9).y and hud.slot_origin(5).y > hud.slot_origin(4).y,"Slots wrap after the fifth bullet")
	var before: Dictionary = view.model.snapshot()
	for amount in range(11):
		view.shown_player_ammo = amount
		view.refresh_ammo()
		check(hud.filled_slot_count() == amount and view.resources_label.text == "弹药","Exactly %d bullets light up with no numeric counter" % amount)
	check(view.model.snapshot() == before,"Display updates never mutate combat or save state")
	view.refresh_resources()
	check(hud.mouse_filter == Control.MOUSE_FILTER_PASS and view.resources_label.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Ammo hover remains reachable through its label")
	check(hud.tooltip_text.contains("远程状态需要消耗弹药才能攻击") and hud.tooltip_text.contains("近战状态每段攻击恢复 1 发弹药"),"Tooltip includes both requested ammo rules")
	var tip: Control = hud._make_custom_tooltip(hud.tooltip_text)
	add_child(tip)
	await get_tree().process_frame
	var text := ""
	for line in tip.find_children("*","Label",true,false): text += line.text + "\n"
	check(text.contains("当前状态：远程") and text.contains("弹药不足") and text.contains("每段攻击恢复 1 发弹药"),"Detailed tooltip contains stance, spending, empty-ammo restriction and recovery")
	tip.queue_free()
	view.select_card("card_000")
	view.play_selected(0)
	await idle()
	check(view.model.ammo == 1 and hud.filled_slot_count() == 1,"Actual ranged attack spends and dims one bullet")
	view.model.ammo = 0
	view.refresh_resources()
	before = view.model.snapshot()
	view.select_card("card_001")
	view.play_selected(0)
	await idle()
	check(view.model.snapshot() == before and hud.filled_slot_count() == 0,"Empty-ammo attack is rejected without changing state")
	view.model.stance = "melee"
	view.refresh_resources()
	view.select_card("card_001")
	view.play_selected(0)
	await idle()
	check(view.model.ammo == 1 and hud.filled_slot_count() == 1,"Actual melee hit restores and lights one bullet")
	view.model.profile.ammoCap = 6
	view.model.ammo = 6
	view.refresh_resources()
	check(hud.filled_slot_count() == 6 and hud.capacity == 6 and hud.tooltip_text.contains("6 / 6") and view.resources_label.text == "弹药","Old capacity remains accurate in hover details and slots, with no title counter")
	view.model.profile = Game.prototype_rules.duplicate(true)
	view.refresh_resources()
	check(not hud.visible,"Legacy non-ammo combat hides the new HUD")
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("AMMO HUD: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
