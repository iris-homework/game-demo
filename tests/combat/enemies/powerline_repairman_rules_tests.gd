extends Node
## Model regression only; use an isolated copied project and user directory.
var checks := 0
var failures: Array[String] = []
var output_dir := "res://artifacts/qa/repairman-energy-suit-2026-10-25/rules"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("REPAIRMAN RULES: " + message)

func repairman() -> CombatModel:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	rules.shuffleInitialDeck = false
	var model := CombatModel.new()
	model.initialize("B14", 100, 100, rules, [Game.enemy_catalog.powerline_repairman], Game.card_catalog)
	return model

func suited_repairman() -> CombatModel:
	var model := repairman()
	model.end_turn()
	return model

func saved(model: CombatModel) -> Dictionary:
	return JSON.parse_string(JSON.stringify(model.snapshot()))

func add_attack(model: CombatModel) -> String:
	var uid := "repairman_qa_attack"
	model.instances[uid] = "noren_35"
	model.hand.append(uid)
	return uid

func test_encounter_and_loop() -> void:
	check(Game.events.E14.nodes.battle.battleId == "B14" and Game.battles.B14.enemyIds == ["powerline_repairman"], "Existing E14 route retains one repairman in B14")
	var model := repairman()
	var enemy: Dictionary = model.enemies[0]
	check(Game.enemy_catalog.powerline_repairman.maxHp == 45 and enemy.hp == 45 and enemy.maxHp == 45, "Formal repairman starts with forty-five HP")
	var sequence: Array = enemy.intentSequence
	check(sequence.size() == 3 and sequence[0].type == "energy_suit" and sequence[0].amount == 1 and sequence[1].type == "attack" and sequence[1].amount == 5 and sequence[1].hits == 1 and sequence[2].type == "attack" and sequence[2].amount == 3 and sequence[2].hits == 2 and enemy.get("intentLoopStart") == 1, "One opening suit is followed by attack5 and attack3 twice")
	check(model.buffs.count(model, "energy_suit", 0) == 0 and model.buffs.count(model, "electric_charge", 0) == 0, "Suit and charge are absent before opening enhancement")
	var total_damage := 0
	var enhancements := 0
	for round_index in 7:
		var first_round := round_index == 0
		var single_attack := round_index % 2 == 1
		var preview := "强化：能量防护服" if first_round else "攻击 5" if single_attack else "攻击 3 ×2"
		var before := saved(model)
		check(enemy.intentIndex == round_index and model.enemy_intent_text(enemy) == preview and saved(model) == before, "Round %d has a read-only matching intent preview" % (round_index + 1))
		var result := model.end_turn()
		if first_round:
			check(result.attacks.is_empty() and result.turnEvents.size() == 1 and result.turnEvents[0].type == "status_apply", "Opening enhancement emits no attack")
			if result.turnEvents.size() == 1:
				var event: Dictionary = result.turnEvents[0]
				check(event.buffId == "energy_suit" and event.source == 0 and event.target == 0 and event.amount == 1 and event.stacksAfter == 1, "Opening suit event is self-targeted and stores one layer")
		else:
			var amount := 5 if single_attack else 3
			var hits := 1 if single_attack else 2
			check(result.attacks.size() == 1 and result.attacks[0].id == "powerline_repairman" and result.attacks[0].hits.size() == hits and result.attacks[0].damage == amount * hits, "Round %d executes configured attack segments" % (round_index + 1))
			total_damage += amount * hits
		for event in result.turnEvents:
			if event.type == "status_apply" and event.get("buffId") == "energy_suit": enhancements += 1
		check(model.player_hp == 100 - total_damage and model.turn == round_index + 2 and model.outcome.is_empty(), "Round %d applies damage and advances once" % (round_index + 1))
		check(model.buffs.count(model, "energy_suit", 0) == 1 and model.buffs.count(model, "electric_charge", 0) == 0, "Suit persists without creating charge from outgoing actions")
		check(Game.valid_combat(saved(model)), "Round %d creates a valid snapshot" % (round_index + 1))
	check(enhancements == 1 and total_damage == 33, "Seven rounds enhance only once, then repeat the two attacks")

