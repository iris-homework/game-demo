extends Node
## Real battle animations/counters, isolated save paths, no window or pointer use.
class CountProbe extends "res://scripts/battle.gd":
	var recording := false
	var history: Array = []
	var draws: Array = []
	var shuffles: Array = []
	var reveal_counts := Vector2i(-99,-99)
	var phase_snapshot_stable := true

	func render_counts() -> void:
		super.render_counts()
		if recording:
			var pair := Vector2i(shown_draw_count,shown_discard_count)
			if history.is_empty() or history.back() != pair: history.append(pair)

	func on_card_drawn() -> void:
		super.on_card_drawn()
		if recording: draws.append(Vector2i(shown_draw_count,shown_discard_count))

	func animate_shuffle(amount: int) -> void:
		if recording: shuffles.append({"amount":amount,"before":Vector2i(shown_draw_count,shown_discard_count)})
		await super.animate_shuffle(amount)
		if recording: shuffles.back().after = Vector2i(shown_draw_count,shown_discard_count)

	func present_encounter_phase() -> void:
		var changing: bool = model.encounter_phase != shown_encounter_phase
		var committed: Dictionary = model.snapshot()
		await super.present_encounter_phase()
		if recording and changing:
			reveal_counts = Vector2i(shown_draw_count,shown_discard_count)
			phase_snapshot_stable = phase_snapshot_stable and model.snapshot() == committed

var checks := 0
var failures: Array[String] = []
var observations: Array = []
var output := "/tmp/midnight-dancer-counts-qa"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("DANCER COUNTS: " + message)

func idle(view: Control) -> void:
	var started := Time.get_ticks_msec()
	while Game.battle_busy or Game.transition_locked or not view.initialized:
		await get_tree().process_frame
		if Time.get_ticks_msec()-started > 20000:
			check(false,"battle animation timeout")
			get_tree().quit(2)
			return
	await get_tree().process_frame
	await get_tree().process_frame

func fixture(draw_size: int) -> CountProbe:
	Game.save_enabled = false
	Game.training_mode = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.pending_save_kind = ""
	Game.state = Game.initial_state()
	Game.start_training("B16")
	var m := CombatModel.new()
	m.restore(Game.state.combat)
	var uids: Array = m.instances.keys()
	m.hand = uids.slice(0,5)
	m.draw_pile = uids.slice(5,5+draw_size)
	m.discard_pile = uids.slice(5+draw_size)
	m.instances[m.hand[0]] = "noren_01"
	m.opening_draw_done = true
	m.enemies[0].hp = 1
	m.energy = 3
	check(Game.commit_combat(m) and Game.valid_combat(m.snapshot()),"valid phase-one fixture with draw " + str(draw_size))
	var view := CountProbe.new()
	add_child(view)
	await idle(view)
	check(view.shown_draw_count == draw_size and view.shown_discard_count == 5-draw_size,"fixture counters match explicit zones")
	return view

func run_case(draw_size: int, route: String) -> void:
	var title := route + "/draw" + str(draw_size)
	var view := await fixture(draw_size)
	view.recording = true
	if route == "counter":
		view.model.parry = 1
		view.shown_player_parry = 1
		view.end_turn_pressed()
	elif route == "console":
		Game.config.developmentMode = true
		Game.console_command("kill")
		view.resume_console_combat()
	else:
		view.select_card(view.model.hand[0])
		view.play_selected(0)
	await idle(view)
	check(view.model.encounter_phase == 2 and view.draws.size() == 5,title+": phase-two hand has five actual draw callbacks")
	check(view.history.all(func(p): return p.x >= 0 and p.y >= 0),title+": every animated pile count stays nonnegative")
	check(view.phase_snapshot_stable,title+": count synchronization never changes the committed model")
	if route != "console":
		var before_draw := draw_size+2
		var before_discard := 10-draw_size
		check(view.reveal_counts == Vector2i(before_draw,before_discard),title+": reveal accounts for both generated cards before dealing")
		var expected: Array = []
		for i in 5:
			if before_draw == 0:
				before_draw = before_discard
				before_discard = 0
			before_draw -= 1
			expected.append(Vector2i(before_draw,before_discard))
		check(view.draws == expected,title+": each draw has the exact expected draw/discard counts")
		check(view.shuffles.size() == (1 if draw_size+2 < 5 else 0),title+": shuffle is presented only when the draw pile actually empties")
		if not view.shuffles.is_empty():
			var shuffle: Dictionary = view.shuffles[0]
			check(shuffle.before == Vector2i(0,10-draw_size) and shuffle.after == Vector2i(10-draw_size,0),title+": shuffle transfers all counters once without double counting")
	else:
		check(view.reveal_counts == Vector2i(view.model.draw_pile.size()+5,view.model.discard_pile.size()),title+": restored console snapshot reconstructs its upcoming deal")
	check(view.shown_draw_count == view.model.draw_pile.size() and view.shown_discard_count == view.model.discard_pile.size(),title+": settled counters equal model zones")
	check(view.draw_count.text == str(view.shown_draw_count) and view.discard_count.text == str(view.shown_discard_count),title+": visible labels equal animated counters")
	check(view.model.instances.size() == 12 and Game.valid_combat(view.model.snapshot()),title+": no lost or duplicate card instances")
	observations.append({"case":title,"reveal":str(view.reveal_counts),"draws":view.draws.map(func(p): return str(p)),"history":view.history.map(func(p): return str(p)),"shuffleCount":view.shuffles.size()})
	view.recording = false
	if draw_size == 5 and route == "card":
		# Actually draw both special cards through normal recycling, then play them.
		view.set_busy(true)
		view.model.draw_cards(view.model.draw_pile.size()+view.model.discard_pile.size())
		await view.commit()
		await view.deal_hand(true)
		view.refresh_counts()
		view.set_busy(false)
		for color in ["black","white"]:
			var uid: String = "encounter_dancer_"+color+"_card"
			check(uid in view.model.hand and view.cards.has(uid),"recycling draws the actual "+color+" special card")
			var discard_before: int = view.shown_discard_count
			view.select_card(uid)
			view.play_selected(-1)
			await idle(view)
			check(uid in view.model.exhaust_pile and view.shown_discard_count == discard_before,color+": exhaust never increments the discard count")
			check(view.exhaust_button.text == "消耗 / 能力 %d" % view.model.exhaust_pile.size(),color+": exhaust counter reflects actual consumed cards")
		var saved := view.model.snapshot()
		view.queue_free()
		await get_tree().process_frame
		Game.state.combat = saved
		view = CountProbe.new()
		add_child(view)
		await idle(view)
		check(view.model.exhaust_pile.size() == 2 and view.shown_draw_count == view.model.draw_pile.size() and view.shown_discard_count == view.model.discard_pile.size(),"restored second-phase view does not add generated cards to counters again")
	view.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Game.battle_busy = false

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR") if not OS.get_environment("QA_OUT_DIR").is_empty() else output
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_path = output.path_join("checkpoint.json")
	Game.meta_path = output.path_join("meta.json")
	var cases := [[5,"card"],[0,"card"],[3,"card"],[1,"card"],[0,"counter"],[0,"console"]]
	if OS.get_cmdline_user_args().has("--repro"): cases = cases.slice(0,2)
	for c in cases: await run_case(c[0],c[1])
	var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	file.close()
	print("DANCER PILE COUNTS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
