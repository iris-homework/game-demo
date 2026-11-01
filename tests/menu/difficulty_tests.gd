extends Node
## Run only in a copied project with difficulty-settings-qa user storage.
## Uses actual menu callbacks and frozen combat snapshots; no system mouse input.
const BATTLES := ["B02", "B04", "B11", "B13", "B14", "B15", "B16"]
var checks := 0
var failures: Array[String] = []
var output := ""
var original_enemies: Dictionary
var original_battles: Dictionary

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures.append(title)
		push_error("DIFFICULTY: " + title)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func reset() -> void:
	if Game.training_mode: Game.restore_training()
	Game.save_enabled = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.page = "menu"
	Game.state = {}

func setup_battle(id: String, difficulty: String) -> CombatModel:
	reset()
	Game.state = Game.initial_state("", difficulty)
	var battle: Dictionary = Game.battles[id]
	Game.state.activeEventId = battle.eventId
	Game.state.activeNodeId = "battle"
	Game.state.currentPlaceId = battle.placeId
	Game.state.currentScene = "battle"
	Game.state.battleId = id
	Game.initialize_combat()
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	return model

func check_enemies(enemies: Array, ids: Array, bonus: int, title: String) -> void:
	check(enemies.size() == ids.size(), title + ": full formation")
	for index in mini(enemies.size(), ids.size()):
		var authored: Dictionary = Game.enemy_catalog[ids[index]]
		check(enemies[index].maxHp == int(authored.maxHp) + bonus and enemies[index].hp == enemies[index].maxHp,
			title + ": initial and maximum HP " + str(ids[index]))
		check(same(enemies[index].intentSequence, authored.intentSequence), title + ": attack patterns preserved " + str(ids[index]))

func test_formal_battles() -> void:
	for difficulty in ["normal", "advanced"]:
		for id in BATTLES:
			var model := setup_battle(id, difficulty)
			var battle: Dictionary = Game.battles[id]
			var bonus := (10 if battle.enemyIds.size() == 1 else 5) if difficulty == "advanced" else 0
			var title: String = difficulty + " " + id
			check_enemies(model.enemies, battle.enemyIds, bonus, title)
			check(Game.valid_save(Game.state), title + ": full opening save validates")
			check(model.player_hp == Game.state.maxHp and model.max_hp == Game.state.maxHp, title + ": player HP unchanged")
			var opening := model.snapshot()
			model.enemy_damage(0, 1, true)
			var damaged := model.snapshot()
			for repeat_index in 3:
				var restored := CombatModel.new()
				restored.restore(damaged)
				check(same(restored.snapshot(), damaged), title + ": repeated restore preserves exact HP and frozen rules " + str(repeat_index))
			Game.state.combat = damaged
			check(Game.restart_unfinished_battle(Game.state) and same(Game.state.combat, opening), title + ": restart uses original adjusted opening without stacking")
			if id == "B16":
				model.restore(opening)
				model.enemy_damage(0, 999, true)
				model.resolve_outcome()
				check(model.advance_encounter_phase() and model.encounter_phase == 2, title + ": first phase transitions")
				check_enemies(model.enemies, battle.phaseTwoEnemyIds, 5 if difficulty == "advanced" else 0, title + " second phase")
				check(Game.valid_combat(model.snapshot()), title + ": second phase frozen definitions validate")
				var phase_two := model.snapshot()
				var restored := CombatModel.new()
				restored.restore(phase_two)
				check(same(restored.snapshot(), phase_two), title + ": second phase restore does not add HP again")
	check(same(Game.enemy_catalog, original_enemies) and same(Game.battles, original_battles), "All difficulty runs leave authored catalogs unchanged")

