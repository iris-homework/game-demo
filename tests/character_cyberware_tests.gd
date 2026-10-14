extends Node
var checks := 0
var failures := 0
const FIRST := "test_cyberware_01"
const SECOND := "test_cyberware_02"
const FIFTH := "test_cyberware_05"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func battle_for(id: String = "noren") -> CombatModel:
	Game.new_game(id)
	Game.state.targetId = "richard"
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.enter_node("battle")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	model.enemies[0].hp = 30
	model.enemies[0].maxHp = 30
	return model

func same_save(a: Dictionary, b: Dictionary) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "res://artifacts/qa/character-cyberware-2026-10-11/test_checkpoint.json"
	Game.meta_path = "res://artifacts/qa/character-cyberware-2026-10-11/test_meta.json"
	check(Game.player_characters.keys() == ["noren"], "Only Noren ships as playable")
	var original: Dictionary = Game.player_characters.noren.duplicate(true)
	var ids: Array = original.cyberwareIds.duplicate()
	check(ids == Game.prototype_rules.cyberware.cards.map(func(c): return c.id), "Noren references all six original definitions in order")
	var normal := battle_for()
	check(normal.cyberware_cards().size() == 6 and normal.profile.playerCyberwareIds == ids, "Noren battle freezes six configured IDs")
	check(normal.cyberware_cards() == Game.prototype_rules.cyberware.cards, "Names, descriptions and effects are unchanged")
	for definition in normal.cyberware_cards():
		check(normal.activate_cyberware(definition.id), "Noren can activate " + definition.id)
	check(normal.next_attack_bonus == 6 and normal.available_cyberware_count() == 0, "All six stack and enter cooldown")
	check(not normal.activate_cyberware(FIRST), "Same-turn reuse remains rejected")
	normal.draw_cards()
	check(normal.play_card(normal.hand[0], 0).damage == 7 and normal.next_attack_bonus == 0, "Six bonuses apply once to next attack")
	check(normal.play_card(normal.hand[0], 0).damage == 1, "Following attack keeps base damage")
	normal.end_turn()
	check(normal.available_cyberware_count() == 6 and normal.activate_cyberware(FIRST), "Next player turn releases cooldown")
	# Only in-memory fixture actors have alternative lists.
	Game.characters["qa_subset"] = Game.characters.noren.duplicate(true)
	Game.characters["qa_subset"].displayName = "科技配置测试角色"
	Game.player_characters["qa_subset"] = original.duplicate(true)
	Game.player_characters["qa_subset"].cyberwareIds = [FIFTH, SECOND]
	Game.characters["qa_empty"] = Game.characters.noren.duplicate(true)
	Game.player_characters["qa_empty"] = original.duplicate(true)
	Game.player_characters["qa_empty"].cyberwareIds = []
	var subset := battle_for("qa_subset")
	check(subset.cyberware_cards().map(func(c): return c.id) == [FIFTH, SECOND], "Actor selection and order control battle list")
	check(not subset.activate_cyberware(FIRST), "Another actor cannot activate unassigned catalog item")
	check(subset.activate_cyberware(FIFTH) and subset.next_attack_bonus == 1, "Assigned shared definition retains effect")
	check(subset.profile.playerCharacterId == "qa_subset" and Game.valid_combat(subset.snapshot()), "Actor snapshot with selected definitions is valid")
	subset.draw_cards()
	Game.commit_combat(subset)
	var saved := Game.state.duplicate(true)
	check(Game.save_game(), "Configured battle saves to isolated path")
	Game.player_characters["qa_subset"].cyberwareIds = []
	Game.state = {}
	check(Game.load_game() and same_save(Game.state, saved), "Live config edits do not replace a saved battle's list or cooldown")
	var restored := CombatModel.new()
	restored.restore(Game.state.combat)
	check(restored.cyberware_cards().size() == 2 and restored.next_attack_bonus == 1, "Restored battle retains selected items and pending bonus")
	check(not restored.activate_cyberware(FIFTH), "Restore cannot bypass cooldown")
	check(restored.play_card(restored.hand[0], 0).damage == 2, "Restored pending bonus resolves exactly once")
	Game.start_training("B12")
	check(Game.state.combat.profile.playerCharacterId == "qa_subset" and Game.state.combat.profile.cyberware.cards.is_empty(), "Training uses current actor's new list")
	Game.finish_training("surrender")
	check(same_save(Game.state, saved), "Training restores previous adventure and its frozen list")
	subset = battle_for("qa_subset")
	check(subset.cyberware_cards().is_empty(), "Next new battle takes updated actor configuration")
	var empty := battle_for("qa_empty")
	check(empty.cyberware_cards().is_empty() and empty.available_cyberware_count() == 0, "Explicit empty list has no cyberware")
	check(not empty.activate_cyberware(FIRST) and Game.valid_combat(empty.snapshot()), "Empty actor cannot activate Noren's cyberware")
	Game.player_characters["qa_empty"].erase("cyberwareIds")
	check(Game.valid_player_character("qa_empty") and Game.player_cyberware("qa_empty").cards.is_empty(), "Missing field means no implicit shared list")
	# Selection and returned definitions are copies, with no cross-actor mutations.
	Game.player_characters["qa_subset"].cyberwareIds = [FIFTH, SECOND]
	var rules := Game.player_cyberware("qa_subset")
	rules.cards[0].nextAttackBonus = 99
	rules.cards.clear()
	check(Game.cyberware_definition(FIFTH).nextAttackBonus == 1 and Game.player_cyberware("noren").cards.size() == 6, "Returned data cannot mutate shared catalog or another actor")
	for bad in ["bad", [FIRST, FIRST], ["missing"], [3], [FIRST,SECOND,FIFTH,"test_cyberware_03","test_cyberware_04","test_cyberware_06","missing"]]:
		Game.player_characters.noren.cyberwareIds = bad
		var before := Game.state.duplicate(true)
		check(not Game.valid_player_character("noren"), "Invalid actor list rejected")
		Game.new_game("noren")
		check(Game.state == before, "Bad configuration never resets existing progress")
	Game.player_characters.noren = original.duplicate(true)
	var definition := Game.cyberware_definition(FIRST)
	var amount = definition.nextAttackBonus
	definition.nextAttackBonus = 0.5
	check(not Game.valid_player_character("noren"), "Unsupported fractional catalog effect rejected")
	definition.nextAttackBonus = amount
	# Legacy snapshots retain full definitions and earned bonuses without new markers.
	normal = battle_for()
	normal.draw_cards()
	normal.activate_cyberware(FIRST)
	Game.commit_combat(normal)
	var legacy := Game.state.duplicate(true)
	legacy.erase("playerCharacterId")
	legacy.combat.profile.erase("playerCharacterId")
	legacy.combat.profile.erase("playerCyberwareIds")
	var legacy_combat: Dictionary = legacy.combat.duplicate(true)
	Game.config.defaultPlayerCharacterId = "qa_empty"
	var migrated = Game.migrate_save(legacy)
	check(Game.valid_save(migrated) and migrated.playerCharacterId == "noren", "Legacy identity remains Noren despite changed default")
	check(migrated.combat == legacy_combat, "Existing legacy cooldown and definitions are preserved without rebuilding")
	Game.config.defaultPlayerCharacterId = "noren"
	var missing := legacy.duplicate(true)
	missing.combat.profile.erase("cyberware")
	missing.combat.erase("usedCyberware")
	missing.combat.erase("nextAttackBonus")
	migrated = Game.migrate_save(missing)
	check(Game.valid_save(migrated) and migrated.combat.profile.cyberware.cards.size() == 6, "Old pre-cyberware Noren battle gains six configured items")
	missing = Game.state.duplicate(true)
	missing.playerCharacterId = "qa_empty"
	missing.combat.profile.playerCharacterId = "qa_empty"
	missing.combat.profile.erase("cyberware")
	missing.combat.profile.erase("playerCyberwareIds")
	missing.combat.erase("usedCyberware")
	missing.combat.erase("nextAttackBonus")
	migrated = Game.migrate_save(missing)
	check(Game.valid_save(migrated) and migrated.combat.profile.cyberware.cards.is_empty(), "Missing legacy catalog fills from owning actor, never global six")
	var old_eight := legacy_combat.duplicate(true)
	for index in [7,8]: old_eight.profile.cyberware.cards.append({"id":"test_cyberware_%02d" % index,"name":"Legacy","nextAttackBonus":1})
	old_eight.usedCyberware = ["test_cyberware_07","test_cyberware_08"]
	old_eight.nextAttackBonus = 2
	check(Game.valid_combat(old_eight), "Older eight-definition snapshot retains previously earned bonus")
	restored.restore(old_eight)
	check(restored.cyberware_cards().size() == 6 and not restored.activate_cyberware("test_cyberware_07"), "Old hidden seventh card remains unavailable")
	var new_snapshot := normal.snapshot()
	for bad in ["bad", [], [FIRST, FIRST], ids.slice(0, 5), ids.duplicate() + [FIRST]]:
		var corrupt := new_snapshot.duplicate(true)
		corrupt.profile.playerCyberwareIds = bad
		check(not Game.valid_combat(corrupt), "Snapshot marker must match selected definition IDs exactly")
	Game.player_characters.noren = original
	for id in ["qa_subset", "qa_empty"]:
		Game.player_characters.erase(id)
		Game.characters.erase(id)
	print("CHARACTER CYBERWARE: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
