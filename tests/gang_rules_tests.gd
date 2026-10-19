extends Node
const Fixtures = preload("res://tests/noren_cards_tests.gd")
var fixtures := Fixtures.new()
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func gang() -> CombatModel:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	rules.shuffleInitialDeck = false
	var definitions: Array = []
	for id in Game.battles.B04.enemyIds: definitions.append(Game.enemy_catalog[id])
	var m := CombatModel.new()
	m.initialize("B04", 100, 100, rules, definitions, Game.card_catalog)
	return m

func saved(m: CombatModel) -> Dictionary:
	return JSON.parse_string(JSON.stringify(m.snapshot()))

func events(result: Dictionary, kind: String) -> Array:
	return result.turnEvents.filter(func(event): return event.type == kind)

func test_encounter() -> void:
	check(Game.events.E04.nodes.battle.battleId == "B04" and Game.battles.B04.placeId == "alley", "Existing event routes to B04 in alley")
	check(Game.battles.B04.enemyIds == ["gang_henchman", "gang_henchman_second", "gang"], "Two distinct henchmen precede boss")
	var m := gang()
	check(m.enemies.map(func(e): return e.hp) == [15, 15, 30], "Authored 15/15/30 HP")
	check(m.enemies.map(func(e): return e.formationSlot) == ["triangle_left_back", "triangle_left_front", "triangle_right"], "Explicit triangle slots independent of action order")
	for round_index in 5:
		check(m.enemy_intent_text(m.enemies[0]) == "攻击 %d" % (4 + round_index), "Henchman preview includes accumulated strength")
		check(m.enemy_intent_text(m.enemies[2]) == "强化 +1", "Boss keeps strengthening while both alive")
		m.block = 999
		var result := m.end_turn()
		check(result.attacks.map(func(a): return a.id) == ["gang_henchman", "gang_henchman_second"], "Henchmen take turns, no boss attack")
		check(result.attacks.all(func(a): return a.hits.size() == 1 and a.hits[0].blocked == 4 + round_index), "Both attacks use strength from preceding rounds")
		check(result.turnEvents.map(func(e): return e.type) == ["attack", "attack", "status_apply", "status_apply"], "Reinforcement occurs after both attacks")
		var gains := events(result, "status_apply")
		check(gains.map(func(e): return e.target) == [0, 1] and gains.all(func(e): return e.source == 2 and e.buffId == "strength" and e.amount == 1), "Boss grants exactly one strength to each henchman")
		check(m.buffs.count(m, "strength", 0) == round_index + 1 and m.buffs.count(m, "strength", 1) == round_index + 1 and m.buffs.count(m, "strength", 2) == 0, "No strength decay or boss self-buff")
		check(Game.valid_combat(saved(m)), "Strengthening phase snapshot valid")
	var adventure := Game.state.duplicate(true)
	Game.state = Game.initial_state()
	Game.start_training("B04")
	check(Game.state.combat.enemies.map(func(e): return e.hp) == [15, 15, 30], "B04 training also uses authored HP")
	Game.finish_training("lose")
	check(Game.state == Game.initial_state(), "B04 training restores prior adventure")
	Game.state = adventure
	Game.state = Game.initial_state()
	Game.state.flags.alleyClue = true
	Game.state.targetId = "richard"
	check(Game.start_event("E04"), "Formal E04 starts after existing clue requirement")
	for step in 3: Game.advance(Game.revision)
	check(Game.state.currentScene == "battle" and Game.state.battleId == "B04" and Game.state.combat.enemies.map(func(e): return e.hp) == [15, 15, 30], "Normal dialogue enters the actual three-enemy encounter")
	check(Game.valid_save(Game.state), "Formal adventure with gang encounter validates")
	Game.state = adventure

