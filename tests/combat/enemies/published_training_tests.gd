extends Node
## Run in a copied project with a QA user directory and absolute QA_OUT_DIR.
## Model, menu and save-isolation assertions; no GPU or physical-input acceptance.
const FORMAL_BATTLES := {"robot":"B02", "gang":"B04", "fish":"B11", "pruning_hound":"B13", "powerline_repairman":"B14", "beacon_jellyfish":"B15", "dancer_duet":"B16"}
const RETIRED := ["warden_shield", "chip_broker", "mutant_mouse", "luggage_lurker", "penitent_ascetic", "rogue_drone", "mirror_inspector"]
var output := ""
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var original_battles: Dictionary
var original_enemies: Dictionary
var sentinel_paths: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message, "passed":ok})
	if not ok:
		failures.append(message)
		push_error("PUBLISHED TRAINING: " + message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func reset(subject: Dictionary = {}) -> void:
	if Game.training_mode: Game.restore_training()
	Game.save_enabled = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.state = subject.duplicate(true)
	Game.page = "menu"
	Game.save_path = output.path_join("empty-checkpoint.json" if subject.is_empty() else "sentinel-checkpoint.json")

func check_catalogs(label: String) -> void:
	check(same(Game.battles, original_battles) and same(Game.enemy_catalog, original_enemies), label + ": formal catalogs intact and temporary definitions removed")

func check_disk(label: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		check(not FileAccess.file_exists(output.path_join("empty-checkpoint.json" + suffix)), label + ": no cold adventure save " + suffix)
	for path in sentinel_paths:
		check(FileAccess.get_file_as_string(path) == "published-training-sentinel:" + path.get_file(), label + ": unchanged " + path.get_file())
	for path in [Game.save_path + ".tmp", Game.meta_path + ".tmp"]:
		check(not FileAccess.file_exists(path), label + ": no temporary save " + path.get_file())

func adventure() -> Dictionary:
	var s := Game.initial_state()
	s.currentScene = "map"
	s.currentPlaceId = "hive"
	s.currentHp = 47
	s.credits = 1234
	s.deck = ["noren_01", "noren_02", "noren_01"]
	s.equippedCyberwareIds = Game.player_characters.noren.cyberwareIds.slice(0, 1)
	s.completedEventIds = ["E01"]
	s.battleHistory = [{"battleId":"B02", "result":"win"}]
	s.claimedRewardIds = ["sentinel_reward"]
	return s

func choice_for(id: String) -> Dictionary:
	for choice in Game.training_enemy_choices():
		if choice.id == id: return choice
	return {}

func test_config() -> void:
	var authored = Game.read_data("training_enemies.json")
	check(authored is Array and authored.size() == 7, "Exactly seven authored week-one practice choices")
	var week: Dictionary = Game.read_data("weeks/week1/week.json")
	var actual_battles: Array = []
	for event_id in week.eventIds:
		for node in Game.events[event_id].nodes.values():
			if node.get("type") == "battle" and not actual_battles.has(node.battleId): actual_battles.append(node.battleId)
	actual_battles.sort()
	var expected := FORMAL_BATTLES.values()
	expected.sort()
	check(actual_battles == expected, "Practice battle set equals actual battle nodes in current week-one events")
	var choices := Game.training_enemy_choices()
	var ids: Array = []
	for choice in choices:
		ids.append(choice.id)
		check(FORMAL_BATTLES.has(choice.id) and not str(choice.displayName).is_empty(), "Choice has expected identity and visible name: " + str(choice.id))
		if not FORMAL_BATTLES.has(choice.id): continue
		var battle_id: String = FORMAL_BATTLES[choice.id]
		var battle: Dictionary = Game.battles[battle_id]
		var definition: Dictionary = Game.enemy_catalog[battle.enemyIds[0]]
		check(choice.battleId == battle_id and same(choice.enemyIds, battle.enemyIds) and choice.placeId == battle.placeId, "Choice resolves formal formation and location: " + str(choice.id))
		check(choice.maxHp == definition.maxHp and same(choice.intentSequence, definition.intentSequence), "Choice uses current formal HP and intents: " + str(choice.id))
		for entry in authored:
			if entry.id == choice.id:
				check(entry.battleId == battle_id and not entry.has("maxHp") and not entry.has("intentSequence"), "Authored choice references battle without duplicating combat rules: " + str(choice.id))
	ids.sort()
	var expected_ids := FORMAL_BATTLES.keys()
	expected_ids.sort()
	check(ids == expected_ids, "Exactly the seven first-week encounter choices, without duplicate or prototype entries")
	check(not Game.has_method("training_scenery_choices") and not Game.has_method("set_b04_scenery_choice"), "Player scenery-selection API removed")

func test_dynamic_formal_choices() -> void:
	for id in FORMAL_BATTLES:
		reset(adventure())
		var original := Game.state.duplicate(true)
		var primary_id: String = Game.battles[FORMAL_BATTLES[id]].enemyIds[0]
		var baseline: Dictionary = Game.enemy_catalog[primary_id].duplicate(true)
		Game.enemy_catalog[primary_id].maxHp = int(baseline.maxHp) + 7
		Game.enemy_catalog[primary_id].intentSequence[0].amount = int(baseline.intentSequence[0].get("amount", 0)) + 2
		var updated: Dictionary = Game.enemy_catalog[primary_id].duplicate(true)
		var choice := choice_for(id)
		check(choice.maxHp == updated.maxHp and same(choice.intentSequence, updated.intentSequence), "Choice follows live formal HP and intents: " + id)
		choice.intentSequence[0].amount = 999
		choice.enemyIds.clear()
		choice.displayName = "tampered"
		var independent := choice_for(id)
		check(same(independent.intentSequence, updated.intentSequence) and same(independent.enemyIds, Game.battles[FORMAL_BATTLES[id]].enemyIds) and independent.displayName != "tampered", "Choice deep copy cannot change future reads or formal data: " + id)
		Game.save_enabled = true
		Game.start_enemy_training(id)
		check(Game.training_mode and Game.state.combat.enemies[0].hp == updated.maxHp and same(Game.state.combat.enemies[0].intentSequence, updated.intentSequence), "Starting practice uses latest formal source: " + id)
		check(Game.training_enemy_id.is_empty() and Game.enemy_catalog.size() == original_enemies.size(), "Formal practice creates no temporary enemy: " + id)
		Game.menu()
		check(same(Game.state, original), "Dynamic practice restores original adventure: " + id)
		Game.enemy_catalog[primary_id] = baseline
		check_catalogs("Dynamic " + id)
		check_disk("Dynamic " + id)

func test_start_and_restore() -> void:
	for id in FORMAL_BATTLES:
		for original in [{}, adventure()]:
			reset(original)
			Game.save_enabled = true
			Game.training_scenery_place_id = "bar"
			Game.start_enemy_training(id)
			var label := str(id) + (" cold" if original.is_empty() else " adventure")
			check(Game.training_mode and Game.page == "battle" and Game.state.currentScene == "battle", label + ": enters playable battle")
			if not Game.training_mode or Game.state.get("combat", {}).is_empty(): continue
			var formal: Dictionary = Game.battles[FORMAL_BATTLES[id]]
			var practice: Dictionary = Game.battles[Game.state.battleId]
			check(Game.state.battleId == "training_" + id and practice.get("trainingOnly", false), label + ": session-only battle")
			check(Game.training_scenery_place_id.is_empty() and practice.placeId == formal.placeId and Game.state.currentPlaceId == formal.placeId, label + ": fixed formal place, stale preview override cleared")
			check(Game.state.battleStart.is_empty() and Game.state.battleReward.is_empty() and Game.state.dialogueHistory.is_empty() and Game.state.activeEventId.is_empty(), label + ": no formal story context or rewards")
			check(Game.state.deck == original.get("deck", []), label + ": owned extra cards copied")
			if not original.is_empty(): check(Game.state.equippedCyberwareIds == original.equippedCyberwareIds, label + ": equipped technology copied")
			var model := CombatModel.new()
			model.restore(Game.state.combat)
			check(model.enemies.size() == formal.enemyIds.size() and same(practice.enemyIds, formal.enemyIds) and Game.training_enemy_id.is_empty(), label + ": whole formal formation without temporary enemy")
			for index in formal.enemyIds.size():
				var definition: Dictionary = Game.enemy_catalog[formal.enemyIds[index]]
				var enemy: Dictionary = model.enemies[index]
				check(enemy.id == definition.id and enemy.hp == definition.maxHp and enemy.maxHp == definition.maxHp and same(enemy.intentSequence, definition.intentSequence) and enemy.combatVisualId == definition.combatVisualId, label + ": formal identity, HP, intents and visual in slot " + str(index))
			check(Game.valid_combat(model.snapshot()), label + ": opening snapshot validates")
			if id == "dancer_duet":
				var stripped: Dictionary = model.snapshot()
				stripped.erase("encounterPhase")
				for key in ["encounterId", "phaseOneEnemies", "phaseTwoEnemies", "phaseTwoCards"]: stripped.profile.erase(key)
				check(not Game.valid_combat(stripped), label + ": Boss copy cannot omit required encounter phase data")
				var forged: Dictionary = model.snapshot()
				forged.battleId = "B02"
				check(not Game.valid_combat(forged), label + ": ordinary battle cannot claim Boss phase data")
				check(model.encounter_phase == 1 and same(practice.phaseTwoEnemyIds, formal.phaseTwoEnemyIds), label + ": boss phase data retained")
				model.enemy_damage(0, 999)
				model.resolve_outcome()
				check(model.advance_encounter_phase() and model.encounter_phase == 2 and model.outcome.is_empty(), label + ": first phase opens second phase instead of winning")
				check(model.enemies.size() == formal.phaseTwoEnemyIds.size(), label + ": full second-phase formation")
				for index in formal.phaseTwoEnemyIds.size():
					var definition: Dictionary = Game.enemy_catalog[formal.phaseTwoEnemyIds[index]]
					check(model.enemies[index].id == definition.id and model.enemies[index].hp == definition.maxHp, label + ": second-phase identity/HP in slot " + str(index))
				check(Game.valid_combat(model.snapshot()), label + ": second-phase snapshot validates")
			else:
				model.end_turn()
				check(model.turn == 2 and Game.valid_combat(model.snapshot()), label + ": normal enemy turn advances with valid snapshot")
			Game.commit_combat(model)
			Game.menu()
			check(not Game.training_mode and Game.page == "menu" and same(Game.state, original), label + ": midfight exit restores exact adventure or empty memory")
			check_catalogs(label)
			check_disk(label)

func test_rejections() -> void:
	for id in FORMAL_BATTLES:
		reset()
		Game.save_path = output.path_join("sentinel-checkpoint.json")
		Game.start_enemy_training(id)
		check(not Game.training_mode and Game.state.is_empty() and Game.page == "menu", "Unreadable cold save rejects practice: " + id)
		check_catalogs("Unreadable " + id)
	for id in RETIRED + ["missing"]:
		reset(adventure())
		var before := Game.state.duplicate(true)
		Game.start_enemy_training(id)
		check(not Game.training_mode and same(Game.state, before), "Removed or unknown enemy cannot start: " + id)
		check_catalogs("Removed " + id)
	for lock in ["transition", "battle_busy", "page"]:
		reset(adventure())
		Game.transition_locked = lock == "transition"
		Game.battle_busy = lock == "battle_busy"
		if lock == "page": Game.page = "map"
		var before := Game.state.duplicate(true)
		Game.start_enemy_training("robot")
		check(not Game.training_mode and same(Game.state, before), "Reject " + lock + " atomically")
	reset(adventure())
	Game.start_enemy_training("robot")
	var before := Game.state.duplicate(true)
	var backup := Game.training_backup.duplicate(true)
	Game.start_enemy_training("fish")
	check(same(Game.state, before) and same(Game.training_backup, backup) and Game.battles.size() == original_battles.size() + 1, "Repeated launch preserves active practice and original backup")
	Game.menu()
	check_catalogs("Repeated launch")
	check_disk("Rejections")

func test_terminal_restore() -> void:
	for id in FORMAL_BATTLES:
		for result in ["win", "lose"]:
			reset(adventure())
			var original := Game.state.duplicate(true)
			Game.save_enabled = true
			Game.start_enemy_training(id)
			var model := CombatModel.new()
			model.restore(Game.state.combat)
			if result == "win":
				for index in model.enemies.size(): model.enemy_damage(index, 999)
				model.resolve_outcome()
				if id == "dancer_duet":
					model.advance_encounter_phase()
					for index in model.enemies.size(): model.enemy_damage(index, 999)
					model.resolve_outcome()
			else:
				var rounds := 0
				while model.outcome.is_empty() and rounds < 40:
					model.end_turn()
					rounds += 1
			check(model.outcome == result, "Production model reaches " + result + ": " + id)
			Game.commit_combat(model)
			check(Game.battle_exit(result, Game.revision), "Training exit accepts " + result + ": " + id)
			check(not Game.training_mode and Game.page == "menu" and same(Game.state, original), result + " restores exact adventure without rewards: " + id)
			check_catalogs(result + " " + id)
			check_disk(result + " " + id)

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func test_menu() -> void:
	reset(adventure())
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var entry: Button = menu.training_toggle
	check(entry.text == "战斗演练" and not menu.training_open, "Single practice entry starts closed")
	var original_states: Dictionary = {}
	for button in menu.ui_layer.find_children("*", "Button", true, false): original_states[button] = [button.disabled, button.focus_mode]
	entry.pressed.emit()
	await get_tree().process_frame
	var modal: Control = menu.training_container
	check(menu.training_open and modal.is_visible_in_tree(), "Practice entry opens modal")
	check(menu.find_child("training_scenery", true, false) == null and menu.find_child("training_scenery_picker", true, false) == null and not menu.has_method("open_scenery_picker"), "No player scenery button, picker or opening method remains")
	var buttons := modal.find_children("*", "Button", true, false)
	check(buttons.size() == 8, "Exactly seven encounter buttons and return, with no duplicate classic section")
	var bounds_seen: Array[Rect2] = []
	var canvas := Rect2(Vector2.ZERO, Vector2(1440, 900))
	for button in buttons:
		var bounds: Rect2 = button.get_global_rect()
		check(button.get_minimum_size().x <= button.size.x and button.get_minimum_size().y <= button.size.y, "Button text fits: " + button.name)
		check(canvas.encloses(bounds), "Button lies within canvas: " + button.name)
		for previous in bounds_seen: check(not bounds.intersects(previous), "No overlapping buttons: " + button.name + "/" + str(previous.position))
		for node in modal.find_children("*", "Label", true, false): check(not bounds.intersects(node.get_global_rect()), "Button clears text: " + button.name + "/" + node.text)
		bounds_seen.append(bounds)
		for path in [button.focus_next, button.focus_previous, button.focus_neighbor_left, button.focus_neighbor_right, button.focus_neighbor_top, button.focus_neighbor_bottom]:
			check(not path.is_empty() and button.get_node_or_null(path) in buttons, "Keyboard navigation stays inside modal: " + button.name + "/" + str(path))
	for id in RETIRED: check(modal.find_child("enemy_choice_" + id, true, false) == null, "Removed prototype has no menu button: " + id)
	check(modal.is_ancestor_of(get_viewport().gui_get_focus_owner()), "Modal owns focus")
	for button in original_states: check(button.disabled and button.focus_mode == Control.FOCUS_NONE, "Underlying menu disabled: " + button.name)
	menu.request_new()
	check(not is_instance_valid(menu.confirm_dialog), "Practice modal blocks new-adventure overlay")
	await key(KEY_ESCAPE)
	check(not menu.training_open and not Game.training_mode, "Escape closes practice without starting combat")
	for button in original_states: check([button.disabled, button.focus_mode] == original_states[button], "Closing restores background control: " + button.name)
	for id in FORMAL_BATTLES:
		reset(adventure())
		var original := Game.state.duplicate(true)
		entry.pressed.emit()
		var choice := modal.find_child("enemy_choice_" + id, true, false) as Button
		check(choice != null, "Unified menu contains first-week choice: " + id)
		if choice != null: choice.pressed.emit()
		check(Game.training_mode and Game.state.get("battleId", "") == "training_" + id and not menu.training_open, "Actual menu callback enters selected practice and closes modal: " + id)
		Game.menu()
		check(same(Game.state, original), "Menu-selected practice restores adventure: " + id)
		check_catalogs("Menu " + id)
		await get_tree().process_frame
	entry.pressed.emit()
	menu.training_cancel.pressed.emit()
	check(not menu.training_open and not Game.training_mode, "Return button closes practice")
	for lock in ["transition", "busy"]:
		Game.transition_locked = lock == "transition"
		Game.battle_busy = lock == "busy"
		entry.pressed.emit()
		check(not menu.training_open, "Practice cannot open while " + lock)
	Game.transition_locked = false
	Game.battle_busy = false
	check_disk("Menu interactions")
	menu.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	await get_tree().process_frame
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("Require absolute QA_OUT_DIR and isolated user directory containing QA")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_path = output.path_join("sentinel-checkpoint.json")
	Game.meta_path = output.path_join("sentinel-meta.json")
	Game.save_enabled = false
	for suffix in ["", ".bak", ".tmp"]:
		var path := output.path_join("empty-checkpoint.json" + suffix)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for path in [Game.save_path, Game.save_path + ".bak", Game.meta_path, Game.meta_path + ".bak"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("published-training-sentinel:" + path.get_file())
		file.close()
		sentinel_paths.append(path)
	original_battles = Game.battles.duplicate(true)
	original_enemies = Game.enemy_catalog.duplicate(true)
	test_config()
	test_dynamic_formal_choices()
	test_start_and_restore()
	test_rejections()
	test_terminal_restore()
	await test_menu()
	reset()
	check_disk("Final")
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures, "records":records, "headless":true, "physicalInput":false}, "\t"))
	file.close()
	print("PUBLISHED_TRAINING_RESULT checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
