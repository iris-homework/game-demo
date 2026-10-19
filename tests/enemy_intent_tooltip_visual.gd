extends "res://tests/enemy_intent_visual.gd"
## Native tooltip hover and synthetic card input, isolated from formal saves.
var mouse_buttons := 0

func pointer(position: Vector2, pressed: int = -1) -> void:
	var event: InputEventMouse
	if pressed < 0:
		event = InputEventMouseMotion.new()
	else:
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed == 1
		mouse_buttons = MOUSE_BUTTON_MASK_LEFT if pressed==1 else 0
	event.position = get_viewport().get_final_transform()*position
	event.global_position = event.position
	event.button_mask = mouse_buttons
	Input.warp_mouse(event.position)
	await get_tree().create_timer(0.1).timeout
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame

func tooltip_boxes() -> Array[Node]:
	return get_tree().root.find_children("EnemyIntentTooltip","PanelContainer",true,false)

func hover_tip(control: Control, name_text: String, expected: String) -> void:
	await pointer(control.get_global_rect().get_center())
	var start := Time.get_ticks_msec()
	while tooltip_boxes().is_empty() and Time.get_ticks_msec()-start < 2500:
		await get_tree().process_frame
	var boxes := tooltip_boxes()
	var hovered := get_viewport().gui_get_hovered_control()
	print("HOVER ",name_text," focused=",DisplayServer.window_is_focused()," pointer=",app.view.get_global_mouse_position()," requested=",control.get_global_rect().get_center()," hovered=",hovered.get_path() if hovered else NodePath()," tooltip=",not boxes.is_empty())
	check(not boxes.is_empty(),"Real hover creates "+name_text+" tooltip")
	if not boxes.is_empty():
		var box := boxes[0] as Control
		var labels: PackedStringArray = []
		for label in box.find_children("*","Label",true,false): labels.append(label.text)
		check("|".join(labels).contains(expected),name_text+" contains full intent detail")
		check(box.size.x < 360 and box.size.y < 700,name_text+" remains a compact readable card")
	await shot(name_text)
	await pointer(Vector2(600,110))
	await get_tree().create_timer(0.15).timeout
	check(tooltip_boxes().is_empty(),"Tooltip disappears on pointer exit")

func _ready() -> void:
	get_tree().create_timer(55).timeout.connect(func():
		push_error("Intent tooltip QA timed out")
		get_tree().quit(2))
	Game.save_enabled = false
	Game.save_path = "user://intent_tooltip_visual_unused.json"
	Game.meta_path = "user://intent_tooltip_visual_meta_unused.json"
	output = "res://artifacts/qa/enemy-intent-tooltip-2026-10-20/hover/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	DisplayServer.window_move_to_foreground()
	await get_tree().create_timer(0.3).timeout
	var view = app.view
	var snapshot: Dictionary = view.model.snapshot().duplicate(true)
	await hover_tip(view.enemy_intents[2],"01-strength-icon","攻击 8 → 易伤 2 → 攻击 6")
	check(view.model.snapshot() == snapshot,"Hovering does not change battle state")
	check(view.targets[2].tooltip_data == view.enemy_intents[2].tooltip_data,"Enemy and icon share the same complete tooltip")
	# Make the primary attack preview a five-hit action without committing fixture state.
	view.model.enemies[0].intent = {"type":"attack","amount":4,"hits":5}
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.refresh_enemy_hud()
	view.update_target_rects()
	await hover_tip(view.enemy_intents[0],"02-multihit-icon","预计合计 20 点")
	# Existing helper installs valid attack instances. Exercise real mouse-event paths.
	await install_hand([1,1])
	view = app.view
	var uid: String = view.model.hand[0]
	view.select_card(uid)
	var before: Dictionary = view.model.snapshot().duplicate(true)
	await hover_tip(view.enemy_intents[0],"03-selected-card-hover","将对你造成 2 次伤害")
	check(view.selected_uid == uid and view.model.snapshot() == before,"Reading intent preserves selected card and resources")
	var target_point: Vector2 = view.targets[0].get_global_rect().get_center()
	await pointer(target_point,1)
	await pointer(target_point,0)
	await idle()
	check(not view.model.hand.has(uid) and view.model.enemies[0].hp == 114,"Clicking enemy after tooltip still plays attack exactly once")
	uid = view.model.hand[0]
	target_point = view.targets[0].get_global_rect().get_center()
	await pointer(view.cards[uid].home+Vector2(90,100),1)
	await pointer(view.enemy_intents[0].get_global_rect().get_center())
	check(view.held_card_uid == uid,"Dragging over intent does not lose held card")
	await pointer(target_point)
	await pointer(target_point,0)
	await idle()
	check(not view.model.hand.has(uid) and view.model.enemies[0].hp == 108,"Drag across intent and release on enemy plays once")
	view = app.view
	# A target-only tooltip uses the same custom card even away from the icon.
	await hover_tip(view.targets[2],"04-enemy-body","伤害预览")
	# Pollution includes both its active effect and the fish's passive effects.
	view.shown_enemies[0].intent = {"type":"pollution","amount":3}
	view.shown_enemies[0].attackPollution = 2
	view.shown_enemies[0].deathPollution = 3
	view.refresh_enemy_hud()
	view.update_target_rects()
	await hover_tip(view.enemy_intents[0],"05-pollution","死亡时，对你施加 3 层污染")
	view.shown_enemies[0].intent = {"type":"vulnerable","amount":2}
	view.refresh_enemy_hud()
	view.update_target_rects()
	await hover_tip(view.enemy_intents[0],"06-vulnerable","受到的攻击伤害增加 50%")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false,"syntheticPointerInput":true},"\t"))
	print("INTENT TOOLTIP VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
