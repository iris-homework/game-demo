extends "res://tests/combat/interaction/interaction_visual.gd"
## Explicit in-memory fixtures. Run graphically and sequentially; --record stores
## viewport frames in memory during playback and writes them only after all cases.
const DRAW_SCRIPT = preload("res://scripts/combat/draw_fx.gd")
const SHUFFLE_SCRIPT = preload("res://scripts/combat/shuffle_fx.gd")
var recycle_events: Array = []
var shuffle_ids: Array[int] = []
var count_history: Array[Vector2i] = []
var record_frames := false
var capture_active := false
var captured_images: Array[Image] = []
var captured_names: Array[String] = []
var capture_tick := 0
var case_name := ""

func idle() -> void:
	var started := Time.get_ticks_msec()
	while Game.transition_locked or Game.battle_busy:
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > 20000:
			verify(false, "Combat timed out")
			get_tree().quit(1)
			return
	await get_tree().process_frame

func _process(_delta: float) -> void:
	if not is_instance_valid(app) or app.shown_page != "battle": return
	var view = app.view
	if not is_instance_valid(view.draw_count): return
	var pair := Vector2i(int(view.draw_count.text), int(view.discard_count.text))
	if count_history.is_empty() or count_history.back() != pair:
		count_history.append(pair)
	if is_instance_valid(view.shuffle_fx):
		var id: int = view.shuffle_fx.get_instance_id()
		if not id in shuffle_ids: shuffle_ids.append(id)

func capture_frame() -> void:
	if not record_frames or not capture_active: return
	capture_tick += 1
	if capture_tick % 2 != 0: return
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 600, Image.INTERPOLATE_LANCZOS)
	captured_images.append(img)
	captured_names.append("%s-%04d.png" % [case_name, capture_tick])

func install_fixture(hand_ids: Array, draw_size: int, discard_size: int, recycle: bool = true) -> void:
	await idle()
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	rules.deck = hand_ids.duplicate()
	for i in draw_size + discard_size: rules.deck.append("noren_01")
	rules.shuffleInitialDeck = false
	rules.recycleDiscardWhenEmpty = recycle
	rules.handSize = 5
	var enemies: Array = [{
		"id":"shuffle_fixture", "displayName":"洗牌测试对手", "maxHp":200,
		"battlePortraitAssetId":"", "intentSequence":[{"type":"attack", "amount":0, "hits":1}]
	}]
	var model := CombatModel.new()
	model.initialize("B04", 100, 100, rules, enemies, Game.card_catalog)
	model.draw_pile.clear()
	model.opening_draw_done = true
	for i in rules.deck.size():
		var uid := "card_%03d" % i
		if i < hand_ids.size(): model.hand.append(uid)
		elif i < hand_ids.size() + draw_size: model.draw_pile.append(uid)
		else: model.discard_pile.append(uid)
	Game.commit_combat(model)
	app.swap_view()
	await idle()
	recycle_events.clear()
	count_history.clear()
	app.view.model.discard_recycled.connect(func(amount: int, uid: String):
		recycle_events.append({"amount":amount, "uid":uid}))
	verify(app.view.cards.size() == hand_ids.size(), "Fixture restores only its explicit hand")
	verify(app.view.pending_recycles.is_empty() and not is_instance_valid(app.view.shuffle_fx),
		"Fixture restoration queues no shuffle")

func draw_fixture(view, amount: int) -> void:
	# Exercise the same synchronous model commit and awaited deal as turn/skill
	# presentation, without an unrelated enemy animation obscuring the capture.
	view.set_busy(true)
	view.model.draw_cards(amount)
	view.commit()
	await view.deal_hand(true)
	view.refresh_counts()
	view.set_busy(false)

func wait_shuffle(view) -> bool:
	var started := Time.get_ticks_msec()
	while not is_instance_valid(view.shuffle_fx):
		if Time.get_ticks_msec() - started > 12000:
			verify(false, case_name + ": shuffle never started")
			return false
		await get_tree().process_frame
	return true

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame

