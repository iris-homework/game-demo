extends Node
var app: Control
var checks := 0
var failures := 0
var output := "res://artifacts/qa/dialogue-middle-click-2026-10-16/"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func click(point: Vector2, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = which
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func capture(title: String) -> void:
	await get_tree().create_timer(0.25).timeout
	app.view.text_label.visible_characters = -1
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	check(img.save_png(output + title + "-%dx%d.png" % [img.get_width(),img.get_height()]) == OK, "Capture " + title)

func _ready() -> void:
	DisplayServer.window_set_title("对白 UI 验证（自动关闭）")
	get_tree().create_timer(30).timeout.connect(func(): get_tree().quit(1))
	Game.save_enabled = false
	Game.save_path = output + "checkpoint.json"
	Game.meta_path = output + "meta.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.new_game()
	await capture("opening")
	check(app.view.find_children("*", "Button", true, false).size() == 3, "Opening has menu, history and skip buttons")
	var footer_absent := true
	for item in app.view.find_children("*", "Label", true, false):
		if item.position.y >= 850: footer_absent = false
	check(footer_absent, "Dialogue footer labels are removed")
	# Each distinct part of the middle and bottom surface must advance exactly once per click.
	for point in [Vector2(720,450), Vector2(120,350), Vector2(700,700), Vector2(120,690), Vector2(1380,795), Vector2(720,875)]:
		Game.new_game()
		await get_tree().process_frame
		var revision: int = Game.revision
		var next_id: String = Game.node_data().next
		app.view.elapsed = 0.0
		app.view.text_label.visible_characters = 0
		await click(point)
		check(Game.revision == revision and app.view.text_label.visible_characters == -1, "First click reveals text at " + str(point))
		await click(point)
		check(Game.revision == revision + 1 and Game.state.activeNodeId == next_id, "Second click advances once at " + str(point))
	Game.new_game()
	app.view.text_label.visible_characters = -1
	var revision: int = Game.revision
	await click(Vector2(720,700), MOUSE_BUTTON_RIGHT)
	await click(Vector2(720,120))
	check(Game.revision == revision, "Right click and area above the middle do not advance")
	app.toggle_debug()
	await get_tree().process_frame
	await click(Vector2(720,800))
	await click(Vector2(120,350))
	check(Game.revision == revision, "Debug overlay blocks middle and bottom clicks")
	app.toggle_debug()
	await get_tree().process_frame
	await key(KEY_SPACE)
	check(Game.revision == revision + 1, "Space still advances")
	Game.new_game()
	app.view.text_label.visible_characters = -1
	revision = Game.revision
	await key(KEY_ENTER)
	check(Game.revision == revision + 1, "Enter still advances")
	Game.new_game()
	Game.skip_dialogue(Game.revision)
	await capture("choice")
	var before: Dictionary = Game.state.duplicate(true)
	await click(Vector2(720,700))
	await click(Vector2(720,450))
	check(Game.state == before, "Middle gap and bottom clicks never bypass a choice")
	await click(app.view.choice_buttons[0].get_global_rect().get_center())
	check(Game.state != before and Game.state.targetId == "richard", "Choice click still selects the intended branch")
	Game.state.completedEventIds = ["E01"]
	Game.visit("hive")
	Game.start_event("E03")
	Game.enter_node("payment")
	await capture("disabled-choice")
	before = Game.state.duplicate(true)
	await click(app.view.choice_buttons[0].get_global_rect().get_center())
	await click(Vector2(720,700))
	check(Game.state == before, "Disabled choice and bottom click cannot bypass payment")
	print("DIALOGUE CLICK VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
