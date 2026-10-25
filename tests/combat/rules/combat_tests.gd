extends Node
var count := 0
var failures: Array[String] = []
func check(ok: bool, title: String) -> void:
	count += 1
	if not ok:
		failures.append(title)
		push_error(title)

func model_for(id: String, hp: int = 100) -> CombatModel:
	var m := CombatModel.new()
	var definitions: Array = []
	for enemy_id in Game.battles[id].enemyIds: definitions.append(Game.enemy_catalog[enemy_id])
	# This helper deliberately exercises the retained legacy prototype rules.
	# Freeze every encounter independently; current authored numbers are checked below.
	var legacy_enemy: Dictionary = definitions[0].duplicate(true)
	legacy_enemy.maxHp = null
	legacy_enemy.intentSequence = []
	for field in ["attackPollution", "deathPollution", "allyDeathIntentSequence", "formationSlot", "intentLoopStart"]:
		legacy_enemy.erase(field)
	definitions = [legacy_enemy]
	m.initialize(id,hp,100,Game.prototype_rules,definitions)
	return m

func _ready() -> void:
	Game.save_enabled = false
	var output := "res://artifacts/qa/battle-restart-2026-10-22/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	Game.save_path = output + "combat-checkpoint.json"
	Game.meta_path = output + "combat-meta.json"
	var current_robot := CombatModel.new()
	current_robot.initialize("B02",100,100,Game.prototype_rules,[Game.enemy_catalog.robot])
	check(current_robot.enemies[0].maxHp == 45 and current_robot.enemies[0].intent.amount == 10,"Current B02 keeps authored HP 45 / attack 10 separately from legacy fixtures")
	for authored in [["B13",35,4,"attack"],["B14",60,1,"energy_suit"],["B15",36,6,"attack"]]:
		var current := CombatModel.new()
		var authored_definitions: Array = []
		for enemy_id in Game.battles[authored[0]].enemyIds: authored_definitions.append(Game.enemy_catalog[enemy_id])
		current.initialize(authored[0],70,70,Game.prototype_rules,authored_definitions)
		check(current.enemies[0].maxHp == authored[1] and current.enemies[0].intent.amount == authored[2] and current.enemies[0].intent.type == authored[3], str(authored[0])+" retains its authored HP and opening action separately from legacy fixtures")
		if authored[0] == "B13":
			check(current.enemies.size() == 2 and current.enemies[0].intent.hits == 2 and current.enemies[1].id == "pruning_hound_second" and current.enemies[1].maxHp == 35 and current.enemies[1].intent.type == "fortify" and current.enemies[1].intent.amount == 5 and current.enemies[1].intent.strength == 1, "Current B13 uses two thirty-five HP hounds with staggered attack/fortify")
	for id in Game.battles:
		var m := model_for(id)
		check(m.enemies[0].hp == 3,id+" HP 3")
		check(m.enemies[0].intent.type == "attack" and m.enemies[0].intent.amount == 1,id+" intention attack 1")
		check(m.draw_cards().size() == 5,id+" draw 5 cards")
		for hit in 3:
			var uid: String = m.hand[0]
			check(m.play_card(uid,0).damage == 1,id+" damage exactly 1")
			check(m.play_card(uid,0).is_empty(),id+" cannot replay discarded card")
			check(m.enemies[0].hp == 2-hit,id+" HP after hit")
		check(m.outcome == "win",id+" 3 cards win")
		check(m.hand.size() == 2 and m.discard_pile.size() == 3,id+" pile accounting")
		check(m.end_turn().is_empty(),id+" finished battle rejects end turn")
	var model := model_for("B04")
	model.draw_cards()
	var old_hand := model.hand.duplicate()
	var snapshot := model.snapshot()
	check(model.play_card(model.hand[0],8).is_empty(),"Invalid target rejected")
	check(model.snapshot() == snapshot,"Invalid target does not mutate")
	var turn_result := model.end_turn()
	check(turn_result.attacks[0].damage == 1 and model.player_hp == 99,"Enemy applies telegraphed damage")
	check(model.turn == 2 and model.hand.size() == 5,"New turn draws hand")
	check(model.hand.all(func(uid): return uid in old_hand),"Discard reshuffle conserves card identities")
	check(model.enemies[0].intent.amount == 1,"Next intent refreshes")
	var near_death := model_for("B04",1)
	near_death.draw_cards()
	near_death.end_turn()
	check(near_death.player_hp == 0 and near_death.outcome == "lose","Natural HP defeat")
	check(near_death.draw_cards().is_empty(),"No draw after defeat")
	var dead := model_for("B04",0)
	check(dead.outcome == "lose","Reenter at zero HP cannot bypass defeat")
	Game.state = Game.initial_state()
	check(Game.state.currentHp == 70 and Game.state.maxHp == 70 and Game.state.currentDay == 1,"Initial HP and date")
	Game.state.completedEventIds = ["E01"]
	Game.state.currentScene = "map"
	for hp in [40,65]:
		Game.state.currentHp = hp
		Game.state.credits = 150
		check(Game.heal_at("clinic"),"clinic service")
		check(Game.state.currentHp == (61 if hp == 40 else 70),"clinic heal30% capped")
		check(Game.state.credits == 0,"clinic correct treatment cost")
		check(Game.state.currentDay == 1,"clinic no automatic time cost")
	Game.state.currentHp = 50
	var laboratory_before := JSON.stringify(Game.state)
	var laboratory_revision := Game.revision
	check(Game.healing_service("hospital").is_empty(), "Laboratory has no healing service")
	check(not Game.heal_at("hospital"), "Laboratory rejects healing")
	check(JSON.stringify(Game.state) == laboratory_before and Game.revision == laboratory_revision, "Rejected laboratory healing preserves state and revision")
	check(not Game.heal_at("bar"),"No healing at non-service location")
	Game.apply_actions([{"op":"advanceDay","days":2}])
	check(Game.state.currentDay == 3,"Explicit day advance")
	Game.apply_actions([{"op":"advanceDay","days":20}])
	check(Game.state.currentDay == 7 and Game.state.currentWeek == 1,"Date capped without advancing week")
	check(not Game.apply_actions([{"op":"healHpPercent","percent":1.3}]),"Invalid healing action rejected")
	# Existing saves without a battle-start baseline retain exact mid-battle resume.
	# New battles use entry-state restart, covered by battle_restart_tests.
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.enter_node("battle")
	Game.state.battleStart = {}
	model = model_for("B04",50)
	model.draw_cards()
	model.play_card(model.hand[0],0)
	Game.commit_combat(model)
	var expected := Game.state.duplicate(true)
	check(Game.save_game(),"Save mid-battle")
	Game.state = {}
	check(Game.load_game(),"Load mid-battle")
	check(JSON.parse_string(JSON.stringify(Game.state)) == JSON.parse_string(JSON.stringify(expected)),"Mid-battle exact roundtrip")
	var restored := CombatModel.new()
	restored.restore(Game.state.combat)
	check(restored.hand.size() == 4 and restored.discard_pile.size() == 1 and restored.enemies[0].hp == 2,"Legacy battle without baseline preserves its exact in-progress piles")
	check(restored.player_hp == 50 and Game.state.currentDay == 7,"HP/date persisted")
	check(not restored.use_item("missing",0,{},Game.item_catalog).ok,"Empty items cannot create effect")
	check(Game.read_data("cards/cards.json").size() == 40 and Game.item_catalog.is_empty(),"Forty Noren cards and unchanged empty items")
	var original := Game.state.duplicate(true)
	Game.start_training("B02")
	check(Game.training_mode and Game.state.currentHp == 70 and Game.state.maxHp == 70,"Practice isolated")
	Game.battle_exit("win",Game.revision)
	check(not Game.training_mode and Game.state == original,"Practice restores exact adventure")
	var legacy := Game.initial_state()
	legacy.schemaVersion = 1
	for key in ["currentHp","maxHp","currentDay","combat","inventory"]: legacy.erase(key)
	legacy.credits = 123
	legacy.flags = {"alleyClue":true}
	legacy.targetId = "lumina"
	var migrated = Game.migrate_save(legacy)
	check(Game.valid_save(migrated),"Version 1 migration accepted")
	check(migrated.credits == 123 and migrated.flags.alleyClue and migrated.targetId == "lumina","Migration preserves story")
	check(migrated.currentHp == 100 and migrated.currentDay == 1,"Migration defaults new fields")
	Game.meta_profile = {"schemaVersion":1,"cyberwareState":{"test_marker":true}}
	check(Game.save_meta(),"Independent meta save")
	Game.new_game()
	check(Game.meta_profile.cyberwareState.test_marker,"New adventure preserves meta")
	Game.meta_profile = {"schemaVersion":1,"cyberwareState":{}}
	check(Game.load_meta() and Game.meta_profile.cyberwareState.test_marker,"Meta roundtrip")
	for path in [Game.save_path,Game.save_path+".bak",Game.save_path+".tmp",Game.meta_path,Game.meta_path+".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("COMBAT TESTS: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
