extends Node
## Real viewport GUI events only: no system pointer movement or production saves.
const Cleanup = preload("res://scripts/combat/audio_cleanup.gd")
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var picks: Array = []
var app: Control
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message,"passed":ok})
	if not ok:
		failures.append(message)
		push_error("CHOICE PICKER: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func view_is(script_name: String) -> bool:
	return is_instance_valid(app) and is_instance_valid(app.view) and app.view.get_script() != null and app.view.get_script().resource_path.ends_with("/" + script_name)

func wait_ready(condition: Callable, seconds := 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not Game.transition_locked and not Game.battle_busy and condition.call():
			await settle()
			return true
		# Transitions use real-time tweens; headless frame counts are not deadlines.
		await get_tree().create_timer(0.02).timeout
	return false

func key_event(code: Key, down: bool, shift := false, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = down
	event.shift_pressed = shift
	event.echo = echo
	get_viewport().push_input(event,true)
	await settle()

func key(code: Key, shift := false) -> void:
	await key_event(code,true,shift)
	await key_event(code,false,shift)

func click(point: Vector2, button_index := MOUSE_BUTTON_LEFT, drift := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion,true)
	await settle()
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button_index
		event.pressed = down
		get_viewport().push_input(event,true)
		await settle()
		if down and drift:
			motion = InputEventMouseMotion.new()
			motion.position = point + Vector2(2,1)
			motion.global_position = motion.position
			motion.relative = Vector2(2,1)
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			get_viewport().push_input(motion,true)
			point = motion.position
			await settle()

func open_picker(options: Array = [{"text":"候选一","value":"first"},{"text":"候选二","value":"second"}]) -> Control:
	app.view.show_card_choice("输入回归",options,func(value): picks.append(value))
	return app.view.pile_overlay

func test_picker() -> bool:
	Game.start_training("B02")
	var ready: bool = await wait_ready(func(): return Game.page == "battle" and view_is("battle.gd") and app.view.initialized)
	check(ready,"real training battle is ready after transition and initialization")
	if not ready: return false
	var view = app.view
	var before: Dictionary = view.model.snapshot()
	var adventure: Dictionary = Game.state.duplicate(true)
	var revision: int = Game.revision
	var picker := open_picker()
	await settle()
	check(picker.option_buttons[0].has_focus(),"first candidate receives initial focus")
	await key(KEY_TAB)
	check(picker.option_buttons[1].has_focus(),"Tab advances to second candidate")
	await key(KEY_TAB)
	check(picker.cancel_button.has_focus(),"Tab includes Cancel")
	await key(KEY_TAB)
	check(picker.option_buttons[0].has_focus(),"Tab wraps inside picker")
	await key(KEY_TAB,true)
	check(picker.cancel_button.has_focus(),"Shift-Tab wraps back to Cancel")
	await key(KEY_DOWN)
	check(picker.option_buttons[0].has_focus(),"Down wraps from Cancel to first candidate")
	await key(KEY_RIGHT)
	check(picker.option_buttons[1].has_focus(),"Right advances within picker")
	await key(KEY_UP)
	check(picker.option_buttons[0].has_focus(),"Up returns to previous candidate")
	await key(KEY_LEFT)
	check(picker.cancel_button.has_focus(),"Left wraps to Cancel")
	for code in [KEY_1,KEY_KP_1,KEY_F1,KEY_F5,KEY_F6,KEY_F7]:
		await key(code)
	check(view.selected_uid.is_empty() and view.model.snapshot() == before and Game.state == adventure and Game.revision == revision,"digits and debug shortcuts cannot change underlying battle or adventure")
	check(not is_instance_valid(app.debug_panel) and view.pile_overlay == picker,"blocked shortcuts cannot open debug or replace picker")
	picker.option_buttons[1].grab_focus()
	await key_event(KEY_ENTER,true)
	await key_event(KEY_ENTER,true,false,true)
	await key_event(KEY_ENTER,false)
	check(picks == ["second"] and not is_instance_valid(view.pile_overlay),"Enter including key-repeat confirms the focused candidate exactly once")
	picker = open_picker()
	await settle()
	await key_event(KEY_SPACE,true)
	await key_event(KEY_SPACE,true,false,true)
	await key_event(KEY_SPACE,false)
	check(picks == ["second","first"] and not is_instance_valid(view.pile_overlay),"Space including key-repeat confirms exactly once")
	picker = open_picker()
	await settle()
	get_viewport().gui_release_focus()
	await key(KEY_ENTER)
	check(picks == ["second","first","first"] and not is_instance_valid(view.pile_overlay),"accept recovers missing focus inside picker")
	picker = open_picker()
	await settle()
	view.end_button.grab_focus()
	await key(KEY_ENTER)
	check(picks.size() == 4 and picks.back() == "first" and view.model.snapshot() == before,"accept recovers foreign focus without activating battle End Turn")
	picker = open_picker()
	await settle()
	await click(picker.option_buttons[1].get_global_rect().get_center(),MOUSE_BUTTON_LEFT,true)
	check(picks.size() == 5 and picks.back() == "second" and not is_instance_valid(view.pile_overlay),"mouse press, held drift and release select candidate once")
	for kind in ["escape","right","button","keyboard-cancel"]:
		picker = open_picker()
		await settle()
		match kind:
			"escape": await key(KEY_ESCAPE)
			"right": await click(Vector2(700,400),MOUSE_BUTTON_RIGHT)
			"button": await click(picker.cancel_button.get_global_rect().get_center())
			"keyboard-cancel":
				picker.cancel_button.grab_focus()
				await key(KEY_SPACE)
		check(not is_instance_valid(view.pile_overlay) and picks.size() == 5,"cancellation closes without selection: " + kind)
	picker = open_picker([])
	await settle()
	check(picker.cancel_button.has_focus() and picker.option_buttons.is_empty(),"empty candidate list focuses Cancel")
	for code in [KEY_TAB,KEY_DOWN,KEY_RIGHT,KEY_UP,KEY_LEFT]:
		await key(code)
		check(picker.cancel_button.has_focus(),"single Cancel retains cyclic focus: " + str(code))
	await key(KEY_TAB,true)
	check(picker.cancel_button.has_focus(),"single Cancel retains reverse Tab focus")
	await key(KEY_ENTER)
	check(not is_instance_valid(view.pile_overlay) and picks.size() == 5,"Enter safely closes empty candidate list")
	var many_options: Array = []
	for i in 12: many_options.append({"text":"候选 %d" % i,"value":i})
	picker = open_picker(many_options)
	await settle()
	for i in 11: await key(KEY_DOWN)
	var last: Button = picker.option_buttons.back()
	var scroll := last.get_parent().get_parent() as ScrollContainer
	check(last.has_focus() and scroll.scroll_vertical > 0 and scroll.get_global_rect().encloses(last.get_global_rect()),"directional focus scrolls long candidate lists to keep the chosen button visible")
	await key(KEY_ESCAPE)
	check(view.model.snapshot() == before and Game.state == adventure and Game.revision == revision,"all picker navigation and cancellation preserve model, adventure and revision")
	Game.finish_training("lose")
	ready = await wait_ready(func(): return Game.page == "menu" and view_is("menu.gd"))
	check(ready,"training exit transition finishes before shop fixture")
	return ready

func test_shop_layout() -> void:
	Game.state = Game.initial_state()
	Game.state.credits = 1000
	Game.go_map()
	var ready: bool = await wait_ready(func(): return Game.page == "map" and view_is("map.gd"))
	check(ready,"map is ready before entering mall")
	if not ready: return
	Game.visit("mall")
	ready = await wait_ready(func(): return (Game.page == "dialogue" and view_is("dialogue.gd")) or (Game.page == "place" and view_is("technology_shop.gd")))
	check(ready,"mall intro or storefront is ready")
	if not ready: return
	if Game.page == "dialogue": Game.skip_dialogue(Game.revision)
	ready = await wait_ready(func(): return Game.page == "place" and view_is("technology_shop.gd"))
	check(ready,"real mall routes to technology shop after intro and transition")
	if not ready: return
	var view = app.view
	check(view.stock.find_children("buy_slot_*","Button",true,false).size() == 6,"shop layout covers six real offers")
	for i in 6:
		var tile: Control = view.stock.get_node("technology_tile_%d" % i)
		var buy: Button = view.stock.get_node("buy_slot_%d" % i)
		var labels: Array = tile.find_children("*","Label",true,false)
		var fits := true
		var separated := true
		for a in labels.size():
			var caption: Label = labels[a]
			fits = fits and caption.size.y >= caption.get_combined_minimum_size().y and tile.get_global_rect().encloses(caption.get_global_rect())
			separated = separated and not caption.get_global_rect().intersects(buy.get_global_rect())
			for b in range(a+1,labels.size()):
				separated = separated and not caption.get_global_rect().intersects(labels[b].get_global_rect())
		check(fits,"all product labels have their real minimum height and fit tile %d" % i)
		check(separated,"product labels do not overlap each other or Buy in tile %d" % i)

func _ready() -> void:
	if not OS.get_user_data_dir().to_lower().contains("qa") or OS.get_user_data_dir().ends_with("/MidnightCommissionDemo"):
		push_error("Run choice picker input QA only in an isolated copied project with a QA user directory")
		get_tree().quit(2)
		return
	get_tree().create_timer(60).timeout.connect(func(): push_error("CHOICE PICKER timeout");get_tree().quit(2))
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "user://choice-picker-input-qa"
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	Game.state = Game.initial_state()
	Game.transition_locked = false
	Game.battle_busy = false
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	var ready: bool = await wait_ready(func(): return Game.page == "menu" and view_is("menu.gd"))
	check(ready,"initial menu is ready before starting training")
	if ready and await test_picker(): await test_shop_layout()
	if is_instance_valid(app.audio_hooks): app.audio_hooks.attach(null)
	await Cleanup.release(app,get_tree())
	app.queue_free()
	await settle()
	var file := FileAccess.open(output.path_join("choice-picker-input-results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"scope":"isolated real viewport synthetic input and node layout; no pixels or physical input"},"\t"))
	file.close()
	print("CHOICE PICKER INPUT TESTS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