func test_saves() -> void:
	reset()
	check(Game.initial_state().difficulty == "normal", "Default new run is normal")
	check(Game.initial_state("", "invalid").is_empty(), "Invalid new-run difficulty rejected")
	Game.state = Game.initial_state("", "advanced")
	check(Game.valid_save(Game.state), "Advanced new state validates")
	check(Game.save_game(), "Advanced state saves to isolated test path")
	Game.state = {}
	check(Game.load_game() and Game.state.difficulty == "advanced", "Advanced difficulty survives disk loading")
	var old := Game.state.duplicate(true)
	old.erase("difficulty")
	var migrated: Dictionary = Game.migrate_save(old)
	check(migrated.difficulty == "normal" and Game.valid_save(migrated), "Missing legacy mode migrates to valid normal adventure")
	check(not old.has("difficulty"), "Migration does not mutate source data")
	for value in ["hard", "", 1, null, true]:
		var invalid := Game.state.duplicate(true)
		invalid.difficulty = value
		check(not Game.valid_save(Game.migrate_save(invalid)), "Malformed saved difficulty rejected: " + str(value))
	# Frozen legacy combat stays numerically unchanged through additive migration.
	var model := setup_battle("B16", "normal")
	old = Game.state.duplicate(true)
	old.erase("difficulty")
	old.combat.profile.erase("difficulty")
	old.battleStart.profile.erase("difficulty")
	migrated = Game.migrate_save(old)
	check(Game.valid_save(migrated) and same(migrated.combat, old.combat), "Old Boss snapshot remains valid with exact original HP and rules")
	# Real save projection restarts an advanced in-progress battle from its opening.
	model = setup_battle("B04", "advanced")
	var opening := model.snapshot()
	model.enemy_damage(0, 7, true)
	Game.commit_combat(model)
	check(Game.save_game(), "Advanced unfinished battle saves")
	Game.state = {}
	check(Game.load_game() and Game.state.difficulty == "advanced" and same(Game.state.combat, opening), "Disk reload preserves advanced mode and original opening bonuses")

func test_training_isolation() -> void:
	reset()
	Game.state = Game.initial_state("", "advanced")
	var source := Game.state.duplicate(true)
	for choice in Game.training_enemy_choices():
		Game.start_enemy_training(choice.id)
		check(Game.training_mode and Game.state.combat.profile.get("difficulty", "normal") == "normal", "Practice remains normal from advanced adventure: " + str(choice.id))
		var battle: Dictionary = Game.battles[choice.battleId]
		check_enemies(Game.state.combat.enemies, battle.enemyIds, 0, "Practice " + str(choice.id))
		Game.menu()
		check(same(Game.state, source), "Practice restores advanced adventure exactly: " + str(choice.id))
	Game.start_tutorial()
	check(Game.tutorial_mode and Game.state.combat.profile.get("difficulty", "normal") == "normal", "Tutorial stays normal from advanced adventure")
	check(Game.state.combat.enemies[0].maxHp == 30, "Teaching fish stays at 30 HP")
	Game.menu()
	check(same(Game.state, source), "Tutorial restores advanced adventure exactly")

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func click(target: Button) -> void:
	var pos := target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	get_viewport().push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func test_menu() -> void:
	reset()
	# No checkpoint and no run must still show mode selection before creation.
	Game.save_path = "user://difficulty_menu_empty.json"
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu.new_button.pressed.emit()
	check(is_instance_valid(menu.confirm_dialog) and menu.confirm_dialog.visible and Game.state.is_empty(), "First new game opens mode selection without creating progress")
	if not is_instance_valid(menu.confirm_dialog):
		menu.queue_free()
		return
	check(menu.pending_difficulty == "normal", "New selection defaults to normal")
	var normal := menu.confirm_dialog.find_child("normal_mode", true, false) as Button
	var advanced := menu.confirm_dialog.find_child("advanced_mode", true, false) as Button
	check(normal != null and advanced != null, "Both mode choices appear")
	if normal == null or advanced == null:
		menu.queue_free()
		return
	check(normal.button_pressed and not advanced.button_pressed, "Normal mode is visibly selected by default")
	for expected in [menu.confirm_ok, normal, advanced, menu.confirm_cancel]:
		await key(KEY_TAB)
		check(get_viewport().gui_get_focus_owner() == expected, "Actual Tab input cycles inside selection: " + str(expected.name))
	var modal_buttons: Array[Node] = menu.confirm_dialog.find_children("*", "Button", true, false)
	var bounds: Array[Rect2] = []
	for button in modal_buttons:
		var box: Rect2 = button.get_global_rect()
		check(Rect2(Vector2.ZERO, Vector2(1440, 900)).encloses(box) and button.get_minimum_size().x <= box.size.x and button.get_minimum_size().y <= box.size.y, "Mode-selection control fits canvas and text: " + str(button.name))
		for prior in bounds:
			check(not box.intersects(prior), "Mode-selection controls do not overlap: " + str(button.name))
		bounds.append(box)
		check(button.get_node_or_null(button.focus_next) in modal_buttons and button.get_node_or_null(button.focus_previous) in modal_buttons, "Tab navigation stays in mode selection: " + str(button.name))
	for node in menu.ui_layer.find_children("*", "Button", true, false):
		check(node.disabled and node.focus_mode == Control.FOCUS_NONE, "Selection disables underlying menu: " + str(node.name))
	await click(advanced)
	check(menu.pending_difficulty == "advanced" and Game.state.is_empty(), "Selecting advanced does not create progress")
	check(advanced.button_pressed and not normal.button_pressed, "Advanced mode selection has exclusive visible feedback")
	await shot("new-game-advanced")
	await key(KEY_ESCAPE)
	check(Game.state.is_empty() and not menu.confirm_dialog.visible, "Escape input cancels first-run mode selection")
	menu.new_button.pressed.emit()
	check(menu.pending_difficulty == "normal", "Reopening resets mode selection to normal")
	menu.confirm_ok.pressed.emit()
	check(Game.state.difficulty == "normal" and Game.page == "dialogue", "Confirm starts normal adventure")
	menu.queue_free()
	await get_tree().process_frame
	Game.menu()
	var prior := Game.state.duplicate(true)
	menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu.new_button.pressed.emit()
	advanced = menu.confirm_dialog.find_child("advanced_mode", true, false) as Button
	advanced.pressed.emit()
	menu.confirm_cancel.pressed.emit()
	check(same(Game.state, prior) and Game.page == "menu", "Return after changing mode preserves current adventure")
	menu.new_button.pressed.emit()
	advanced = menu.confirm_dialog.find_child("advanced_mode", true, false) as Button
	advanced.pressed.emit()
	menu.confirm_ok.pressed.emit()
	check(Game.state.difficulty == "advanced" and Game.page == "dialogue", "Confirm replaces adventure with selected advanced mode")
	menu.queue_free()
	await get_tree().process_frame

