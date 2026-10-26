extends Node
## Real battle + viewport events. Never warps the pointer or writes player saves.
const Cleanup = preload("res://scripts/combat/audio_cleanup.gd")
var app: Control
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message,"passed":ok})
	if not ok:
		failures.append(message)
		push_error("EXHAUST PICKER: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func settle_pose() -> void:
	# Presentation tweens use wall time, including during accelerated headless runs.
	await get_tree().create_timer(0.3).timeout
	await settle()

func card_center(card: CombatCard) -> Vector2:
	return card.get_global_transform() * (card.size * 0.5)

func central_cards(picker: Control) -> Array:
	return picker.card_views.filter(func(card): return Rect2(440,180,560,490).has_point(card_center(card)))

func button_point(button: Button) -> Vector2:
	# Bottom hand cards may be clipped; click the visible part of their hit area.
	return button.get_global_rect().intersection(Rect2(0,0,1440,900)).get_center()

func original_hand_visible(view: Control) -> bool:
	return view.model.hand.all(func(uid): return view.cards.has(uid) and view.cards[uid].is_visible_in_tree() and view.cards[uid].modulate.a > 0.95)

func idle() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while Game.battle_busy or Game.transition_locked:
		await get_tree().create_timer(0.01).timeout
		if Time.get_ticks_msec() > deadline:
			push_error("EXHAUST PICKER idle timeout")
			get_tree().quit(2)
			return
	await settle()

func key(code: Key, shift := false, repeat := false) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		event.shift_pressed = shift
		get_viewport().push_input(event,true)
		await settle()
		if down and repeat:
			event = InputEventKey.new()
			event.keycode = code
			event.pressed = true
			event.echo = true
			get_viewport().push_input(event,true)
			await settle()

func click(point: Vector2, index := MOUSE_BUTTON_LEFT, drift := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion,true)
	await settle()
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = index
		event.pressed = down
		get_viewport().push_input(event,true)
		await settle()
		if down and drift:
			point += Vector2(2,1)
			motion = InputEventMouseMotion.new()
			motion.position = point
			motion.global_position = point
			motion.relative = Vector2(2,1)
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			get_viewport().push_input(motion,true)
			await settle()

func install_hand(numbers: Array) -> void:
	await idle()
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules,true)
	rules.deck = []
	for number in numbers: rules.deck.append("noren_%02d" % int(number))
	for i in 12: rules.deck.append("noren_01")
	rules.shuffleInitialDeck = false
	var enemies: Array = [{"id":"picker_target","displayName":"训练对手","maxHp":120,"battlePortraitAssetId":"","intentSequence":[{"type":"attack","amount":1}]}]
	var model := CombatModel.new()
	model.initialize("B04",100,100,rules,enemies,Game.card_catalog)
	model.opening_draw_done = true
	for i in numbers.size():
		var uid := "card_%03d" % i
		model.draw_pile.erase(uid)
		model.hand.append(uid)
	Game.commit_combat(model)
	app.swap_view()
	await idle()

func open_exhaust() -> Control:
	app.view.select_card("card_000",false)
	app.view.play_selected(-1)
	await settle()
	return app.view.pile_overlay

