extends Node
const Fixtures = preload("res://tests/combat/cards/noren_cards_tests.gd")
var fixtures := Fixtures.new()
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fish_fixture(ids: Array = ["fish", "fish_second"]) -> CombatModel:
	var m: CombatModel = fixtures.fixture([1], "melee", ids.size())
	m.battle_id = "B11"
	for index in ids.size():
		var enemy: Dictionary = Game.enemy_catalog[ids[index]].duplicate(true)
		enemy.hp = int(enemy.maxHp)
		enemy.block = 0
		enemy.bleed = 0
		enemy.weak = 0
		enemy.intentIndex = 0
		enemy.intent = m.intent_for(enemy, 0)
		m.enemies[index] = enemy
	return m

func events(result: Dictionary, kind: String) -> Array:
	return result.get("turnEvents", []).filter(func(event): return event.get("type", "") == kind)

func json_snapshot(m: CombatModel) -> Dictionary:
	return JSON.parse_string(JSON.stringify(m.snapshot()))

func test_catalog_and_cycles() -> void:
	check(Game.battles.B11.enemyIds == ["fish", "fish_second"], "B11 has two distinct ordered fish IDs")
	var expected := [
		[{"type":"attack", "amount":6, "hits":1}, {"type":"attack", "amount":2, "hits":2}, {"type":"pollution", "amount":3}],
		[{"type":"pollution", "amount":3}, {"type":"attack", "amount":6, "hits":1}, {"type":"attack", "amount":2, "hits":2}]
	]
	var m := fish_fixture()
	for index in 2:
		var enemy: Dictionary = m.enemies[index]
		check(enemy.hp == 30 and enemy.maxHp == 30, "Fish %d starts at 30 HP" % index)
		check(enemy.get("combatVisualId", "") == "fish", "Fish %d shares fish visual" % index)
		check(enemy.get("deathPollution", 0) == 3, "Fish %d has three-stack death pollution" % index)
		check(enemy.get("attackPollution", 0) == 2, "Fish %d has two-stack contact pollution" % index)
		check(enemy.intentSequence.size() == 3, "Fish %d has exactly three intents" % index)
	# Seven actual end-turn transitions exercise both full cycles and wrap again.
	# A large player block each round keeps the intent test independent of death.
	for round_index in 7:
		m.block = 999
		var attack_ids: Array = []
		var action_types: Array = []
		for index in 2:
			var intent: Dictionary = m.enemies[index].intent
			var wanted: Dictionary = expected[index][round_index % 3]
			check(intent.type == wanted.type and int(intent.amount) == wanted.amount and int(intent.get("hits", 1)) == int(wanted.get("hits", 1)), "Fish %d round %d exact intent" % [index, round_index + 1])
			check(m.enemies[index].intentIndex == round_index, "Fish %d round %d intent advances once" % [index, round_index + 1])
			if wanted.type == "attack": attack_ids.append(m.enemies[index].id)
			action_types.append("attack" if wanted.type == "attack" else "status_apply")
		var result := m.end_turn()
		check(result.attacks.map(func(a): return a.id) == attack_ids, "Round %d attacks excludes pollution action" % (round_index + 1))
		var actions: Array = result.get("turnEvents", []).filter(func(e): return e.type != "status_tick")
		check(actions.map(func(e): return e.type) == action_types, "Round %d chronological actions" % (round_index + 1))
		check(m.turn == round_index + 2 and result.outcome == "", "Round %d continues normally" % (round_index + 1))
		check(Game.valid_combat(json_snapshot(m)), "Round %d snapshot validates" % (round_index + 1))

