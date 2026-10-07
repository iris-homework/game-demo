extends Node

var app: Control
var checks := 0
var failures := 0
var output_dir := ""
var capture_only := false
var input_records: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	input_records.append({"check":message, "passed":ok, "page":Game.page,
		"activeEvent":Game.state.get("activeEventId", ""), "place":Game.state.get("currentPlaceId", "")})
	if not ok:
		failures += 1
		push_error("MAP VISUAL: " + message)

func settle(seconds: float = 0.22) -> void:
	await get_tree().create_timer(seconds).timeout

func wait_unlocked() -> void:
	var frames := 0
	while (Game.transition_locked or Game.battle_busy) and frames < 100:
		frames += 1
		await settle(0.1)
	check(not Game.transition_locked and not Game.battle_busy, "scene transition and battle animations release input")

func stage() -> void:
	Game.transition_locked = false
	Game.battle_busy = false
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.state.completedEventIds = ["E01"]
	Game.state.targetId = "richard"
	Game.state.credits = 300
	Game.page = "map"
	Game.changed.emit()
	await settle()

func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_viewport().get_final_transform() * point
	event.global_position = event.position
	Input.warp_mouse(event.position)
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame

func click(point: Vector2) -> void:
	await motion(point)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = get_viewport().get_final_transform() * point
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle(0.08)

func press_escape() -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle(0.08)

func button_center(node: Control) -> Vector2:
	return node.get_global_rect().get_center()

func map_button(name_text: String) -> Control:
	return app.view.find_child(name_text, true, false) as Control

func text_button(fragment: String) -> Button:
	for node in app.view.find_children("*", "Button", true, false):
		if fragment in node.text:
			return node
	return null

func play_dialogue(choice: int = 0) -> void:
	var guard := 0
	while Game.page == "dialogue" and guard < 50:
		guard += 1
		app.view.text_label.visible_characters = -1
		if not app.view.choice_buttons.is_empty():
			await click(button_center(app.view.choice_buttons[choice]))
		elif is_instance_valid(app.view.advance_button):
			await click(button_center(app.view.advance_button))
		else:
			break
	check(guard < 50, "actual dialogue input terminates")

