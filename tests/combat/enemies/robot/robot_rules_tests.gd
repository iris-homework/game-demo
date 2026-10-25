extends Node
## Robot presentation must consume these ordinary attack results without
## reapplying damage or giving the full-screen beam extra gameplay targets.
var checks := 0
var failures: Array[String] = []
var output_dir := "res://artifacts/qa/robot-charge-2026-10-25/rules"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func robot() -> CombatModel:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	rules.shuffleInitialDeck = false
	var model := CombatModel.new()
	model.initialize("B02", 100, 100, rules, [Game.enemy_catalog.robot], Game.card_catalog)
	return model

func saved(model: CombatModel) -> Dictionary:
	return JSON.parse_string(JSON.stringify(model.snapshot()))

func test_encounter_and_loop() -> void:
	check(Game.events.E02.nodes.battle.battleId == "B02" and Game.battles.B02.placeId == "junkyard", "Existing garbage-yard event routes to B02")
	check(Game.battles.B02.enemyIds == ["robot"], "B02 contains the single robot")
	check(Game.enemy_catalog.robot.maxHp == 40, "Formal robot catalog retains authored forty HP")
	check(Game.enemy_catalog.robot.combatVisualId == "robot" and not Game.enemy_catalog.robot.prototype, "Robot uses its own combat visual and authored intent")
	var model := robot()
	check(model.enemies[0].hp == 40 and model.enemies[0].maxHp == 40, "Formal robot starts with authored forty HP")
	var sequence: Array = model.enemies[0].intentSequence
	var expected_sequence: Array = JSON.parse_string('[{"type":"attack","amount":10,"hits":1},{"type":"charge","amount":5},{"type":"attack","amount":5,"hits":2}]')
	check(sequence == expected_sequence, "Robot sequence is attack10, charge5, attack5 twice")
	var total_damage := 0
	for round_index in 7:
		var phase := round_index % 3
		var preview: String = ["攻击10", "充能+5电能", "攻击10×2"][phase]
		var before := saved(model)
		check(model.enemies[0].intentIndex == round_index and model.enemy_intent_text(model.enemies[0]).replace(" ", "") == preview and saved(model) == before, "Round %d previews current action without mutation" % (round_index + 1))
		var result := model.end_turn()
		if phase == 1:
			check(result.attacks.is_empty() and result.turnEvents.size() == 1 and result.turnEvents[0].type == "status_apply", "Round %d charges without an attack" % (round_index + 1))
			if result.turnEvents.size() == 1:
				var event: Dictionary = result.turnEvents[0]
				check(event.buffId == "electric_charge" and event.target == 0 and event.amount == 5 and event.stacksAfter == 5, "Charge event targets robot with five electric stacks")
			check(model.buffs.count(model, "electric_charge", 0) == 5, "Charge persists through next player phase")
		else:
			var expected_hits := 2 if phase == 2 else 1
			check(result.attacks.size() == 1 and result.turnEvents.size() == 1 and result.turnEvents[0].type == "attack", "Round %d emits exactly one ordinary attack" % (round_index + 1))
			if result.attacks.size() == 1:
				var attack: Dictionary = result.attacks[0]
				check(attack.id == "robot" and attack.index == 0 and attack.hits.size() == expected_hits and attack.damage == 10 * expected_hits, "Round %d executes expected attack segments" % (round_index + 1))
				check(attack.hits.all(func(hit): return hit.damage == 10), "Every charged segment receives the frozen five-point bonus")
			check(model.buffs.count(model, "electric_charge", 0) == 0, "Attack consumes all charge once")
			total_damage += 10 * expected_hits
		check(model.player_hp == 100 - total_damage and model.turn == round_index + 2 and result.outcome.is_empty(), "Round %d deducts HP once and continues" % (round_index + 1))
		check(Game.valid_combat(saved(model)), "Round %d produces valid combat snapshot" % (round_index + 1))
	var prior := Game.state.duplicate(true)
	Game.state = Game.initial_state()
	Game.state.completedEventIds = ["E01"]
	Game.state.refreshedEventIds = ["E02"]
	Game.state.targetId = "richard"
	check(Game.start_event("E02"), "Refreshed E02 starts through its existing event route")
	for step in 4: Game.advance(Game.revision)
	check(Game.state.currentScene == "battle" and Game.state.battleId == "B02" and Game.state.combat.enemies[0].id == "robot", "Actual E02 dialogue enters robot battle")
	check(Game.state.combat.enemies[0].intent.amount == 10 and Game.valid_save(Game.state), "Formal routed battle starts with attack10 and valid adventure")
	Game.state = prior

