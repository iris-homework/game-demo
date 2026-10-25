extends Node
## Model-only regression; run in an isolated copied project and user directory.
var checks := 0
var failures: Array[String] = []
var output_dir := "res://artifacts/qa/pruning-hound-pair-2026-10-25/rules"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("HOUND RULES: " + message)

func hounds() -> CombatModel:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	rules.shuffleInitialDeck = false
	var model := CombatModel.new()
	model.initialize("B13", 100, 100, rules, [Game.enemy_catalog.pruning_hound, Game.enemy_catalog.pruning_hound_second], Game.card_catalog)
	return model

func saved(model: CombatModel) -> Dictionary:
	return JSON.parse_string(JSON.stringify(model.snapshot()))

func event_index(events: Array, kind: String, target: int) -> int:
	for index in events.size():
		if events[index].type == kind and int(events[index].get("target", events[index].get("index", -1))) == target: return index
	return -1

func test_staggered_loop() -> void:
	check(Game.battles.B13.enemyIds == ["pruning_hound", "pruning_hound_second"] and Game.events.E13.nodes.battle.battleId == "B13", "B13 contains two hounds through the existing E13 route")
	var model := hounds()
	check(model.enemies.size() == 2 and model.enemies.all(func(enemy): return enemy.hp == 35 and enemy.maxHp == 35 and enemy.combatVisualId == "pruning_hound"), "Both formal hounds have thirty-five HP and share their published visual")
	check(model.enemies[0].intent.type == "attack" and model.enemies[0].intent.amount == 4 and model.enemies[0].intent.hits == 2 and model.enemies[1].intent.type == "fortify", "Opening actions are attack4 twice and fortify")
	var strengths := [0, 0]
	var total_damage := 0
	for round_index in 6:
		var attacker := round_index % 2
		var fortifier := 1 - attacker
		var per_hit: int = 4 + strengths[attacker]
		var before := saved(model)
		check(model.enemy_intent_text(model.enemies[attacker]).replace(" ", "") == "攻击%d×2" % per_hit and model.enemy_intent_text(model.enemies[fortifier]) == "强化：格挡 +5／力量 +1" and saved(model) == before, "Round%d previews the staggered actions and each hound's own strength without mutation" % round_index)
		var result := model.end_turn()
		check(result.attacks.size() == 1 and result.attacks[0].index == attacker and result.attacks[0].hits.size() == 2 and result.attacks[0].damage == per_hit * 2 and result.attacks[0].hits.all(func(hit): return hit.damage == per_hit), "Round%d executes exactly two attack segments from the correct hound" % round_index)
		var applications: Array = result.turnEvents.filter(func(event): return event.type == "status_apply")
		strengths[fortifier] += 1
		check(applications.size() == 2 and applications[0].target == fortifier and applications[0].buffId == "block" and applications[0].amount == 5 and applications[0].stacksAfter == 5 and applications[1].target == fortifier and applications[1].buffId == "strength" and applications[1].amount == 1 and applications[1].stacksAfter == strengths[fortifier], "Fortify gives only its owner five block and one additive strength")
		check(model.buffs.count(model, "strength", 0) == strengths[0] and model.buffs.count(model, "strength", 1) == strengths[1] and model.enemies[attacker].block == 0 and model.enemies[fortifier].block == 5, "The two hounds retain separate strength and only the new fortifier retains block")
		var clears: Array = result.turnEvents.filter(func(event): return event.type == "block_clear")
		check(clears.size() == (0 if round_index == 0 else 1), "Block-clear event exists only for an owner with previous block")
		if not clears.is_empty():
			check(clears[0].target == attacker and event_index(result.turnEvents, "block_clear", attacker) < event_index(result.turnEvents, "attack", attacker), "The attacker's old block clears immediately before its own action")
		total_damage += per_hit * 2
		check(model.player_hp == 100 - total_damage and model.turn == round_index + 2 and Game.valid_combat(saved(model)), "Round%d applies damage once and produces a valid next-player snapshot" % round_index)
	check(strengths == [3, 3] and total_damage == 66, "Six rounds alternate evenly and accumulate three strength on each hound")