func test_battle_views() -> void:
	for id in ["B02", "B04", "B16"]:
		setup_battle(id, "advanced")
		Game.page = "battle"
		var app: Control = load("res://scenes/main.tscn").instantiate()
		add_child(app)
		var deadline := Time.get_ticks_msec() + 15000
		while (not is_instance_valid(app.view) or not app.view.get("initialized") or Game.transition_locked or Game.battle_busy) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(Time.get_ticks_msec() < deadline, id + ": advanced battle view becomes ready")
		for index in app.view.model.enemies.size():
			var enemy: Dictionary = app.view.model.enemies[index]
			check(app.view.enemy_summary_plates[index].hp_label.text == "%d / %d" % [enemy.hp, enemy.maxHp], id + ": real battle HP display uses adjusted values")
		await shot("advanced-battle-" + id)
		var hp_before: int = app.view.model.player_hp
		await app.view.end_turn_pressed()
		check(app.view.model.turn == 2 and app.view.model.player_hp < hp_before, id + ": actual enemy turn remains playable")
		check(Game.state.difficulty == "advanced" and Game.valid_save(Game.state), id + ": played advanced battle remains a valid adventure")
		await preload("res://scripts/combat/audio_cleanup.gd").release(app, get_tree())
		app.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

func _ready() -> void:
	await get_tree().process_frame
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not OS.get_user_data_dir().contains("difficulty-settings-qa"):
		push_error("Difficulty QA requires copied project, isolated difficulty-settings-qa user directory and absolute QA_OUT_DIR")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = "user://difficulty_checkpoint.json"
	Game.meta_path = "user://difficulty_meta.json"
	for path in [Game.save_path, Game.save_path + ".bak", Game.save_path + ".tmp", "user://difficulty_menu_empty.json"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	original_enemies = Game.enemy_catalog.duplicate(true)
	original_battles = Game.battles.duplicate(true)
	test_formal_battles()
	test_saves()
	test_training_isolation()
	await test_menu()
	await test_battle_views()
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures, "headless":DisplayServer.get_name() == "headless", "physicalInput":false}, "\t"))
	file.close()
	print("DIFFICULTY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