func test_attack_pollution() -> void:
	for row in [
		{"amount":6, "hits":1, "block":6, "damage":0, "stacks":0},
		{"amount":6, "hits":1, "block":4, "damage":2, "stacks":2},
		{"amount":2, "hits":2, "block":0, "damage":4, "stacks":4},
		{"amount":2, "hits":2, "block":2, "damage":2, "stacks":2},
		{"amount":2, "hits":2, "block":1, "damage":3, "stacks":4},
		{"amount":0, "hits":2, "block":0, "damage":0, "stacks":0}
	]:
		var m := fish_fixture(["fish"])
		m.enemies[0].intent = {"type":"attack", "amount":row.amount, "hits":row.hits}
		m.block = row.block
		var result := m.end_turn()
		var label := "Attack %dx%d with %d block" % [row.amount, row.hits, row.block]
		check(m.player_hp == 100 - row.damage and result.attacks[0].damage == row.damage, label + " exact HP loss")
		check(m.buffs.count(m, "pollution") == row.stacks, label + " pollution only for damaging segments")
		check(events(result, "status_tick").is_empty(), label + " new pollution waits for player's next turn end")
		var running := 0
		for hit in result.attacks[0].hits:
			if hit.damage > 0: running += 2
			check(hit.get("pollutionAfter", -1) == running, label + " hit carries chronological pollution")
		check(events(result, "attack").size() == 1 and events(result, "attack")[0].get("index", -1) == 0, label + " attack event identifies source")
	var m: CombatModel = fixtures.fixture()
	m.end_turn()
	check(m.player_hp == 90 and m.buffs.count(m, "pollution") == 0, "Non-fish ordinary attack does not gain pollution")
	m = fish_fixture(["fish_second"])
	m.block = 100
	m.parry = 2
	var result := m.end_turn()
	check(result.attacks.is_empty() and m.player_hp == 100 and m.parry == 2 and m.enemies[0].hp == 30, "Pollution intent bypasses block without damage or parry")
	check(m.buffs.count(m, "pollution") == 3, "Pollution intent applies three layers")
	var applications := events(result, "status_apply")
	check(applications.size() == 1, "Pollution intent emits one status application")
	if applications.size() == 1:
		check(applications[0].source == 0 and applications[0].target == -1 and applications[0].buffId == "pollution" and applications[0].stacksAfter == 3, "Application event carries source recipient and stacks")

func test_ticks_and_death() -> void:
	for block_value in [0, 2, 8]:
		var m := fish_fixture(["fish"])
		m.enemies[0].intent = {"type":"wait", "amount":0}
		m.block = block_value
		m.parry = 2
		m.buffs.apply(m, "pollution", 5)
		var result := m.end_turn()
		var ticks := events(result, "status_tick")
		check(ticks.size() == 1, "Player pollution emits one tick with block %d" % block_value)
		if ticks.size() == 1:
			var tick: Dictionary = ticks[0]
			check(tick.target == -1 and tick.buffId == "pollution" and tick.damage == maxi(0, 5 - block_value) and tick.blocked == mini(5, block_value), "Pollution first consumes current block")
			check(tick.hpAfter == 100 - maxi(0, 5 - block_value) and tick.blockAfter == maxi(0, block_value - 5) and not tick.killed and tick.stacksAfter == 4, "Tick records pre-next-turn HP block and decayed stacks")
		check(m.buffs.count(m, "pollution") == 4 and m.parry == 2 and m.enemies[0].hp == 30, "Tick decrements once without retaliation or contact application")
		check(m.block == 0, "Player next turn clears leftover block after tick")
	var m := fish_fixture()
	m.buffs.apply(m, "pollution", 3)
	m.buffs.apply(m, "pollution", 4, 0)
	m.buffs.apply(m, "pollution", 2, 1)
	var result := m.end_turn()
	check(result.get("turnEvents", []).map(func(e): return e.type) == ["status_tick", "attack", "status_tick", "status_apply", "status_tick"], "Player tick before enemy actions; each enemy ticks after own action")
	check(m.player_hp == 91 and m.buffs.count(m, "pollution") == 7, "Player old pollution ticks before fish adds five new layers")
	check(m.enemies[0].hp == 26 and m.enemies[1].hp == 28 and m.buffs.count(m, "pollution", 0) == 3 and m.buffs.count(m, "pollution", 1) == 1, "Both enemies tick and decay once at own turn end")
	# Direct hook isolates block handling from the enemy own-turn-start clear.
	m = fish_fixture(["fish"])
	m.enemies[0].block = 3
	m.enemies[0].weak = 2
	m.buffs.apply(m, "pollution", 5, 0)
	m.buffs.own_turn_end(m, 0)
	check(m.enemies[0].hp == 28 and m.enemies[0].block == 0 and m.buffs.count(m, "pollution", 0) == 4 and m.enemies[0].weak == 1, "Enemy pollution uses block and is not reduced by weak")
	m = fish_fixture(["fish"])
	m.enemies[0].intent = {"type":"wait", "amount":0}
	m.enemies[0].intentSequence = [{"type":"wait", "amount":0}]
	m.buffs.apply(m, "pollution", 1)
	m.buffs.apply(m, "pollution", 1, 0)
	result = m.end_turn()
	check(m.player_hp == 99 and m.enemies[0].hp == 29 and events(result, "status_tick").size() == 2, "One-layer pollution damages both owners once")
	check(not m.snapshot().has("buffs") and not m.enemies[0].has("buffs"), "Last layer removes optional saved containers")
	result = m.end_turn()
	check(events(result, "status_tick").is_empty() and m.player_hp == 99 and m.enemies[0].hp == 29, "Expired pollution cannot tick on the following round")
	m = fish_fixture()
	m.player_hp = 2
	m.buffs.apply(m, "pollution", 3)
	result = m.end_turn()
	check(result.outcome == "lose" and result.attacks.is_empty() and result.drawn.is_empty() and m.turn == 1, "Fatal player tick stops all enemies and next-turn draw")
	check(events(result, "status_apply").is_empty() and events(result, "status_tick").size() == 1 and events(result, "status_tick")[0].killed, "Fatal tick emits death once and no later action")
	var stopped := json_snapshot(m)
	check(m.end_turn().is_empty() and json_snapshot(m) == stopped, "Ended combat cannot tick again")
	m = fish_fixture(["fish_second"])
	m.enemies[0].hp = 2
	m.buffs.apply(m, "pollution", 3, 0)
	result = m.end_turn()
	check(result.outcome == "win" and m.enemies[0].hp == 0 and result.drawn.is_empty(), "Last enemy own-turn pollution death wins battle")
	check(result.get("turnEvents", []).map(func(e): return e.type) == ["status_apply", "status_tick"], "Dying enemy completes its action before end-of-turn tick")
	m = fish_fixture()
	m.enemies[0].hp = 0
	result = m.end_turn()
	check(result.attacks.is_empty() and events(result, "status_apply").size() == 1 and events(result, "status_apply")[0].source == 1, "Already dead fish does not act; survivor keeps its own sequence")
	m = fish_fixture()
	m.player_hp = 1
	m.enemies[0].intent = {"type":"attack", "amount":2, "hits":2}
	result = m.end_turn()
	check(result.outcome == "lose" and result.attacks.size() == 1 and result.attacks[0].hits.size() == 1 and events(result, "status_apply").is_empty(), "Lethal attack stops later segments and second fish")