func test_cards_and_commit() -> void:
	await install_hand([12,1,1,2,23])
	var view: Control = app.view
	var before: Dictionary = view.model.snapshot()
	var adventure: Dictionary = Game.state.duplicate(true)
	var revision: int = Game.revision
	var picker := await open_exhaust()
	check(is_instance_valid(picker) and picker.card_mode,"real 12 Dismantle opens the card presentation mode")
	check(picker.options.size() == 4 and picker.card_views.size() == 4 and picker.option_buttons.size() == 4,"every other hand instance has one card and one selection control")
	check(picker.options.map(func(option): return option.value) == ["card_001","card_002","card_003","card_004"],"source card is excluded and candidate instance order is preserved")
	check(picker.card_views[0].uid != picker.card_views[1].uid and picker.card_views[0].data.id == picker.card_views[1].data.id,"identical card definitions remain independent selectable instances")
	check(picker.selected_index == -1 and picker.confirm_button.disabled,"opening requires an explicit choice before confirmation")
	check(picker.option_buttons[0].has_focus(),"first card receives keyboard focus without being selected")
	check(view.model.snapshot() == before and Game.state == adventure and Game.revision == revision and not Game.battle_busy,"opening picker spends nothing and does not commit a battle revision")
	check(view.cards.values().all(func(card): return not card.visible),"original candidates and pending source card are hidden while the modal presents their choice views")
	await settle_pose()
	check(central_cards(picker).is_empty() and picker.card_views.all(func(card): return card_center(card).y > 700),"before selection all candidates remain in the bottom hand and no card occupies the center")
	var original_candidate_views: Array = picker.card_views.duplicate()
	for card in picker.card_views:
		check(card.preview_only and not card.allow_zoom_preview and card.face_texture != null,"candidate renders the current full card artwork without nested zoom or battle input: " + card.uid)
	await click(button_point(picker.option_buttons[0]),MOUSE_BUTTON_LEFT,true)
	check(picker.selected_index == 0 and not picker.confirm_button.disabled,"press, held drift and release stage the first card and enable confirmation")
	check(view.model.snapshot() == before and Game.state == adventure and Game.revision == revision and not Game.battle_busy,"staging a card never spends resources or resolves its effect")
	await settle_pose()
	check(central_cards(picker) == [picker.card_views[0]] and picker.card_views.filter(func(card): return card.selected).size() == 1,"only the selected hand instance flies into the center")
	check(picker.card_views.slice(1).all(func(card): return card_center(card).y > 700),"unselected candidates remain in the bottom hand while the chosen card is centered")
	await click(button_point(picker.option_buttons[1]))
	check(picker.selected_index == 1,"clicking the duplicate switches to its separate instance")
	check(view.model.snapshot() == before,"changing the pending candidate leaves all model zones unchanged")
	await settle_pose()
	check(central_cards(picker) == [picker.card_views[1]] and card_center(picker.card_views[0]).y > 700,"changing selection returns the old card to the hand and centers only the new card")
	check(picker.card_views == original_candidate_views,"changing selection moves the same card views without creating a second preview copy")
	for code in [KEY_1,KEY_KP_1,KEY_F1,KEY_F5,KEY_F6,KEY_F7]: await key(code)
	check(is_instance_valid(view.pile_overlay) and not is_instance_valid(app.debug_panel) and view.model.snapshot() == before,"underlying battle and debug shortcuts remain isolated while cards are pending")
	var selected_uid: String = picker.options[picker.selected_index].value
	await click(picker.confirm_button.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,true)
	check(not is_instance_valid(view.pile_overlay),"confirm closes the picker before committing the chosen card")
	check(selected_uid == "card_002" and selected_uid in view.model.exhaust_pile and not "card_001" in view.model.exhaust_pile,"confirmation exhausts only the staged duplicate UID")
	check("card_000" in view.model.discard_pile and not "card_000" in view.model.exhaust_pile,"Dismantle itself follows its ordinary discard destination")
	check(view.model.ammo == int(before.norenState.ammo)+3,"confirmation grants Dismantle ammo exactly once")
	var committed: Dictionary = view.model.snapshot()
	await idle()
	check(view.model.snapshot() == committed,"visual playback never repeats the confirmed model transaction")
	check(view.cards.size() == view.model.hand.size(),"hand views synchronize with the committed hand after playback")

func test_cancel() -> void:
	await install_hand([12,1,2,23])
	var view: Control = app.view
	for kind in ["escape","right","button","keyboard-cancel"]:
		var before: Dictionary = view.model.snapshot()
		var state: Dictionary = Game.state.duplicate(true)
		var revision: int = Game.revision
		var picker := await open_exhaust()
		await click(button_point(picker.option_buttons[1]))
		await settle_pose()
		match kind:
			"escape": await key(KEY_ESCAPE)
			"right": await click(Vector2(700,400),MOUSE_BUTTON_RIGHT)
			"button": await click(picker.cancel_button.get_global_rect().get_center())
			"keyboard-cancel":
				picker.cancel_button.grab_focus()
				await key(KEY_SPACE)
		check(not is_instance_valid(view.pile_overlay),"pending selection can be canceled: " + kind)
		check(view.model.snapshot() == before and Game.state == state and Game.revision == revision and not Game.battle_busy,"cancellation spends nothing or moves any cards: " + kind)
		check(original_hand_visible(view),"canceling restores visibility of every original hand instance: " + kind)

