extends Node

const OUTPUT := "res://artifacts/qa/battle-restart-2026-10-22/"
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func same(a, b) -> bool:
	# JSON reload changes integer representations, but not saved meaning.
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func read_checkpoint() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	return parsed if parsed is Dictionary else {}

func write_fixture(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Open isolated fixture " + path.get_file())
	if file == null: return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()

func begin_case(label: String, battle_id: String = "B04", hp: int = 63) -> Dictionary:
	Game.save_enabled = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.training_backup.clear()
	Game.save_path = OUTPUT + label + "-checkpoint.json"
	Game.meta_path = OUTPUT + label + "-meta.json"
	Game.state = Game.initial_state()
	Game.state.currentHp = hp
	Game.state.targetId = "richard"
	Game.state.activeEventId = Game.battles[battle_id].eventId
	Game.state.currentPlaceId = Game.battles[battle_id].placeId
	Game.save_enabled = true
	Game.enter_node("battle")
	check(Game.state.get("battleStart") is Dictionary and not Game.state.get("battleStart", {}).is_empty(), label + ": captures baseline")
	return Game.state.get("battleStart", {}).duplicate(true)

func current_model() -> CombatModel:
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	return model

func check_projected(baseline: Dictionary, message: String) -> void:
	var disk := read_checkpoint()
	check(same(disk.get("combat"), baseline), message + ": disk combat is baseline")
	check(disk.get("currentHp") == baseline.get("playerHp"), message + ": disk HP is entry HP")
	check(same(disk.get("battleStart"), baseline), message + ": persisted baseline is unchanged")
	check(Game.valid_save(disk), message + ": projected save validates")

func finish_story() -> void:
	var steps := 0
	while Game.state.currentScene == "dialogue" and Game.node_data().has("next") and steps < 100:
		Game.advance(Game.revision)
		steps += 1
	check(steps < 100, "Post-battle story terminates")

func test_live_and_disk() -> void:
	var baseline := begin_case("live")
	if baseline.is_empty(): return
	check(baseline.playerHp == 63 and baseline.maxHp == 100, "Entry preserves non-full HP")
	check(baseline.turn == 1 and not baseline.openingDrawDone and baseline.hand.is_empty(), "Baseline precedes the opening draw")
	check(baseline.drawPile.size() == baseline.instances.size(), "Baseline includes the shuffled complete deck")
	var original_enemy_hp: int = Game.state.combat.enemies[0].hp
	Game.state.combat.enemies[0].hp -= 1
	check(same(Game.state.battleStart, baseline), "Nested live enemy edits cannot mutate the independent baseline")
	Game.state.combat.enemies[0].hp = original_enemy_hp
	var model := current_model()
	model.draw_cards()
	Game.commit_combat(model)
	check(Game.state.combat.hand.size() == 5 and Game.state.combat.openingDrawDone, "Live opening draw is committed")
	check_projected(baseline, "Opening draw")
	var played := false
	for uid in model.hand.duplicate():
		if not model.play_card(uid, 0).is_empty():
			played = true
			break
	check(played and model.outcome.is_empty(), "A real card is played without ending the encounter")
	Game.commit_combat(model)
	check(same(Game.state.combat, model.snapshot()) and not same(Game.state.combat, baseline), "Live state retains the card effect")
	check_projected(baseline, "Card play")
	check(model.activate_cyberware("backup_energy"), "Activate a real technology")
	Game.commit_combat(model)
	check(Game.state.combat.usedCyberware == ["backup_energy"] and Game.state.combat.cyberwareCooldowns.backup_energy == 3 and Game.state.combat.norenState.energy == model.energy, "Live technology state remains active")
	check_projected(baseline, "Technology")
	var turn := model.end_turn()
	check(not turn.is_empty() and model.turn == 2 and model.outcome.is_empty(), "Real enemy turn reaches a surviving second turn")
	check(model.player_hp < int(baseline.playerHp), "Enemy turn actually damages the non-full-HP player")
	Game.commit_combat(model)
	check(Game.state.currentHp == model.player_hp and same(Game.state.combat, model.snapshot()), "Live HP and second-turn state are retained")
	check_projected(baseline, "Enemy turn")
	var live: Dictionary = Game.state.combat.duplicate(true)
	check(Game.save_game(), "Explicit save succeeds")
	check(same(Game.state.combat, live) and same(Game.state.battleStart, baseline), "Explicit save never mutates live state or baseline")
	check_projected(baseline, "Explicit save")
	check(Game.console_command("addcard 23").begins_with("已添加"), "Console adds a next-battle card")
	check(Game.state.deck == ["noren_23"] and same(Game.state.combat, live), "Console preserves the running deck and live state")
	check_projected(baseline, "Console save")
	check(read_checkpoint().deck == ["noren_23"], "Console ownership is persisted beside the baseline")

func test_resume_paths() -> void:
	var baseline := begin_case("resume")
	if baseline.is_empty(): return
	var first := current_model()
	var expected_hand := first.draw_cards().duplicate()
	Game.commit_combat(first)
	first.end_turn()
	Game.commit_combat(first)
	Game.menu()
	check(Game.page == "menu" and same(Game.state.combat, baseline) and Game.state.currentHp == 63, "Menu restores unfinished battle to entry")
	Game.resume()
	check(Game.page == "battle" and same(Game.state.combat, baseline), "Continue resumes the entry snapshot")
	var reopened := current_model()
	check(reopened.draw_cards() == expected_hand, "Menu continue preserves the first hand order")
	Game.commit_combat(reopened)
	var drawn := current_model()
	check(drawn.opening_draw_done and drawn.draw_cards().is_empty() and drawn.hand == expected_hand, "Restoring an already drawn model does not duplicate the opening hand")
	# Cover resume independently of menu: callers may already be on the menu.
	reopened.end_turn()
	Game.commit_combat(reopened)
	Game.page = "menu"
	Game.resume()
	check(same(Game.state.combat, baseline), "Continue itself normalizes an unfinished live battle")
	Game.state = {}
	Game.page = "menu"
	Game.resume()
	check(Game.page == "battle" and same(Game.state.combat, baseline) and Game.state.currentHp == 63, "Cold continue loads entry HP and combat")
	reopened = current_model()
	check(reopened.draw_cards() == expected_hand, "Cold continue preserves the first hand order")
	# A valid externally retained live snapshot must also normalize on load.
	reopened.end_turn()
	Game.commit_combat(reopened)
	write_fixture(Game.save_path, Game.state)
	Game.state = {}
	check(Game.load_game() and same(Game.state.combat, baseline), "Loading a valid live new-format checkpoint normalizes it")
	for attempt in 3:
		reopened = current_model()
		check(reopened.draw_cards() == expected_hand, "Repeated restart keeps the same shuffled hand %d" % attempt)
		Game.commit_combat(reopened)
		Game.menu()
		Game.resume()
		check(same(Game.state.battleStart, baseline), "Repeated restart does not replace its baseline %d" % attempt)

func test_terminal_results() -> void:
	for outcome in ["win", "lose"]:
		var baseline := begin_case("terminal-" + outcome, "B02", 63 if outcome == "win" else 1)
		if baseline.is_empty(): continue
		var model := current_model()
		model.draw_cards(10)
		if outcome == "win":
			for uid in model.hand.duplicate():
				if model.card(uid).type == "attack":
					model.play_card(uid, 0)
					break
		else:
			model.end_turn()
		check(model.outcome == outcome, outcome + ": reached naturally")
		Game.commit_combat(model)
		var terminal := model.snapshot()
		check(same(read_checkpoint().combat, terminal), outcome + ": terminal snapshot is saved, not rolled back")
		Game.menu()
		Game.resume()
		check(same(Game.state.combat, terminal), outcome + ": menu continue retains terminal snapshot")
		Game.state = {}
		check(Game.load_game() and same(Game.state.combat, terminal), outcome + ": cold continue retains terminal snapshot")
		var revision := Game.revision
		if outcome == "win":
			check(Game.battle_exit(outcome, revision), "Win returns to its authored story")
		else:
			check(Game.page == "defeat" and Game.state.currentScene == "defeat" and not Game.can_continue(), "Committed defeat resumes only the terminal page")
		check(Game.state.battleStart.is_empty(), outcome + ": clears old baseline at battle exit")
		check(not Game.battle_exit(outcome, revision), outcome + ": rejects duplicate battle exit")
		if outcome == "win":
			finish_story()
			check(Game.state.credits == int(Game.config.initialCredits) + 50 and Game.has_battle_reward(), "Victory pays exactly once after story")
			var options: Array = Game.state.battleReward.options.duplicate()
			Game.menu()
			Game.resume()
			Game.enter_node("finish")
			check(Game.state.credits == int(Game.config.initialCredits) + 50 and Game.state.battleReward.options == options, "Finish and menu reentry do not repay or reroll")
			check(Game.choose_reward_card(options[0], Game.revision), "Claim one victory card")
			check(not Game.choose_reward_card(options[1], Game.revision), "Second victory card is rejected")
			Game.state = {}
			check(Game.load_game() and Game.state.credits == int(Game.config.initialCredits) + 50 and Game.state.deck == [options[0]], "Claimed reward survives cold continue exactly once")
		else:
			check(Game.state.currentHp == 0 and Game.state.battleReward.is_empty() and Game.state.credits == int(Game.config.initialCredits), "Defeat retains zero HP without rewards")
			check(not Game.choose(0, Game.revision) and Game.page == "defeat", "Defeat cannot choose the legacy map exit")

func test_next_battle_and_training() -> void:
	var baseline := begin_case("next-and-training")
	if baseline.is_empty(): return
	var model := current_model()
	model.draw_cards()
	model.end_turn()
	Game.commit_combat(model)
	var adventure: Dictionary = Game.state.duplicate(true)
	var disk_before := FileAccess.get_file_as_string(Game.save_path)
	for exit_kind in ["menu", "win", "lose"]:
		Game.start_training("B02")
		check(Game.training_mode, exit_kind + ": training starts")
		var practice := current_model()
		practice.draw_cards()
		practice.end_turn()
		Game.commit_combat(practice)
		check(FileAccess.get_file_as_string(Game.save_path) == disk_before, exit_kind + ": training never overwrites adventure disk")
		if exit_kind == "menu": Game.menu()
		else: Game.finish_training(exit_kind)
		check(not Game.training_mode and same(Game.state, adventure), exit_kind + ": training restores exact adventure and baseline")
	Game.state.completedEventIds = ["E01"]
	Game.go_map()
	check(Game.start_event("E02"), "A different available event starts")
	check(Game.state.battleStart.is_empty() and Game.state.combat.is_empty(), "Starting an event clears the old encounter baseline")
	Game.state.currentHp = 42
	Game.enter_node("battle")
	check(Game.state.battleStart.battleId == "B02" and Game.state.battleStart.playerHp == 42, "Next encounter captures its own HP and identity")
	check(not same(Game.state.battleStart, baseline), "Next encounter never reuses the earlier snapshot")

func test_legacy() -> void:
	var baseline := begin_case("legacy")
	if baseline.is_empty(): return
	var model := current_model()
	model.draw_cards()
	model.end_turn()
	Game.commit_combat(model)
	var old: Dictionary = Game.state.duplicate(true)
	old.erase("battleStart")
	var live: Dictionary = old.combat.duplicate(true)
	var migrated: Dictionary = Game.migrate_save(old)
	check(not old.has("battleStart") and migrated.get("battleStart", null) == {}, "Schema 2 migration adds an empty baseline without mutating source")
	check(Game.valid_save(migrated) and same(migrated.combat, live), "Schema 2 migration preserves the unknown historical battle start")
	write_fixture(Game.save_path, old)
	Game.state = {}
	check(Game.load_game() and same(Game.state.combat, live) and Game.state.battleStart.is_empty(), "Legacy cold continue preserves the mid-battle snapshot")
	Game.menu()
	Game.resume()
	check(same(Game.state.combat, live), "Legacy menu continue does not invent entry HP or deck")
	check(Game.save_game() and same(read_checkpoint().combat, live), "Legacy save still persists the current battle exactly")
	var schema_one := Game.initial_state()
	schema_one.schemaVersion = 1
	for key in ["battleStart", "currentHp", "maxHp", "currentDay", "combat", "inventory"]: schema_one.erase(key)
	schema_one.credits = 123
	var upgraded: Dictionary = Game.migrate_save(schema_one)
	check(Game.valid_save(upgraded) and upgraded.battleStart.is_empty() and upgraded.currentHp == 100 and upgraded.credits == 123, "Schema 1 retains its established migration defaults")
	Game.state.completedEventIds = ["E01"]
	Game.go_map()
	Game.start_event("E02")
	var entry_hp: int = Game.state.currentHp
	Game.enter_node("battle")
	check(not Game.state.battleStart.is_empty() and Game.state.battleStart.playerHp == entry_hp, "Legacy adventure adopts restart policy only at its next encounter")

func test_invalid_baselines() -> void:
	var baseline := begin_case("invalid")
	if baseline.is_empty(): return
	var valid: Dictionary = Game.state.duplicate(true)
	check(Game.valid_save(valid), "New entry state validates before corruption")
	for fault in ["type", "partial", "battle", "player", "maximum", "opening", "turn", "outcome", "duplicate_uid", "enemy_id"]:
		var bad := valid.duplicate(true)
		match fault:
			"type": bad.battleStart = []
			"partial": bad.battleStart = {"battleId":"B04"}
			"battle": bad.battleStart.battleId = "B02"
			"player": bad.battleStart.profile.playerCharacterId = "unknown_actor"
			"maximum": bad.battleStart.maxHp += 1
			"opening": bad.battleStart.openingDrawDone = true
			"turn": bad.battleStart.turn = 2
			"outcome": bad.battleStart.outcome = "win"
			"duplicate_uid": bad.battleStart.drawPile.append(bad.battleStart.drawPile[0])
			"enemy_id": bad.battleStart.enemies[0].erase("id")
		check(not Game.valid_save(bad), "Reject corrupted or cross-encounter baseline: " + fault)
		write_fixture(Game.save_path, bad)
		write_fixture(Game.save_path + ".bak", valid)
		Game.state = {}
		check(Game.load_game() and same(Game.state.combat, baseline), "Recover valid backup after bad baseline: " + fault)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	Game.save_enabled = false
	Game.save_path = OUTPUT + "unused-checkpoint.json"
	Game.meta_path = OUTPUT + "unused-meta.json"
	seed(20261022)
	test_live_and_disk()
	test_resume_paths()
	test_terminal_results()
	test_next_battle_and_training()
	test_legacy()
	test_invalid_baselines()
	Game.save_enabled = false
	var report_file := FileAccess.open(OUTPUT + "battle-restart-results.json", FileAccess.WRITE)
	check(report_file != null, "Open isolated result report")
	if report_file != null:
		var report := {"checks":checks, "failures":failures, "scope":"isolated model and flow regression; no physical-input or visual acceptance"}
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	print("BATTLE RESTART TESTS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
