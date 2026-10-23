extends Node
var app: Control
var checks := 0
var failures := 0
var output: String

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "Capture " + name)

func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func(): get_tree().quit(1))
	Game.save_enabled = false
	Game.save_path = "user://dialogue_skip_visual.json"
	Game.meta_path = "user://dialogue_skip_visual_meta.json"
	var size := DisplayServer.window_get_size()
	output = "res://artifacts/qa/dialogue-skip-2026-10-15/%dx%d" % [size.x,size.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.new_game()
	await get_tree().create_timer(0.4).timeout
	check(app.view.skip_button.visible and not app.view.skip_button.disabled, "Skip enabled in opening")
	check(app.view.skip_button.get_rect() == Rect2(1096,16,140,44), "Skip sits beside menu in top right")
	await capture("01-opening")
	app.view.text_label.visible_characters = 0
	await click(app.view.skip_button)
	check(Game.state.activeNodeId == "contract", "Click while typing reaches choice")
	check(app.view.skip_button.disabled and app.view.choice_buttons.size() == 3, "Choice stops and disables skip")
	var previous: Dictionary = Game.state.duplicate(true)
	await click(app.view.skip_button)
	check(Game.state == previous, "Disabled button cannot choose")
	app.view.text_label.visible_characters = -1
	await capture("02-choice")
	await click(app.view.choice_buttons[0])
	check(not app.view.skip_button.disabled, "Choosing re-enables skip")
	await click(app.view.skip_button)
	check(Game.page == "result" and "E01" in Game.state.completedEventIds, "Skip selected branch enters result")
	Game.claim_rewards(Game.revision)
	Game.start_event("E02")
	await get_tree().process_frame
	await click(app.view.skip_button)
	check(Game.page == "battle" and Game.transition_locked, "Skip enters normal battle transition")
	await get_tree().create_timer(1.8).timeout
	check(app.shown_page == "battle" and not Game.transition_locked, "Battle transition completes")
	print("DIALOGUE SKIP VISUAL: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