func test_death_pollution() -> void:
	var m := fish_fixture()
	m.block = 99
	var hit := m.enemy_damage(0, 29)
	check(hit.deathPollution == 0 and m.buffs.count(m, "pollution") == 0, "Nonlethal damage does not trigger death trait")
	hit = m.enemy_damage(0, 1)
	check(hit.deathPollution == 3 and hit.playerPollutionAfter == 3, "Lethal hit records three pollution")
	check(m.block == 99 and m.player_hp == 100, "Death applies stacks without consuming block or dealing immediate damage")
	m.enemy_damage(0, 99)
	check(m.buffs.count(m, "pollution") == 3, "Repeated damage to dead fish never reapplies death trait")
	var restored := CombatModel.new()
	restored.restore(json_snapshot(m))
	restored.enemy_damage(0, 99)
	check(restored.buffs.count(restored, "pollution") == 3, "Restored dead fish never reapplies death trait")
	restored.enemy_damage(1, 30)
	check(restored.buffs.count(restored, "pollution") == 6, "Second fish has independent death trigger after restore")
	m = fish_fixture()
	m.enemies[0].block = 30
	hit = m.enemy_damage(0, 30)
	check(not hit.killed and hit.deathPollution == 0, "Fully blocked damage cannot trigger death")
	m.buffs.apply(m, "pollution", 998)
	m.enemy_damage(0, 30)
	check(m.buffs.count(m, "pollution") == 999, "Death pollution respects 999 cap")
	m = fish_fixture()
	m.enemies[0].hp = 6
	var result := fixtures.play(m)
	check(result.hits[0].deathPollution == 3 and m.buffs.count(m, "pollution") == 3, "Card kill carries death effect to animation")
	m = fish_fixture()
	m.stance = "ranged"
	m.enemies[0].hp = 10
	m.enemies[0].bleed = 2
	result = fixtures.play(m)
	check(result.hits[0].attackDamage == 9 and result.hits[0].bleedDamage == 1 and result.hits[0].killed, "Ranged bleed can deliver lethal damage")
	check(result.hits[0].deathPollution == 3 and result.hits[0].playerPollutionAfter == 3, "Merged bleed hit retains death effect and chronological layers")
	m = fish_fixture()
	m.instances["card_000"] = "noren_38"
	for enemy in m.enemies: enemy.hp = 4
	result = fixtures.play(m)
	check(result.outcome == "win" and m.buffs.count(m, "pollution") == 6, "AoE killing both fish applies six before victory")
	check(result.hits.map(func(h): return h.playerPollutionAfter) == [3, 6], "AoE death effects preserve per-target order")
	m = fish_fixture(["fish"])
	m.instances["card_000"] = "noren_35"
	m.stance = "ranged"
	m.enemies[0].hp = 1
	result = fixtures.play(m)
	check(m.buffs.count(m, "pollution") == 3, "Three-hit lethal card triggers death pollution once")
	check(result.hits.size() == 1 and result.hits[0].deathPollution == 3 and m.ammo == 1, "Lethal first shot skips remaining shots and spends normal ammo once")
	m = fish_fixture(["fish"])
	m.enemies[0].hp = 1
	m.parry = 2
	result = m.end_turn()
	check(result.outcome == "win" and result.attacks[0].counters.size() == 1, "Lethal parry stops remaining counters")
	check(m.buffs.count(m, "pollution") == 5 and result.attacks[0].counters[0].playerPollutionAfter == 5, "Parry death adds three after two attack-contact stacks")
	m = fish_fixture(["fish_second"])
	m.enemies[0].hp = 1
	m.buffs.apply(m, "pollution", 1, 0)
	result = m.end_turn()
	var tick: Dictionary = events(result, "status_tick")[0]
	check(result.outcome == "win" and m.buffs.count(m, "pollution") == 6, "Enemy pollution death adds three after its pollution intent")
	check(tick.deathPollution == 3 and tick.playerPollutionAfter == 6, "Status death event retains passive presentation data")
	m = fish_fixture()
	m.enemy_damage(0, 30)
	m.block = 1
	result = m.end_turn()
	tick = events(result, "status_tick")[0]
	check(tick.damage == 2 and tick.blocked == 1 and tick.stacksAfter == 2, "Death pollution ticks normally through block then decays")
	check(m.buffs.count(m, "pollution") == 5, "Surviving second fish adds its normal three after tick")

