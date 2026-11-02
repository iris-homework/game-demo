extends Node
## Model, ordered playback events and frozen saves; isolated QA storage only.
var checks := 0
var failures: Array[String] = []
var output := ""
const CASES := [
	["B17", [85], [0,14,20,0,14,20]],
	["B18", [72], [0,24,12,0,24,12]],
	["B19", [42,42], [10,12,22,10,12,22]],
	["B20", [45,45], [8,18,26,8,18,26]],
	["B21", [80], [0,17,18,0,20,24]],
	["B22", [78], [14,12,0,14,14,12]]]

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("WEEK2 INTENTS: " + message)

func saved(model: CombatModel) -> Dictionary:
	return JSON.parse_string(JSON.stringify(model.snapshot()))

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func model_for(id: String, difficulty: String = "normal") -> CombatModel:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	rules.shuffleInitialDeck = false
	rules.difficulty = difficulty
	var defs: Array = []
	for enemy_id in Game.battles[id].enemyIds: defs.append(Game.enemy_catalog[enemy_id])
	var model := CombatModel.new()
	model.initialize(id, 1000, 1000, rules, defs, Game.card_catalog)
	return model

func test_loops_and_saves() -> void:
	for row in CASES:
		var model := model_for(row[0])
		check(model.enemies.map(func(e): return e.hp) == row[1], row[0]+" authored formation and HP")
		var advanced := model_for(row[0], "advanced")
		var bonus := 10 if row[1].size() == 1 else 5
		check(advanced.enemies.map(func(e): return e.hp) == row[1].map(func(hp): return hp+bonus), row[0]+" difficulty depends on actual formation size")
		var adv_restored := CombatModel.new()
		adv_restored.restore(saved(advanced))
		check(same(saved(advanced), saved(adv_restored)), row[0]+" loading does not apply HP bonus twice")
		for turn_index in row[2].size():
			var before := saved(model)
			for enemy in model.enemies:
				var tip := preload("res://scripts/combat/intent_tooltip.gd").describe(enemy, model.enemy_intent_text(enemy))
				check(not tip.plain.is_empty(), row[0]+" tooltip available")
			check(same(before, saved(model)), row[0]+" previews are read only")
			var restored := CombatModel.new()
			restored.restore(before)
			seed(2000+turn_index)
			var result := model.end_turn()
			seed(2000+turn_index)
			var resumed := restored.end_turn()
			var damage := 0
			for attack in result.attacks: damage += int(attack.damage)
			check(damage == row[2][turn_index], "%s turn %d direct damage %d" % [row[0],turn_index+1,row[2][turn_index]])
			check(same(result,resumed) and same(saved(model),saved(restored)), row[0]+" exact continued JSON roundtrip")
			check(Game.valid_combat(saved(model)), row[0]+" current frozen save validates")
		# Keep old single-enemy 60/10 snapshots without regenerating from today's data.
		var old := saved(model)
		old.enemies = [old.enemies[0]]
		old.enemies[0].hp = 60
		old.enemies[0].maxHp = 60
		old.enemies[0].intentSequence = [{"type":"attack","amount":10,"hits":1,"animation":"pierce"}]
		old.enemies[0].intent = old.enemies[0].intentSequence[0].duplicate(true)
		old.enemies[0].intentIndex = 0
		old.enemies[0].buffs = {}
		old.enemies[0].block = 0
		var legacy := CombatModel.new()
		legacy.restore(old)
		check(Game.valid_combat(old) and same(old,saved(legacy)) and legacy.end_turn().attacks[0].damage == 10, row[0]+" old 60HP single enemy keeps frozen attack ten")

