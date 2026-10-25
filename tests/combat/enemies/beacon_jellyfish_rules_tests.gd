extends Node
## Pure rules and JSON roundtrips; no user saves or window required.
var checks := 0
var failures: Array[String] = []
var output_dir := "res://artifacts/qa/beacon-jellyfish-2026-10-25/rules"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("JELLYFISH RULES: " + message)

func jellyfish() -> CombatModel:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	rules.shuffleInitialDeck = false
	var model := CombatModel.new()
	model.initialize("B15", 100, 100, rules, [Game.enemy_catalog.beacon_jellyfish], Game.card_catalog)
	return model

func saved(model: CombatModel) -> Dictionary:
	return JSON.parse_string(JSON.stringify(model.snapshot()))

func triple(model: CombatModel) -> Dictionary:
	model.instances.jellyfish_qa_attack = "noren_35"
	model.hand.append("jellyfish_qa_attack")
	return model.play_card("jellyfish_qa_attack", 0)

func test_loop() -> void:
	var model := jellyfish()
	check(Game.events.E15.nodes.battle.battleId == "B15" and Game.battles.B15.enemyIds == ["beacon_jellyfish"], "Existing port encounter uses the same single jellyfish")
	check(model.enemies[0].displayName == "信标水母" and model.enemies[0].hp == 36 and model.enemies[0].maxHp == 36, "Name retained with thirty-six HP")
	check(model.buffs.count(model, "soft", 0) == 1 and model.enemies[0].block == 0, "Innate soft is active before the first attack without starting block")
	var hp := 100
	for round_index in 6:
		var amount := 10 if round_index % 2 == 0 else 8
		var before := saved(model)
		check(model.enemy_intent_text(model.enemies[0]) == "攻击 %d" % amount and saved(model) == before, "Round %d preview is correct and read-only" % round_index)
		var result := model.end_turn()
		hp -= amount
		check(result.attacks.size() == 1 and result.attacks[0].hits.size() == 1 and result.attacks[0].damage == amount and model.player_hp == hp, "Round %d resolves the authored single hit exactly once" % round_index)
		var weak_events: Array = result.turnEvents.filter(func(e): return e.type == "status_apply" and e.get("buffId") == "weak")
		check(weak_events.size() == round_index % 2, "Only attack eight applies weakness")
		check(model.weak == (2 if round_index % 2 == 1 else (0 if round_index == 0 else 1)), "Weakness has two layers after application and decays on the player's own turn end")
		check(model.buffs.count(model, "soft", 0) == 1 and Game.valid_combat(saved(model)), "Innate passive persists and each completed round validates")
	model = jellyfish()
	model.end_turn()
	model.block = 100
	var result := model.end_turn()
	check(result.attacks[0].damage == 0 and model.player_hp == 90 and model.weak == 2, "Fully blocking attack eight still receives two weak stacks")
	model = jellyfish()
	model.buffs.apply(model, "weak", 1, 0)
	check(model.enemy_intent_text(model.enemies[0]) == "攻击 8", "Enemy weakness rounds ten to eight in its preview")
	check(model.end_turn().attacks[0].damage == 8, "Actual weakened attack agrees with preview")