func test_existing_damage_rules() -> void:
	for row in [
		{"block":10, "weak":0, "strength":0, "damage":0, "blocked":10, "preview":10},
		{"block":4, "weak":0, "strength":0, "damage":6, "blocked":4, "preview":10},
		{"block":0, "weak":2, "strength":0, "damage":8, "blocked":0, "preview":8},
		{"block":0, "weak":0, "strength":3, "damage":13, "blocked":0, "preview":13},
		{"block":4, "weak":1, "strength":3, "damage":6, "blocked":4, "preview":10},
		{"block":0, "weak":0, "strength":-20, "damage":0, "blocked":0, "preview":0}
	]:
		var model := robot()
		model.block = row.block
		model.enemies[0].weak = row.weak
		if row.strength != 0: model.buffs.apply(model, "strength", row.strength, 0)
		var label := "block%d weak%d strength%d" % [row.block, row.weak, row.strength]
		var before := saved(model)
		check(model.enemy_intent_text(model.enemies[0]) == "攻击 %d" % row.preview and saved(model) == before, label + " read-only preview uses ordinary damage modifiers")
		var result := model.end_turn()
		var hit: Dictionary = result.attacks[0].hits[0]
		check(hit.damage == row.damage and hit.blocked == row.blocked and model.player_hp == 100 - row.damage, label + " exact damage and block absorption")
		check(model.enemies[0].weak == maxi(0, row.weak - 1) and model.buffs.count(model, "strength", 0) == row.strength, label + " weak decays while signed strength persists")
		check(Game.valid_combat(saved(model)), label + " state validates")
	var fatal := robot()
	fatal.player_hp = 10
	var result := fatal.end_turn()
	check(result.outcome == "lose" and fatal.player_hp == 0 and fatal.turn == 1 and result.attacks.size() == 1, "Lethal robot hit ends battle once without advancing another turn")
	check(fatal.end_turn().is_empty(), "Completed battle cannot apply robot damage twice")

func charged_robot() -> CombatModel:
	var model := robot()
	model.end_turn()
	model.end_turn()
	return model

func add_attack(model: CombatModel, id: String = "noren_35") -> String:
	var uid := "robot_qa_attack"
	model.instances[uid] = id
	model.hand.append(uid)
	return uid

func test_electric_charge() -> void:
	var model := charged_robot()
	check(model.buffs.count(model, "electric_charge", 0) == 5 and model.enemies[0].intent.type == "attack" and model.enemies[0].intent.amount == 5, "Two real turns reach charged two-hit attack")
	var badges: Array = model.buffs.enemy_badges(model.enemies[0]).filter(func(badge): return badge.buffId == "electric_charge")
	check(badges.size() == 1 and badges[0].count == 5 and badges[0].category == "positive" and "电能" in badges[0].description, "Electric charge has a positive five-stack badge and explanation")
	model.buffs.apply(model, "electric_charge", 2, 0)
	check(model.buffs.count(model, "electric_charge", 0) == 7, "Charge layers add rather than replace")
	model.enemies[0].block = 100
	for index in 8:
		var hit := model.enemy_damage(0, 1, false, true)
		check(hit.damage == 0 and model.buffs.count(model, "electric_charge", 0) == maxi(0, 6 - index), "Fully blocked attack %d removes one charge, floored at zero" % (index + 1))
	check(model.buffs.enemy_badges(model.enemies[0]).all(func(badge): return badge.buffId != "electric_charge"), "Zero charge removes its badge")
	check(model.enemy_intent_text(model.enemies[0]).replace(" ", "") == "攻击5×2", "Depleted charge updates upcoming per-hit preview")
	var result := model.end_turn()
	check(result.attacks[0].hits.size() == 2 and result.attacks[0].damage == 10, "Fully depleted charged attack falls back to base five twice")

	model = charged_robot()
	var uid := add_attack(model)
	model.stance = "ranged"
	model.buffs.apply(model, "bleed", 5, 0)
	result = model.play_card(uid, 0)
	check(result.hits.size() == 3 and result.damage == 21, "Real three-hit ranged card includes three ordinary bleed triggers")
	check(model.buffs.count(model, "electric_charge", 0) == 2 and model.buffs.count(model, "bleed", 0) == 2, "Three attack bodies remove three electric layers; bleed damage removes none")
	check(model.enemy_intent_text(model.enemies[0]).replace(" ", "") == "攻击7×2", "Three-hit interruption lowers preview to seven twice")
	result = model.end_turn()
	check(result.attacks[0].hits.size() == 2 and result.attacks[0].damage == 14 and model.buffs.count(model, "electric_charge", 0) == 0, "Remaining two layers boost both next segments then disappear")
	check(model.enemy_intent_text(model.enemies[0]) == "攻击 10", "Consumed charge does not leak into next cycle")

	model = charged_robot()
	model.enemy_damage(0, 1)
	model.buffs.apply(model, "pollution", 3, 0)
	model.buffs.own_turn_end(model, 0)
	model.buffs.apply(model, "parry", 1)
	model.buffs.after_enemy_attack(model, 0, 10)
	check(model.buffs.count(model, "electric_charge", 0) == 5 and model.enemies[0].hp == 31, "Ordinary damage, pollution tick and parry counter do not count as attacks received")

	model = charged_robot()
	model.block = 100
	result = model.end_turn()
	check(result.attacks[0].damage == 0 and result.attacks[0].hits.size() == 2 and result.attacks[0].hits.all(func(hit): return hit.blocked == 10), "Fully blocked outgoing attack still uses charge on every segment")
	check(model.buffs.count(model, "electric_charge", 0) == 0 and not model.enemies[0].get("buffs", {}).has("electric_charge"), "Fully blocked outgoing attack consumes and removes all stored charge")
	model = charged_robot()
	model.buffs.apply(model, "strength", -99, 0)
	result = model.end_turn()
	check(result.attacks[0].damage == 0 and model.buffs.count(model, "electric_charge", 0) == 0, "An executed zero-damage attack consumes charge")

	model = charged_robot()
	model.buffs.apply(model, "strength", 3, 0)
	model.enemies[0].weak = 1
	model.buffs.apply(model, "vulnerable", 2)
	model.block = 12
	var before := saved(model)
	check(model.enemy_intent_text(model.enemies[0]).replace(" ", "") == "攻击15×2" and saved(model) == before, "Charge combines with strength, weak and player turn-end vulnerability in read-only preview")
	result = model.end_turn()
	check(result.attacks[0].damage == 18 and result.attacks[0].hits[0].blocked == 12 and result.attacks[0].hits[0].damage == 3 and result.attacks[0].hits[1].damage == 15, "Modified charged segments match preview before individual block absorption")

	model = charged_robot()
	model.player_hp = 5
	result = model.end_turn()
	check(result.outcome == "lose" and result.attacks[0].hits.size() == 1 and model.buffs.count(model, "electric_charge", 0) == 0, "Lethal first segment still consumes all charge and skips unexecuted segments")
	model = charged_robot()
	model.enemies[0].hp = 2
	uid = add_attack(model)
	result = model.play_card(uid, 0)
	check(result.outcome == "win" and result.hits.size() == 1 and model.buffs.count(model, "electric_charge", 0) == 4, "Lethal received segment removes one layer without counting unexecuted segments")

