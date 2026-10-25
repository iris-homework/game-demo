extends Node
var checks := 0
var failures: Array[String] = []
var output := "/tmp/midnight-dancer-rules-20261025/mechanics"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("DANCER MECHANICS: " + message)

func boss() -> CombatModel:
	Game.save_enabled = false
	Game.training_mode = false
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.page = "map"
	Game.battle_busy = false
	Game.transition_locked = false
	Game.start_training("B16")
	var m := CombatModel.new()
	m.restore(Game.state.combat)
	m.player_hp = 10000
	m.max_hp = 10000
	return m

func phase_two() -> CombatModel:
	var m := boss()
	m.enemy_damage(0, 999)
	m.resolve_outcome()
	check(m.advance_encounter_phase(), "phase two opens")
	return m

func to_hand(m: CombatModel, card_id: String) -> String:
	var uid: String = "encounter_" + card_id
	for zone in [m.draw_pile, m.discard_pile, m.hand]: zone.erase(uid)
	m.hand.append(uid)
	return uid

func run_rules() -> void:
	var m := boss()
	check(m.enemies[0].hp == 80, "phase one 80 HP")
	check(m.instances.values().count("dancer_black_card") == 0, "no encounter cards in phase one")
	for i in 4:
		var expected := 15 if i % 2 == 0 else 10
		check(m.enemies[0].intent.amount == expected, "phase one ordered intent " + str(i))
		m.block = 100
		var before := m.player_hp
		var result := m.end_turn()
		check(result.attacks.size() == 1 and m.player_hp == before, "phase-one block absorbs attack")
		check(m.weak == (2 if i % 2 == 1 else (1 if i > 0 else 0)), "weak once per whole attack, including blocked hit")
	m = phase_two()
	check(m.enemies.map(func(e): return e.hp) == [80, 80], "phase two both 80 HP")
	check(m.enemies.all(func(e): return m.buffs.count(m,"soul_link", m.enemies.find(e)) == 2), "initial soul links two each")
	check(m.enemies[1].block == 0 and m.buffs.count(m,"strength",0) == 0, "entry player round grants no soul-link buffs")
	check(m.instances.values().count("dancer_black_card") == 1 and m.instances.values().count("dancer_white_card") == 1, "exactly one card each generated")
	check(Game.valid_combat(m.snapshot()), "phase two snapshot valid")
	check(m.enemies[0].intentSequence.map(func(i): return int(i.amount)) == [15,3,10], "black base intentions are attack fifteen, vulnerable three, attack ten")
	check(m.enemies[1].intentSequence.map(func(i): return int(i.amount)) == [2,4,10], "white base intentions are weak two, attack four times three, heal ten")
	var preview_saved := m.snapshot()
	check(m.enemy_intent_damage(m.enemies[0]) == 17, "initial attack preview includes pending two soul strength")
	check(m.snapshot() == preview_saved, "pending soul-link preview never mutates model")
	var phase_saved := m.snapshot()
	var copy := CombatModel.new()
	copy.restore(JSON.parse_string(JSON.stringify(phase_saved)))
	check(JSON.parse_string(JSON.stringify(copy.snapshot())) == JSON.parse_string(JSON.stringify(phase_saved)), "all phase mechanics JSON roundtrip")
	for cycle in 2:
		for step in 3:
			check(m.enemies[0].intent.type == ["attack","vulnerable","attack"][step], "black three-step cycle")
			check(m.enemies[1].intent.type == ["weak","attack","heal_ally"][step], "white three-step cycle")
			m.block = 1000
			if step == 2: m.enemies[0].hp = 75
			var result := m.end_turn()
			var link_events: Array = result.turnEvents.filter(func(e): return e.type == "status_apply" and e.get("target",-1) >= 0 and e.buffId in ["block","strength"])
			check(link_events.size() == 2, "one pair of soul-link events per enemy phase")
			check(result.turnEvents.find(link_events[1]) < result.turnEvents.find(result.attacks[0]), "both soul links trigger before the first attack")
			if cycle == 0 and step == 0:
				check(result.attacks[0].hits[0].blocked == 17, "first black attack resolves fifteen plus two new strength")
			if step == 1:
				check(result.attacks.size() == 1 and result.attacks[0].hits.size() == 3, "white hits exactly three times")
				check(m.buffs.count(m,"vulnerable") == 3, "black applies three vulnerable")
			if step == 2:
				check(m.enemies[0].hp == 80, "heal caps at max HP")
				check(result.turnEvents.any(func(e): return e.type == "heal" and e.amount == 5 and e.hpAfter == 80), "heal event records actual restoration")
			check(m.enemies[1].block == 10, "white receives fixed ten block survives enemy actions into player round")
			check(m.buffs.count(m,"strength",0) == (cycle*3+step+1)*2, "black gains two permanent strength each round")
	# Removing the final link during player input prevents this enemy phase's
	# strength, including in the head-intent preview and after snapshot restore.
	m = phase_two()
	m.energy = 20
	var remove_uid := to_hand(m,"dancer_black_card")
	m.play_card(remove_uid)
	check(m.enemy_intent_damage(m.enemies[0]) == 17, "one remaining white link still predicts full bonus")
	to_hand(m,"dancer_black_card")
	m.play_card(remove_uid)
	check(m.enemy_intent_damage(m.enemies[0]) == 15, "removing final white link updates preview before enemy phase")
	copy.restore(m.snapshot())
	check(copy.buffs.count(copy,"strength",0) == 0 and copy.enemies[1].block == 0, "restore does not trigger soul links")
	var unlinked := copy.end_turn()
	check(unlinked.attacks[0].damage == 15 and copy.buffs.count(copy,"strength",0) == 0, "removed white link prevents imminent strength and attack bonus")
	check(copy.enemies[1].block == 10, "other dancer's link still supplies white shield")
	copy.buffs.clear(copy,"soul_link",0)
	copy.end_turn()
	check(copy.enemies[1].block == 0, "old shield expires before disabled link can regrant it")
	m = phase_two()
	m.enemy_damage(1,999)
	check(m.enemy_intent_damage(m.enemies[0]) == 15, "dead white source grants no predicted strength")
	m.end_turn()
	check(m.buffs.count(m,"strength",0) == 0, "dead white source grants no actual strength")
	for dead_index in 2:
		m = phase_two()
		m.block = 1000
		m.end_turn()
		check(m.buffs.count(m,"strength",0) == 2 and m.enemies[1].block == 10, "both living dancers granted first enemy-phase buffs")
		m.enemy_damage(dead_index,999)
		check(m.buffs.count(m,"soul_link",1-dead_index) == 2, "survivor retains link layers, but no living partner")
		var after_death := m.end_turn()
		check(not after_death.turnEvents.any(func(e): return e.type == "status_apply" and e.get("target",-1) >= 0 and e.buffId in ["block","strength"]), "either dancer's death stops both cross buffs: " + str(dead_index))
		check(m.buffs.count(m,"strength",0) == 2, "death stops future strength without retracting previously earned strength")
		if dead_index == 0:
			check(m.enemies[1].block == 0, "surviving white's old shield expires without being replenished")
		else:
			check(m.enemy_intent_damage(m.enemies[0]) == 18, "surviving black predicts attack ten plus existing strength under vulnerability, no new link bonus")
	m = phase_two()
	m.player_hp = 1
	m.buffs.apply(m,"pollution",2)
	var terminal := m.end_turn()
	check(terminal.outcome == "lose" and not terminal.turnEvents.any(func(e): return e.type == "status_apply"), "lethal player-turn status prevents enemy-phase soul links")
	m = phase_two()
	m.energy = 20
	var black_uid := to_hand(m,"dancer_black_card")
	check(m.card_cost(black_uid) == 1 and m.card_target(black_uid) == "self", "black card one cost and automatic white target")
	var white_strength := m.buffs.count(m,"strength",0)
	check(not m.play_card(black_uid).is_empty() and m.buffs.count(m,"soul_link",1) == 1, "black card removes white link only")
	check(m.buffs.count(m,"soul_link",0) == 2 and black_uid in m.discard_pile and m.energy == 19, "cost and normal discard; black link intact")
	check(m.play_card(black_uid).is_empty() and m.energy == 19, "duplicate submission rejected")
	m.begin_dancer_enemy_turn()
	check(m.buffs.count(m,"strength",0) == white_strength+2, "one remaining link still grants full two strength")
	to_hand(m,"dancer_black_card")
	m.play_card(black_uid)
	check(m.buffs.count(m,"soul_link",1) == 0, "second use removes final link")
	white_strength = m.buffs.count(m,"strength",0)
	m.begin_dancer_enemy_turn()
	check(m.buffs.count(m,"strength",0) == white_strength, "zero white links stops new strength")
	check(white_strength > 0, "removal retains already earned strength")
	var white_uid := to_hand(m,"dancer_white_card")
	m.play_card(white_uid)
	check(m.buffs.count(m,"soul_link",0) == 1, "white card removes black link")
	to_hand(m,"dancer_white_card")
	m.play_card(white_uid)
	m.enemies[1].block = 0
	m.begin_dancer_enemy_turn()
	check(m.enemies[1].block == 0, "zero black links stops new block")
	m = phase_two()
	m.enemy_damage(0,999)
	m.enemies[1].intentIndex = 2
	m.enemies[1].intent = m.intent_for(m.enemies[1],2)
	var result := m.end_turn()
	check(m.enemies[0].hp == 0 and not result.turnEvents.any(func(e): return e.type == "heal"), "healing never revives dead black dancer")
	check(m.enemies[1].block == 0, "dead link holder grants no block")
	m = boss()
	m.draw_cards()
	var attack_id: String = m.hand.filter(func(uid): return m.card(uid).type == "attack")[0]
	m.weak = 2
	var definition: Dictionary = m.card(attack_id)
	var effect: Dictionary = definition.effects.filter(func(e): return e.type == "damage")[0]
	var reduced := m.attack_hit_amount(definition,effect,"melee",2,m.enemies[0],0,0)
	m.weak = 0
	var normal := m.attack_hit_amount(definition,effect,"melee",2,m.enemies[0],0,0)
	m.weak = 2
	check(reduced == roundi(normal*0.75), "player weak reduces attack damage 25 percent")
	m.block = 1000
	m.end_turn()
	check(m.weak == 1, "player weak decays on own turn end")
	var old := m.snapshot()
	old.norenState.erase("weak")
	check(Game.valid_combat(old), "old snapshots may omit player weak")
	copy = CombatModel.new()
	copy.restore(old)
	check(copy.weak == 0, "old snapshot missing weak restores zero")
	for value in [-1, 1.5, 1000, "2"]:
		var bad := m.snapshot()
		bad.norenState.weak = value
		check(not Game.valid_combat(bad), "invalid player weak rejected " + str(value))
	m = phase_two()
	# Old released dancer encounters freeze 10 HP and attack 6 in both phases.
	var legacy := m.snapshot()
	legacy.encounterPhase = 1
	legacy.profile.erase("phaseOneEnemies")
	legacy.profile.erase("phaseTwoCards")
	for definition_old in legacy.profile.phaseTwoEnemies:
		definition_old.maxHp = 10
		definition_old.erase("buffs")
		definition_old.intentSequence = [{"type":"attack","amount":6,"hits":1}]
	legacy.enemies = [legacy.profile.phaseTwoEnemies[0].duplicate(true)]
	legacy.enemies[0].merge({"hp":10,"block":0,"bleed":0,"weak":0,"intentIndex":0,"intent":{"type":"attack","amount":6,"hits":1}},true)
	for color in ["black","white"]:
		var card_id: String = "dancer_"+color+"_card"
		var card_uid: String = "encounter_"+card_id
		legacy.instances.erase(card_uid)
		for zone in [legacy.drawPile,legacy.hand,legacy.discardPile]: zone.erase(card_uid)
		legacy.cardCatalog.erase(card_id)
	legacy.norenState.erase("weak")
	check(Game.valid_combat(legacy), "released legacy ten-HP phase-one snapshot remains valid")
	copy = CombatModel.new()
	copy.restore(legacy)
	copy.enemy_damage(0,10)
	copy.resolve_outcome()
	check(copy.advance_encounter_phase() and copy.enemies.all(func(e): return e.hp == 10 and e.intent.amount == 6), "legacy transition retains frozen old numbers")
	check(Game.valid_combat(copy.snapshot()) and copy.instances == legacy.instances, "legacy phase-two snapshot validates without injected new cards")
	var bad_instances := m.snapshot()
	bad_instances.instances.erase("encounter_dancer_black_card")
	check(not Game.valid_combat(bad_instances), "new phase-two snapshot rejects missing generated card")
	var duplicate_start := m.instances.duplicate(true)
	check(not m.advance_encounter_phase() and m.instances == duplicate_start, "phase transition cannot generate cards twice")
	m.enemies[0].hp = 70
	m.enemies[0].intentIndex = 2
	m.enemies[0].intent = m.intent_for(m.enemies[0],2)
	m.enemies[1].intentIndex = 2
	m.enemies[1].intent = m.intent_for(m.enemies[1],2)
	m.block = 1000
	m.end_turn()
	check(m.enemies[0].hp == 80, "white restores exactly ten when enough HP is missing")
	for value in [-1, 1.5, 3, "2"]:
		var bad := m.snapshot()
		bad.enemies[0].buffs.soul_link = value
		check(not Game.valid_combat(bad), "invalid soul count rejected " + str(value))
	var bad := m.snapshot()
	bad.profile.phaseTwoEnemies[1].intentSequence[2].targetIds = ["missing"]
	check(not Game.valid_combat(bad), "invalid frozen heal target rejected")
	check(not Game.card_catalog.has("dancer_black_card") and not Game.reward_rules.cards.has("dancer_white_card"), "encounter cards excluded from owned and reward catalogs")

func _ready() -> void:
	if not OS.get_environment("QA_OUT_DIR").is_empty(): output = OS.get_environment("QA_OUT_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_path = output.path_join("checkpoint.json")
	Game.meta_path = output.path_join("meta.json")
	run_rules()
	var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	file.close()
	print("DANCER MECHANICS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