func inspect_shuffle(view, amount: int, previous_cards: int, retained_discard: int = 0) -> void:
	if not await wait_shuffle(view): return
	var fx = view.shuffle_fx
	var frozen: Dictionary = view.model.snapshot()
	var saved: Dictionary = Game.state.combat.duplicate(true)
	var count_before := int(view.discard_count.text)
	var observed := {"transferred":0, "landed":0}
	fx.transferred.connect(func(count: int): observed.transferred += count)
	fx.landed.connect(func(): observed.landed += 1)
	verify(fx.arrived == 0 and count_before == amount + retained_discard,
		case_name + ": discard count stays at source before first arrival")
	verify(fx.origin.x > fx.destination.x and fx.visual_count == mini(amount, 12),
		case_name + ": card backs fly from right discard pile to left draw pile")
	verify(absf(absf(fx.angle_at(0.5, 0)) - PI / 2.0) < 0.01,
		case_name + ": card is horizontal at the arc crest")
	var follows_arc := true
	for t in [0.25, 0.5, 0.75]:
		var tangent: Vector2 = fx.path_at(t + 0.001, 0) - fx.path_at(t - 0.001, 0)
		var long_edge := Vector2.DOWN.rotated(fx.angle_at(t, 0))
		follows_arc = follows_arc and absf(long_edge.dot(tangent.normalized())) > 0.999
	verify(follows_arc, case_name + ": card long edge follows the curved flight direction")
	verify(absf(fx.angle_at(0.0, 0)) < 0.01 and absf(fx.angle_at(1.0, 0)) < 0.01,
		case_name + ": cards return upright at the pile endpoints")
	verify(view.cards.size() == previous_cards and int(view.draw_count.text) == 0,
		case_name + ": existing deck is exhausted before the shuffle")
	var old_draws_landed := true
	for child in view.get_children():
		if child.get_script() == DRAW_SCRIPT and child.progress < 1.0: old_draws_landed = false
	verify(old_draws_landed, case_name + ": earlier draw flights land before recycling")
	verify(Game.battle_busy and view.end_button.disabled, case_name + ": shuffle holds the input lock")
	view.end_turn_pressed()
	view.select_card(view.model.hand[0])
	view.show_pile("抽牌堆", view.model.draw_pile)
	view.show_cyberware()
	await key(KEY_1)
	await key(KEY_ESCAPE)
	await click(view.end_button.get_global_rect().get_center())
	verify(view.selected_uid.is_empty() and not is_instance_valid(view.pile_overlay) and Game.page == "battle",
		case_name + ": repeated turn, selection, keyboard and modal input are blocked")
	verify(view.model.snapshot() == frozen and Game.state.combat == saved,
		case_name + ": attempted input preserves the already committed result")
	while is_instance_valid(fx) and fx.elapsed < 0.32 + float(fx.visual_count - 1) * 0.0175:
		await get_tree().process_frame
	await shot(case_name + "-midflight")
	var frozen_throughout := true
	var no_early_draw := true
	var exact_counts := true
	while is_instance_valid(view.shuffle_fx):
		frozen_throughout = frozen_throughout and view.model.snapshot() == frozen and Game.state.combat == saved
		no_early_draw = no_early_draw and view.cards.size() == previous_cards
		exact_counts = exact_counts and int(view.draw_count.text) == int(observed.transferred)
		exact_counts = exact_counts and int(view.discard_count.text) == count_before - int(observed.transferred)
		await get_tree().process_frame
	verify(frozen_throughout, case_name + ": animation never mutates model or saved snapshot")
	verify(no_early_draw, case_name + ": new hand cards wait until final shuffle arrival")
	verify(exact_counts, case_name + ": counters change by exact landed transfer amounts")
	verify(observed.transferred == amount and observed.landed == 1,
		case_name + ": all represented cards transfer once and landed fires once")
	await idle()
	await settle(0.25)
	verify(not is_instance_valid(view.shuffle_fx) and view.pending_recycles.is_empty(),
		case_name + ": active shuffle and queued recycle clear at completion")
	verify(view.get_children().filter(func(child): return child.get_script() == SHUFFLE_SCRIPT).is_empty(),
		case_name + ": transient shuffle node is freed")
	verify(view.model.snapshot() == frozen and Game.state.combat == saved,
		case_name + ": drawing presentation preserves the committed result")
	verify(int(view.draw_count.text) == view.model.draw_pile.size()
		and int(view.discard_count.text) == view.model.discard_pile.size(),
		case_name + ": final pile counters match model")
	verify(not Game.battle_busy and not view.end_button.disabled and view.cards.size() == view.model.hand.size(),
		case_name + ": hand interaction resumes after all flights")
	verify(count_history.all(func(pair): return pair.x >= 0 and pair.y >= 0),
		case_name + ": no negative pile count appears")
	await shot(case_name + "-settled")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://shuffle_visual_unused.json"
	Game.meta_path = "user://shuffle_visual_meta_unused.json"
	output = "res://artifacts/qa/shuffle-2026-10-20/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suffix="): output += arg.trim_prefix("--suffix=") + "/"
	DirAccess.make_dir_recursive_absolute(output)
	record_frames = OS.get_cmdline_user_args().has("--record")
	if record_frames: RenderingServer.frame_post_draw.connect(capture_frame)
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.start_training("B04")
	await idle()

	await install_fixture([], 0, 7)
	case_name = "empty-deck"
	capture_active = true
	var view = app.view
	draw_fixture(view, 5)
	await inspect_shuffle(view, 7, 0)
	capture_active = false
	verify(recycle_events.size() == 1 and recycle_events[0].amount == 7,
		"Empty deck emits one exact recycle event")
	verify(view.model.hand.size() == 5 and view.model.draw_pile.size() == 2,
		"Empty deck refill draws five and retains two cards")

	await install_fixture([], 2, 7)
	case_name = "mid-deal"
	capture_active = true
	view = app.view
	draw_fixture(view, 5)
	await inspect_shuffle(view, 7, 2)
	capture_active = false
	verify(recycle_events.size() == 1 and recycle_events[0].uid == view.model.hand[2],
		"Mid-deal event identifies the first recycled card after two old-deck cards")
	verify(view.model.hand.slice(0, 2) == ["card_001", "card_000"] and view.model.draw_pile.size() == 4,
		"Mid-deal keeps the old deck order and only draws three recycled cards")

	await install_fixture(["noren_07", "noren_01"], 0, 4)
	case_name = "noren-draw-skill"
	capture_active = true
	view = app.view
	view.select_card("card_000")
	view.play_selected(-1)
	await inspect_shuffle(view, 4, 1, 1)
	capture_active = false
	verify(recycle_events.size() == 1 and recycle_events[0].amount == 4,
		"Official Quick Judgment skill recycles only its four prior discards")
	verify(view.model.discard_pile == ["card_000"] and not "card_000" in view.model.hand
		and not "card_000" in view.model.draw_pile,
		"The skill being played never joins its own recycled draw")
	verify(view.model.hand.size() == 3 and view.model.energy == 2 and view.model.draw_pile.size() == 2,
		"Official skill pays one energy and draws exactly two cards")

	var restored: Dictionary = view.model.snapshot()
	var shuffle_count := shuffle_ids.size()
	view.commit()
	app.swap_view()
	await idle()
	await settle(0.20)
	view = app.view
	verify(view.model.snapshot() == restored and view.cards.size() == restored.hand.size(),
		"Restoring completed combat preserves the same cards and snapshot")
	verify(shuffle_ids.size() == shuffle_count and view.pending_recycles.is_empty()
		and not is_instance_valid(view.shuffle_fx), "Restore never replays transient recycle events")

	await install_fixture([], 2, 7, false)
	case_name = "recycle-disabled"
	view = app.view
	shuffle_count = shuffle_ids.size()
	draw_fixture(view, 5)
	await idle()
	verify(recycle_events.is_empty() and shuffle_ids.size() == shuffle_count,
		"Disabled recycling emits no event and creates no shuffle")
	verify(view.model.hand.size() == 2 and view.model.draw_pile.is_empty() and view.model.discard_pile.size() == 7,
		"Disabled recycling draws only available cards and keeps discards intact")
	verify(view.draw_count.text == "0" and view.discard_count.text == "7" and view.pending_recycles.is_empty(),
		"Disabled recycling leaves exact settled counters and no queued work")

	await install_fixture([], 0, 20)
	case_name = "large-pile"
	capture_active = true
	view = app.view
	draw_fixture(view, 5)
	await inspect_shuffle(view, 20, 0)
	capture_active = false
	verify(view.model.draw_pile.size() == 15 and view.model.hand.size() == 5,
		"Twelve representative flights transfer all twenty cards without loss")
	if record_frames:
		RenderingServer.frame_post_draw.disconnect(capture_frame)
		DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
		for i in captured_images.size():
			captured_images[i].save_png(output.path_join("frames").path_join(captured_names[i]))
	print("SHUFFLE VISUAL: %d checks, %d failures; %d recorded frames; %s" % [
		checks, failures, captured_images.size(), output])
	get_tree().quit(0 if failures == 0 else 1)