func test_block_lifecycle() -> void:
	var model := hounds()
	model.enemies[0].block = 5
	model.enemies[1].block = 7
	model.block = 9
	model.buffs.player_turn_end(model)
	check(model.enemies[0].block == 5 and model.enemies[1].block == 7 and model.block == 9, "Ending the player turn does not clear either enemy's or player's block early")
	model.buffs.own_turn_start(model, 0)
	check(model.enemies[0].block == 0 and model.enemies[1].block == 7 and model.block == 9, "Starting one enemy action clears only that enemy's block")
	model.buffs.own_turn_start(model)
	check(model.enemies[1].block == 7 and model.block == 0, "Starting the player turn clears only player block")

	model = hounds()
	model.enemies[0].block = 5
	model.enemies[1].block = 7
	var normal := model.end_turn()
	check(model.enemies[0].block == 0 and model.enemies[1].block == 5 and normal.turnEvents.size() == 5, "A fortifying hound clears its old seven block before gaining a fresh five")
	check(normal.turnEvents[0].type == "block_clear" and normal.turnEvents[0].target == 0 and normal.turnEvents[1].type == "attack" and normal.turnEvents[2].type == "block_clear" and normal.turnEvents[2].target == 1 and normal.turnEvents[3].buffId == "block" and normal.turnEvents[4].buffId == "strength", "Old-block clear, attack and fortify events preserve each unit's own action order")

	model = hounds()
	model.enemies[0].block = 5
	model.enemies[1].block = 7
	model.player_hp = 1
	var result := model.end_turn()
	check(result.outcome == "lose" and result.attacks.size() == 1 and result.attacks[0].hits.size() == 1 and model.enemies[0].block == 0 and model.enemies[1].block == 7, "If the first hound kills the player, the unacted second hound retains its old block")
	check(result.turnEvents.size() == 2 and result.turnEvents[0].type == "block_clear" and result.turnEvents[0].target == 0 and result.turnEvents[1].type == "attack", "No block-clear or fortify event is emitted for an enemy that never acts")

	model = hounds()
	model.block = 10
	result = model.end_turn()
	check(result.attacks[0].damage == 0 and result.attacks[0].hits.size() == 2 and result.attacks[0].hits.all(func(hit): return hit.blocked == 4), "Player block remains available throughout the enemy's two attack segments")
	check(model.player_hp == 100 and model.block == 0 and model.enemies[1].block == 5, "Remaining player block clears at new player turn while newly fortified enemy block survives")
	var hit := model.enemy_damage(1, 3, false, true)
	check(hit.blocked == 3 and hit.damage == 0 and model.enemies[1].block == 2, "Fortified block absorbs a player attack during the following player phase")
	result = model.end_turn()
	check(model.enemies[0].block == 5 and model.enemies[1].block == 0 and event_index(result.turnEvents, "status_apply", 0) < event_index(result.turnEvents, "block_clear", 1) and event_index(result.turnEvents, "block_clear", 1) < event_index(result.turnEvents, "attack", 1), "First hound gains new block before the second clears its own residual block; the first block survives")

func test_live_targets_and_modifiers() -> void:
	for dead_index in [0, 1]:
		var model := hounds()
		model.enemies[dead_index].hp = 0
		model.enemies[dead_index].block = 7
		var result := model.end_turn()
		check(model.enemies[dead_index].block == 7 and model.buffs.count(model, "strength", dead_index) == 0 and result.turnEvents.all(func(event): return int(event.get("target", event.get("index", -1))) != dead_index), "A defeated hound neither acts nor loses block nor receives fortify, index%d" % dead_index)
		if dead_index == 0:
			check(result.attacks.is_empty() and model.enemies[1].block == 5 and model.buffs.count(model, "strength", 1) == 1, "Only living second hound fortifies")
		else:
			check(result.attacks.size() == 1 and result.attacks[0].index == 0 and result.attacks[0].hits.size() == 2 and result.attacks[0].damage == 8, "Only living first hound executes two attacks")
	var model := hounds()
	model.enemies[0].hp = 0
	var uid := "hound_qa_attack"
	model.instances[uid] = "noren_35"
	model.hand.append(uid)
	var before := saved(model)
	check(model.play_card(uid, 0).is_empty() and saved(model) == before, "Attack cannot target the defeated hound or spend resources")
	var result := model.play_card(uid, 1)
	check(result.hits.size() == 3 and result.hits.all(func(hit): return hit.target == 1) and model.enemies[1].hp == 29, "Real multiattack targets only the surviving selected hound")
	model = hounds()
	model.buffs.apply(model, "strength", 3, 0)
	model.buffs.apply(model, "strength", 5, 1)
	model.enemies[0].weak = 1
	model.block = 4
	result = model.end_turn()
	check(result.attacks[0].hits.size() == 2 and result.attacks[0].damage == 6 and result.attacks[0].hits[0].blocked == 4 and model.buffs.count(model, "strength", 0) == 3 and model.buffs.count(model, "strength", 1) == 6, "Each attack segment keeps ordinary weakness/block rules; fortify adds to its own existing strength")

