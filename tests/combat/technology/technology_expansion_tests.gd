extends Node
## Full rules transactions, frozen snapshots and previews; QA user directory only.
const Fixtures = preload("res://tests/combat/cards/noren_cards_tests.gd")
const FORCE := "emergency_forcefield"
const MAG := "folding_magazine"
const CLEAN := "purification_filter"
const PHASE := "phase_plating"
const RECYCLE := "recycling_protocol"
const COUNTER := "counter_calibrator"
var fixtures := Fixtures.new()
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("TECHNOLOGY EXPANSION: " + message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func fixture(technologies: Array, cards: Array = [1], form: String = "melee", targets: int = 1) -> CombatModel:
	var m: CombatModel = fixtures.fixture(cards, form, targets)
	m.profile.cyberware = {"cards":[]}
	m.profile.playerCyberwareIds = technologies.duplicate()
	for id in technologies: m.profile.cyberware.cards.append(Game.cyberware_definition(id).duplicate(true))
	return m

func conserved(m: CombatModel, context: String) -> void:
	var zones: Array = m.hand + m.draw_pile + m.discard_pile + m.exhaust_pile
	var unique := {}
	for uid in zones: unique[uid] = true
	check(zones.size() == unique.size() and zones.size() == m.instances.size() and Game.valid_combat(m.snapshot()), context + ": all instances conserved and snapshot valid")

func test_active() -> void:
	var m := fixture([FORCE,MAG,CLEAN])
	check(m.available_cyberware_count() == 3, "Three new active technologies initially ready")
	m.energy = 0
	m.ammo = 9
	check(m.activate_cyberware(FORCE) and m.block == 10 and m.energy == 0, "Forcefield supplies ten block at zero energy")
	check(m.activate_cyberware(MAG) and m.ammo == 10 and m.energy == 0, "Magazine supplies ammo up to cap without spending energy")
	check(m.cyberware_cooldown(FORCE) == 3 and m.cyberware_cooldown(MAG) == 4, "Independent authored cooldowns")
	m.buffs.apply(m,"pollution",999)
	m.buffs.apply(m,"weak",999)
	m.buffs.apply(m,"vulnerable",999)
	m.buffs.apply(m,"strength",-7)
	m.buffs.apply(m,"parry",2)
	m.buffs.apply(m,"next_damage",6)
	m.buffs.apply(m,"melee_attack_bleed")
	m.buffs.apply(m,"pollution",8,0)
	m.buffs.apply(m,"weak",3,0)
	var enemies_before := m.enemies.duplicate(true)
	check(m.activate_cyberware(CLEAN), "Filter activates with multiple capped debuffs")
	check(m.weak == 0 and m.buffs.count(m,"pollution") == 0 and m.buffs.count(m,"vulnerable") == 0 and m.buffs.count(m,"strength") == 0, "Filter removes all debuff layers and negative strength")
	check(m.block == 10 and m.parry == 2 and m.turn_damage_bonus == 6 and "melee_attack_bleed" in m.powers and m.enemies == enemies_before, "Filter preserves positive statuses, powers, block and enemy states")
	check(m.cyberware_cooldown(CLEAN) == 999, "Filter uses literal 999-turn cooldown")
	var after := m.snapshot()
	check(not m.activate_cyberware(CLEAN) and not m.activate_cyberware(FORCE) and not m.activate_cyberware(MAG) and same(after,m.snapshot()), "Cooling activations reject atomically")
	conserved(m,"Active technologies")
	m = fixture([CLEAN])
	m.buffs.apply(m,"strength",7)
	check(m.activate_cyberware(CLEAN) and m.buffs.count(m,"strength") == 7, "Filter can activate without debuffs and preserves positive strength")
	# Generic catalog statuses must also be cleansed without hard-coded ID lists.
	m = fixture([CLEAN])
	var synthetic := m.buffs.definition("pollution")
	synthetic.id = "qa_generic_debuff"
	synthetic.handler = "none"
	synthetic.duration = "battle"
	m.buffs._catalog[synthetic.id] = synthetic
	m.buffs.apply(m,synthetic.id,11)
	check(m.activate_cyberware(CLEAN) and m.buffs.count(m,synthetic.id) == 0, "Filter cleanses generic negative catalog entries without explicit handler support")
	for enemy in m.enemies:
		enemy.intent = {"type":"attack","amount":0,"hits":1}
		enemy.intentSequence = [enemy.intent.duplicate()]
	for index in 998: m.end_turn()
	check(m.turn == 999 and m.cyberware_cooldown(CLEAN) == 1 and not m.cyberware_available(CLEAN), "Filter still cooling on turn 999")
	m.end_turn()
	check(m.turn == 1000 and m.cyberware_available(CLEAN) and m.activate_cyberware(CLEAN), "Filter truly becomes available on turn 1000")
	for id in [FORCE,MAG,CLEAN]:
		m = fixture([id])
		m.profile.erase("ruleset")
		after = m.snapshot()
		check(not m.activate_cyberware(id) and same(after,m.snapshot()), "New Noren-only active rejects legacy rules: " + id)
		m = fixture([id])
		m.outcome = "win"
		after = m.snapshot()
		check(not m.activate_cyberware(id) and same(after,m.snapshot()), "Terminal battle cannot activate: " + id)
	m = fixture([FORCE,MAG])
	m.activate_cyberware(FORCE)
	m.activate_cyberware(MAG)
	for i in 3: m.end_turn()
	check(m.cyberware_available(FORCE) and not m.cyberware_available(MAG) and m.cyberware_cooldown(MAG) == 1, "Forcefield ready on turn four while magazine still cooling")
	m.end_turn()
	check(m.cyberware_available(MAG) and m.cyberware_available(FORCE), "Magazine ready on turn five")

func test_stance() -> void:
	var m := fixture([PHASE,"dimensional_pocket"])
	check(m.block == 0 and not m.technology_turn_state.stanceBlockUsed, "Initial melee does not grant plating block")
	m.change_stance("melee")
	check(m.block == 0 and not m.technology_turn_state.stanceBlockUsed, "Same stance does not consume first switch")
	check(m.activate_cyberware("dimensional_pocket") and m.block == 4 and m.stance == "ranged", "Pocket actual switch grants four block")
	m.change_stance("melee")
	check(m.block == 4 and m.technology_turn_state.stanceBlockUsed, "Second switch draws normally without more block")
	m.end_turn()
	check(m.block == 0 and not m.technology_turn_state.stanceBlockUsed, "Player turn boundary clears block and resets switch opportunity")
	m.change_stance("ranged")
	check(m.block == 4, "Plating triggers again on next turn")
	conserved(m,"Plating across turns")
	m = fixture([PHASE],[4])
	var before := m.snapshot()
	var preview := m.card_preview("card_000")
	check(same(before,m.snapshot()) and "获得4点格挡" in preview.text, "Switch card preview includes plating without spending it")
	var result := m.play_card("card_000",-1)
	check(not result.is_empty() and m.block == 10 and m.stance == "ranged", "Switch card stacks its own six block with plating four")
	conserved(m,"Switch card plating")

func test_exhaust() -> void:
	var m := fixture([RECYCLE],[45,45])
	m.energy = 0
	var before := m.snapshot()
	var preview := m.card_preview("card_000")
	check("回收协议：抽1张牌" in preview.text and same(before,m.snapshot()), "Exhaust preview includes extra draw and remains read-only")
	var result := m.play_card("card_000",-1)
	check(result.drawn.size() == 3 and m.technology_turn_state.exhaustDrawUsed and not "card_000" in m.hand, "Instant calculation draws two plus one and stays exhausted")
	result = m.play_card("card_001",-1)
	check(result.drawn.size() == 2 and m.exhaust_pile.has("card_001"), "Second exhausted card this turn grants no extra draw")
	conserved(m,"Two self-exhausts")
	m = fixture([RECYCLE],[12,2])
	result = m.play_card("card_000",-1,"card_001")
	check(result.drawn.size() == 1 and result.exhaustedCards == ["card_001"] and not result.exhausted, "Selected hand exhaust triggers protocol while dismantle itself is discarded")
	check(not "card_001" in m.hand and m.ammo == 5, "Selected exhaust never plays discarded card effects")
	conserved(m,"Selected hand exhaust")
	m = fixture([RECYCLE],[12,2])
	m.card_catalog.noren_12.exhaust = true
	result = m.play_card("card_000",-1,"card_001")
	check(result.drawn.size() == 1 and m.exhaust_pile.size() == 2, "Selected plus self exhaust within one play only draws once")
	conserved(m,"Multiple exhausts in one card")
	m = fixture([RECYCLE],[23])
	result = m.play_card("card_000",-1)
	check(result.drawn.size() == 1 and result.exhausted and not m.powers.is_empty(), "Power entering exhaust triggers protocol after applying power")
	conserved(m,"Power exhaust")
	m = fixture([RECYCLE],[45])
	m.exhaust_pile.append_array(m.draw_pile)
	m.draw_pile.clear()
	result = m.play_card("card_000",-1)
	check(result.drawn.is_empty() and m.technology_turn_state.exhaustDrawUsed, "Empty supply consumes opportunity without inventing cards")
	m.end_turn()
	check(not m.technology_turn_state.exhaustDrawUsed, "Protocol opportunity resets on next player turn")
	conserved(m,"Exhausted supply")
	m = fixture([RECYCLE],[1])
	m.play_card("card_000",0)
	check(not m.technology_turn_state.exhaustDrawUsed, "Ordinary discard does not trigger protocol")

func test_attack() -> void:
	for form in ["melee","ranged"]:
		var m := fixture([COUNTER],[35,35],form,2)
		m.block = 1
		m.card_catalog.noren_35.cost = 0
		m.card_catalog.noren_35.effects = [{"type":"damage","amount":4,"hits":3}]
		m.card_catalog.noren_35.target = "all"
		var before := m.snapshot()
		var preview := m.card_preview("card_000",0)
		var expected := 9 if form == "ranged" else 6
		check(preview.effects[1].samples.all(func(sample): return sample == [expected,expected,expected]) and same(before,m.snapshot()), "Guarded first attack preview applies +2 before form multiplier: " + form)
		var result := m.play_card("card_000",0)
		check(result.hits.size() == 6 and result.hits.all(func(hit): return hit.attackDamage == expected), "Guarded first attack adds bonus to every hit and every target: " + form)
		check(m.block == 1 and m.technology_turn_state.firstAttackUsed, "Bonus keeps block and spends first attack opportunity: " + form)
		result = m.play_card("card_001",0)
		var unboosted := 6 if form == "ranged" else 4
		check(result.hits.all(func(hit): return hit.attackDamage == unboosted), "Later attacks get no calibration bonus: " + form)
		conserved(m,"Guarded attacks " + form)
	var m := fixture([COUNTER],[1,1])
	m.play_card("card_000",0)
	m.block = 10
	check(m.guarded_attack_bonus() == 0 and m.technology_turn_state.firstAttackUsed, "Unguarded first attack still consumes first attack opportunity")
	m.end_turn()
	m.block = 1
	check(m.guarded_attack_bonus() == 2 and not m.technology_turn_state.firstAttackUsed, "First attack opportunity resets at next turn")
	m = fixture([COUNTER],[1])
	m.block = 1
	var before := m.snapshot()
	check(m.play_card("card_000",-1).is_empty() and same(before,m.snapshot()), "Rejected target cannot spend first attack")
	m.energy = 0
	before = m.snapshot()
	check(m.play_card("card_000",0).is_empty() and same(before,m.snapshot()), "Rejected energy cannot spend first attack")

func test_snapshots() -> void:
	var m := fixture([PHASE,RECYCLE,COUNTER],[12,2,1])
	m.change_stance("ranged")
	m.play_card("card_000",-1,"card_001")
	m.play_card("card_002",0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(m.snapshot()))
	check(Game.valid_combat(saved) and saved.technologyTurnState.values().all(func(value): return value == true), "All three opportunities freeze after use")
	var restored := CombatModel.new()
	restored.restore(saved)
	check(same(saved,restored.snapshot()) and restored.guarded_attack_bonus() == 0, "Exact JSON roundtrip retains spent opportunities")
	restored.change_stance("melee")
	check(restored.block == m.block, "Restore cannot re-trigger already used plating")
	for bad in [null,[],{}, {"stanceBlockUsed":true}, {"stanceBlockUsed":1,"exhaustDrawUsed":true,"firstAttackUsed":true}, {"stanceBlockUsed":true,"exhaustDrawUsed":true,"firstAttackUsed":true,"extra":false}]:
		var corrupt := saved.duplicate(true)
		corrupt.technologyTurnState = bad
		check(not Game.valid_combat(corrupt), "Malformed trigger state rejects: " + str(bad))
	var missing := saved.duplicate(true)
	missing.erase("technologyTurnState")
	check(not Game.valid_combat(missing), "New frozen passive battle cannot omit spent opportunity mapping")
	m = fixture([])
	var old := m.snapshot()
	check(not old.has("technologyTurnState") and Game.valid_combat(old), "Old frozen loadouts need no new state")
	restored.restore(old)
	check(same(old,restored.snapshot()), "Old snapshots restore without adding new fields")
	m = fixture([PHASE])
	var corrupt := m.snapshot()
	corrupt.technologyTurnState.firstAttackUsed = true
	check(not Game.valid_combat(corrupt), "State cannot claim attack trigger without corresponding equipped effect")
	m = fixture([])
	m.profile.cyberware.cards = [Game.cyberware_definition("test_cyberware_01"),Game.cyberware_definition("test_cyberware_02"),Game.cyberware_definition("test_cyberware_03"),Game.cyberware_definition("test_cyberware_04"),Game.cyberware_definition(PHASE)]
	m.profile.playerCyberwareIds = m.profile.cyberware.cards.map(func(entry): return entry.id)
	m.change_stance("ranged")
	check(m.block == 0 and not m.snapshot().has("technologyTurnState") and Game.valid_combat(m.snapshot()), "Fifth technology in frozen legacy loadout cannot trigger or require new state")

func test_phase_boundary() -> void:
	Game.state = Game.initial_state()
	Game.state.currentWeek = 2
	Game.state.ownedCyberwareIds = [PHASE,RECYCLE,COUNTER,CLEAN]
	Game.state.equippedCyberwareIds = Game.state.ownedCyberwareIds.duplicate()
	var boss_id := ""
	for id in Game.battles:
		if Game.battles[id].get("encounterId", "") == "noss_sovereign": boss_id = id
	check(not boss_id.is_empty(), "Authored Noss encounter available")
	if boss_id.is_empty(): return
	Game.state.battleId = boss_id
	Game.initialize_combat()
	var m := CombatModel.new()
	m.restore(Game.state.combat)
	m.draw_cards()
	m.change_stance("ranged")
	m.technology_turn_state.exhaustDrawUsed = true
	m.technology_turn_state.firstAttackUsed = true
	m.activate_cyberware(CLEAN)
	m.kill_enemies()
	check(m.encounter_phase == 2 and m.turn == 2 and m.technology_turn_state.values().all(func(value): return value == false), "Boss next player turn resets all three opportunities once")
	check(m.cyberware_cooldown(CLEAN) == 998 and m.block == 0, "Boss phase ticks filter cooldown once and clears old block")
	m.change_stance("melee")
	check(m.block == 4, "Plating available in fresh Boss phase")
	conserved(m,"Noss next player turn")

func test_battle_restart() -> void:
	Game.state = Game.initial_state()
	Game.state.ownedCyberwareIds = [PHASE,RECYCLE,COUNTER,CLEAN]
	Game.state.equippedCyberwareIds = Game.state.ownedCyberwareIds.duplicate()
	Game.state.battleId = "B04"
	Game.state.targetId = "richard"
	Game.state.activeEventId = "E04"
	Game.state.activeNodeId = "battle"
	Game.state.currentPlaceId = "alley"
	Game.state.currentScene = "battle"
	Game.initialize_combat()
	var initial: Dictionary = Game.state.battleStart.duplicate(true)
	var m := CombatModel.new()
	m.restore(Game.state.combat)
	m.draw_cards()
	m.change_stance("ranged")
	m.activate_cyberware(CLEAN)
	check(Game.commit_combat(m) and Game.save_game(), "Actual Game commits new technology combat and saves opening projection")
	Game.state = {}
	check(Game.load_game() and same(Game.state.combat,initial), "Formal restart policy restores exact frozen opening with unspent passives")

func _ready() -> void:
	if not "qa" in OS.get_user_data_dir().to_lower():
		push_error("Technology expansion tests require an isolated QA user directory")
		fixtures.free()
		get_tree().quit(2)
		return
	Game.save_enabled = false
	Game.save_path = "user://technology_expansion_test_checkpoint.json"
	Game.meta_path = "user://technology_expansion_test_meta.json"
	seed(20261109)
	test_active()
	test_stance()
	test_exhaust()
	test_attack()
	test_snapshots()
	test_phase_boundary()
	test_battle_restart()
	for path in [Game.save_path,Game.save_path+".bak",Game.save_path+".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	fixtures.free()
	print("TECHNOLOGY EXPANSION: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
