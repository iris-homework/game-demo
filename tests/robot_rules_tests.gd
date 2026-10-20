extends Node
## Robot presentation must consume these ordinary attack results without
## reapplying damage or giving the full-screen beam extra gameplay targets.
var checks := 0
var failures: Array[String] = []
var output_dir := "res://artifacts/qa/robot-laser-2026-10-20/rules"

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
	check(Game.enemy_catalog.robot.maxHp == null, "Unauthored robot HP remains null in catalog")
	check(Game.enemy_catalog.robot.combatVisualId == "robot" and not Game.enemy_catalog.robot.prototype, "Robot uses its own combat visual and authored intent")
	var model := robot()
	check(model.enemies[0].hp == int(Game.prototype_rules.enemyMaxHp), "Formal robot retains existing profile HP fallback")
	var sequence: Array = model.enemies[0].intentSequence
	check(sequence.size() == 1 and sequence[0].size() == 3 and sequence[0].type == "attack" and int(sequence[0].amount) == 10 and int(sequence[0].hits) == 1, "Robot sequence is exactly one attack10")
	for round_index in 7:
		check(model.enemies[0].intentIndex == round_index and model.enemy_intent_text(model.enemies[0]) == "攻击 10", "Round %d shows attack10 with one cursor advance" % (round_index + 1))
		var result := model.end_turn()
		check(result.attacks.size() == 1 and result.turnEvents.size() == 1 and result.turnEvents[0].type == "attack", "Round %d emits exactly one ordinary attack" % (round_index + 1))
		if result.attacks.size() == 1:
			var attack: Dictionary = result.attacks[0]
			check(attack.id == "robot" and attack.index == 0 and attack.hits.size() == 1 and attack.damage == 10, "Round %d attacks once for ten damage" % (round_index + 1))
		check(model.player_hp == 100 - 10 * (round_index + 1) and model.turn == round_index + 2 and result.outcome.is_empty(), "Round %d deducts HP once and continues" % (round_index + 1))
		check(Game.valid_combat(saved(model)), "Round %d produces valid combat snapshot" % (round_index + 1))
	var prior := Game.state.duplicate(true)
	Game.state = Game.initial_state()
	Game.state.completedEventIds = ["E01"]
	Game.state.targetId = "richard"
	check(Game.start_event("E02"), "E02 starts with its existing E01 prerequisite")
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

func test_snapshot_compatibility() -> void:
	var model := robot()
	model.enemies[0].weak = 2
	model.buffs.apply(model, "strength", 3, 0)
	model.end_turn()
	var snapshot := saved(model)
	var restored := CombatModel.new()
	restored.restore(snapshot)
	check(Game.valid_combat(snapshot) and saved(restored) == snapshot, "New robot snapshot restores exactly after a real turn")
	check(restored.enemies[0].intent.amount == 10 and restored.enemies[0].intentIndex == 1, "Restoring new robot keeps attack10 and cursor")
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
	check(Game.enemy_catalog.robot.intentSequence[0].amount == 10, "Old snapshot restoration never rewrites current robot catalog")

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
		check(Game.state.combat.enemies[0].maxHp == Game.TRAINING_ENEMY_HP and Game.enemy_catalog.robot.maxHp == null, outcome + " training overrides only its copy of HP")
		var model := CombatModel.new()
		model.restore(Game.state.combat)
		model.end_turn()
		Game.commit_combat(model)
		check(Game.state.currentHp == 90 and Game.state.combat.turn == 2, outcome + " training commits its ordinary attack result in memory")
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
	test_snapshot_compatibility()
	test_training_isolation()
	var report := {"checks":checks, "failures":failures, "robotIntent":"attack10_loop", "formalHp":"existing_profile_fallback", "trainingHp":Game.TRAINING_ENEMY_HP, "legacyIntent":"saved_attack1_retained"}
	FileAccess.open(output_dir + "/rules-result.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROBOT RULES: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