func test_charged_snapshot() -> void:
	var model := charged_robot()
	var snapshot := saved(model)
	var restored := CombatModel.new()
	restored.restore(snapshot)
	check(Game.valid_combat(snapshot) and snapshot.enemies[0].buffs.electric_charge == 5 and saved(restored) == snapshot, "Charged attack snapshot restores exact stored layers, intent and cursor")
	seed(2031)
	var expected := model.end_turn()
	seed(2031)
	var resumed := restored.end_turn()
	check(JSON.stringify(expected) == JSON.stringify(resumed) and saved(model) == saved(restored), "Restored charged robot consumes layers and executes identical segments")
	for bad_count in [-1, 1.5, "5"]:
		var malformed := snapshot.duplicate(true)
		malformed.enemies[0].buffs.electric_charge = bad_count
		check(not Game.valid_combat(malformed), "Snapshot rejects invalid electric count: %s" % str(bad_count))
	var wrong_target := snapshot.duplicate(true)
	wrong_target.buffs = {"electric_charge":5}
	check(not Game.valid_combat(wrong_target), "Enemy-only charge cannot be smuggled into player buff state")

func test_snapshot_compatibility() -> void:
	var model := robot()
	model.enemies[0].weak = 2
	model.buffs.apply(model, "strength", 3, 0)
	model.end_turn()
	var snapshot := saved(model)
	var restored := CombatModel.new()
	restored.restore(snapshot)
	check(Game.valid_combat(snapshot) and saved(restored) == snapshot, "New robot snapshot restores exactly after a real turn")
	check(restored.enemies[0].intent.type == "charge" and restored.enemies[0].intent.amount == 5 and restored.enemies[0].intentIndex == 1, "Restoring new robot keeps upcoming charge and cursor")
	seed(2030)
	var expected := model.end_turn()
	seed(2030)
	var resumed := restored.end_turn()
	check(JSON.stringify(expected) == JSON.stringify(resumed) and saved(model) == saved(restored), "Restored robot continues with identical damage, status, and card state")
	# Old B02 snapshots have a frozen empty sequence and profile attack1.
	# Exercise both explicit Finn and old snapshots with no visual identifier.
	for with_visual in [true, false]:
		model = robot()
		model.profile.intent = {"type":"attack", "amount":1, "hits":1}
		model.enemies[0].intentSequence = []
		model.enemies[0].intent = model.profile.intent.duplicate(true)
		model.enemies[0].prototype = true
		if with_visual: model.enemies[0].combatVisualId = "finn"
		else: model.enemies[0].erase("combatVisualId")
		snapshot = saved(model)
		restored = CombatModel.new()
		restored.restore(snapshot)
		check(Game.valid_combat(snapshot) and saved(restored) == snapshot, "Old attack1 snapshot preserves all saved fields, visual=%s" % with_visual)
		for round_index in 3:
			var result := restored.end_turn()
			check(result.attacks.size() == 1 and result.attacks[0].damage == 1 and restored.player_hp == 99 - round_index and restored.enemies[0].intent.amount == 1, "Old snapshot round %d stays attack1, visual=%s" % [round_index + 1, with_visual])
	# Previous authored attack10-loop snapshots also keep their frozen sequence.
	model = robot()
	model.enemies[0].intentSequence = [{"type":"attack", "amount":10, "hits":1}]
	model.enemies[0].intent = model.enemies[0].intentSequence[0].duplicate(true)
	snapshot = saved(model)
	restored = CombatModel.new()
	restored.restore(snapshot)
	check(Game.valid_combat(snapshot) and saved(restored) == snapshot, "Previous authored attack10-loop snapshot remains valid and unchanged")
	for round_index in 3:
		var result := restored.end_turn()
		check(result.attacks.size() == 1 and result.attacks[0].hits.size() == 1 and result.attacks[0].damage == 10 and restored.enemies[0].intent.type == "attack", "Previous attack10-loop snapshot round %d stays frozen" % (round_index + 1))
	check(Game.enemy_catalog.robot.intentSequence.size() == 3 and Game.enemy_catalog.robot.intentSequence[0].amount == 10, "Old snapshot restoration never rewrites current robot catalog")