func test_boundary_and_cycles() -> void:
	for dead_index in [0, 1]:
		var m := gang()
		m.block = 999
		m.end_turn()
		m.enemy_damage(dead_index, 15)
		check(m.enemies[2].intent.type == "strength_allies" and not m.enemies[2].has("intentPhase"), "Player-turn death does not immediately change boss intent")
		var before := saved(m)
		var restored := CombatModel.new()
		restored.restore(before)
		check(saved(restored) == before and restored.enemies[2].intent.type == "strength_allies", "Loading pending death does not switch early")
		for step in 7:
			m.block = 999
			var result := m.end_turn()
			var changes := events(result, "intent_change")
			check(changes.size() == (1 if step == 0 else 0), "Boss switches once at first eligible boundary")
			if step == 0:
				check(result.turnEvents[0].type == "intent_change" and result.turnEvents[0].intent.amount == 8, "Switch event precedes first surviving henchman")
			check(result.attacks[0].index == 1 - dead_index, "Only surviving henchman acts first")
			if step % 3 == 1:
				var applications := events(result, "status_apply")
				check(result.attacks.size() == 1 and applications.size() == 1 and applications[0].buffId == "vulnerable" and applications[0].amount == 2, "Boss second phase applies two vulnerable")
			else:
				var expected := 8 if step % 3 == 0 else 6
				var magnified := step % 3 == 2
				check(result.attacks.size() == 2 and result.attacks[1].index == 2 and result.attacks[1].hits[0].blocked == roundi(expected * (1.5 if magnified else 1.0)), "Boss attack8/vulnerable2/attack6 cycle, per-hit vulnerability")
			check(m.buffs.count(m, "strength", 1 - dead_index) == 1, "Boss stops reinforcement after switching")
			check(Game.valid_combat(saved(m)), "Combat phase validates and keeps cursor")
		# Losing the second henchman must not restart the already active cycle.
		var cursor: int = m.enemies[2].intentIndex
		m.enemy_damage(1 - dead_index, 15)
		m.block = 999
		var result := m.end_turn()
		check(events(result, "intent_change").is_empty() and m.enemies[2].intentIndex == cursor + 1, "Second death does not restart boss cycle")
	# Death during an enemy's action must wait until the NEXT boundary.
	var m := gang()
	m.enemies[0].hp = 1
	m.block = 999
	m.parry = 1
	var result := m.end_turn()
	check(m.enemies[0].hp == 0 and result.attacks[0].counters.size() == 1, "First henchman dies to parry during enemy turn")
	check(events(result, "intent_change").is_empty() and result.attacks.size() == 2 and m.enemies[2].intent.type == "strength_allies", "No mid-turn phase switch after parry")
	var gains := events(result, "status_apply")
	check(gains.size() == 1 and gains[0].target == 1 and gains[0].buffId == "strength", "Original boss intent still buffs surviving henchman")
	m.block = 999
	result = m.end_turn()
	check(result.turnEvents[0].type == "intent_change" and result.attacks.back().index == 2 and result.attacks.back().hits[0].blocked == 8, "Parry casualty switches at next boundary, starting at attack8")
	# A status kill at a henchman's own turn end also waits for next boundary.
	m = gang()
	m.enemies[0].hp = 1
	m.buffs.apply(m, "pollution", 1, 0)
	m.block = 999
	result = m.end_turn()
	check(m.enemies[0].hp == 0 and events(result, "intent_change").is_empty() and m.enemies[2].intent.type == "strength_allies", "Enemy-turn pollution death does not switch mid-turn")
	m.block = 999
	result = m.end_turn()
	check(events(result, "intent_change").size() == 1 and result.attacks.back().hits[0].blocked == 8, "Pollution casualty switches next turn")
	m = gang()
	m.enemy_damage(0, 15)
	m.enemy_damage(1, 15)
	m.block = 999
	result = m.end_turn()
	check(result.attacks.size() == 1 and result.attacks[0].index == 2 and result.attacks[0].hits[0].blocked == 8, "Both dead at boundary leaves only boss attack8")

