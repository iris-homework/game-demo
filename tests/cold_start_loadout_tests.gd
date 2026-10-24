extends Node
## Headless-only suite. Every file operation is confined to this dedicated folder.
const QA_DIR := "user://cold_start_loadout_qa"
const CHIPS := ["money_chip", "swift_chip"]
const Library := preload("res://scripts/card_library.gd")
var checks := 0
var failures := 0
var original_battles: Dictionary
var original_enemies: Dictionary

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("COLD START LOADOUT: " + message)

func paths() -> Array:
	return [Game.save_path, Game.save_path + ".bak", Game.save_path + ".tmp", Game.save_path + ".bak.tmp", Game.meta_path, Game.meta_path + ".bak", Game.meta_path + ".tmp"]

func disk_snapshot() -> Dictionary:
	var result := {}
	for path in paths():
		result[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result

func remove_qa_files() -> void:
	for path in paths():
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Open dedicated QA fixture " + path.get_file())
	if file != null:
		file.store_string(content)
		file.close()

func reset(subject: Dictionary = {}) -> void:
	if Game.training_mode: Game.restore_training()
	Game.state = subject.duplicate(true)
	Game.page = "menu"
	Game.transition_locked = false
	Game.battle_busy = false
	Game.pending_save_kind = ""
	Game.save_enabled = false

func subject() -> Dictionary:
	var saved := Game.initial_state()
	saved.currentScene = "map"
	saved.deck = ["noren_36"]
	saved.removedStartingCards = ["noren_01"]
	for id in CHIPS:
		if not id in saved.ownedCyberwareIds: saved.ownedCyberwareIds.append(id)
	saved.equippedCyberwareIds = CHIPS.duplicate()
	return saved

func counts(ids: Array) -> Dictionary:
	var result := {}
	for id in ids: result[id] = int(result.get(id, 0)) + 1
	return result

func read_only_probe(action: Callable, label: String):
	var before_state: Dictionary = Game.state.duplicate(true)
	var before_page: String = Game.page
	var before_revision: int = Game.revision
	var before_disk := disk_snapshot()
	var event_rng: int = Game.event_refresh_rng.state
	var market_rng: int = Game.black_market_model.rng.state
	seed(730241)
	var expected_random := randi()
	seed(730241)
	var value = action.call()
	check(randi() == expected_random, label + ": global RNG unchanged")
	check(Game.event_refresh_rng.state == event_rng and Game.black_market_model.rng.state == market_rng, label + ": event and market RNG unchanged")
	check(Game.state == before_state and Game.page == before_page and Game.revision == before_revision, label + ": state, page and revision unchanged")
	check(disk_snapshot() == before_disk, label + ": primary, backup, meta and temporary files unchanged")
	return value

func library_counts() -> Dictionary:
	var library := Library.new()
	add_child(library)
	var result: Dictionary = library.display_counts.duplicate()
	check(library.owned_only, "Actual library opens in owned scope")
	library.free()
	return result

func check_training(expected: Dictionary, single_enemy: bool, label: String) -> void:
	var before_state: Dictionary = Game.state.duplicate(true)
	var before_disk := disk_snapshot()
	if single_enemy: Game.start_enemy_training("pruning_hound")
	else: Game.start_training("B04")
	check(Game.training_mode and Game.page == "battle", label + ": enters training")
	if Game.training_mode:
		var model := CombatModel.new()
		model.restore(Game.state.combat)
		check(counts(model.instances.values()) == counts(Game.full_deck_ids(expected)), label + ": actual combat instances include extras and starting-card removals")
		check(model.cyberware_cards().map(func(card): return card.id) == expected.equippedCyberwareIds, label + ": frozen combat technologies match the selected source")
		check(Game.state.deck == expected.deck and Game.state.removedStartingCards == expected.removedStartingCards, label + ": temporary adventure carries the complete deck edits")
		if expected.equippedCyberwareIds == CHIPS:
			check(model.passive_technology_amount("victory_credits") == 30 and model.passive_technology_amount("opening_draw") == 2, label + ": real passive chip effects are bound")
			model.draw_cards()
			check(model.hand.size() == 7, label + ": swift chip produces the actual seven-card opening")
		check(disk_snapshot() == before_disk, label + ": entering training writes no checkpoint")
		Game.menu()
	check(not Game.training_mode and Game.page == "menu" and Game.state == before_state, label + ": exit restores the exact original memory state")
	check(Game.battles == original_battles and Game.enemy_catalog == original_enemies and Game.training_enemy_id.is_empty() and Game.training_battle_id.is_empty(), label + ": temporary enemy and battle definitions are cleaned up")
	check(disk_snapshot() == before_disk, label + ": exit leaves all files unchanged")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = QA_DIR + "/checkpoint.json"
	Game.meta_path = QA_DIR + "/meta_profile.json"
	DirAccess.make_dir_recursive_absolute(QA_DIR)
	remove_qa_files()
	original_battles = Game.battles.duplicate(true)
	original_enemies = Game.enemy_catalog.duplicate(true)
	check(Game.cyberware_definition("money_chip").get("effect") == "victory_credits" and Game.cyberware_definition("swift_chip").get("effect") == "opening_draw", "Fixture uses the authored passive technology IDs")
	var saved := subject()
	reset(saved)
	check(Game.valid_save(Game.state), "Custom loadout is a valid adventure")
	check(Game.save_game(), "Explicit save writes only the dedicated QA checkpoint")
	Game.state.credits += 1
	check(Game.save_game(), "Second explicit save creates a valid backup")
	saved = Game.state.duplicate(true)
	check(FileAccess.file_exists(Game.save_path + ".bak"), "Valid backup exists")
	var expected_counts := counts(Game.full_deck_ids(saved))
	reset()
	var preview: Dictionary = read_only_probe(Game.saved_adventure_preview, "Cold saved preview")
	# JSON numbers restore as floats; compare every field after the same transport
	# normalization rather than weakening this to a subset of loadout fields.
	check(JSON.parse_string(JSON.stringify(preview)) == JSON.parse_string(JSON.stringify(saved)), "Primary checkpoint takes precedence over the older backup")
	check(read_only_probe(Game.owned_card_counts, "Cold owned counts") == expected_counts, "Owned counts include rewarded power and omit one sold starting card")
	check(read_only_probe(library_counts, "Actual main-menu library") == expected_counts, "Actual owned-library view uses the saved loadout")
	Game.page = "card_library"
	check(read_only_probe(Game.owned_card_counts, "Library-page counts") == expected_counts, "Cold card-library page uses the same saved source")
	Game.page = "menu"
	check_training(saved, false, "Cold classic practice")
	check_training(saved, true, "Cold single-enemy practice")

	var memory := saved.duplicate(true)
	memory.deck = ["noren_23", "noren_23"]
	memory.removedStartingCards = []
	memory.equippedCyberwareIds = Game.player_characters.noren.cyberwareIds.slice(0, 1)
	reset(memory)
	check(read_only_probe(Game.owned_card_counts, "Warm owned counts") == counts(Game.full_deck_ids(memory)), "Live memory takes precedence over different disk contents")
	check_training(memory, false, "Warm classic practice")
	check_training(memory, true, "Warm single-enemy practice")

	reset()
	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path + ".bak"))
	write_text(Game.save_path, "{broken primary")
	check(read_only_probe(Game.saved_adventure_preview, "Backup preview") == backup, "Invalid primary falls back to valid backup")
	check(read_only_probe(Game.owned_card_counts, "Backup counts") == counts(Game.full_deck_ids(backup)), "Owned counts read the backup loadout")
	check_training(backup, false, "Backup classic practice")
	check_training(backup, true, "Backup single-enemy practice")

	write_text(Game.save_path + ".bak", "{broken backup")
	var before_disk := disk_snapshot()
	var revision: int = Game.revision
	check(read_only_probe(Game.saved_adventure_preview, "Corrupt preview").is_empty(), "Two corrupt checkpoints produce no guessed adventure")
	check(read_only_probe(Game.owned_card_counts, "Corrupt owned counts").is_empty(), "Two corrupt checkpoints do not advertise a default deck")
	Game.start_training("B04")
	check(not Game.training_mode and Game.state.is_empty() and Game.page == "menu", "Classic training rejects unreadable saved loadouts")
	Game.start_enemy_training("pruning_hound")
	check(not Game.training_mode and Game.state.is_empty() and Game.page == "menu", "Single-enemy training rejects unreadable saved loadouts")
	check(Game.revision == revision and disk_snapshot() == before_disk, "Rejected starts preserve revision and both damaged files")
	check(Game.battles == original_battles and Game.enemy_catalog == original_enemies and Game.training_enemy_id.is_empty() and Game.training_battle_id.is_empty(), "Rejected single-enemy start removes its provisional catalog entries")

	remove_qa_files()
	reset()
	var fresh := Game.initial_state()
	check(read_only_probe(Game.saved_adventure_preview, "No-save preview").is_empty(), "New users have no saved preview")
	check(read_only_probe(Game.owned_card_counts, "No-save counts") == counts(Game.full_deck_ids(fresh)), "New users see the authored starter deck")
	check_training(fresh, false, "New-user classic practice")
	check_training(fresh, true, "New-user single-enemy practice")
	check(not Game.has_save(), "New-user practice does not create an adventure save")
	remove_qa_files()
	print("COLD START LOADOUT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