func test_keyboard() -> void:
	await install_hand([12,1,2,23])
	var view: Control = app.view
	var before: Dictionary = view.model.snapshot()
	var picker := await open_exhaust()
	await key(KEY_TAB)
	check(picker.option_buttons[1].has_focus(),"Tab advances between card candidates")
	await key(KEY_ENTER,false,true)
	check(picker.selected_index == 1 and is_instance_valid(view.pile_overlay) and not picker.confirm_button.disabled,"Enter with repeat selects the focused card without resolving the battle")
	check(view.model.snapshot() == before,"keyboard candidate selection is a read-only pending choice")
	await key(KEY_RIGHT)
	check(picker.option_buttons[2].has_focus(),"directional navigation advances after a pending choice")
	await key(KEY_SPACE,false,true)
	check(picker.selected_index == 2 and is_instance_valid(view.pile_overlay),"Space with repeat changes the pending card without confirming")
	await settle_pose()
	check(central_cards(picker) == [picker.card_views[2]],"keyboard changes also leave exactly one selected card in the center")
	var focus_inside := true
	var reaches_confirm := false
	var reaches_cancel := false
	for i in 7:
		await key(KEY_TAB)
		var focus := get_viewport().gui_get_focus_owner()
		focus_inside = focus_inside and is_instance_valid(focus) and picker.is_ancestor_of(focus)
		reaches_confirm = reaches_confirm or focus == picker.confirm_button
		reaches_cancel = reaches_cancel or focus == picker.cancel_button
	check(focus_inside and reaches_confirm and reaches_cancel,"Tab cycles within cards, Confirm and Cancel after a card is selected")
	picker.confirm_button.grab_focus()
	await key(KEY_ENTER,false,true)
	check(not is_instance_valid(view.pile_overlay) and "card_003" in view.model.exhaust_pile,"keyboard Confirm accepts the staged card exactly once despite repeat")
	check(view.model.ammo == int(before.norenState.ammo)+3,"keyboard confirmation spends and grants resources only once")
	await idle()

func test_long_list() -> void:
	var numbers: Array = [12]
	for i in 17: numbers.append(1 if i % 2 == 0 else 2)
	await install_hand(numbers)
	var view: Control = app.view
	var before: Dictionary = view.model.snapshot()
	var picker := await open_exhaust()
	check(picker.option_buttons.size() == 17 and picker.card_views.size() == 17,"large hands retain every candidate instance")
	for i in 16: await key(KEY_TAB)
	var last: Button = picker.option_buttons.back()
	check(last.has_focus(),"Tab can reach the last candidate in a large hand")
	check(picker.find_children("*","ScrollContainer",true,false).is_empty(),"large hand uses the bottom fan without a central grid or scroll browser")
	check(picker.option_buttons.all(func(btn): return btn.get_global_rect().intersection(Rect2(0,0,1440,900)).has_area()),"every compressed hand candidate retains a visible input region")
	await key(KEY_SPACE)
	check(picker.selected_index == 16 and not picker.confirm_button.disabled,"last compressed hand candidate can be staged with the keyboard")
	await settle_pose()
	check(central_cards(picker) == [picker.card_views[16]],"large hand moves only its selected instance into the center")
	await key(KEY_ESCAPE)
	check(view.model.snapshot() == before and not is_instance_valid(view.pile_overlay) and original_hand_visible(view),"canceling a large-hand choice preserves model and restores every original card")

func _ready() -> void:
	if not OS.get_user_data_dir().to_lower().contains("qa") or OS.get_user_data_dir().ends_with("/MidnightCommissionDemo"):
		push_error("Run exhaust picker QA only in an isolated copied project with a QA user directory")
		get_tree().quit(2)
		return
	get_tree().create_timer(90).timeout.connect(func(): push_error("EXHAUST PICKER timeout");get_tree().quit(2))
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "user://exhaust-picker-qa"
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	Game.state = Game.initial_state()
	Game.transition_locked = false
	Game.battle_busy = false
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await idle()
	Game.start_training("B04")
	await idle()
	await test_cards_and_commit()
	await test_cancel()
	await test_keyboard()
	await test_long_list()
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path),"no checkpoint or meta file was written by the complete suite")
	if is_instance_valid(app.audio_hooks): app.audio_hooks.attach(null)
	await Cleanup.release(app,get_tree())
	app.queue_free()
	await settle()
	var file := FileAccess.open(output.path_join("exhaust-picker-results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"scope":"isolated real battle and viewport synthetic input; no system pointer movement or pixels"},"\t"))
	file.close()
	print("EXHAUST PICKER TESTS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
