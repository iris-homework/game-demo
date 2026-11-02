extends Node
var checks := 0
var failures: Array[String] = []
var output := ""
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("NOSS INTENTS: "+label)
func saved(m: CombatModel) -> Dictionary:
	return JSON.parse_string(JSON.stringify(m.snapshot()))
func fresh(advanced: bool = false, legacy: bool = false) -> CombatModel:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules,true)
	rules.shuffleInitialDeck = false
	rules.encounterId = "noss_sovereign"
	rules.battleType = "boss"
	rules.difficulty = "advanced" if advanced else "normal"
	var defs: Array = []
	for id in Game.battles.B23.enemyIds: defs.append(Game.enemy_catalog[id].duplicate(true))
	rules.phaseOneEnemies = defs.duplicate(true)
	rules.phaseTwoEnemies = [Game.enemy_catalog.noss_phase2.duplicate(true)]
	if legacy:
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/noss_legacy_enemies.json"))
		defs = [old.noss_hand_left,old.noss_hand_right,old.noss]
		rules.phaseOneEnemies = defs.duplicate(true)
		rules.phaseTwoEnemies = [old.noss_phase2]
	else: rules.phaseOneEndEnemyId = Game.battles.B23.phaseOneEndEnemyId
	var m := CombatModel.new()
	m.initialize("B23",1000,1000,rules,defs,Game.card_catalog)
	return m
func second() -> CombatModel:
	var m := fresh()
	m.enemy_damage(2,999)
	m.resolve_outcome()
	check(m.enemies[0].hp == 40 and m.enemies[1].hp == 40 and m.advance_encounter_phase(),"body death alone replaces living hands")
	return m
func damage(result: Dictionary) -> int:
	var value := 0
	for a in result.attacks: value += int(a.damage)
	return value
func test_first() -> void:
	var m := fresh()
	check(m.enemies.map(func(e): return e.hp) == [40,40,100],"authored 40/40/100 HP")
	var adv := fresh(true)
	check(adv.enemies.map(func(e): return e.hp) == [45,45,105],"advanced applies formation bonus once")
	adv.enemy_damage(2,999); adv.resolve_outcome(); adv.advance_encounter_phase()
	check(adv.enemies[0].maxHp == 170,"advanced phase two retains single-enemy bonus")
	for expected in [18,8,26,0,19,9,29,0]:
		var result := m.end_turn()
		check(damage(result) == expected,"first phase authored group damage "+str(expected))
		check(Game.valid_combat(saved(m)),"first-phase frozen snapshot validates")
		if m.turn in [2,5,6,9]:
			check(m.enemies[2].block == 12 and result.turnEvents.back().get("buffId") == "block", "护主 shield appears only at whole enemy-phase end")
	m = fresh();m.enemy_damage(0,999);m.enemy_damage(1,999);m.resolve_outcome()
	check(m.outcome.is_empty() and not m.advance_encounter_phase(),"hands alone cannot end phase")
	m.end_turn();m.end_turn()
	check(m.buffs.count(m,"strength",2) == 1 and damage(m.end_turn()) == 12,"command falls back to self when hands are dead")
	m = fresh();m.enemy_damage(1,999);m.end_turn()
	check(m.enemies[2].block == 0,"dead protector cannot queue a shield")
	m = fresh();m.enemies[2].hp = 1;m.buffs.apply(m,"pollution",1,2)
	var result := m.end_turn()
	check(result.phaseChanged and m.encounter_phase == 2 and m.enemies.size() == 1,"body poison death advances despite surviving hands")
	m = fresh();m.enemies[2].hp = 6;m.parry = 2
	result = m.end_turn()
	check(result.phaseChanged and m.encounter_phase == 2 and result.attacks.size() == 2,"parry killing body transitions without extra enemy actions")
	m = fresh();m.draw_cards();m.instances.qa = "qa";m.card_catalog.qa = {"id":"qa","name":"QA","type":"attack","target":"enemy","cost":0,"effects":[{"type":"damage","amount":100,"hits":4}]};m.hand.append("qa")
	result = m.play_card("qa",2)
	check(result.phaseChanged and result.hits.size() == 1 and m.enemies[0].hp == 160,"single-target multihit body kill does not spill into new phase")
	var old := fresh(false,true)
	old.enemy_damage(2,999);old.resolve_outcome()
	check(old.outcome.is_empty() and not old.advance_encounter_phase() and Game.valid_combat(saved(old)),"legacy snapshot retains ninety HP definitions and all-enemy clear rule")
	var restored := CombatModel.new();restored.restore(saved(old))
	check(saved(old) == saved(restored) and restored.enemies[2].maxHp == 90,"legacy restore is exact without retroactive phase flag")
