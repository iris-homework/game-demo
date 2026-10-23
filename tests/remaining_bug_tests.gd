extends Node
## Headless only, in a copied project with an isolated user directory.
var checks := 0
var failures := 0
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("REMAINING BUGS: " + message)

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func write_state(path: String, value: Dictionary) -> void:
	write_text(path, JSON.stringify(value))

func fresh(path: String) -> void:
	Game.save_enabled = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.save_path = output.path_join(path)
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.page = "map"

func test_backup() -> void:
	fresh("recovery.json")
	check(Game.save_game(), "first checkpoint saves")
	var first := FileAccess.get_file_as_string(Game.save_path)
	Game.state.credits += 10
	var event_rng_state := Game.event_refresh_rng.state
	var market_rng_state := Game.black_market_model.rng.state
	check(Game.save_game(), "second checkpoint saves")
	check(Game.event_refresh_rng.state == event_rng_state and Game.black_market_model.rng.state == market_rng_state, "backup validation does not consume adventure RNG")
	check(FileAccess.get_file_as_string(Game.save_path + ".bak") == first, "valid previous main rotates into backup")
	write_text(Game.save_path, "broken JSON")
	Game.state = {}
	check(Game.load_game(), "broken main recovers from valid backup")
	Game.state.credits += 20
	check(Game.save_game(), "recovered adventure saves new progress")
	check(FileAccess.get_file_as_string(Game.save_path + ".bak") == first, "saving after recovery preserves known good backup")
	var current = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	check(current.credits == Game.config.initialCredits + 20, "new main contains recovered and advanced state")
	# Syntactically valid but semantically invalid data must also not replace backup.
	current.currentDay = 99
	write_state(Game.save_path, current)
	check(Game.save_game(), "invalid schema state can be replaced from valid live state")
	check(FileAccess.get_file_as_string(Game.save_path + ".bak") == first, "semantically invalid main never rotates into backup")
	# A blocked staging path must fail before either valid checkpoint is replaced.
	var main_before := FileAccess.get_file_as_string(Game.save_path)
	DirAccess.make_dir_absolute(Game.save_path + ".bak.tmp")
	write_text((Game.save_path + ".bak.tmp").path_join("blocker"), "test")
	Game.state.credits += 1
	check(not Game.save_game(), "backup staging failure is reported")
	check(FileAccess.get_file_as_string(Game.save_path) == main_before and FileAccess.get_file_as_string(Game.save_path + ".bak") == first, "backup staging failure preserves both checkpoints")
	DirAccess.remove_absolute((Game.save_path + ".bak.tmp").path_join("blocker"))
	DirAccess.remove_absolute(Game.save_path + ".bak.tmp")
	check(Game.save_game(), "retry after backup staging failure succeeds")
	check(FileAccess.get_file_as_string(Game.save_path + ".bak") == main_before, "successful retry rotates valid main")
	fresh("blocked-backup.json")
	check(Game.save_game(), "backup rename fixture saves original main")
	main_before = FileAccess.get_file_as_string(Game.save_path)
	DirAccess.make_dir_absolute(Game.save_path + ".bak")
	write_text((Game.save_path + ".bak").path_join("blocker"), "test")
	Game.state.credits += 10
	check(not Game.save_game(), "backup replacement failure is reported")
	check(FileAccess.get_file_as_string(Game.save_path) == main_before, "backup replacement failure preserves original main")
	# Force failure at the final main rename, with an existing good recovery copy.
	fresh("blocked-main")
	DirAccess.make_dir_absolute(Game.save_path)
	write_text(Game.save_path.path_join("blocker"), "test")
	write_state(Game.save_path + ".bak", Game.state)
	var backup_before := FileAccess.get_file_as_string(Game.save_path + ".bak")
	check(not Game.save_game(), "final main replacement failure is reported")
	check(FileAccess.get_file_as_string(Game.save_path + ".bak") == backup_before, "main replacement failure preserves existing backup")

