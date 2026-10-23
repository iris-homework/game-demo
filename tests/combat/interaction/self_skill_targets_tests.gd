extends "res://tests/combat/cards/noren_cards_visual.gd"
## Headless view checks; never warps the system pointer or writes a player save.

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://self_skill_targets_unused.json"
	Game.meta_path = "user://self_skill_targets_meta_unused.json"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.start_training("B04")
	await idle()
	for form in ["melee", "ranged"]:
		await install_hand([2,23,11,34,1], form)
		var view = app.view
		var before: Dictionary = view.model.snapshot()
		for index in 5:
			var uid := "card_%03d" % index
			view.select_card(uid, false)
			var self_target: bool = view.model.card_target(uid) == "self"
			check(view.selected_uid == uid, "%s %s is selectable" % [form,uid])
			for target in view.targets:
				check(target.get("brackets_enabled") == not self_target and target.armed == not self_target,
					"%s %s configures all enemy brackets for its effective target" % [form,uid])
				check(not target.tooltip_data.is_empty() and not target.disabled,
					"Enemy inspection and hit area remain available")
			# Deliver hover through the viewport, without moving the desktop pointer.
			var motion := InputEventMouseMotion.new()
			motion.position = view.targets[0].get_global_rect().get_center()
			motion.global_position = motion.position
			get_viewport().push_input(motion, true)
			await get_tree().process_frame
			if not view.targets[0].is_hovered():
				print("HOVER DIAGNOSTIC: ", {"event":motion.position,"pointer":view.get_global_mouse_position(),"rect":view.targets[0].get_global_rect(),"hover":get_viewport().gui_get_hovered_control()})
			check(view.targets[0].is_hovered(), "Viewport hover reaches enemy while holding %s" % uid)
			check(view.aim.visible == not self_target, "Enemy aim matches effective target")
			check(view.model.snapshot() == before, "Selection and hover do not alter combat")
			view.cancel_selection()
			check(view.targets.all(func(target): return target.get("brackets_enabled") == true and not target.armed),
				"Cancel restores ordinary enemy hover without arming targets")
	app.queue_free()
	await get_tree().process_frame
	print("SELF SKILL TARGETS: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