func test_sin() -> void:
	var m := second()
	for expected in [18,10,30,0,21,11,31,0]:
		check(Game.valid_combat(saved(m)),"new phase-two action shape accepted")
		var restore := CombatModel.new();restore.restore(saved(m))
		seed(991);var result := m.end_turn()
		seed(991);var resumed := restore.end_turn()
		check(damage(result) == expected,"second-phase damage "+str(expected))
		check(JSON.stringify(result) == JSON.stringify(resumed) and saved(m) == saved(restore),"sin, strength and cycle survive JSON roundtrip")
	for hits in 4:
		m = second();m.end_turn();m.end_turn()
		check(m.weak == 1 and m.buffs.count(m,"alien_sin",0) == 3,"聚日 follows weakening triple attack and grants three sin")
		m.enemies[0].block = 100
		for i in hits:
			var hit := m.enemy_damage(0,0,false,true)
			check(hit.alienSinAfter == 2-i,"even fully blocked zero-damage attack segments remove one sin")
		check(m.enemy_intent_damage(m.enemies[0]) == 30-hits*4,"live heavy preview 30/26/22/18")
		var result := m.end_turn()
		check(damage(result) == 30-hits*4 and result.attacks[0].alienSinUsed == 3-hits and m.buffs.count(m,"alien_sin",0) == 0,"heavy uses remaining sin once then clears it")
	m = second();m.end_turn();m.end_turn()
	m.enemy_damage(0,1);m.buffs.apply(m,"pollution",1,0);m.buffs.own_turn_end(m,0)
	m.buffs.apply(m,"parry",1);m.buffs.after_enemy_attack(m,0,2)
	check(m.buffs.count(m,"alien_sin",0) == 3,"direct, poison and parry damage do not discharge sin")
	m.buffs.apply(m,"energy_suit",1,0);m.enemy_damage(0,1,false,true)
	check(m.buffs.count(m,"alien_sin",0) == 2,"energy suit never blocks independent sin decay")
	m.buffs.apply(m,"alien_sin",999,0)
	check(m.buffs.count(m,"alien_sin",0) == 3,"sin has a global three-layer cap")
	m.buffs.clear(m,"electric_charge",0)
	m.enemies[0].intent = Game.enemy_catalog.noss_phase2.intentSequence[0].duplicate(true)
	check(m.enemy_intent_damage(m.enemies[0]) == 6,"sin does not amplify ordinary light swords")
	m = second();m.end_turn();m.end_turn();m.buffs.apply(m,"strength",2,0);m.buffs.apply(m,"weak",1,0);m.buffs.apply(m,"vulnerable",2)
	check(m.enemy_intent_damage(m.enemies[0]) == 36 and damage(m.end_turn()) == 36,"sin adds before enemy weak and player vulnerable, preview equals actual")
func test_validation() -> void:
	var m := second();m.end_turn();m.end_turn()
	for value in [-1,4,0.5,"3",true]:
		var bad := saved(m);bad.enemies[0].buffs.alien_sin = value
		check(not Game.valid_combat(bad),"reject invalid alien_sin "+str(value))
	for key in ["postSin","sinMultiplier"]:
		for value in [-1,0.5,"3",true]:
			var bad := saved(m);bad.profile.phaseTwoEnemies[0].intentSequence[1 if key == "postSin" else 2][key] = value
			check(not Game.valid_combat(bad),"reject malformed frozen "+key)
	var bad := saved(m);bad.profile.phaseOneEndEnemyId = "noss_hand_left"
	check(not Game.valid_combat(bad),"reject malformed phase-one target")
	check(not m.buffs.valid_card_effect({"type":"buff","id":"alien_sin","amount":3}),"boss status cannot be applied by unsupported cards")
func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in OS.get_user_data_dir().to_lower():get_tree().quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused.json");Game.meta_path = output.path_join("unused-meta.json")
	test_first();test_sin();test_validation()
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("NOSS INTENTS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
