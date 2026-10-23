extends Node
var app: Control
var checks := 0
var failures := 0
var output := "res://artifacts/qa/dialogue-history-2026-10-16/"

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

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = output + "checkpoint.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Game.save_path.get_base_dir()))
	Game.meta_path = output + "meta.json"
	Game.new_game()
	check(Game.state.dialogueHistory.size() == 1, "New game records opening")
	check(Game.state.dialogueHistory[0].text == Game.render_text(Game.node_data().text), "Rendered text snapshot")
	Game.advance(Game.revision)
	check(Game.state.dialogueHistory.size() == 2, "Advance retains previous dialogue")
	var before: Dictionary = Game.state.duplicate(true)
	Game.advance(Game.revision - 1)
	check(Game.state == before, "Stale advance cannot append")
	Game.menu()
	Game.resume()
	check(Game.state == before, "Resume does not duplicate history")
	Game.skip_dialogue(Game.revision)
	check(Game.state.activeNodeId == "contract", "Skip stops at choice")
	var count: int = Game.state.dialogueHistory.size()
	Game.choose(99, Game.revision)
	check(Game.state.dialogueHistory.size() == count, "Invalid choice is not recorded")
	var chosen: String = Game.node_data().choices[0].label
	Game.choose(0, Game.revision)
	check(Game.state.dialogueHistory[count].text == Game.render_text(chosen), "Selected choice captured")
	check(Game.state.dialogueHistory[count].kind == "choice", "Choice has distinct presentation")
	check(Game.state.dialogueHistory.size() == count + 2, "Choice then destination dialogue only")
	check(Game.valid_save(Game.state), "New snapshot valid")
	before = Game.state.duplicate(true)
	check(Game.save_game(), "Save to isolated file")
	Game.new_game()
	check(Game.state.dialogueHistory.size() == 1, "New adventure clears previous history")
	var loaded := Game.load_game()
	# JSON stores numbers as floats; compare normalized state and exact text snapshots.
	check(loaded and Game.state.dialogueHistory == before.dialogueHistory and JSON.parse_string(JSON.stringify(Game.state)) == JSON.parse_string(JSON.stringify(before)), "History survives disk round trip")
	var legacy := before.duplicate(true)
	legacy.erase("dialogueHistory")
	var migrated: Dictionary = Game.migrate_save(legacy)
	check(Game.valid_save(migrated) and migrated.dialogueHistory.is_empty(), "Old save gains empty history")
	var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	check(Game.load_game() and Game.state.dialogueHistory.size() == 1, "Old save starts at current dialogue only")
	check(Game.state.dialogueHistory[0].text == Game.render_text(Game.node_data().text), "No fabricated old dialogue")
	var invalid := before.duplicate(true)
	invalid.dialogueHistory = ["bad"]
	check(not Game.valid_save(invalid), "Malformed history rejected")
	invalid.dialogueHistory = [{"eventId":"E01"}]
	check(not Game.valid_save(invalid), "Incomplete history rejected")

	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.new_game()
	await get_tree().process_frame
	var revision: int = Game.revision
	app.view.elapsed = 0
	app.view.text_label.visible_characters = 0
	await click(app.view.history_button.get_global_rect().get_center())
	check(is_instance_valid(app.view.history_overlay), "Button opens history")
	check(Game.revision == revision, "Opening never advances")
	var visible: int = app.view.text_label.visible_characters
	await get_tree().create_timer(0.15).timeout
	check(app.view.text_label.visible_characters == visible, "Typewriter pauses while reading history")
	await click(Vector2(100,800))
	await key(KEY_1)
	app.view.advance()
	app.view.select(0)
	app.view.skip()
	check(Game.revision == revision, "Modal blocks underlying clicks and actions")
	await key(KEY_ESCAPE)
	check(Game.page == "dialogue" and not is_instance_valid(app.view.history_overlay), "Escape closes only history")
	await click(Vector2(720,700))
	check(Game.revision == revision and app.view.text_label.visible_characters == -1, "Returning preserves reveal behavior")
	await click(Vector2(720,700))
	check(Game.revision == revision + 1, "Normal continue restored")
	Game.skip_dialogue(Game.revision)
	await get_tree().process_frame
	before = Game.state.duplicate(true)
	await click(app.view.history_button.get_global_rect().get_center())
	await key(KEY_1)
	await click(Vector2(720,450))
	check(Game.state == before, "History cannot choose underlying option")
	await key(KEY_HOME)
	check(app.view.history_text.get_v_scroll_bar().value == 0, "Home reaches earliest record")
	await key(KEY_END)
	check(app.view.history_text.get_v_scroll_bar().value > 0, "End reaches latest record")
	var scroll_before: float = app.view.history_text.get_v_scroll_bar().value
	await click(Vector2(800,450), MOUSE_BUTTON_WHEEL_UP)
	check(app.view.history_text.get_v_scroll_bar().value < scroll_before, "Mouse wheel scrolls history")
	await key(KEY_END)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		check(img.save_png(output + "history-%dx%d.png" % [img.get_width(),img.get_height()]) == OK, "Rendered history screenshot")
	await key(KEY_ESCAPE)
	check(app.view.skip_button.disabled and not app.view.choice_buttons[0].disabled, "Original disabled states restored")
	await click(app.view.choice_buttons[0].get_global_rect().get_center())
	check(Game.state.flags.get("openingSupportChipId") == "money_chip", "Choice works after closing history")
	await click(app.view.history_button.get_global_rect().get_center())
	await key(KEY_TAB)
	check(app.view.history_overlay.is_ancestor_of(get_viewport().gui_get_focus_owner()), "Tab focus stays inside modal")
	await click(Vector2(1155,170))
	check(not is_instance_valid(app.view.history_overlay), "Close button returns to conversation")
	print("DIALOGUE HISTORY: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
