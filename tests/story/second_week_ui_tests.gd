extends Node
## Copied-project regression: real main/Battle input, no production saves.
const Cleanup := preload("res://scripts/combat/audio_cleanup.gd")
var app: Control
var output := ""
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("SECOND WEEK UI: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func wait_for(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await get_tree().create_timer(0.02).timeout
	return false

func idle() -> bool:
	return not Game.transition_locked and not Game.battle_busy and is_instance_valid(app.view)

func key_event(code: Key, down: bool, echo := false, shift := false, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	event.echo = echo
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	get_viewport().push_input(event, true)
	await settle()

func key(code: Key) -> void:
	await key_event(code, true)
	await key_event(code, false)

func shot(name: String, viewport: Viewport) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("QA_CAPTURE") != "1": return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(output.path_join(name + ".png"))

func test_week_archive() -> void:
	var cases := [
		[1, 1, false, false, "进行中 / 第 1 天", "完成第一周后开放"],
		[1, 7, true, false, "已完成", "可进入"],
		[2, 1, true, false, "已完成", "进行中 / 第 1 天"],
		[2, 3, true, false, "已完成", "进行中 / 第 3 天"],
		[2, 7, true, false, "已完成", "进行中 / 第 7 天"],
		[2, 7, true, true, "已完成", "已完成"],
		[2, 3, false, false, "已完成", "进行中 / 第 3 天"]]
	for case in cases:
		Game.state = Game.initial_state()
		Game.state.currentWeek = case[0]
		Game.state.currentDay = case[1]
		Game.state.flags = {"week1Complete":case[2], "week2Complete":case[3]}
		Game.state.currentScene = "map"
		Game.page = "map"
		Game.refresh_event_pool()
		Game.changed.emit()
		if not await wait_for(idle):
			check(false, "map becomes idle before opening archive")
			return
		var before: String = JSON.stringify(Game.state)
		app.view.show_weeks()
		await settle()
		var dialog: AcceptDialog = app.view._week_dialog
		var lines := dialog.dialog_text.split("\n", false)
		check(lines[0] == "第一周：" + case[4], "first-week archive: " + str(case))
		check(lines[1] == "第二周：" + case[5], "second-week archive: " + str(case))
		check(lines[2] == "第三周：暂未开放", "archive does not advertise an unimplemented chapter")
		app.view.show_weeks()
		check(app.view._week_dialog == dialog, "opening archive twice reuses the modal")
		if case[0] == 2 and case[1] == 3 and case[2]: await shot("week2_day3_archive", dialog)
		app.view._close_weeks()
		await settle()
		check(JSON.stringify(Game.state) == before, "archive open/close preserves adventure")

func test_phase_shortcut() -> void:
	Game.state = Game.initial_state()
	Game.state.currentWeek = 2
	Game.state.currentDay = 7
	Game.state.currentScene = "map"
	Game.page = "map"
	Game.refresh_event_pool()
	Game.changed.emit()
	if not await wait_for(idle):
		check(false, "map becomes idle before Boss fixture")
		return
	check(Game.start_event("E23"), "formal second-week Boss starts")
	if not await wait_for(idle):
		check(false, "Boss introduction becomes idle")
		return
	Game.skip_dialogue(Game.revision)
	if not await wait_for(func(): return idle() and app.shown_page == "battle" and app.view.initialized):
		check(false, "actual Boss battle becomes playable")
		return
	var view = app.view
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	model.kill_enemies()
	check(model.encounter_phase == 2 and Game.commit_combat(model), "model transitions once before dialogue presentation")
	view.call_deferred("resume_console_combat")
	if not await wait_for(func(): return view.get_node_or_null("NossPhaseDialogue") != null):
		check(false, "actual transition opens six-line modal")
		return
	var interlude = view.get_node("NossPhaseDialogue")
	var before: Dictionary = view.model.snapshot()
	check(Game.battle_busy and interlude.cursor == 0, "transition begins under battle input lock")
	PlayerSettings.bindings.advance = KEY_SPACE
	await key_event(KEY_SPACE, true)
	check(interlude.cursor == 1, "default Space advances once")
	await key_event(KEY_SPACE, true, true)
	await key_event(KEY_SPACE, false)
	check(interlude.cursor == 1, "default key echo/release does not advance")
	await key(KEY_ENTER)
	check(interlude.cursor == 2, "default Enter alias advances once")
	await key(KEY_KP_ENTER)
	check(interlude.cursor == 3, "default keypad Enter alias advances once")
	# Advance may share a battle binding; the modal must own the gesture.
	PlayerSettings.bindings.advance = KEY_E
	for old_default in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		await key(old_default)
		if not is_instance_valid(interlude):
			check(false, "unbound defaults must not close the transition dialogue")
			return
		check(interlude.cursor == 3, "unbound old default does not activate focused button: " + str(old_default))
	await key_event(KEY_E, true, false, true)
	await key_event(KEY_E, false, false, true)
	await key_event(KEY_E, true, false, false, true)
	await key_event(KEY_E, false, false, false, true)
	await key_event(KEY_E, true, true)
	await key_event(KEY_E, false)
	check(interlude.cursor == 3, "modified keys and echo cannot advance")
	await key(KEY_E)
	check(interlude.cursor == 4, "custom advance key works inside actual busy Battle/main")
	await shot("phase_custom_key", get_viewport())
	await key(KEY_E)
	check(interlude.cursor == 5, "custom key release cannot double-advance")
	await key(KEY_E)
	check(await wait_for(idle), "last custom key completes presentation and releases input lock")
	check(view.get_node_or_null("NossPhaseDialogue") == null, "finished interlude is removed")
	check(view.model.snapshot() == before, "dialogue keys do not play cards or end a battle turn")
	check(Game.state.dialogueHistory.filter(func(entry): return entry.has("phaseKey")).size() == 6, "each transition line is recorded exactly once")

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in output.to_lower() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("SECOND WEEK UI: copied QA project and absolute QA_OUT_DIR required")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused_checkpoint.json")
	Game.meta_path = output.path_join("unused_meta.json")
	PlayerSettings.settings_path = output.path_join("settings.cfg")
	var original_bindings := PlayerSettings.bindings.duplicate()
	Game.page = "menu"
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	if await wait_for(idle):
		await test_week_archive()
		await test_phase_shortcut()
	else:
		check(false, "actual main opens in isolated project")
	PlayerSettings.bindings = original_bindings
	await Cleanup.release(app, get_tree())
	app.queue_free()
	await settle()
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "suite never writes adventure or meta saves")
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}, "\t"))
	print("SECOND WEEK UI: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