func test_composites() -> void:
	var model := model_for("B17")
	model.end_turn()
	check(model.enemies[0].block == 18, "warden gets eighteen block")
	model.enemy_damage(0,5,false,true)
	model.buffs.apply(model,"parry",1)
	var result := model.end_turn()
	check(model.enemies[0].hp == 78 and model.enemies[0].block == 8, "old block expires; parry precedes new shield")
	check(result.turnEvents.back().buffId == "block" and result.turnEvents.back().stacksAfter == 8, "post-attack block is a separate ordered event")
	model.end_turn()
	check(model.enemies[0].block == 0, "post-attack shield expires at next own action")
	model = model_for("B17")
	model.end_turn()
	model.enemies[0].hp = 5
	model.buffs.apply(model,"parry",1)
	model.end_turn()
	check(model.outcome == "win" and model.enemies[0].block == 0, "dead attacker cannot receive post-attack shield")
	model = model_for("B20")
	result = model.end_turn()
	check(model.enemies[0].block == 8 and model.buffs.count(model,"electric_charge",0) == 4, "合箱 grants block and charge together")
	for i in 3: model.enemy_damage(0,0,false,true)
	check(model.enemies[0].block == 8 and model.buffs.count(model,"electric_charge",0) == 1 and model.enemy_intent_text(model.enemies[0]) == "攻击 6 ×2", "three blocked hits discharge without HP loss and refresh preview")
	result = model.end_turn()
	check(result.attacks[0].damage == 12 and model.buffs.count(model,"electric_charge",0) == 0, "remaining charge applies to both hits and consumes once")
	model = model_for("B21")
	model.enemies[0].block = 20
	model.buffs.apply(model,"soft",1,0)
	result = model.end_turn()
	check(model.enemies[0].hp == 75 and model.enemies[0].block == 0 and model.buffs.count(model,"strength",0) == 3, "self loss bypasses shield and does not trigger soft")
	check(result.turnEvents[1].type == "self_hp_loss" and result.turnEvents[1].hpAfter == 75, "self loss event precedes strength grant")
	model = model_for("B21")
	model.enemies[0].hp = 3
	result = model.end_turn()
	check(model.outcome == "win" and model.enemies[0].hp == 0 and model.buffs.count(model,"strength",0) == 0, "lethal self loss ends battle without granting dead enemy strength")
	for shield in [0,5,20]:
		model = model_for("B22")
		model.end_turn()
		model.block = shield
		result = model.end_turn()
		var stolen := mini(shield,8)
		var damage := maxi(0,12-(shield-stolen))
		check(model.enemies[0].block == stolen and result.attacks[0].damage == damage, "steal actual shield capped eight before attack: "+str(shield))
		check(result.turnEvents[0].type == "block_steal" and result.turnEvents[0].playerBlockAfter == shield-stolen, "shield removal precedes hit display: "+str(shield))
		check(model.enemy_intent_damage(model.enemies[0]) >= 0, "steal does not mutate attack base")
	model = model_for("B18")
	model.end_turn()
	check(model.enemy_intent_text(model.enemies[0]) == "攻击 12 ×2", "two vulnerable layers predict next turn's twenty-four damage")
	model.end_turn()
	model.block = 100
	model.end_turn()
	check(model.weak == 2, "broker's fully blocked attack still applies weakness")
	model = model_for("B19")
	model.enemy_damage(0,999)
	model.end_turn()
	check(model.buffs.count(model,"pollution") == 3 and model.enemies[0].hp == 0, "dead mouse skips attack without death pollution")

func test_legacy_formal_openings() -> void:
	for row in CASES:
		Game.state = Game.initial_state()
		Game.state.currentWeek = 2
		Game.state.currentDay = 1
		Game.state.currentScene = "battle"
		Game.state.battleId = row[0]
		Game.state.activeEventId = Game.battles[row[0]].eventId
		Game.state.activeNodeId = "battle"
		Game.state.currentPlaceId = Game.battles[row[0]].placeId
		Game.initialize_combat()
		var opening: Dictionary = Game.state.battleStart.duplicate(true)
		opening.enemies = [opening.enemies[0]]
		var enemy: Dictionary = opening.enemies[0]
		enemy.hp = 60
		enemy.maxHp = 60
		enemy.buffs = {}
		enemy.intentSequence = [{"type":"attack","amount":10,"hits":1,"animation":"pierce"}]
		enemy.intent = enemy.intentSequence[0].duplicate(true)
		Game.state.battleStart = opening.duplicate(true)
		Game.state.combat = opening.duplicate(true)
		check(Game.valid_save(Game.state) and Game.valid_battle_start(Game.state), row[0]+" full old single-enemy opening save remains loadable")
		var restored := CombatModel.new()
		restored.restore(JSON.parse_string(JSON.stringify(Game.state.combat)))
		check(restored.enemies.size() == 1 and restored.enemies[0].maxHp == 60 and restored.end_turn().attacks[0].damage == 10, row[0]+" full old save continues original formation and attack")

func test_validation() -> void:
	for row in [["B17",1,"postBlock"],["B20",0,"charge"],["B21",0,"selfHpLoss"],["B22",1,"stealBlock"],["B18",2,"onHitWeak"]]:
		var model := model_for(row[0])
		for value in [-1,0.5,1000,true,"2"]:
			var bad := saved(model)
			bad.enemies[0].intentSequence[row[1]][row[2]] = value
			check(not Game.valid_combat(bad), "%s rejects invalid %s=%s" % [row[0],row[2],str(value)])
		var bad := saved(model)
		bad.enemies[0].intent[row[2]] = 2
		bad.enemies[0].intent.type = "weak" if row[2] in ["postBlock","stealBlock","onHitWeak"] else "attack"
		check(not Game.valid_combat(bad), row[2]+" rejects incompatible action type")

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in OS.get_user_data_dir().to_lower():
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	test_loops_and_saves()
	test_composites()
	test_validation()
	test_legacy_formal_openings()
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("WEEK2 INTENTS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