func shot(name_text: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output_dir.path_join(name_text + ".png")
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK: push_error("Screenshot write failed: " + path)

func card_inside(card: Control) -> bool:
	var area := get_viewport().get_visible_rect()
	var bounds := card.get_global_rect()
	return area.encloses(bounds) and bounds.position.y >= 60

func header_labels_inside(card: Control) -> bool:
	var area := card.get_global_rect().grow(1.0)
	for child in card.get_children():
		if child is Label and not area.encloses(child.get_global_rect()):
			return false
	return true

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--output-dir" and i + 1 < args.size(): output_dir = args[i + 1]
		if args[i] == "--capture-only": capture_only = true
	if output_dir.is_empty(): output_dir = OS.get_temp_dir().path_join("midnight_map_visual")
	DirAccess.make_dir_recursive_absolute(output_dir)
	Game.save_enabled = false
	Game.save_path = output_dir.path_join("test-checkpoint.json")
	Game.meta_path = output_dir.path_join("test-meta.json")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await stage()
	await motion(Vector2(18,88))
	await settle()
	await shot("01-overview")
	var environment := FileAccess.open(output_dir.path_join("environment.json"), FileAccess.WRITE)
	if environment != null:
		environment.store_string(JSON.stringify({"window":str(DisplayServer.window_get_size()),
			"logicalViewport":str(get_viewport().get_visible_rect().size),
			"reportedViewportTextureSize":str(get_viewport().get_texture().get_size()),
			"captureSize":str(get_viewport().get_texture().get_image().get_size()),
			"renderer":ProjectSettings.get_setting("rendering/renderer/rendering_method")}, "\t"))
	if capture_only:
		app.view._show_preview("hive")
		await settle()
		check(card_inside(app.view.preview) and header_labels_inside(app.view.preview), "captured preview text stays inside card")
		check(app.view.preview.get_node("place_description").get_line_count() > 1, "captured Chinese introduction wraps into multiple lines")
		check(app.view.preview.get_node("place_description").get_visible_line_count() == app.view.preview.get_node("place_description").get_line_count(), "captured short introduction shows every wrapped line")
		var description_label: Label = app.view.preview.get_node("place_description")
		print("PREVIEW TEXT: size=%s lineHeight=%s lines=%s visible=%s" % [description_label.size, description_label.get_line_height(), description_label.get_line_count(), description_label.get_visible_line_count()])
		await shot("00-hover-preview")
		app.view._hide_preview()
		app.view.select_place("hive")
		await settle()
		check(card_inside(app.view.detail) and header_labels_inside(app.view.detail), "captured fixed header stays inside card")
		check(app.view.detail.get_node("detail_scroll").get_global_rect().grow(1.0).encloses(map_button("event_E03").get_global_rect()), "captured single-task action is fully visible without scrolling")
		await shot("02-task-detail")
		app.view.close_detail()
		Game.state.currentPlaceId = "hive"
		Game.changed.emit()
		await settle()
		await shot("03-current-target")
		Game.state.faction = "company"
		Game.state.completedEventIds = ["E01", "E03", "E04", "E05A", "E06"]
		Game.state.flags = {"alleyClue":true, "portClue":true}
		Game.changed.emit()
		await settle()
		await shot("04-company")
		Game.state.faction = "resistance"
		Game.state.targetId = "lumina"
		Game.state.completedEventIds = ["E01", "E03", "E04", "E05B", "E07"]
		Game.changed.emit()
		await settle()
		await shot("05-resistance")
		if failures == 0: print("MAP CAPTURE OK: %d checks; %s" % [checks, output_dir])
		get_tree().quit(0 if failures == 0 else 1)
		return
	check(app.view.markers.size() == 16, "16 actual marker controls")
	check(not is_instance_valid(app.view.detail), "overview starts without fixed card")
	var avatar: Control = app.view.markers.bar.get("_avatar_root")
	await click(button_center(avatar))
	check(app.view.selected_id == "bar", "current portrait shares location hit area")
	app.view.close_detail()
	var badges: Array = app.view.markers.hive.get("_badges")
	await click(button_center(badges[0]))
	check(app.view.selected_id == "hive", "task badge shares location hit area")
	app.view.close_detail()
	await motion(Vector2(18,88))
	await settle()
	var start_place: String = Game.state.currentPlaceId
	await motion(app.view.get_marker_center("hive"))
	await settle(0.08)
	# 两个渲染帧可能已经超过 0.2s；按实际创建时间验证延迟，避免把慢帧误判为即时显示。
	check(not is_instance_valid(app.view.preview) or float(app.view.preview.get_meta("hover_delay_seconds", 0.0)) >= 0.2, "hover preview respects actual 0.2s delay")
	await settle(0.25)
	check(is_instance_valid(app.view.preview), "real pointer hover opens read-only preview")
	if is_instance_valid(app.view.preview):
		check(float(app.view.preview.get_meta("hover_delay_seconds", 0.0)) >= 0.2, "shown preview records full hover delay")
		check(header_labels_inside(app.view.preview), "preview title description and task text stay inside card")
		check(app.view.preview.get_node("place_description").get_line_count() > 1, "Chinese introduction wraps rather than truncating one line")
		check(app.view.preview.get_node("place_description").get_visible_line_count() == app.view.preview.get_node("place_description").get_line_count(), "short introduction shows all wrapped lines")
	check(Game.state.currentPlaceId == start_place, "hover preserves current place")
	await shot("06-hover-task")
	await motion(Vector2(18,88))
	await settle(0.1)
	check(not is_instance_valid(app.view.preview), "moving away removes preview")
	await click(app.view.get_marker_center("hive"))
	check(app.view.selected_id == "hive" and is_instance_valid(app.view.detail), "real marker click fixes task detail")
	check(not is_instance_valid(app.view.preview), "fixed detail removes preview")
	var rect_before: Rect2 = app.view.map_rect
	if is_instance_valid(app.view.detail):
		check(card_inside(app.view.detail), "task detail stays inside map window")
		check(header_labels_inside(app.view.detail), "fixed card title and status text stay inside card")
		check(app.view.detail.get_node("detail_scroll").get_global_rect().grow(1.0).encloses(map_button("event_E03").get_global_rect()), "single-task action is fully visible without scrolling")
		var card_pos: Vector2 = app.view.detail.position
		await motion(app.view.detail.get_global_rect().get_center())
		await settle(1.0)
		check(is_instance_valid(app.view.detail) and app.view.detail.position == card_pos, "pointer entering fixed card does not hide or move it")
	await motion(app.view.get_marker_center("bar"))
	await settle(0.3)
	check(app.view.selected_id == "hive" and not is_instance_valid(app.view.preview), "hover B preserves fixed A and suppresses second preview")
	await click(app.view.get_marker_center("bar"))
	check(app.view.selected_id == "bar", "click B replaces fixed A")
	check(app.view.map_rect == rect_before, "detail replacement does not move map")
	check(Game.state.currentPlaceId == start_place, "selection preserves actual current place")
	await click(button_center(text_button("周次")))
	await settle()
	check(is_instance_valid(app.view.find_child("week_dialog", true, false)), "actual HUD click opens week modal")
	await press_escape()
	check(Game.page == "map" and is_instance_valid(app.view.detail), "Escape closes week modal before fixed detail")
	await press_escape()
	check(Game.page == "map" and not is_instance_valid(app.view.detail), "Escape closes map detail before menu navigation")
	await click(app.view.get_marker_center("hive"))
	await click(app.view.map_rect.position + Vector2(20,app.view.map_rect.size.y - 20))
	check(not is_instance_valid(app.view.detail) and Game.page == "map", "blank click closes card without entering place")
	# Every physical marker must remain individually reachable.
	for p in Game.places:
		app.view.close_detail()
		await click(app.view.get_marker_center(p.id))
		check(app.view.selected_id == p.id, "actual hit area individually selects " + p.id)
		if is_instance_valid(app.view.detail): check(card_inside(app.view.detail), "edge card stays inside " + p.id)
	app.view.close_detail()
	await click(app.view.get_marker_center("market"))
	await click(button_center(map_button("enter_place")))
	check(Game.page == "place" and Game.state.currentPlaceId == "market", "edge card enter button stays reachable")
	Game.go_map()
	await settle()
	start_place = Game.state.currentPlaceId
	await click(app.view.get_marker_center("tower"))
	check(map_button("enter_place") == null, "locked location has no enter action")
	check(Game.page == "map" and Game.state.currentPlaceId == start_place, "locked click preserves state")
	await shot("07-locked-detail")
	app.view.close_detail()
	await click(app.view.get_marker_center("hospital"))
	check(map_button("enter_place") != null and map_button("heal_place") != null, "open no-event hospital retains enter and service")
	Game.state.currentHp = 50
	var heal := map_button("heal_place")
	if heal != null:
		await click(button_center(heal))
		check(Game.state.currentHp == 80, "one real heal click resolves once")
		check(Game.state.currentPlaceId == start_place, "heal does not move current avatar")
		check(app.view.selected_id == "hospital" and is_instance_valid(app.view.detail), "heal-triggered rebuild restores selected hospital")
		await shot("08-heal-detail")
		var enter := map_button("enter_place")
		if enter != null:
			await click(button_center(enter))
			check(Game.page == "place" and Game.state.currentPlaceId == "hospital", "explicit enter updates place")
			Game.go_map()
			await settle()
			check(not is_instance_valid(app.view.detail), "returning from location starts with clean overview")
			check(Game.map_place_state("hospital").current, "returned avatar reflects actual visited hospital")
	app.view.close_detail()
	Game.state.currentHp = 50
	await click(app.view.get_marker_center("clinic"))
	await click(button_center(map_button("heal_place")))
	check(Game.state.currentHp == 80 and Game.state.currentPlaceId == "hospital", "clinic heal resolves once without moving avatar")
	check(app.view.selected_id == "clinic", "clinic heal rebuild preserves fixed card")
	await stage()
	await click(app.view.get_marker_center("hive"))
	var event_action := map_button("event_E03")
	check(event_action != null, "authored task action exists")
	if event_action != null:
		Game.battle_busy = true
		await click(button_center(event_action))
		check(Game.page == "map" and Game.state.activeEventId == "E01", "busy lock rejects map task action")
		Game.battle_busy = false
		await click(button_center(event_action))
		check(Game.page == "dialogue" and Game.state.activeEventId == "E03" and Game.state.currentPlaceId == "hive", "explicit event action starts correct event and updates current place")
	await stage()
	Game.state.currentPlaceId = "hive"
	Game.changed.emit()
	await settle()
	check(Game.map_place_state("hive").current and Game.map_place_state("hive").target, "same-place target and avatar state")
	await shot("09-current-target")
	# Long text/multiple events are isolated fixture copies, never saved to formal paths.
	var source_place: Dictionary = Game.place_data("bar")
	var old_description: String = source_place.description
	source_place.description = "藏在后巷的午夜酒馆。这里交换消息、接取委托，也有人静静等待城市入睡。".repeat(10)
	for i in range(8):
		var fixture: Dictionary = Game.events.E02.duplicate(true)
		fixture.id = "MAP_LIST_%02d" % i
		fixture.placeId = "bar"
		fixture.title = "用于检查长标题换行和任务列表滚动的事件 %d" % i
		fixture.description = "这是仅存在于测试内存的长任务说明，检查换行与排版。".repeat(4)
		Game.events[fixture.id] = fixture
	Game.changed.emit()
	await settle()
	await click(app.view.get_marker_center("bar"))
	check(map_button("event_MAP_LIST_07") != null, "all repeated fixture events retained in list")
	check(card_inside(app.view.detail), "long detail remains within window")
	await shot("10-long-list")
	var scroll := app.view.detail.find_child("event_scroll", true, false) as ScrollContainer
	if scroll == null: scroll = app.view.detail.find_child("detail_scroll", true, false) as ScrollContainer
	check(scroll != null, "long content uses a reachable scroll container")
	if scroll != null:
		await motion(scroll.get_global_rect().get_center())
		for i in range(12):
			var wheel := InputEventMouseButton.new()
			wheel.position = get_viewport().get_final_transform() * scroll.get_global_rect().get_center()
			wheel.global_position = wheel.position
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			Input.parse_input_event(wheel)
			await get_tree().process_frame
		await settle()
		check(scroll.scroll_vertical > 0, "real wheel scrolls long content")
		check(Game.state.currentPlaceId == "hive" and Game.page == "map", "wheel stays in detail and does not enter event")
		await shot("11-long-list-scrolled")
		for i in range(65):
			var wheel := InputEventMouseButton.new()
			wheel.position = get_viewport().get_final_transform() * scroll.get_global_rect().get_center()
			wheel.global_position = wheel.position
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			Input.parse_input_event(wheel)
			await get_tree().process_frame
		await settle()
		var last_action := map_button("event_MAP_LIST_07")
		check(last_action != null and scroll.get_global_rect().has_point(button_center(last_action)), "last event action is reachable after scrolling")
		await shot("11-final-list")
		if last_action != null and scroll.get_global_rect().has_point(button_center(last_action)):
			var event_revision := Game.revision
			await click(button_center(last_action))
			check(Game.page == "dialogue" and Game.state.activeEventId == "MAP_LIST_07", "real click starts exact last scrolled event")
			check(Game.revision == event_revision + 1, "last event click submits once")
			await shot("11-click-result")
	for i in range(8): Game.events.erase("MAP_LIST_%02d" % i)
	source_place.description = old_description
	await stage()
	var locked_fixture: Dictionary = Game.events.E02.duplicate(true)
	locked_fixture.id = "MAP_LOCKED_INPUT"
	locked_fixture.placeId = "tower"
	locked_fixture.unlockCondition = {}
	Game.events[locked_fixture.id] = locked_fixture
	Game.changed.emit()
	await settle()
	await click(app.view.get_marker_center("tower"))
	check(not Game.map_place_state("tower").target and map_button("event_MAP_LOCKED_INPUT") == null and map_button("enter_place") == null, "available event cannot expose locked place action")
	Game.events.erase(locked_fixture.id)
	await stage()
	await click(app.view.get_marker_center("hive"))
	await click(button_center(map_button("event_E03")))
	await play_dialogue()
	check(Game.page == "result" and "E03" in Game.state.completedEventIds, "real task and dialogue clicks complete E03")
	if Game.page == "result":
		await click(button_center(text_button("返回城市地图")))
	check(Game.page == "map" and Game.map_place_state("alley").target and not Game.map_place_state("hive").target, "result button rebuilds correct next target")
	await shot("13-target-advanced")
	check(Game.save_game() and Game.load_game(), "advanced target round-trips through isolated checkpoint")
	await settle()
	check(Game.page == "map" and Game.map_place_state("alley").target, "checkpoint restores advanced target")
	for outcome in ["lose", "surrender"]:
		await stage()
		await click(app.view.get_marker_center("hive"))
		await click(button_center(map_button("event_E03")))
		await play_dialogue(1)
		await wait_unlocked()
		check(Game.page == "battle", "real dialogue reaches battle for " + outcome)
		# Outcome submission exercises Game's real return route; combat is tested separately.
		check(Game.battle_exit(outcome, Game.revision), "battle outcome submitted " + outcome)
		await wait_unlocked()
		await play_dialogue()
		check(Game.page == "map" and Game.map_place_state("hive").target and not "E03" in Game.state.completedEventIds, "real return choice preserves unfinished target " + outcome)
		check(Game.save_game() and Game.load_game(), "battle-return checkpoint round-trip " + outcome)
		await settle()
		check(Game.page == "map" and Game.map_place_state("hive").target, "battle-return reload keeps target " + outcome)
		await shot("14-return-" + outcome)
	await stage()
	Game.state.flags.week1Complete = true
	Game.state.completedEventIds = ["E01", "E03", "E04", "E05A", "E06", "E09", "E12"]
	Game.state.faction = "company"
	Game.changed.emit()
	await settle()
	check(Game.map_target_events().is_empty(), "completed week has no false target")
	check(Game.map_place_state("pump").available.size() > 0, "optional services and events survive main completion")
	await shot("12-week-complete")
	check(Game.save_game(), "map saves only to explicit test path")
	var stored: String = Game.state.currentPlaceId
	Game.state.currentPlaceId = "port"
	check(Game.load_game(), "test map reload succeeds")
	await settle()
	check(Game.state.currentPlaceId == stored and not is_instance_valid(app.view.detail), "read checkpoint restores avatar with clean detail state")
	var report := FileAccess.open(output_dir.path_join("checks.json"), FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"checks":checks,"failures":failures,"results":input_records}, "\t"))
	print("MAP VISUAL: %d checks, %d failures; %s" % [checks, failures, output_dir])
	get_tree().quit(0 if failures == 0 else 1)