func test_training_isolation() -> void:
	var prior := Game.state.duplicate(true)
	Game.state = Game.initial_state()
	Game.state.currentHp = 57
	Game.state.credits = 4321
	Game.state.deck = ["noren_36"]
	Game.state.flags.robotQa = true
	var adventure := Game.state.duplicate(true)
	# Deliberately enable saving: production training guards, rather than a
	# globally disabled writer, must keep all three dedicated QA files intact.
	var baseline: Dictionary = {}
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = Game.save_path + suffix
		var marker: String = "robot training isolation sentinel " + suffix
		FileAccess.open(path, FileAccess.WRITE).store_string(marker)
		baseline[path] = marker
	Game.save_enabled = true
	for outcome in ["win", "lose"]:
		Game.start_training("B02")
		check(Game.training_mode and Game.state.battleId == "B02" and Game.state.combat.enemies[0].intent.amount == 10, outcome + " training uses authored robot intent")
		check(Game.state.combat.enemies[0].maxHp == Game.TRAINING_ENEMY_HP and Game.enemy_catalog.robot.maxHp == 40, outcome + " training overrides only its copy of HP")
		var model := CombatModel.new()
		model.restore(Game.state.combat)
		var training_hp_before := model.player_hp
		model.end_turn()
		Game.commit_combat(model)
		check(Game.state.currentHp == training_hp_before - 10 and Game.state.combat.turn == 2, outcome + " training commits its ordinary attack result in memory")
		Game.checkpoint()
		Game.finish_training(outcome)
		check(not Game.training_mode and Game.training_backup.is_empty() and Game.state == adventure and Game.page == "menu", outcome + " training restores entire original adventure without rewards")
		for path in baseline:
			check(FileAccess.get_file_as_string(path) == baseline[path], outcome + " training leaves QA save file unchanged: " + path.get_file())
	Game.save_enabled = false
	Game.state = prior

func _ready() -> void:
	Game.save_enabled = false
	var args := OS.get_cmdline_user_args()
	if args.has("--output-dir"): output_dir = args[args.find("--output-dir") + 1].trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(output_dir)
	Game.save_path = output_dir + "/training-save-sentinel.json"
	Game.meta_path = output_dir + "/robot-meta-unused.json"
	test_encounter_and_loop()
	test_existing_damage_rules()
	test_electric_charge()
	test_charged_snapshot()
	test_snapshot_compatibility()
	test_training_isolation()
	var report := {"checks":checks, "failures":failures, "robotIntent":"attack10_charge5_attack5x2_loop", "formalHp":40, "trainingHp":Game.TRAINING_ENEMY_HP, "legacyIntent":"saved_attack1_and_attack10_loop_retained"}
	FileAccess.open(output_dir + "/rules-result.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROBOT RULES: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