func test_strength_and_vulnerability() -> void:
	var m: CombatModel = fixtures.fixture([36], "ranged")
	m.buffs.apply(m, "strength", 2)
	m.buffs.apply(m, "vulnerable", 3, 0)
	m.buffs.apply(m, "bleed", 3, 0)
	var before := saved(m)
	var preview := m.card_preview("card_000", 0)
	check(preview.effects.filter(func(e): return e.type == "damage")[0].samples == [[8, 8, 8, 8]], "Four hits each receive strength and vulnerable, rounded per hit")
	check(preview.effects.filter(func(e): return e.type == "bleed_damage")[0].samples == [[3, 2, 1, 0]], "Bleed preview unaffected by strength or vulnerable")
	check(saved(m) == before, "Preview leaves statuses, cursors and snapshot untouched")
	var result := m.play_card("card_000", 0)
	check(result.damage == 38 and result.hits.map(func(h): return h.attackDamage) == [8, 8, 8, 8] and result.hits.map(func(h): return h.bleedDamage) == [3, 2, 1, 0], "Real multi-hit matches preview and excludes bleed amplification")
	check(m.buffs.count(m, "strength") == 2, "Strength not consumed by attack")
	for index in [-1, 0]:
		m = fixtures.fixture([1])
		check(m.buffs.apply(m, "strength", -2000, index) and m.buffs.count(m, "strength", index) == -999, "Signed strength lower bound")
		check((m.buffs.player_badges(m) if index == -1 else m.buffs.enemy_badges(m.enemies[index]))[0].count == -999, "Negative strength has visible signed badge")
		m.block = 999
		m.end_turn()
		check(m.buffs.count(m, "strength", index) == -999, "Negative strength persists across turns")
		check(m.buffs.apply(m, "strength", 3000, index) and m.buffs.count(m, "strength", index) == 999, "Signed strength upper bound")
		m.buffs.apply(m, "strength", -999, index)
		check(m.buffs.count(m, "strength", index) == 0, "Opposite strength stacks cancel to zero")
	m = fixtures.fixture([36], "melee")
	m.buffs.apply(m, "strength", -999)
	m.enemies[0].block = 5
	result = m.play_card("card_000", 0)
	check(result.damage == 0 and m.enemies[0].block == 5 and m.enemies[0].hp == 1000, "Negative strength clamps attack to zero without healing or growing block")
	m = fixtures.fixture([1])
	m.buffs.apply(m, "strength", 2, 0)
	m.buffs.apply(m, "weak", 1, 0)
	m.buffs.apply(m, "vulnerable", 2)
	m.block = 4
	check(m.enemy_intent_text(m.enemies[0]) == "攻击 14", "Intent includes strength, weak and post-decay vulnerable")
	result = m.end_turn()
	check(result.attacks[0].hits[0].damage == 10 and result.attacks[0].hits[0].blocked == 4, "Attack modifiers apply before block")
	check(m.buffs.count(m, "vulnerable") == 1 and m.enemy_intent_text(m.enemies[0]) == "攻击 12", "One vulnerable layer expires before next enemy attack preview")
	m = fixtures.fixture([1])
	m.buffs.apply(m, "vulnerable", 5000)
	check(m.buffs.count(m, "vulnerable") == 999 and not m.buffs.apply(m, "vulnerable", -1), "Vulnerable capped 999 and never accepts negative stacks")
	m.buffs.clear(m, "vulnerable")
	m.buffs.apply(m, "vulnerable", 2)
	m.buffs.apply(m, "strength", 999)
	m.buffs.apply(m, "pollution", 3)
	var ticks := m.buffs.own_turn_end(m)
	check(ticks[0].damage == 3 and m.player_hp == 97 and m.buffs.count(m, "vulnerable") == 1, "Player pollution ignores strength/vulnerable; vulnerable decays after tick")
	m.buffs.apply(m, "vulnerable", 3, 0)
	m.buffs.apply(m, "strength", 999, 0)
	m.buffs.apply(m, "pollution", 3, 0)
	ticks = m.buffs.own_turn_end(m, 0)
	check(ticks[0].damage == 3 and m.buffs.count(m, "vulnerable", 0) == 2, "Enemy pollution ignores modifiers and decays on owner's turn end")
	check(m.enemy_damage(0, 5).damage == 5 and m.player_damage(5).damage == 5, "Non-attack direct damage bypasses vulnerable")
	m = fixtures.fixture([1])
	m.buffs.apply(m, "vulnerable", 2, 0)
	m.buffs.apply(m, "strength", 100)
	m.parry = 2
	m.block = 999
	result = m.end_turn()
	check(result.attacks[0].counters.map(func(h): return h.damage) == [3, 3], "Parry buff damage ignores strength and enemy vulnerable")

