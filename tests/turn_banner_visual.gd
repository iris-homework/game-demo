extends "res://tests/interaction_visual.gd"
## Real viewport coverage for phase order, input isolation and restore behavior.
var announcements: Array[String] = []
var last_banner_id := 0
var record := false
var recorded_frame := 0
var frame_folder := ""

func _process(_delta: float) -> void:
	if not is_instance_valid(app) or app.shown_page != "battle": return
	var banner = app.view.turn_banner
	if is_instance_valid(banner) and banner.get_instance_id() != last_banner_id:
		last_banner_id = banner.get_instance_id()
		announcements.append(banner.title)

func capture_frame() -> void:
	if not record: return
	if recorded_frame % 2 == 0:
		var img := get_viewport().get_texture().get_image()
		img.resize(960,600,Image.INTERPOLATE_LANCZOS)
		img.save_png(frame_folder.path_join("%04d.png" % recorded_frame))
	recorded_frame += 1

func wait_banner(text: String) -> void:
	var started := Time.get_ticks_msec()
	while true:
		if app.shown_page == "battle" and is_instance_valid(app.view.turn_banner) and app.view.turn_banner.title == text: return
		if Time.get_ticks_msec()-started > 6000:
			push_error("Missing announcement: "+text)
			get_tree().quit(1)
			return
		await get_tree().process_frame

func contains_day_strip(node: Node) -> bool:
	if node is Label and (node.text == "第 1 天" or node.text.contains("W E E K")): return true
	for child in node.get_children():
		if contains_day_strip(child): return true
	return false

func _ready() -> void:
	Game.save_enabled = false
	output = OS.get_temp_dir().path_join("midnight_turn_%d_" % DisplayServer.window_get_size().x)
	frame_folder = output+"frames"
	record = OS.get_cmdline_user_args().has("--record")
	if record:
		DirAccess.make_dir_recursive_absolute(frame_folder)
		RenderingServer.frame_post_draw.connect(capture_frame)
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await motion(Vector2(720,270))
	Game.start_training("B12")
	await wait_banner("第1回合")
	var view = app.view
	verify(Game.battle_busy and not view.initialized,"Opening announcement locks battle before the first deal")
	verify(not contains_day_strip(view),"Battle hides seven-day strip and week caption")
	await click(Vector2(1280,647))
	view.show_cyberware()
	view.show_pile("抽牌堆",view.model.draw_pile)
	view.finish("surrender")
	Game.menu()
	verify(view.model.turn == 1 and view.model.hand.is_empty() and Game.page == "battle" and not is_instance_valid(view.pile_overlay),"Opening overlay blocks turn, modal and navigation actions")
	while view.turn_banner.reveal < 0.5: await get_tree().process_frame
	await shot("first_rise")
	while view.turn_banner.reveal < 1.0: await get_tree().process_frame
	await shot("first_full")
	while view.turn_banner.erase < 0.5: await get_tree().process_frame
	await shot("first_erase")
	await idle()
	verify(view.cards.size() == 5 and view.model.turn == 1 and not is_instance_valid(view.turn_banner),"Round one hands control back after dealing")
	var day: int = Game.state.currentDay
	var departing: Array = view.cards.values()
	var first_position: Vector2 = departing[0].position
	view.end_turn_pressed()
	await wait_banner("敌方回合")
	verify(Game.battle_busy and view.model.turn == 1 and view.model.player_hp == 100,"Enemy announcement precedes damage and turn advance")
	verify(view.cards.is_empty() and view.model.hand.size() == 5,"Hand visuals detach immediately without resolving the model early")
	view.end_turn_pressed()
	view.select_card(view.model.hand[0])
	verify(view.selected_uid.is_empty() and view.model.player_hp == 100,"Repeated end turn and card selection cannot bypass announcement")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	verify(Game.page == "battle","Escape cannot interrupt turn announcement")
	await settle(0.14)
	verify(is_instance_valid(departing[0]) and departing[0].position.distance_to(first_position) > 10.0 and is_instance_valid(view.turn_banner),"Unused cards fly during the enemy announcement")
	await shot("enemy_discard")
	while view.turn_banner.reveal < 1.0: await get_tree().process_frame
	await shot("enemy_full")
	await wait_banner("第2回合")
	verify(view.model.turn == 2 and view.model.player_hp == 99 and Game.battle_busy,"Round two follows exactly one enemy damage resolution")
	while view.turn_banner.reveal < 1.0: await get_tree().process_frame
	await shot("second_full")
	await idle()
	await shot("second_ready")
	record = false
	verify(view.cards.size() == 5 and Game.state.currentDay == day,"Round changes preserve adventure date and restore hand")
	view.end_turn_pressed()
	await wait_banner("第3回合")
	await idle()
	verify(view.model.turn == 3 and view.model.player_hp == 98,"Later round numbers increment normally")
	verify(announcements == ["第1回合","敌方回合","第2回合","敌方回合","第3回合"],"Opening and subsequent announcement order is exact")
	# Rebuild from the existing battle snapshot: this is not a new player turn.
	app.swap_view()
	await idle()
	view = app.view
	verify(view.model.turn == 3 and view.cards.size() == 5 and announcements.size() == 5,"Restoring existing hand does not replay a turn or draw extra cards")
	view.model.player_hp = 1
	view.commit()
	view.end_turn_pressed()
	await idle()
	verify(Game.page == "menu" and announcements.size() == 6 and announcements.back() == "敌方回合","Lethal enemy turn exits without announcing another player round")
	verify(not Game.battle_busy and not Game.transition_locked,"Battle exit releases input locks")
	Game.new_game()
	Game.go_map()
	await get_tree().process_frame
	verify(contains_day_strip(app.view),"Nonbattle map retains day strip")
	await shot("map_days")
	print("TURN BANNER VISUAL: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
