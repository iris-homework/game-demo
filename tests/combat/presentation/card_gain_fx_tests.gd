extends "res://tests/combat/cards/noren_cards_visual.gd"
## Headless presentation-contract checks; never call inherited pointer/shot helpers.
var observations: Array = []
var seen: Dictionary = {}
var case_results: Array = []
var attached_correctly := true
var draw_precedes_hand := true

func watch_added_node(node: Node) -> void:
	var script = node.get_script()
	if script != null and script.resource_path == "res://scripts/combat/card_gain_fx.gd":
		# ready fires before add_child returns and deal_hand creates its card views.
		node.ready.connect(func(): sample_fx(app.view))

func sample_fx(view: Control) -> void:
	for effect in get_tree().get_nodes_in_group("card_gain_fx"):
		var instance_id := effect.get_instance_id()
		if seen.has(instance_id): continue
		seen[instance_id] = true
		observations.append({"kind":effect.kind,"amount":effect.amount})
		attached_correctly = attached_correctly and effect.get_parent() == view.stage.player
		if effect.kind == "draw":
			draw_precedes_hand = draw_precedes_hand and view.cards.size() < view.model.hand.size()

func reset_observations() -> void:
	observations.clear()
	seen.clear()
	attached_correctly = true
	draw_precedes_hand = true

func observe_idle(view: Control, committed: Dictionary = {}) -> void:
	var started := Time.get_ticks_msec()
	var model_unchanged := true
	while Game.battle_busy or Game.transition_locked:
		sample_fx(view)
		if not committed.is_empty(): model_unchanged = model_unchanged and view.model.snapshot() == committed
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > 20000:
			check(false,"Presentation timed out")
			get_tree().quit(2)
			return
	# Effects may finish after the existing card/stance animation unlocks.
	while not get_tree().get_nodes_in_group("card_gain_fx").is_empty():
		sample_fx(view)
		if not committed.is_empty(): model_unchanged = model_unchanged and view.model.snapshot() == committed
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > 22000:
			check(false,"Gain effects failed to clean themselves up")
			get_tree().quit(2)
			return
	if not committed.is_empty():
		check(model_unchanged and view.model.snapshot() == committed,"Presentation preserves the committed model")
	await get_tree().process_frame

func expect_effects(expected: Array, title: String) -> void:
	check(observations == expected,title + ": observed actual gain amounts")
	check(attached_correctly,title + ": effects follow the player actor")
	if expected.any(func(effect): return effect.kind == "draw"):
		check(draw_precedes_hand,title + ": draw cue starts before replenishing hand views")
	case_results.append({"case":title,"expected":expected.duplicate(true),"observed":observations.duplicate(true)})

func exercise(title: String, expected: Array, target: int = -1) -> void:
	var view: Control = app.view
	reset_observations()
	view.select_card("card_000")
	view.play_selected(target)
	sample_fx(view)
	check(Game.battle_busy,title + ": successful card locks input")
	if expected.any(func(effect): return effect.kind == "block"):
		check(observations.any(func(effect): return effect.kind == "block"),title + ": shield begins immediately on successful play")
	var committed: Dictionary = view.model.snapshot()
	view.select_card("card_001")
	view.play_selected(0)
	view.end_turn_pressed()
	check(view.model.snapshot() == committed,title + ": busy lock rejects repeated play and end turn")
	await observe_idle(view,committed)
	expect_effects(expected,title)
	check(view.cards.size() == view.model.hand.size(),title + ": final hand views match the model")
	check(get_tree().get_nodes_in_group("card_gain_fx").is_empty(),title + ": gain effects clean up")

func limit_draw_pile(amount: int) -> void:
	var model: CombatModel = app.view.model
	while model.draw_pile.size() > amount:
		model.exhaust_pile.append(model.draw_pile.pop_back())
	app.view.commit()

func _ready() -> void:
	output = "res://artifacts/qa/card-gain-fx-2026-10-23/"
	Game.save_enabled = false
	Game.save_path = "user://card_gain_fx_unused.json"
	Game.meta_path = "user://card_gain_fx_meta_unused.json"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state = Game.initial_state()
	get_tree().node_added.connect(watch_added_node)
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	reset_observations()
	Game.start_training("B04")
	await idle()
	await observe_idle(app.view)
	expect_effects([],"Opening hand does not trigger card-play draw effects")
	await install_hand([2,1])
	await exercise("护身",[{"kind":"block","amount":5}])
	await install_hand([4,1])
	await exercise("拉开距离 shield and stance",[{"kind":"block","amount":6}])
	await install_hand([7,1])
	await exercise("快速判断",[{"kind":"draw","amount":2}])
	await install_hand([3,1],"ranged")
	await exercise("贴近 stance entry draw",[{"kind":"draw","amount":2}])
	await install_hand([9,1],"ranged")
	await exercise("切入斩 attack then stance draw",[{"kind":"draw","amount":2}],0)
	await install_hand([16,1])
	await exercise("后跳斩 melee draw",[{"kind":"draw","amount":2}],0)
	await install_hand([16,1],"ranged")
	await exercise("后跳斩 ranged condition has no draw",[],0)
	await install_hand([5,1])
	await exercise("Ammo-only card has no gain cue",[])
	await install_hand([7,1])
	limit_draw_pile(0)
	await exercise("Draw request with no drawable cards",[])
	await install_hand([7,1])
	limit_draw_pile(1)
	await exercise("Draw cue uses the one card actually drawn",[{"kind":"draw","amount":1}])
	await install_hand([7,1])
	app.view.model.energy = 0
	app.view.commit()
	reset_observations()
	var failed_before: Dictionary = app.view.model.snapshot()
	app.view.select_card("card_000")
	app.view.play_selected(-1)
	await idle()
	await observe_idle(app.view)
	check(app.view.model.snapshot() == failed_before and not Game.battle_busy,"Rejected card preserves model and input availability")
	expect_effects([],"Rejected draw card has no cue")
	await install_hand([2,1])
	# Frozen-catalog fixture: exercise two supported effects on one committed card.
	app.view.model.card_catalog.noren_02.effects = [{"type":"block","amount":3},{"type":"draw","amount":1}]
	app.view.commit()
	await exercise("Combined block and draw fixture",[{"kind":"block","amount":3},{"kind":"draw","amount":1}])
	await install_hand([2,1])
	reset_observations()
	app.view.end_turn_pressed()
	await observe_idle(app.view)
	check(app.view.model.turn == 2 and app.view.cards.size() == app.view.model.hand.size(),"Next-turn hand replenishes normally")
	expect_effects([],"Next-turn draw has no card-play cue")
	await install_hand([2,1])
	app.view.select_card("card_000")
	app.view.play_selected(-1)
	# Teardown after card flight finishes, while its longer cosmetic cue is alive.
	await idle()
	var live_effects := get_tree().get_nodes_in_group("card_gain_fx")
	check(not live_effects.is_empty(),"Lifecycle test begins with an active shield cue")
	var references: Array = live_effects.map(func(effect): return weakref(effect))
	app.view.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(get_tree().get_nodes_in_group("card_gain_fx").is_empty() and references.all(func(reference): return reference.get_ref() == null),"Battle-view teardown frees active gain effects")
	Game.battle_busy = false
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path),"Presentation checks never write save or meta files")
	var result := {"checks":checks,"failures":failures,"headless":true,"cases":case_results,"limitations":["No rendered-image or human visual review","No physical input or menu-exit interaction; teardown checks node lifecycle"]}
	var file := FileAccess.open(output + "result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("CARD GAIN FX: %d checks, %d failures" % [checks,failures])
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
