extends Node
## Actual library and battle views in a copied project with disposable QA saves.
const AudioCleanup = preload("res://scripts/combat/audio_cleanup.gd")
var app: Control
var output := ""
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("RESOURCE VISUAL: " + message)

func idle() -> void:
	var deadline := Time.get_ticks_msec() + 25000
	while Game.battle_busy or Game.transition_locked:
		await get_tree().process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("RESOURCE VISUAL: timed out waiting for battle")
			get_tree().quit(2)
			return
	await get_tree().process_frame
	await get_tree().process_frame

func shot(name: String) -> void:
	# Force the completed viewport draw even when another application obscures QA.
	await get_tree().process_frame
	RenderingServer.force_draw()
	var path := output.path_join(name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Capture " + name)
	captures.append(path)

func install_hand(form: String, initial_energy: int = 0) -> void:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	rules.shuffleInitialDeck = false
	rules.deck = ["noren_44", "noren_45"]
	for index in 12: rules.deck.append("noren_01")
	var model := CombatModel.new()
	model.initialize("B02", 100, 100, rules, [Game.enemy_catalog[Game.battles.B02.enemyIds[0]]], Game.card_catalog)
	model.stance = form
	model.opening_draw_done = true
	model.energy = initial_energy
	for index in 2:
		var uid := "card_%03d" % index
		model.draw_pile.erase(uid)
		model.hand.append(uid)
	Game.commit_combat(model)
	app.swap_view()
	await idle()

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in OS.get_user_data_dir().to_lower() or DisplayServer.get_name() == "headless":
		push_error("RESOURCE VISUAL requires GPU, absolute QA_OUT_DIR and isolated QA user directory")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	Game.state = Game.initial_state()
	Game.state.deck = ["noren_44", "noren_45"]
	Game.page = "menu"
	var adventure: Dictionary = Game.state.duplicate(true)
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await idle()
	Game.open_card_library()
	await idle()
	app.view.filters = {"rarity":"all", "cost":"0", "type":"skill"}
	app.view.refresh_library()
	await idle()
	check(app.view.card_views.map(func(card): return card.data.id) == ["noren_45", "noren_44"], "Owned library displays both added cards through existing filters")
	check(app.view.card_views.all(func(card): return card.face_texture != null and card.preview_only), "Library uses both real PNGs and read-only card controls")
	await shot("library-resource-cards")
	print("RESOURCE VISUAL stage: library captured")
	app.view.close_library()
	await idle()
	Game.start_training("B02")
	await idle()
	print("RESOURCE VISUAL stage: training entered")
	for form in ["melee", "ranged"]:
		await install_hand(form)
		check(app.view.model.energy == 0 and app.view.energy_value.text == "0 / 3" and app.view.model.hand.size() == 2, form + ": both zero-cost cards are available in an empty-energy hand")
		check(app.view.cards.values().all(func(card): return card.face_texture != null), form + ": both actual card PNGs load")
		await shot(form + "-empty-energy-hand")
		app.view.select_card("card_000")
		app.view.play_selected(0)
		await idle()
		check(app.view.model.energy == 2 and app.view.energy_value.text == "2 / 3" and app.view.model.discard_pile == ["card_000"], form + ": supply plays from zero, updates the real HUD and enters ordinary discard")
		check(app.view.model.exhaust_pile.is_empty(), form + ": supply does not exhaust")
		app.view.select_card("card_001")
		app.view.play_selected(0)
		await idle()
		check(app.view.model.energy == 2 and app.view.model.hand.size() == 2 and app.view.model.exhaust_pile == ["card_001"], form + ": calculation draws two cards at zero cost and exhausts itself")
		check(Game.valid_combat(app.view.model.snapshot()), form + ": animated cards preserve a valid snapshot")
		await shot(form + "-after-resource-cards")
	await install_hand("ranged", 3)
	app.view.select_card("card_000")
	app.view.play_selected(0)
	await idle()
	check(app.view.model.energy == 5 and app.view.energy_value.text == "5 / 3" and app.view.energy_panel.is_overclocked(), "Existing overclocked HUD shows all five energy without clipping or changing per-turn recovery")
	check(Game.valid_combat(app.view.model.snapshot()), "Supply above normal recovery remains save-valid")
	await shot("overclocked-five-energy")
	Game.menu()
	await idle()
	check(not Game.training_mode and Game.state == adventure, "Exiting disposable training restores the original adventure")
	check(await AudioCleanup.release(app, get_tree()), "Audio playback references drain before closing QA")
	app.queue_free()
	app = null
	await get_tree().process_frame
	await get_tree().process_frame
	FileAccess.open(output.path_join("visual-results.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"physicalInput":false,"inputMethod":"existing view selection and play methods; no OS mouse movement"}, "\t"))
	print("RESOURCE VISUAL: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