func test_snapshots() -> void:
	var m := gang()
	m.buffs.apply(m, "strength", -7)
	m.buffs.apply(m, "strength", -8, 0)
	m.buffs.apply(m, "vulnerable", 999)
	m.buffs.apply(m, "vulnerable", 999, 1)
	var snapshot := saved(m)
	check(Game.valid_combat(snapshot), "Signed buffs validate on both owners")
	var copy := CombatModel.new()
	copy.restore(snapshot)
	check(saved(copy) == snapshot and copy.buffs.count(copy, "strength") == -7 and copy.buffs.count(copy, "strength", 0) == -8, "JSON roundtrip preserves signed buffs exactly")
	for invalid in [-1000, 1000, 0.5, INF, "2"]:
		for index in [-1, 0]:
			var bad := snapshot.duplicate(true)
			if index < 0: bad.buffs.strength = invalid
			else: bad.enemies[index].buffs.strength = invalid
			check(not Game.valid_combat(bad), "Reject malformed/out-of-range strength on either owner")
	for invalid in [-1, 1000, 0.5, INF, "2"]:
		var bad := snapshot.duplicate(true)
		bad.buffs.vulnerable = invalid
		check(not Game.valid_combat(bad), "Reject malformed/out-of-range vulnerable")
	for field in ["phase", "allies", "sequence", "index"]:
		var bad := snapshot.duplicate(true)
		match field:
			"phase": bad.enemies[2].intentPhase = "invalid"
			"allies": bad.enemies[2].allyDeathIntentSequence.allyIds = ["missing"]
			"sequence": bad.enemies[2].allyDeathIntentSequence.sequence = []
			"index": bad.enemies[2].intentIndex = -1
		check(not Game.valid_combat(bad), "Reject corrupt conditional phase metadata")
	m = gang()
	m.enemy_damage(0, 15)
	m.block = 999
	m.end_turn()
	snapshot = saved(m)
	copy = CombatModel.new()
	copy.restore(snapshot)
	check(saved(copy) == snapshot and copy.enemies[2].intent.type == "vulnerable", "Save after attack8 preserves next vulnerable intent")
	copy.block = 999
	check(events(copy.end_turn(), "status_apply")[0].buffId == "vulnerable", "Resume active phase without repeating attack8")
	# An existing B04 prototype snapshot remains independent of the new catalog.
	m = fixtures.fixture([1])
	snapshot = saved(m)
	copy = CombatModel.new()
	copy.restore(snapshot)
	check(Game.valid_combat(snapshot) and saved(copy) == snapshot and not snapshot.has("buffs") and copy.enemies.size() == 1, "Legacy unphased battle snapshot keeps original shape and enemies")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://gang_rules_qa.json"
	Game.meta_path = "user://gang_rules_meta_qa.json"
	test_encounter()
	test_boundary_and_cycles()
	test_strength_and_vulnerability()
	test_snapshots()
	fixtures.free()
	var report := {"checks":checks, "failures":failures, "phaseSwitch":"enemy_turn_start_only", "vulnerable":"attack_only"}
	var output := "res://artifacts/qa/gang-alley-2026-10-19/rules-result.json"
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("GANG RULES: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