func test_soft() -> void:
	var model := jellyfish()
	var badges: Array = model.buffs.enemy_badges(model.enemies[0]).filter(func(b): return b.buffId == "soft")
	check(badges.size() == 1 and badges[0].category == "positive" and badges[0].description.contains("3点格挡"), "Soft is a positive visible passive with its rule tooltip")
	model.buffs.apply(model, "soft", 1, 0)
	check(model.buffs.count(model, "soft", 0) == 1, "Reapplying soft does not duplicate the trigger")
	for row in [{"block":0,"amount":5,"damage":5,"after":3}, {"block":8,"amount":5,"damage":0,"after":6}, {"block":2,"amount":5,"damage":3,"after":3}, {"block":0,"amount":0,"damage":0,"after":3}]:
		model = jellyfish()
		model.enemies[0].block = row.block
		var hit := model.enemy_damage(0, row.amount, false, true)
		check(hit.damage == row.damage and hit.blockAfter == row.after and model.enemies[0].hp == 36-row.damage, "Damage uses previous block, then soft grants three: %s" % str(row))
	model = jellyfish()
	model.enemies[0].block = 10
	var bypass := model.enemy_damage(0, 2, true, true)
	check(bypass.damage == 2 and bypass.blockAfter == 13, "Ignoring block still triggers soft without consuming old block")
	model = jellyfish()
	var result := triple(model)
	check(result.hits.size() == 3 and result.damage == 2 and model.enemies[0].hp == 34, "Three two-point melee hits lose only two HP because new block protects later segments")
	check(result.hits.map(func(h): return h.blockAfter) == [3,4,5] and result.hits.map(func(h): return h.damage) == [2,0,0], "Each segment records its own post-soft block and damage")
	model = jellyfish()
	model.stance = "ranged"
	result = triple(model)
	check(result.hits.size() == 3 and result.damage == 3 and result.hits.all(func(h): return h.blockAfter == 3), "Three ranged hits each trigger soft even when fully blocked")
	model = jellyfish()
	model.stance = "ranged"
	model.buffs.apply(model, "bleed", 5, 0)
	result = triple(model)
	check(result.damage == 12 and model.enemies[0].hp == 24 and model.enemies[0].block == 0 and model.enemies[0].bleed == 2, "Soft block is available to subsequent bleed; bleed does not grant extra block")
	model = jellyfish()
	var hp: int = model.enemies[0].hp
	model.enemy_damage(0, 3)
	check(model.enemies[0].hp == hp-3 and model.enemies[0].block == 0, "Non-attack direct damage does not trigger soft")
	model.buffs.apply(model, "pollution", 2, 0)
	model.buffs.own_turn_end(model, 0)
	check(model.enemies[0].block == 0 and model.enemies[0].hp == hp-5, "Pollution damage does not trigger soft")
	model.buffs.apply(model, "parry", 1)
	var counters: Array = model.buffs.after_enemy_attack(model, 0, 10)
	check(counters.size() == 1 and counters[0].damage == 5 and model.enemies[0].block == 0, "Parry counter damage does not trigger soft")
	model = jellyfish()
	model.enemy_damage(0, 1, false, true)
	var turn_result := model.end_turn()
	check(model.enemies[0].block == 0 and model.buffs.count(model,"soft",0) == 1 and turn_result.turnEvents[0].type == "block_clear", "Soft block expires when its owner acts, while the passive persists")
	model = jellyfish()
	model.buffs.apply(model, "energy_suit", 1, 0)
	model.buffs.apply(model, "electric_charge", 2, 0)
	model.enemy_damage(0, 1, false, true)
	check(model.enemies[0].block == 3 and model.buffs.count(model,"electric_charge",0) == 3, "Soft and energy suit independently react to the same hit")
	model = jellyfish()
	model.enemy_damage(0, 36, false, true)
	model.resolve_outcome()
	check(model.outcome == "win" and model.enemies[0].hp == 0, "Soft cannot absorb the triggering lethal hit or prevent victory")

func test_saves() -> void:
	var model := jellyfish()
	triple(model)
	var snapshot := saved(model)
	var restored := CombatModel.new()
	restored.restore(snapshot)
	check(Game.valid_combat(snapshot) and saved(restored) == snapshot and restored.enemies[0].buffs.soft is int, "Passive and accumulated block survive exact JSON roundtrip")
	for round_index in 3:
		# Recycled piles shuffle globally; compare under the same random input.
		seed(20261025 + round_index)
		var expected := model.end_turn()
		seed(20261025 + round_index)
		var resumed := restored.end_turn()
		check(JSON.stringify(expected) == JSON.stringify(resumed) and saved(model) == saved(restored), "Restored cycle and weakness remain identical at round%d" % round_index)
	for invalid in [-1, 0.5, 2, true, "1"]:
		var malformed := snapshot.duplicate(true)
		malformed.enemies[0].buffs.soft = invalid
		check(not Game.valid_combat(malformed), "Soft rejects invalid state %s" % str(invalid))
	var malformed := snapshot.duplicate(true)
	malformed.buffs = {"soft":1}
	check(not Game.valid_combat(malformed), "Enemy-only passive rejected on the player")
	check(not model.buffs.valid_card_effect({"type":"buff","id":"soft","amount":1}), "Innate soft cannot be applied by an unsupported card effect")
	var legacy := jellyfish()
	legacy.enemies[0].erase("buffs")
	legacy.enemies[0].intentSequence = [{"type":"attack","amount":6,"hits":1,"animation":"pierce"}]
	legacy.enemies[0].intent = legacy.enemies[0].intentSequence[0].duplicate(true)
	snapshot = saved(legacy)
	restored = CombatModel.new()
	restored.restore(snapshot)
	check(Game.valid_combat(snapshot) and saved(restored) == snapshot, "Old attack-six snapshot remains valid and exact")
	restored.enemy_damage(0, 2, false, true)
	check(restored.enemies[0].block == 0 and restored.buffs.count(restored,"soft",0) == 0 and restored.end_turn().attacks[0].damage == 6, "Old battle retains its frozen attack-six and has no retroactive passive")
	check(Game.enemy_catalog.beacon_jellyfish.intentSequence[0].amount == 10 and Game.enemy_catalog.beacon_jellyfish.buffs.soft == 1, "Legacy restore never mutates the current catalog")

func _ready() -> void:
	Game.save_enabled = false
	var args := OS.get_cmdline_user_args()
	if args.has("--output-dir"): output_dir = args[args.find("--output-dir")+1].trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(output_dir)
	Game.save_path = output_dir + "/unused-checkpoint.json"
	Game.meta_path = output_dir + "/unused-meta.json"
	test_loop()
	test_soft()
	test_saves()
	FileAccess.open(output_dir + "/rules-result.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("JELLYFISH RULES: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
