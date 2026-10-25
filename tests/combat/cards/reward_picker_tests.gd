extends Node
## Isolated headless UI callbacks and synthetic viewport input, never system mouse input.
const Cleanup = preload("res://scripts/combat/audio_cleanup.gd")
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var layouts: Array[Dictionary] = []
var app: Control
var offers: Array[String] = []
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message, "passed":ok})
	if not ok:
		failures.append(message)
		push_error("REWARD PICKER: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func key(code: Key, shift: bool = false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.shift_pressed = shift
		event.pressed = down
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await settle()

func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)
	await settle()

func click(point: Vector2) -> void:
	await motion(point)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await settle()

func remove_app() -> void:
	if not is_instance_valid(app): return
	if is_instance_valid(app.audio_hooks): app.audio_hooks.attach(null)
	await Cleanup.release(app, get_tree())
	app.queue_free()
	await settle()

func stage(source: String) -> void:
	await remove_app()
	Game.save_enabled = false
	Game.save_path = output.path_join("checkpoint-" + source + ".json")
	Game.meta_path = output.path_join("meta.json")
	Game.pending_save_kind = ""
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.state = Game.initial_state()
	Game.state.activeEventId = "E02" if source == "battle" else "E01R"
	Game.state.activeNodeId = "finish"
	Game.state.currentPlaceId = "junkyard" if source == "battle" else "bar"
	Game.state.battleId = "B02" if source == "battle" else ""
	Game.state.currentScene = "result"
	Game.state.currentDay = 4
	Game.state.result = "win"
	Game.state.completedEventIds = ["E01", "E02", "E04", "E11"]
	if source == "battle": Game.state.battleHistory = [{"battleId":"B02", "result":"win"}]
	else: Game.state.completedEventIds.append("E01R")
	Game.state.deck = [offers[0], offers[0]]
	Game.prepare_battle_reward()
	Game.state.battleReward.options = offers.duplicate()
	Game.page = "result"
	Game.revision += 1
	check(Game.valid_save(Game.state), source + " fixture is a valid current reward checkpoint")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle()

func opened_picker() -> Control:
	app.view.reward_view.open_picker()
	return app.view.reward_view.picker

func layout_check(picker: Control, context: String) -> void:
	var canvas := Rect2(0,0,1440,900)
	var valid := true
	for i in picker.option_buttons.size():
		var button: Button = picker.option_buttons[i]
		var bounds: Rect2 = button.get_global_rect()
		var card: CombatCard = picker.cards[i]
		valid = valid and canvas.encloses(bounds) and canvas.encloses(card.get_global_rect())
		valid = valid and not bounds.intersects(picker.back_button.get_global_rect())
		for j in range(i + 1, picker.option_buttons.size()):
			valid = valid and not bounds.intersects(picker.option_buttons[j].get_global_rect())
		valid = valid and card.preview_only and card.managed_input and not card.enabled
		valid = valid and card.mouse_filter == Control.MOUSE_FILTER_IGNORE and card.card_button.mouse_filter == Control.MOUSE_FILTER_IGNORE
	check(valid and canvas.encloses(picker.back_button.get_global_rect()), context + " card hit areas fit, do not overlap each other or Back, and card art cannot steal input")
	var labels_fit := true
	for node in picker.find_children("*", "Label", true, false):
		# Card-face text is authored in texture space and scaled with the card.
		if picker.cards.any(func(card): return card.is_ancestor_of(node)): continue
		labels_fit = labels_fit and node.get_combined_minimum_size().x <= node.size.x + 1 and node.get_combined_minimum_size().y <= node.size.y + 1
	check(labels_fit, context + " picker labels have enough layout space")
	var entry := {"context":context,"cards":[],"back":rect_data(picker.back_button.get_global_rect())}
	for i in picker.cards.size():
		entry.cards.append({"id":picker.cards[i].uid,"card":rect_data(picker.cards[i].get_global_rect()),"button":rect_data(picker.option_buttons[i].get_global_rect())})
	layouts.append(entry)

func rect_data(value: Rect2) -> Array:
	return [value.position.x,value.position.y,value.size.x,value.size.y]

