extends Node
var app: Control
var checks := 0
var failures := 0
var output := "res://artifacts/qa/reward-focus-2026-10-11/"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle(seconds: float = 0.25) -> void:
	await get_tree().create_timer(seconds).timeout

func idle() -> void:
	var start := Time.get_ticks_msec()
	while Game.transition_locked or Game.battle_busy:
		await get_tree().process_frame
		if Time.get_ticks_msec()-start > 10000:
			check(false,"Timed out waiting for battle")
			get_tree().quit(1)
			return
	await settle()

func move_mouse(pos: Vector2) -> void:
	var point := get_viewport().get_final_transform() * pos
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await get_tree().process_frame

func click(pos: Vector2) -> void:
	await move_mouse(pos)
	var point := get_viewport().get_final_transform() * pos
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle(0.06)

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle(0.08)

func shot(id: String) -> void:
	await settle()
	print("REWARD SCREENSHOT: " + id)
	await RenderingServer.frame_post_draw
	var pixels := get_viewport().get_texture().get_image()
	check(pixels.save_png(output+id+".png") == OK,"Save screenshot " + id)

func configure_battle(id: String) -> void:
	Game.state = Game.initial_state()
	Game.state.targetId = "richard"
	Game.state.activeEventId = Game.battles[id].eventId
	Game.state.currentPlaceId = Game.battles[id].placeId
	Game.enter_node("battle")

func _ready() -> void:
	get_window().title = "Reward focus regression"
	get_window().always_on_top = true
	Game.save_enabled = false
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_path = output + "visual_checkpoint.json"
	Game.meta_path = output + "visual_meta.json"
	output += "%dx%d-" % [get_window().size.x,get_window().size.y]
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	configure_battle("B02")
	await idle()
	for i in range(3):
		var view = app.view
		var card: CombatCard = view.cards[view.model.hand[0]]
		await click(card.get_global_transform() * Vector2(90,30))
		check(not view.selected_uid.is_empty(),"Mouse selects attack card")
		await click(Vector2(1030,400))
		await idle()
	check(Game.page == "dialogue" and Game.state.credits == 0,"Natural victory reaches dialogue before rewards")
	await shot("post-battle-dialogue")
	var advances := 0
	while Game.page == "dialogue" and advances < 8:
		await click(Vector2(1257,792))
		advances += 1
	await settle()
	check(Game.page == "result" and Game.has_battle_reward() and Game.state.credits == int(Game.config.initialCredits) + 50,"Finish dialogue via button opens reward")
	if not Game.has_battle_reward():
		get_tree().quit(1)
		return
	await shot("reward")
	var reward = app.view.reward_view
	check(reward.exit_button.get_global_rect().end.x <= 1440 and reward.exit_button.position.y > 750,"Map exit is inside lower-right corner")
	await click(Vector2(540,591))
	check(is_instance_valid(reward.picker) and reward.option_buttons.size() == 3,"Click reward entry opens three cards")
	check(reward.exit_button.disabled,"Modal blocks underlying exit")
	check(get_viewport().gui_get_focus_owner() == null,"Opening picker does not highlight the first card by default")
	await shot("choice")
	for i in range(3):
		await move_mouse(reward.option_buttons[i].get_global_rect().get_center())
		await settle(0.06)
		for j in range(3):
			check(reward.option_buttons[j].is_hovered() == (i == j) and not reward.option_buttons[j].has_focus(),"Only hovered card %d is highlighted; inspect card %d" % [i+1,j+1])
		await shot("hover-%d" % (i+1))
	await move_mouse(Vector2(194,233))
	await settle(0.06)
	for b in reward.option_buttons:
		check(not b.is_hovered() and not b.has_focus(),"Moving off cards clears highlights")
	await shot("no-hover")
	await key(KEY_TAB)
	check(reward.option_buttons[0].has_focus(),"Tab starts keyboard navigation at first card")
	await key(KEY_TAB)
	check(reward.option_buttons[1].has_focus(),"Tab moves focus to second card")
	await key(KEY_TAB)
	check(reward.option_buttons[2].has_focus(),"Tab moves focus to third card")
	await key(KEY_TAB)
	var focused := get_viewport().gui_get_focus_owner()
	check(is_instance_valid(focused) and reward.picker.is_ancestor_of(focused),"Tab stays in picker on back button")
	await key(KEY_TAB)
	check(reward.option_buttons[0].has_focus(),"Tab wraps inside picker")
	await shot("keyboard-focus")
	await move_mouse(reward.option_buttons[1].get_global_rect().get_center())
	await settle(0.06)
	check(get_viewport().gui_get_focus_owner() == null and reward.option_buttons[1].is_hovered(),"Mouse resumes on second card without stale keyboard highlight")
	await shot("mouse-after-keyboard")
	await click(Vector2(1246,813))
	check(Game.page == "result" and is_instance_valid(reward.picker),"Outside click cannot leave reward through modal")
	await key(KEY_ESCAPE)
	check(Game.page == "result" and not is_instance_valid(reward.picker) and Game.state.deck.is_empty(),"Escape closes picker without claiming or exiting")
	await click(Vector2(1080,599))
	check(get_viewport().gui_get_focus_owner() == null,"Reopening picker does not restore stale card focus")
	await click(Vector2(712,483))
	await settle()
	check(Game.state.deck == ["test_reward_02"] and Game.state.battleReward.status == "claimed","Mouse picks only second card")
	await shot("claimed")
	await click(Vector2(1246,813))
	check(Game.page == "map" and Game.state.credits == int(Game.config.initialCredits) + 50,"Lower-right button returns to map with rewards")
	# Keyboard selection and reload while the card is still pending.
	Game.state.activeEventId = "E11"
	Game.state.currentPlaceId = "pump"
	Game.state.battleReward = {}
	Game.state.battleId = "B11"
	Game.state.result = "win"
	Game.state.battleHistory.append({"battleId":"B11","result":"win"})
	Game.enter_node("finish")
	check(Game.save_game() and Game.load_game(),"Pending reward reloads")
	await settle()
	await click(Vector2(1080,599))
	await key(KEY_3)
	check(Game.state.deck == ["test_reward_02","test_reward_03"] and Game.state.credits == 2000,"Keyboard selects after reload without repeating credits")
	# Expanded deck: empty first-turn hand must stay empty after a view restore.
	Game.state.activeEventId = "E02"
	Game.state.currentPlaceId = "junkyard"
	Game.state.battleReward = {}
	Game.state.battleId = "B02"
	Game.state.currentScene = "battle"
	Game.initialize_combat()
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	model.enemies[0].hp = 30
	model.enemies[0].maxHp = 30
	model.draw_cards()
	for uid in model.hand.duplicate(): model.play_card(uid,0)
	Game.commit_combat(model)
	Game.checkpoint()
	await idle()
	check(app.view.model.hand.is_empty() and app.view.model.draw_pile.size() == 2 and app.view.model.discard_pile.size() == 5,"First-turn empty hand restores without extra draw")
	check(Game.save_game() and Game.load_game(),"Expanded empty-hand snapshot survives disk roundtrip")
	await idle()
	check(app.view.cards.is_empty() and app.view.model.hand.is_empty(),"Reload keeps the empty hand")
	print("REWARD VISUAL: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
