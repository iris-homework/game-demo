extends Node
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func start_battle() -> CombatModel:
	Game.state.targetId = "richard"
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.enter_node("battle")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	return model

func same_checkpoint(a: Dictionary, b: Dictionary) -> bool:
	# Loading normalizes credits to int; compare all fields as JSON values.
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "res://artifacts/qa/player-characters-2026-10-10/test_checkpoint.json"
	Game.meta_path = "res://artifacts/qa/player-characters-2026-10-10/test_meta.json"
	check(Game.player_characters.keys() == ["noren"], "Only Noren is playable in shipped data")
	Game.new_game()
	check(Game.player_character_id() == "noren", "Default player ID is Noren")
	check(Game.state.currentHp == 70 and Game.state.maxHp == 70, "Noren starts with 70 HP")
	check(Game.display_name("@player") == "诺伦", "Player name resolves through ID")
	check(Game.player_asset_id() == "noren" and Game.player_asset_id("battlePortraitAssetId") == "noren_battle", "Both portraits resolve through ID")
	check(Game.player_definition().skills.is_empty(), "No invented character skills")
	Game.state.targetId = "richard"
	check(Game.render_text("{主角姓名}追踪{目标姓名}") == "诺伦追踪理查德", "Player and target substitutions coexist")
	var normal := start_battle()
	check(normal.instances.size() == 10 and normal.draw_cards().size() == 5, "Noren starts with ten cards and draws five")
	var strike: String = normal.instances.find_key("noren_01")
	normal.draw_pile.erase(strike)
	if not strike in normal.hand: normal.hand.append(strike)
	normal.enemies[0].hp = 30; normal.enemies[0].maxHp = 30
	check(normal.play_card(strike, 0).damage == 6, "Noren initial strike deals six")
	check(normal.profile.playerCharacterId == "noren" and normal.profile.playerSkills == [], "Combat snapshots include character metadata")
	# A temporary actor proves the runtime follows configuration; never shipped as content.
	Game.characters["qa_actor"] = {"displayName":"接入测试", "portraitAssetId":"bartender", "battlePortraitAssetId":"mech_battle"}
	Game.player_characters["qa_actor"] = {"attributes":{"maxHp":137}, "startingDeck":["test_attack","test_attack","test_attack","test_attack","test_attack","test_attack","test_attack"], "skills":[{"id":"qa_skill", "name":"技能接口测试", "description":"仅测试配置保存，无战斗效果"}]}
	Game.new_game("qa_actor")
	check(Game.player_character_id() == "qa_actor" and Game.state.maxHp == 137 and Game.state.currentHp == 137, "Explicit player uses configured attributes")
	check(Game.display_name("@player") == "接入测试" and Game.render_text("{主角姓名}") == "接入测试", "New player name replaces story references")
	check(Game.state.portraits.left == "@player" and Game.resolve_character_id(Game.node_data().speakerId) == "bartender", "Initial dialogue retains NPC and dynamic player")
	Game.advance(Game.revision)
	check(Game.node_data().speakerId == "@player" and Game.display_name(Game.node_data().speakerId) == "接入测试", "Authored player dialogue resolves new actor")
	check(Game.player_asset_id() == "bartender" and Game.player_asset_id("battlePortraitAssetId") == "mech_battle", "New actor chooses both new portrait assets")
	Game.state.deck = ["test_reward_01"]
	var model := start_battle()
	check(model.instances.size() == 8 and model.instances.values().count("test_reward_01") == 1, "Character starting deck plus acquired cards")
	check(model.profile.playerSkills[0].id == "qa_skill" and model.profile.playerAttributes.maxHp == 137, "Skills and attributes reach combat metadata")
	model.draw_cards()
	model.play_card(model.hand[0], 0)
	Game.commit_combat(model)
	# Compare persisted semantics: JSON normalizes numeric types and StringName keys.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.state))
	check(Game.valid_save(saved) and Game.save_game(), "New actor checkpoint saves")
	Game.player_characters.qa_actor.attributes.maxHp = 200
	Game.player_characters.qa_actor.startingDeck = ["test_attack"]
	Game.state = {}
	check(Game.load_game() and same_checkpoint(Game.state, saved), "Load preserves existing HP, piles and snapshot despite config edits")
	Game.start_training("B02")
	check(Game.player_character_id() == "qa_actor" and Game.state.maxHp == 200 and Game.state.combat.instances.size() == 2, "Training uses current character base deck plus owned reward")
	Game.finish_training("lose")
	check(same_checkpoint(Game.state, saved), "Training restores full adventure identity and progress")
	var before := Game.state.duplicate(true)
	Game.new_game("bartender")
	check(Game.state == before and Game.initial_state("unknown").is_empty(), "NPC and unknown ID cannot start an adventure")
	for bad in ["", "bartender", "unknown", 7]:
		var broken := saved.duplicate(true)
		broken.playerCharacterId = bad
		check(not Game.valid_save(Game.migrate_save(broken)), "Invalid explicit player ID rejected: " + str(bad))
	var mismatch := saved.duplicate(true)
	mismatch.combat.profile.playerCharacterId = "noren"
	check(not Game.valid_save(mismatch), "Combat and adventure IDs must agree")
	# Missing legacy identity always means Noren, never the new default character.
	Game.new_game("noren")
	model = start_battle()
	model.draw_cards()
	model.activate_cyberware("test_cyberware_01")
	model.play_card(model.hand[0], 0)
	Game.commit_combat(model)
	var legacy := Game.state.duplicate(true)
	legacy.erase("playerCharacterId")
	legacy.portraits.left = "noren"
	legacy.combat.profile.erase("playerCharacterId")
	legacy.combat.profile.erase("playerAttributes")
	legacy.combat.profile.erase("playerSkills")
	var original := legacy.duplicate(true)
	Game.config.defaultPlayerCharacterId = "qa_actor"
	var migrated = Game.migrate_save(legacy)
	check(migrated.playerCharacterId == "noren" and migrated.portraits.left == "@player", "Legacy saves migrate to Noren, independent of default")
	check(Game.valid_save(migrated), "Legacy battle checkpoint remains valid")
	check(migrated.currentHp == original.currentHp and migrated.maxHp == original.maxHp and migrated.deck == original.deck and migrated.combat == original.combat, "Legacy migration preserves HP, deck, cooldown and combat exactly")
	check(legacy == original, "Migration never mutates its input")
	var v1 := original.duplicate(true)
	v1.schemaVersion = 1
	for key in ["currentHp","maxHp","currentDay","combat","inventory"]: v1.erase(key)
	var migrated_v1 = Game.migrate_save(v1)
	check(Game.valid_save(migrated_v1) and migrated_v1.playerCharacterId == "noren" and migrated_v1.maxHp == 100, "Schema 1 saves remain compatible")
	Game.config.defaultPlayerCharacterId = "noren"
	# Config errors fail before changing the active adventure.
	var valid: Dictionary = Game.player_characters.noren.duplicate(true)
	for hp in [0, -1, 1.5, "100"]:
		Game.player_characters.noren.attributes.maxHp = hp
		check(not Game.valid_player_character("noren"), "Invalid max HP rejected")
	Game.player_characters.noren = valid.duplicate(true)
	Game.player_characters.noren.startingDeck = ["unknown"]
	check(not Game.valid_player_character("noren"), "Unknown starting card rejected")
	Game.player_characters.noren = valid.duplicate(true)
	Game.player_characters.noren.skills = [{"id":"bad"}]
	check(not Game.valid_player_character("noren"), "Incomplete skill metadata rejected")
	Game.player_characters.noren = valid
	var character: Dictionary = Game.characters.noren.duplicate(true)
	Game.characters.noren.displayName = 3
	check(not Game.valid_player_character("noren"), "Invalid display name rejected")
	Game.characters.noren = character.duplicate(true)
	Game.characters.noren.mapAvatarCrop = ["bad", 0, 1, 1]
	check(not Game.valid_player_character("noren"), "Malformed avatar crop rejected before rendering")
	Game.characters.noren = character.duplicate(true)
	Game.characters.noren.mapAvatarCrop = [0.5, 0, 1, 1]
	check(not Game.valid_player_character("noren"), "Out-of-bounds avatar crop rejected")
	Game.characters.noren = character
	Game.characters.erase("qa_actor")
	Game.player_characters.erase("qa_actor")
	print("PLAYER CHARACTER CHECKS: ", checks, " / failures: ", failures)
	get_tree().quit(0 if failures == 0 else 1)