func test_modal(source: String) -> void:
	await stage(source)
	var reward: Control = app.view.reward_view
	var before: Dictionary = Game.state.duplicate(true)
	var revision: int = Game.revision
	var picker := opened_picker()
	await get_tree().create_timer(0.6).timeout
	check(picker.option_buttons.size() == 3 and picker.cards.size() == 3 and picker.option_slots.size() == 3, source + " real result view displays three complete choices")
	check(picker.owned_labels.size() == 3 and picker.owned_labels[0].text == "已拥有 2 张" and picker.owned_labels[1].text == "未拥有" and picker.owned_labels[2].text == "未拥有", source + " ownership captions count actual duplicate cards and distinguish new choices")
	check(picker.active_index == -1 and get_viewport().gui_get_focus_owner() == null, source + " opens with no automatic highlighted or focused choice")
	check(reward.option_buttons == picker.option_buttons and reward.exit_button.disabled and reward.card_reward_button.disabled, source + " underlying controls are suspended and keyboard choices point at the picker")
	check(Game.state == before and Game.revision == revision, source + " opening the picker never changes reward or credits")
	for resolution in [Vector2i(1280,800),Vector2i(1600,1000)]:
		get_window().size = resolution
		await settle()
		layout_check(picker, source + " " + str(resolution))
	var hit_rect: Rect2 = picker.option_buttons[1].get_global_rect()
	await motion(hit_rect.get_center())
	await get_tree().create_timer(0.25).timeout
	check(picker.active_index == 1 and picker.hovered_index == 1, source + " viewport pointer highlights the card under it")
	check(picker.option_buttons[1].get_global_rect() == hit_rect, source + " hover animation never shifts the target hit area")
	picker.back_button.grab_focus()
	await settle()
	check(picker.active_index == -1, source + " keyboard Back focus suppresses the parked pointer's card highlight")
	picker.option_buttons[0].grab_focus()
	await settle()
	await motion(hit_rect.get_center() + Vector2(2,0))
	check(picker.active_index == 1 and not picker.option_buttons[0].has_focus(), source + " pointer takeover within an already hovered card restores its highlight")
	await motion(Vector2(40,40))
	await key(KEY_TAB)
	check(picker.option_buttons[0].has_focus() and picker.active_index == 0, source + " Tab enters the first choice and highlights it")
	await key(KEY_TAB)
	check(picker.option_buttons[1].has_focus() and picker.active_index == 1, source + " Tab advances to the next choice")
	await key(KEY_TAB, true)
	await key(KEY_TAB, true)
	check(picker.back_button.has_focus(), source + " Shift-Tab wraps to Back inside the modal")
	await key(KEY_TAB)
	check(picker.option_buttons[0].has_focus(), source + " forward focus wraps from Back to the first choice")
	await key(KEY_TAB)
	await motion(picker.option_buttons[2].get_global_rect().get_center())
	check(picker.active_index == 2 and not picker.option_buttons[1].has_focus(), source + " pointer takeover clears the previous keyboard highlight")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(reward.picker) and Game.state == before and Game.revision == revision, source + " Escape returns without claiming or forfeiting a card")
	check(not reward.exit_button.disabled and reward.card_reward_button.has_focus(), source + " close restores the reward button and focus")
	picker = opened_picker()
	await settle()
	picker.back_button.pressed.emit()
	await settle()
	check(not is_instance_valid(reward.picker) and Game.state == before, source + " Back closes only the picker")
	picker = opened_picker()
	await get_tree().create_timer(0.6).timeout
	var failed_path := Game.save_path.path_join("blocked.json")
	check(Game.save_game(), source + " pending checkpoint can be persisted")
	var disk_before := FileAccess.get_file_as_bytes(Game.save_path)
	var real_path := Game.save_path
	Game.save_path = failed_path
	Game.save_enabled = true
	picker.option_buttons[0].pressed.emit()
	await settle()
	check(Game.state == before and Game.revision == revision and is_instance_valid(reward.picker), source + " failed save retains pending options and does not grant a card")
	check(FileAccess.get_file_as_bytes(real_path) == disk_before and not picker.option_buttons[0].disabled, source + " failed selection leaves the original disk and retry action intact")
	Game.save_path = real_path
	if source == "battle": await key(KEY_2)
	else: await click(picker.option_buttons[1].get_global_rect().get_center())
	check(Game.state.battleReward.status == "claimed" and Game.state.battleReward.selectedCardId == offers[1] and Game.state.deck.count(offers[1]) == 1, source + " real key or pointer input grants exactly the selected card")
	check(Game.state.credits == before.credits and Game.state.deck.size() == before.deck.size() + 1, source + " selection does not repeat the credit reward")
	check(not is_instance_valid(app.view.reward_view.picker) and app.view.reward_view.exit_button.text == "返回地图  →", source + " successful selection returns to claimed reward view")
	await key(KEY_2)
	check(Game.state.deck.count(offers[1]) == 1 and not Game.choose_reward_card(offers[0], revision), source + " repeat or stale selection cannot claim another card")
	var file := JSON.parse_string(FileAccess.get_file_as_string(real_path)) as Dictionary
	check(file.battleReward.status == "claimed" and file.deck.count(offers[1]) == 1 and Game.valid_save(file), source + " the selected card and consumed claim persist together")
	Game.save_enabled = false
	await remove_app()

func _ready() -> void:
	if OS.get_user_data_dir().ends_with("/MidnightCommissionDemo"):
		push_error("Run reward picker QA only in an isolated copied project/user directory")
		get_tree().quit(2)
		return
	get_tree().create_timer(90).timeout.connect(func(): push_error("REWARD PICKER timeout");get_tree().quit(2))
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "user://reward-picker-qa"
	DirAccess.make_dir_recursive_absolute(output)
	for rarity in ["B","A","S"]:
		for id in Game.card_catalog:
			if Game.card_catalog[id].get("rarity") == rarity:
				offers.append(id)
				break
	check(offers.size() == 3, "fixture uses one real B, A and S card")
	await test_modal("battle")
	await test_modal("event")
	var file := FileAccess.open(output.path_join("reward-picker-results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"layouts":layouts,"scope":"isolated headless UI nodes and synthetic viewport input; no pixel or physical-input acceptance"},"\t"))
	file.close()
	print("REWARD PICKER TESTS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