func test_suit_and_incoming_attacks() -> void:
	var model := repairman()
	model.enemy_damage(0, 1, false, true)
	check(model.enemies[0].hp == 44 and model.buffs.count(model, "electric_charge", 0) == 0, "An attack before enhancement creates no electric charge")
	model.buffs.apply(model, "electric_charge", 2, 0)
	model.enemies[0].block = 10
	model.enemy_damage(0, 1, false, true)
	check(model.buffs.count(model, "electric_charge", 0) == 1, "Before enhancement the original received-attack charge decay still applies through block")

	model = suited_repairman()
	var badges: Array = model.buffs.enemy_badges(model.enemies[0]).filter(func(badge): return badge.buffId == "energy_suit")
	check(badges.size() == 1 and badges[0].count == 1 and badges[0].category == "positive", "Energy suit has one positive status badge")
	model.buffs.apply(model, "energy_suit", 1, 0)
	check(model.buffs.count(model, "energy_suit", 0) == 1, "Reapplying suit does not stack its passive trigger")
	model.buffs.apply(model, "electric_charge", 2, 0)
	for index in 3:
		var hit := model.enemy_damage(0, 1, false, true)
		check(hit.damage == 1 and hit.electricChargeAfter == index + 3 and model.buffs.count(model, "electric_charge", 0) == index + 3, "Suited damaging hit %d adds one charge without decay" % (index + 1))
	check(model.buffs.count(model, "electric_charge", 0) == 5, "Existing two charge becomes five after three damaging attack segments")

	for row in [{"block":3, "amount":3, "damage":0, "charge":2}, {"block":2, "amount":3, "damage":1, "charge":3}, {"block":0, "amount":0, "damage":0, "charge":2}]:
		model = suited_repairman()
		model.buffs.apply(model, "electric_charge", 2, 0)
		model.enemies[0].block = row.block
		var hit := model.enemy_damage(0, row.amount, false, true)
		check(hit.damage == row.damage and hit.electricChargeAfter == row.charge and model.buffs.count(model, "electric_charge", 0) == row.charge, "Suit only gains charge for actual attack HP loss: block%d amount%d" % [row.block, row.amount])

	model = suited_repairman()
	model.buffs.apply(model, "electric_charge", 2, 0)
	var uid := add_attack(model)
	model.stance = "ranged"
	model.buffs.apply(model, "bleed", 5, 0)
	var result := model.play_card(uid, 0)
	check(result.hits.size() == 3 and result.damage == 21 and model.enemies[0].hp == 24, "Real ranged three-hit card resolves attack bodies and three bleed ticks")
	check(model.buffs.count(model, "electric_charge", 0) == 5 and model.buffs.count(model, "bleed", 0) == 2, "Three attack bodies produce exactly three charge; attached bleed produces none")

	model = suited_repairman()
	model.buffs.apply(model, "electric_charge", 2, 0)
	model.buffs.apply(model, "bleed", 5, 0)
	model.enemies[0].block = 3
	uid = add_attack(model)
	model.stance = "ranged"
	result = model.play_card(uid, 0)
	check(result.hits.size() == 3 and result.hits[0].attackDamage == 0 and result.hits[0].bleedDamage == 5 and model.buffs.count(model, "electric_charge", 0) == 4, "Bleed-only HP loss after a blocked attack body creates no charge; later damaging bodies create two")

	model = suited_repairman()
	model.buffs.apply(model, "electric_charge", 2, 0)
	model.enemy_damage(0, 1)
	model.buffs.apply(model, "pollution", 3, 0)
	model.buffs.own_turn_end(model, 0)
	model.buffs.apply(model, "parry", 1)
	model.buffs.after_enemy_attack(model, 0, 10)
	check(model.enemies[0].hp == 36 and model.buffs.count(model, "electric_charge", 0) == 2, "Ordinary damage, pollution and parry counter neither generate nor decay charge")

func test_outgoing_charge_consumption() -> void:
	var model := suited_repairman()
	model.buffs.apply(model, "electric_charge", 2, 0)
	var before := saved(model)
	check(model.enemy_intent_text(model.enemies[0]) == "攻击 7" and saved(model) == before, "Single attack preview includes charge without consuming it")
	var result := model.end_turn()
	check(result.attacks[0].damage == 7 and result.attacks[0].electricChargeUsed == 2 and model.buffs.count(model, "electric_charge", 0) == 0, "Single attack consumes all two charge once")
	model.buffs.apply(model, "electric_charge", 4, 0)
	before = saved(model)
	check(model.enemy_intent_text(model.enemies[0]).replace(" ", "") == "攻击7×2" and saved(model) == before, "Two-hit attack previews frozen charge on every segment")
	model.block = 2
	result = model.end_turn()
	check(result.attacks[0].damage == 12 and result.attacks[0].hits.size() == 2 and result.attacks[0].hits[0].damage == 5 and result.attacks[0].hits[1].damage == 7 and model.buffs.count(model, "electric_charge", 0) == 0, "Both attack segments receive full charge before block and charge is consumed once")
	check(model.buffs.count(model, "energy_suit", 0) == 1 and model.enemy_intent_text(model.enemies[0]) == "攻击 5", "Charge consumption preserves suit and does not alter the two-attack cycle")

	model = suited_repairman()
	model.end_turn()
	model.buffs.apply(model, "electric_charge", 3, 0)
	model.block = 100
	result = model.end_turn()
	check(result.attacks[0].damage == 0 and result.attacks[0].hits.size() == 2 and result.attacks[0].hits.all(func(hit): return hit.blocked == 6) and model.buffs.count(model, "electric_charge", 0) == 0, "Fully blocked outgoing multiattack still consumes charge for all segments")