func test_snapshot_and_training() -> void:
	var m := fish_fixture()
	var definition := m.buffs.definition("pollution")
	check(definition.get("category") == "negative" and definition.get("target") == "both" and definition.get("maxStacks") == 999, "Pollution catalog contract")
	for target in [-1, 0, 1]:
		check(m.buffs.apply(m, "pollution", 998, target) and m.buffs.apply(m, "pollution", 5, target) and m.buffs.count(m, "pollution", target) == 999, "Pollution caps at 999 for target %d" % target)
	var saved := json_snapshot(m)
	check(Game.valid_combat(saved), "Pollution JSON validates on both sides")
	check(not saved.has("turnEvents"), "Presentation event stream stays outside persistent combat state")
	var unchanged := m.snapshot()
	check(m.buffs.player_badges(m).any(func(b): return b.buffId == "pollution" and b.category == "negative" and b.count == 999), "Player pollution has a negative status badge")
	check(m.buffs.enemy_badges(m.enemies[0]).any(func(b): return b.buffId == "pollution" and b.category == "negative" and b.count == 999) and m.snapshot() == unchanged, "Enemy pollution badge is read-only")
	var restored := CombatModel.new()
	restored.restore(saved)
	check(json_snapshot(restored) == saved, "Pollution JSON restores exactly")
	m.buffs.clear(m, "pollution")
	m.buffs.clear(m, "pollution", 0)
	check(restored.buffs.count(restored, "pollution") == 999 and restored.buffs.count(restored, "pollution", 0) == 999, "Restored pollution is independent of source model")
	for value in [-1, 1000, 1.5, "2"]:
		for target in [-1, 0]:
			var broken := saved.duplicate(true)
			if target == -1: broken.buffs.pollution = value
			else: broken.enemies[target].buffs.pollution = value
			check(not Game.valid_combat(broken), "Invalid pollution rejected for target %d value %s" % [target, str(value)])
	# Represent a pre-feature running fish battle: no optional fields, old frozen stats.
	var legacy := json_snapshot(fish_fixture(["fish"]))
	legacy.enemies[0].erase("attackPollution")
	legacy.enemies[0].erase("deathPollution")
	legacy.enemies[0].erase("combatVisualId")
	legacy.enemies[0].maxHp = 3
	legacy.enemies[0].hp = 3
	legacy.enemies[0].intentSequence = [{"type":"attack", "amount":1, "hits":1}]
	legacy.enemies[0].intent = legacy.enemies[0].intentSequence[0].duplicate()
	legacy = JSON.parse_string(JSON.stringify(legacy))
	check(not legacy.has("buffs") and not legacy.enemies[0].has("buffs") and Game.valid_combat(legacy), "Old running snapshot needs no new status fields")
	restored = CombatModel.new()
	restored.restore(legacy)
	check(json_snapshot(restored) == legacy, "Old fish snapshot frozen stats retained exactly")
	restored.end_turn()
	check(restored.player_hp == 99 and restored.buffs.count(restored, "pollution") == 0, "Old fish snapshot without contact trait keeps old attack")
	restored.enemy_damage(0, 99)
	check(restored.buffs.count(restored, "pollution") == 0, "Old frozen fish without death trait keeps old death behavior")
	# An already-running battle retains its explicitly frozen five-stack death trait.
	var old_death := json_snapshot(fish_fixture())
	for enemy in old_death.enemies: enemy.deathPollution = 5
	old_death = JSON.parse_string(JSON.stringify(old_death))
	check(Game.valid_combat(old_death), "Old explicit five-stack death traits remain valid")
	restored = CombatModel.new()
	restored.restore(old_death)
	check(json_snapshot(restored) == old_death and restored.enemies.all(func(enemy): return enemy.deathPollution == 5), "Restore keeps explicit old death pollution instead of replacing it with current three")
	var old_hit := restored.enemy_damage(0, 30)
	check(old_hit.deathPollution == 5 and old_hit.playerPollutionAfter == 5, "Old frozen first fish still adds five death stacks")
	old_hit = restored.enemy_damage(1, 30)
	check(old_hit.deathPollution == 5 and old_hit.playerPollutionAfter == 10, "Old frozen second fish independently brings total to ten")
	restored.enemy_damage(0, 99)
	check(restored.buffs.count(restored, "pollution") == 10 and Game.enemy_catalog.fish.deathPollution == 3 and Game.enemy_catalog.fish_second.deathPollution == 3, "Repeated old death is ignored and current three-stack catalog stays unchanged")
	Game.state = Game.initial_state()
	Game.state.battleId = "B11"
	Game.initialize_combat()
	check(Game.state.combat.enemies.map(func(e): return e.id) == ["fish", "fish_second"] and Game.state.combat.enemies.all(func(e): return e.hp == 30 and e.maxHp == 30), "Game formal B11 initializes two 30-HP fish")
	var adventure: Dictionary = Game.state.duplicate(true)
	var catalog: Dictionary = Game.enemy_catalog.duplicate(true)
	for battle_id in ["B11", "B04", "B02"]:
		Game.start_training(battle_id)
		check(Game.training_mode and Game.state.battleId == battle_id, "Training starts requested battle " + battle_id)
		var expected_hp: Array = [15, 15, 30] if battle_id == "B04" else ([30, 30] if battle_id == "B11" else [100])
		check(Game.state.combat.enemies.map(func(e): return e.hp) == expected_hp and Game.state.combat.enemies.map(func(e): return e.maxHp) == expected_hp, "Training exact HP for " + battle_id)
		check(Game.valid_combat(Game.state.combat), "Training snapshot valid " + battle_id)
		var training := CombatModel.new()
		training.restore(Game.state.combat)
		training.buffs.apply(training, "pollution", 4)
		training.player_hp -= 3
		Game.commit_combat(training)
		Game.finish_training("lose")
		check(not Game.training_mode and Game.state == adventure and Game.training_backup.is_empty(), "Training restores full adventure after pollution " + battle_id)
		check(Game.enemy_catalog == catalog, "Training never mutates authored catalog " + battle_id)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://fish_rules_qa.json"
	Game.meta_path = "user://fish_rules_meta_qa.json"
	test_catalog_and_cycles()
	test_attack_pollution()
	test_ticks_and_death()
	test_death_pollution()
	test_snapshot_and_training()
	fixtures.free()
	print("FISH RULES: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