func test_snapshots_and_legacy() -> void:
	var catalog_before := JSON.stringify([Game.enemy_catalog.pruning_hound, Game.enemy_catalog.pruning_hound_second])
	var model := hounds()
	model.end_turn()
	var snapshot := saved(model)
	var restored := CombatModel.new()
	restored.restore(snapshot)
	check(Game.valid_combat(snapshot) and saved(restored) == snapshot and restored.enemies[1].block == 5, "Snapshot preserves both hounds, separate buffs and staggered next actions exactly")
	for round_index in 4:
		seed(3130 + round_index)
		var expected := model.end_turn()
		seed(3130 + round_index)
		var resumed := restored.end_turn()
		check(JSON.stringify(expected) == JSON.stringify(resumed) and saved(model) == saved(restored), "Restored pair continues identically through round%d" % round_index)
	for field in ["amount", "strength"]:
		for invalid in [-1, 1.5, "1"]:
			for location in ["intent", "intentSequence"]:
				var malformed := snapshot.duplicate(true)
				if location == "intent": malformed.enemies[0].intent[field] = invalid
				else: malformed.enemies[0].intentSequence[1][field] = invalid
				check(not Game.valid_combat(malformed), "Snapshot rejects malformed fortify %s=%s in %s" % [field, str(invalid), location])
	var malformed := snapshot.duplicate(true)
	malformed.enemies[0].intent.strength = 1000
	check(not Game.valid_combat(malformed), "Fortify strength above the supported maximum is rejected")
	var legacy := hounds()
	legacy.enemies.resize(1)
	legacy.enemies[0].hp = 36
	legacy.enemies[0].maxHp = 36
	legacy.enemies[0].intentSequence = [{"type":"attack", "amount":6, "hits":1, "animation":"pierce"}]
	legacy.enemies[0].intent = legacy.enemies[0].intentSequence[0].duplicate(true)
	snapshot = saved(legacy)
	restored = CombatModel.new()
	restored.restore(snapshot)
	check(Game.valid_combat(snapshot) and saved(restored) == snapshot, "Old single thirty-six HP / attack6 B13 snapshot remains valid and exact")
	for round_index in 3:
		var result := restored.end_turn()
		check(restored.enemies.size() == 1 and restored.enemies[0].maxHp == 36 and result.attacks.size() == 1 and result.attacks[0].hits.size() == 1 and result.attacks[0].damage == 6, "Old B13 snapshot retains one attack6 hound in round%d" % round_index)
	check(JSON.stringify([Game.enemy_catalog.pruning_hound, Game.enemy_catalog.pruning_hound_second]) == catalog_before, "Restoring current and legacy battles never modifies either hound catalog entry")

func _ready() -> void:
	Game.save_enabled = false
	var args := OS.get_cmdline_user_args()
	if args.has("--output-dir"): output_dir = args[args.find("--output-dir") + 1].trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(output_dir)
	Game.save_path = output_dir + "/unused-checkpoint.json"
	Game.meta_path = output_dir + "/unused-meta.json"
	test_staggered_loop()
	test_block_lifecycle()
	test_live_targets_and_modifiers()
	test_snapshots_and_legacy()
	FileAccess.open(output_dir + "/rules-result.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures}, "\t"))
	print("HOUND RULES: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
