extends Node
## Logic and synthetic viewport-input coverage. No physical-device/visual claims.
const OUTPUT := "res://artifacts/qa/technology-autosave-2026-10-23/"
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var app: Control

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message, "passed":ok})
	if not ok:
		failures.append(message)
		push_error("TECHNOLOGY LOADOUT: " + message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func owned() -> Array:
	return Game.owned_cyberware_ids()

func stage_map(label: String = "logic") -> void:
	Game.save_enabled = false
	Game.training_mode = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_backup.clear()
	Game.save_path = OUTPUT + label + "-checkpoint.json"
	Game.meta_path = OUTPUT + label + "-meta.json"
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.page = "map"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(Game.save_path + suffix): DirAccess.remove_absolute(Game.save_path + suffix)

func write_fixture(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Open isolated fixture " + path.get_file())
	if file != null:
		file.store_string(JSON.stringify(value, "\t"))
		file.close()

func cards_ids(rules: Dictionary) -> Array:
	var result: Array = []
	for definition in rules.get("cards", []): result.append(definition.id)
	return result

func test_validation_and_commit() -> void:
	stage_map()
	var defaults := owned()
	check(defaults.size() == 3 and not "test_cyberware_01" in defaults, "Only the three authored technologies are owned")
	check(Game.equipped_cyberware_ids() == defaults, "New adventure defaults to authored equipment")
	var owned_copy := Game.owned_cyberware_ids()
	owned_copy.clear()
	check(Game.owned_cyberware_ids() == defaults, "Owned technology accessor returns an independent copy")
	var copy: Array = Game.equipped_cyberware_ids()
	copy.clear()
	check(Game.equipped_cyberware_ids() == defaults, "Equipment accessor returns an independent copy")
	for invalid in [null, {}, "backup_energy", [1], ["unknown"], ["test_cyberware_01"], [defaults[0], defaults[0]], defaults + ["test_cyberware_01"], defaults + ["test_cyberware_01", "test_cyberware_02"]]:
		check(not Game.valid_technology_loadout(invalid, Game.player_character_id()), "Reject malformed, duplicate, unknown, unowned or oversized list: " + str(invalid))
	check(not Game.valid_technology_loadout([], "unknown_actor"), "Reject unknown player even for empty equipment")
	for selection in [[], [defaults[2]], [defaults[2], defaults[0]], defaults]:
		var revision: int = Game.revision
		check(Game.valid_technology_loadout(selection, Game.player_character_id()), "Validate empty/subset/ordered equipment: " + str(selection))
		check(Game.set_technology_loadout(selection, revision), "Commit empty/subset/ordered equipment: " + str(selection))
		check(Game.revision == revision + 1, "Successful equipment commit advances revision exactly once")
		check(Game.equipped_cyberware_ids() == selection, "Commit preserves exact selection and order")
		check(cards_ids(Game.player_cyberware()) == selection, "Runtime technology definitions follow equipment")
		check(cards_ids(Game.player_cyberware(Game.player_character_id())) == defaults, "Explicit player technology definitions retain authored defaults")
	var original: Dictionary = Game.state.duplicate(true)
	var revision: int = Game.revision
	check(not Game.set_technology_loadout([], revision - 1), "Reject stale revision")
	check(not Game.set_technology_loadout(["test_cyberware_01"], revision), "Reject unowned technology at commit boundary")
	check(Game.state == original and Game.revision == revision, "Rejected commits preserve state and revision")
	# Temporarily author a fourth owned item in memory to exercise the four-slot
	# boundary without adding any prototype technology to production ownership.
	Game.player_characters[Game.player_character_id()].cyberwareIds.append("test_cyberware_01")
	check(Game.valid_technology_loadout(defaults + ["test_cyberware_01"], Game.player_character_id()), "Exactly four owned technologies are accepted")
	Game.player_characters[Game.player_character_id()].cyberwareIds = defaults

func test_guards() -> void:
	stage_map("guards")
	var emitted := [0]
	var record_request := func(): emitted[0] += 1
	Game.technology_loadout_requested.connect(record_request)
	for other_page in ["menu", "place", "dialogue", "battle", "result", "cyberware", "card_library"]:
		Game.page = other_page
		var before: Dictionary = Game.state.duplicate(true)
		var revision: int = Game.revision
		check(not Game.set_technology_loadout([], revision), "Reject commit outside map: " + other_page)
		check(Game.state == before and Game.revision == revision, "Outside-map rejection leaves state unchanged: " + other_page)
		Game.open_technology_loadout()
	Game.page = "map"
	for flag in ["training_mode", "transition_locked", "battle_busy"]:
		Game.set(flag, true)
		var revision: int = Game.revision
		var before: Dictionary = Game.state.duplicate(true)
		check(not Game.set_technology_loadout([], revision), "Reject locked or training commit: " + flag)
		check(Game.state == before and Game.revision == revision, "Locked rejection preserves state: " + flag)
		Game.open_technology_loadout()
		Game.set(flag, false)
	Game.page = "map"
	Game.state.currentScene = "dialogue"
	check(not Game.set_technology_loadout([], Game.revision), "Reject map page with mismatched underlying scene")
	Game.open_technology_loadout()
	check(emitted[0] == 0, "Invalid page, scene, training and locks never emit configuration request")
	Game.state.currentScene = "map"
	Game.open_technology_loadout()
	check(emitted[0] == 1, "Eligible map emits one configuration request")
	Game.technology_loadout_requested.disconnect(record_request)

func test_persistence_and_migration() -> void:
	stage_map("persistence")
	Game.save_enabled = true
	var selection := [owned()[2], owned()[0]]
	check(Game.set_technology_loadout(selection, Game.revision), "Persist ordered subset")
	var disk = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	check(disk is Dictionary and disk.get("equippedCyberwareIds") == selection and Game.valid_save(disk), "Checkpoint contains valid ordered equipment")
	Game.state = {}
	check(Game.load_game() and Game.equipped_cyberware_ids() == selection, "Cold load round-trips ordered equipment")
	var authored: Array = Game.player_characters[Game.player_character_id()].cyberwareIds.duplicate()
	Game.player_characters[Game.player_character_id()].cyberwareIds = []
	Game.state = {}
	check(Game.load_game() and Game.equipped_cyberware_ids() == selection and Game.owned_cyberware_ids() == authored, "Cold load retains saved ownership and equipment when authored defaults change")
	check(Game.set_technology_loadout([selection[0]], Game.revision), "Saved ownership still allows configuration after authored defaults change")
	Game.player_characters[Game.player_character_id()].cyberwareIds = authored
	check(Game.set_technology_loadout([], Game.revision), "Persist intentionally empty equipment")
	Game.state = {}
	check(Game.load_game() and Game.equipped_cyberware_ids().is_empty(), "Cold load preserves intentionally empty equipment")
	var old: Dictionary = Game.state.duplicate(true)
	old.erase("equippedCyberwareIds")
	old.erase("ownedCyberwareIds")
	var migrated: Dictionary = Game.migrate_save(old)
	check(not old.has("equippedCyberwareIds") and not old.has("ownedCyberwareIds") and migrated.get("equippedCyberwareIds") == owned() and migrated.get("ownedCyberwareIds") == owned(), "Legacy migration adds ownership/equipment defaults without mutating source")
	check(Game.valid_save(migrated), "Migrated legacy map remains valid")
	for bad in [["test_cyberware_01"], [owned()[0], owned()[0]], ["unknown"], "invalid"]:
		var malformed := migrated.duplicate(true)
		malformed.equippedCyberwareIds = bad
		check(not Game.valid_save(malformed), "Save validation rejects malformed equipment: " + str(bad))
	for bad in [null, {}, "invalid", [1], ["unknown"], [owned()[0], owned()[0]]]:
		var malformed := migrated.duplicate(true)
		malformed.ownedCyberwareIds = bad
		check(not Game.valid_save(malformed), "Save validation rejects malformed ownership: " + str(bad))
	var unowned := migrated.duplicate(true)
	unowned.ownedCyberwareIds = [owned()[0]]
	unowned.equippedCyberwareIds = [owned()[2]]
	check(not Game.valid_save(unowned), "Save validation rejects equipment absent from saved ownership")
	var original: Dictionary = Game.state.duplicate(true)
	var revision: int = Game.revision
	var saved_path: String = Game.save_path
	write_fixture(OUTPUT + "write-blocker", {})
	Game.save_path = OUTPUT + "write-blocker/checkpoint.json"
	check(not Game.set_technology_loadout(selection, revision), "Failed disk write rejects equipment commit")
	check(Game.state == original and Game.revision == revision, "Failed disk write preserves memory and revision")
	Game.save_path = saved_path

func test_combat_freezing() -> void:
	stage_map("combat")
	var selection := [owned()[2], owned()[0]]
	check(Game.set_technology_loadout(selection, Game.revision), "Prepare next-battle technology selection")
	Game.state.battleId = "B02"
	Game.state.currentScene = "battle"
	Game.state.activeEventId = Game.battles.B02.eventId
	Game.state.currentPlaceId = Game.battles.B02.placeId
	Game.page = "battle"
	Game.initialize_combat()
	check(cards_ids(Game.state.combat.profile.cyberware) == selection, "New battle freezes selected technologies in order")
	check(Game.state.combat.profile.playerCyberwareIds == selection, "New battle profile metadata matches equipment")
	var frozen: Dictionary = Game.state.combat.duplicate(true)
	Game.state.equippedCyberwareIds = []
	check(Game.state.combat == frozen and Game.state.battleStart == frozen, "Adventure equipment edits cannot mutate frozen combat or opening")
	var legacy: Dictionary = Game.state.duplicate(true)
	legacy.erase("equippedCyberwareIds")
	legacy.erase("ownedCyberwareIds")
	var migrated: Dictionary = Game.migrate_save(legacy)
	check(same(migrated.combat, frozen) and same(migrated.battleStart, frozen), "Legacy equipment migration preserves existing frozen battle rules")
	check(Game.valid_save(migrated), "Legacy battle remains valid after additive equipment migration")

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func click(control: Control) -> void:
	if not is_instance_valid(control):
		check(false, "Required clickable control exists")
		return
	var pos := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = pos
	get_viewport().push_input(move, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await settle()

func escape() -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = down
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await settle()

func test_map_modal() -> void:
	stage_map("ui")
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle()
	var map_view: Control = app.view
	var trigger := map_view.get_node_or_null("technology_loadout_button") as Button
	var deck := map_view.get_node_or_null("current_deck_button") as Button
	check(is_instance_valid(trigger) and is_instance_valid(deck), "Real map exposes technology configuration beside deck")
	if trigger == null or deck == null: return
	check(is_equal_approx(trigger.position.x + trigger.size.x + 8.0, deck.position.x) and is_equal_approx(trigger.position.y, deck.position.y), "Technology button sits exactly 8 pixels left of deck")
	check(get_viewport().get_visible_rect().encloses(trigger.get_global_rect()), "Technology entry stays inside map canvas")
	Game.save_enabled = true
	var revision: int = Game.revision
	await click(trigger)
	check(is_instance_valid(app.technology_browser), "Real map button opens technology configuration")
	if not is_instance_valid(app.technology_browser): return
	var browser: Control = app.technology_browser
	check(map_view.process_mode == Node.PROCESS_MODE_DISABLED and trigger.disabled and deck.disabled, "Technology modal pauses map and disables background buttons")
	check(browser.slot_buttons.size() == 4 and browser.technology_buttons.size() == owned().size(), "Configuration shows four slots and only owned technologies")
	check(browser.slot_buttons[3].disabled and browser.slot_buttons[3].text.contains("空位"), "Missing fourth technology displays an inactive empty slot")
	var close_button: Button
	var manual_buttons := 0
	for node in browser.find_children("*", "Button", true, false):
		if node.text.contains("关闭"): close_button = node
		if node.text in ["保存配置", "取消"]: manual_buttons += 1
	check(manual_buttons == 0 and is_instance_valid(close_button), "Panel offers close without manual save or cancel buttons")
	await click(browser.slot_buttons[0])
	var selection := [owned()[1], owned()[2]]
	check(browser.selected_ids == selection and Game.equipped_cyberware_ids() == selection, "Clicking carried slot immediately updates adventure and visible selection")
	check(Game.revision == revision + 1 and browser.expected_revision == Game.revision, "Auto-save advances and synchronizes revision exactly once")
	var disk = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	check(disk is Dictionary and disk.get("equippedCyberwareIds") == selection, "Slot click writes selection to disk before closing")
	check(is_instance_valid(app.technology_browser) and map_view.process_mode == Node.PROCESS_MODE_DISABLED, "Auto-save keeps configuration open and map paused")
	await escape()
	check(not is_instance_valid(app.technology_browser) and Game.equipped_cyberware_ids() == selection, "Escape keeps automatically saved technology changes")
	check(map_view.process_mode == Node.PROCESS_MODE_INHERIT and not trigger.disabled and not deck.disabled, "Close restores map processing and button state")
	check(get_viewport().gui_get_focus_owner() == trigger, "Close restores focus to technology entry")
	await click(trigger)
	browser = app.technology_browser
	check(browser.selected_ids == selection, "Reopening loads automatically saved selection")
	Game.revision += 1
	var stale_revision: int = Game.revision
	var original: Dictionary = Game.state.duplicate(true)
	await click(browser.slot_buttons[0])
	check(is_instance_valid(app.technology_browser) and Game.state == original and Game.revision == stale_revision, "Stale UI change stays open and preserves adventure")
	check(browser.selected_ids == selection and browser.expected_revision == stale_revision and browser.message_label.text.contains("保存失败"), "Rejected stale change restores saved UI and synchronizes revision for retry")
	var valid_path: String = Game.save_path
	Game.save_path = OUTPUT + "write-blocker/checkpoint.json"
	await click(browser.technology_buttons[owned()[0]])
	check(is_instance_valid(app.technology_browser) and Game.state == original and Game.revision == stale_revision, "Failed auto-save preserves adventure and revision")
	check(browser.selected_ids == selection and browser.message_label.text.contains("保存失败"), "Failed auto-save restores selection and displays failure")
	check(browser.slot_buttons[2].disabled and browser.technology_buttons[owned()[0]].get_node("selection_state").text == "点击携带", "Failed auto-save refreshes slots and owned technology highlight")
	Game.save_path = valid_path
	await click(browser.technology_buttons[owned()[0]])
	check(browser.selected_ids == selection + [owned()[0]] and Game.revision == stale_revision + 1, "Retry after disk failure saves successfully without reopening")
	for i in range(3): await click(browser.slot_buttons[0])
	check(browser.selected_ids.is_empty() and Game.equipped_cyberware_ids().is_empty(), "Consecutive clicks automatically save intentionally empty equipment")
	disk = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	check(disk is Dictionary and disk.get("equippedCyberwareIds") == [], "Empty equipment persists immediately to disk")
	check(browser.slot_buttons.size() == 4, "Empty equipment still shows all four slots")
	for slot in browser.slot_buttons: check(slot.disabled and slot.text.contains("空位"), "Unfilled equipment slot is inactive and visibly empty")
	await click(browser.technology_buttons[owned()[2]])
	await click(browser.technology_buttons[owned()[0]])
	selection = [owned()[2], owned()[0]]
	check(browser.selected_ids == selection and Game.equipped_cyberware_ids() == selection, "Consecutive owned technology clicks immediately save selected order")
	await click(browser.technology_buttons[owned()[2]])
	check(Game.equipped_cyberware_ids() == [owned()[0]], "Clicking selected owned technology immediately saves removal")
	for node in browser.find_children("*", "Button", true, false):
		if node.text.contains("关闭"): close_button = node
	await click(close_button)
	check(not is_instance_valid(app.technology_browser) and Game.equipped_cyberware_ids() == [owned()[0]], "Close button preserves automatically saved selection")
	await click(deck)
	check(is_instance_valid(app.deck_browser), "Existing deck entry remains functional")
	Game.open_technology_loadout()
	check(not is_instance_valid(app.technology_browser), "Deck modal prevents stacking technology modal")
	await escape()
	await click(trigger)
	app.open_current_deck()
	check(not is_instance_valid(app.deck_browser), "Technology modal prevents stacking deck modal")
	app.open_exit_confirmation("menu")
	check(not is_instance_valid(app.exit_dialog), "Technology modal prevents stacking exit confirmation")
	await escape()
	app.queue_free()
	await settle()
	Game.state = {}
	check(Game.load_game() and Game.equipped_cyberware_ids() == [owned()[0]], "Cold load preserves changes made only through automatic UI saving")

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	get_tree().create_timer(60).timeout.connect(func(): push_error("Technology loadout tests timed out"); get_tree().quit(2))
	test_validation_and_commit()
	test_guards()
	test_persistence_and_migration()
	test_combat_freezing()
	await test_map_modal()
	var file := FileAccess.open(OUTPUT + "test-result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"userDataDirectory":OS.get_user_data_dir(),"scope":"Logic and synthetic headless viewport input; no screenshot or physical device claims"}, "\t"))
		file.close()
	print("TECHNOLOGY LOADOUT: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