func test_snapshot_and_legacy() -> void:
	for before_enhancement in [true, false]:
		var model := repairman() if before_enhancement else suited_repairman()
		if not before_enhancement: model.buffs.apply(model, "electric_charge", 3, 0)
		var snapshot := saved(model)
		var restored := CombatModel.new()
		restored.restore(snapshot)
		check(Game.valid_combat(snapshot) and saved(restored) == snapshot, "Snapshot exactly preserves suit, charge and opening/loop position, opening=%s" % before_enhancement)
		for round_index in 4:
			seed(2140 + round_index)
			var expected := model.end_turn()
			seed(2140 + round_index)
			var resumed := restored.end_turn()
			check(JSON.stringify(expected) == JSON.stringify(resumed) and saved(model) == saved(restored), "Resumed enhancement/loop remains identical for round%d, opening=%s" % [round_index, before_enhancement])
	var snapshot := saved(suited_repairman())
	for bad_start in [-1, 1.5, 3]:
		var malformed := snapshot.duplicate(true)
		malformed.enemies[0].intentLoopStart = bad_start
		check(not Game.valid_combat(malformed), "Snapshot rejects bad intentLoopStart %s" % str(bad_start))
	var malformed := snapshot.duplicate(true)
	malformed.enemies[0].intentSequence = []
	check(not Game.valid_combat(malformed), "Loop start cannot reference an empty sequence")
	malformed = snapshot.duplicate(true)
	malformed.enemies[0].buffs.energy_suit = 2
	check(not Game.valid_combat(malformed), "Suit rejects two layers")
	malformed = snapshot.duplicate(true)
	malformed.buffs = {"energy_suit":1}
	check(not Game.valid_combat(malformed), "Enemy-only suit is rejected in player buff state")

	var legacy := repairman()
	legacy.enemies[0].maxHp = 48
	legacy.enemies[0].hp = 48
	legacy.enemies[0].intentSequence = [{"type":"attack", "amount":8, "hits":1, "animation":"pierce"}]
	legacy.enemies[0].intent = legacy.enemies[0].intentSequence[0].duplicate(true)
	legacy.enemies[0].erase("intentLoopStart")
	snapshot = saved(legacy)
	var restored := CombatModel.new()
	restored.restore(snapshot)
	check(Game.valid_combat(snapshot) and saved(restored) == snapshot, "Old B14 forty-eight HP / attack8 snapshot remains exact and valid")
	for round_index in 4:
		var result := restored.end_turn()
		check(result.attacks.size() == 1 and result.attacks[0].damage == 8 and restored.enemies[0].maxHp == 48 and restored.enemies[0].intent.amount == 8 and restored.buffs.count(restored, "energy_suit", 0) == 0, "Old B14 round%d keeps frozen attack8 and gains no suit" % round_index)
	check(Game.enemy_catalog.powerline_repairman.maxHp == 45 and Game.enemy_catalog.powerline_repairman.intentSequence[0].type == "energy_suit", "Legacy restore never rewrites the current catalog")

func _ready() -> void:
	Game.save_enabled = false
	var args := OS.get_cmdline_user_args()
	if args.has("--output-dir"): output_dir = args[args.find("--output-dir") + 1].trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(output_dir)
	Game.save_path = output_dir + "/unused-checkpoint.json"
	Game.meta_path = output_dir + "/unused-meta.json"
	test_encounter_and_loop()
	test_suit_and_incoming_attacks()
	test_outgoing_charge_consumption()
	test_snapshot_and_legacy()
	FileAccess.open(output_dir + "/rules-result.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures}, "\t"))
	print("REPAIRMAN RULES: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