func test_card_validation() -> void:
	fresh("legacy-combat.json")
	Game.state.activeEventId = "E02"
	Game.state.currentPlaceId = Game.battles.B02.placeId
	Game.enter_node("battle")
	Game.state.battleStart = {}
	var legacy := Game.state.duplicate(true)
	check(Game.valid_save(legacy), "legacy combat without opening remains valid")
	var id: String = legacy.combat.instances.values()[0]
	for value in [7, "broken", null, [], {}]:
		var damaged := legacy.duplicate(true)
		damaged.combat.cardCatalog[id] = value
		check(not Game.valid_save(damaged), "reject malformed frozen card: " + str(value))
	for value in [7, "broken", [null], [{"type":7}], [{"type":"damage", "amount":"broken"}]]:
		var damaged := legacy.duplicate(true)
		damaged.combat.cardCatalog[id].effects = value
		check(not Game.valid_save(damaged), "reject malformed frozen effects: " + str(value))
	for field in ["cost", "description"]:
		var damaged := legacy.duplicate(true)
		damaged.combat.cardCatalog[id].erase(field)
		check(not Game.valid_save(damaged), "reject missing modern card presentation field: " + field)
	var historical := legacy.duplicate(true)
	historical.combat.cardCatalog[id].description = "历史说明"
	historical.combat.cardCatalog[id].cost = 2
	historical.combat.cardCatalog[id].effects = [{"type":"damage", "amount":17}]
	check(Game.valid_save(historical), "valid frozen values need not match today's card definitions")
	var prototype := legacy.duplicate(true)
	prototype.combat.cardCatalog[id] = Game.prototype_rules.cards.test_attack.duplicate(true)
	check(Game.valid_save(prototype), "nullable legacy cost and missing rarity remain compatible")
	write_state(Game.save_path + ".bak", historical)
	var damaged := legacy.duplicate(true)
	damaged.combat.cardCatalog[id] = 7
	write_state(Game.save_path, damaged)
	Game.state = {}
	check(Game.load_game() and Game.state.combat.cardCatalog[id] is Dictionary and Game.state.combat.cardCatalog[id].description == "历史说明", "malformed main falls back before model or UI consumption")

func text_in(node: Node) -> String:
	var text := str(node.text) if node is Label else ""
	for child in node.get_children(): text += text_in(child)
	return text

func test_result_text() -> void:
	fresh("opening.json")
	Game.new_game()
	Game.skip_dialogue(Game.revision)
	Game.choose(0, Game.revision)
	Game.skip_dialogue(Game.revision)
	check(Game.state.currentDay == 1 and Game.state.currentScene == "result", "opening finishes on day one")
	var result := preload("res://scenes/result.tscn").instantiate()
	add_child(result)
	check("不消耗时间" in text_in(result) and not "时间推进1天" in text_in(result), "opening result displays no time cost")
	result.free()

func motion(view: Control, point: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	view._input(event)

func begin_drag(view: Control) -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(720, 440)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._input(event)
	motion(view, Vector2(750, 470), true)
	check(view._drag_pending and view._dragging, "map begins normal held drag")

func test_map_modal() -> void:
	fresh("map.json")
	var app := preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	var view: Control = app.view
	view._window_active = true
	view.set_map_zoom(1.5)
	for kind in ["debug", "deck", "technology", "exit", "console"]:
		begin_drag(view)
		match kind:
			"debug": app.toggle_debug()
			"deck": app.open_current_deck()
			"technology": app.open_technology_loadout()
			"exit": app.open_exit_confirmation("menu")
			"console": app.open_card_console()
		check(not view._drag_pending and not view._dragging, kind + " modal cancels map drag before suspension")
		match kind:
			"debug": app.close_debug()
			"deck": app.close_current_deck()
			"technology": app.close_technology_loadout()
			"exit": app.close_exit_confirmation()
			"console": app.close_card_console()
		var pan: Vector2 = view._pan
		motion(view, Vector2(800, 510), false)
		check(view._pan == pan and not view._drag_pending, kind + " close cannot resume drag after missed release")
		await get_tree().process_frame
	begin_drag(view)
	var pan: Vector2 = view._pan
	motion(view, Vector2(820, 520), false)
	check(view._pan == pan and not view._drag_pending, "motion without left mask cancels stale drag")
	begin_drag(view)
	motion(view, Vector2(810, 510), true)
	check(view._dragging, "normal held drag continues after cancellation")
	app.free()

func _ready() -> void:
	if not "remaining-bugs" in OS.get_user_data_dir():
		push_error("Run in isolated remaining-bugs project")
		get_tree().quit(2)
		return
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(2))
	output = OS.get_environment("QA_OUT_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	Game.meta_path = output.path_join("meta.json")
	test_backup()
	test_card_validation()
	test_result_text()
	await test_map_modal()
	Game.save_enabled = false
	write_text(output.path_join("result.json"), JSON.stringify({"checks":checks, "failures":failures}))
	print("REMAINING BUGS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
