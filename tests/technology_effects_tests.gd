extends Node

const POCKET := "dimensional_pocket"
const CLOCK := "accelerated_clock"
const ENERGY := "backup_energy"
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func model_for() -> CombatModel:
	Game.state = Game.initial_state()
	# Active technologies are purchased/equipped explicitly, not starting gifts.
	Game.state.ownedCyberwareIds = [POCKET, CLOCK, ENERGY]
	Game.state.equippedCyberwareIds = [POCKET, CLOCK, ENERGY]
	Game.state.targetId = "richard"
	Game.state.activeEventId = "E04"
	Game.state.activeNodeId = "battle"
	Game.state.currentPlaceId = "alley"
	Game.state.currentScene = "battle"
	Game.state.battleId = "B04"
	Game.initialize_combat()
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	# Preserve valid authored enemy IDs while allowing 999 safe turn boundaries.
	for enemy in model.enemies:
		enemy.hp = 1000
		enemy.maxHp = 1000
		enemy.intent = {"type":"attack", "amount":0, "hits":1}
		enemy.intentSequence = [enemy.intent.duplicate()]
		enemy.erase("allyDeathIntentSequence")
	model.draw_pile.sort()
	model.draw_cards()
	return model

func check_piles(model: CombatModel, message: String) -> void:
	var all: Array = model.draw_pile + model.hand + model.discard_pile + model.exhaust_pile
	var unique := {}
	for uid in all: unique[uid] = true
	check(all.size() == model.instances.size() and unique.size() == all.size(), message + ": UID conservation")
	check(Game.valid_combat(model.snapshot()), message + ": valid snapshot")

func test_authored_loadout() -> void:
	check(Game.valid_player_character("noren"), "Noren accepts all three effect definitions")
	check(Game.player_cyberware("noren").cards.is_empty(), "New adventures have no starting technologies")
	model_for()
	check(Game.player_cyberware().cards.map(func(c): return c.id) == [POCKET, CLOCK, ENERGY], "Explicitly equipped technologies retain loadout order")
	for row in [[POCKET, "异次元口袋", 3], [CLOCK, "加速时钟", 999], [ENERGY, "后备能源", 3]]:
		var definition := Game.cyberware_definition(row[0])
		check(definition.name == row[1] and definition.cooldownTurns == row[2], "Authored name and cooldown: " + row[1])

func test_pocket_and_energy() -> void:
	var m := model_for()
	var original_hand := m.hand.duplicate()
	var original_energy := m.energy
	var original_ammo := m.ammo
	check(m.activate_cyberware(POCKET), "Pocket activates from melee")
	check(m.stance == "ranged" and m.stance_discount and m.hand == original_hand, "Pocket enters ranged and grants the existing stance discount")
	check(m.energy == original_energy and m.ammo == original_ammo, "Pocket spends neither energy nor ammo")
	check(m.cyberware_cooldown(POCKET) == 3 and m.available_cyberware_count() == 2, "Pocket starts three-turn cooldown")
	var after := m.snapshot()
	check(not m.activate_cyberware(POCKET) and m.snapshot() == after, "Repeated pocket activation cannot change any state")
	check(m.activate_cyberware(ENERGY) and m.energy == original_energy + 1, "Backup energy can exceed normal per-turn energy")
	check(m.cyberware_cooldown(ENERGY) == 3 and m.next_attack_bonus == 0, "Energy has its own cooldown and grants no attack bonus")
	for remaining in [2, 1]:
		m.end_turn()
		check(m.cyberware_cooldown(POCKET) == remaining and m.cyberware_cooldown(ENERGY) == remaining, "Both cooldowns tick once at player turn start: %d" % remaining)
		var before := m.snapshot()
		check(not m.activate_cyberware(POCKET) and not m.activate_cyberware(ENERGY) and m.snapshot() == before, "Cooling activations preserve state")
	m.end_turn()
	check(m.turn == 4 and m.cyberware_cooldown(POCKET) == 0 and m.cyberware_available(POCKET), "Three-turn cooldown is ready on turn four")
	var hand_before := m.hand.size()
	check(m.activate_cyberware(POCKET) and m.stance == "melee" and m.hand.size() == hand_before + 2, "Pocket entering melee draws two through existing stance rules")
	m.energy = 0
	check(m.activate_cyberware(ENERGY) and m.energy == 1, "Backup energy restores one from zero")
	check_piles(m, "Pocket extra draw")

func test_redraw() -> void:
	var m := model_for()
	var original_hand := m.hand.duplicate()
	var original_draw := m.draw_pile.duplicate()
	var before_energy := m.energy
	check(m.activate_cyberware(CLOCK), "Clock activates with five cards")
	check(m.hand.size() == original_hand.size() and m.discard_pile == original_hand, "Clock discards every original card and draws equal count")
	check(m.hand == reversed(original_draw) and m.energy == before_energy, "Clock follows real draw order and does not cost energy")
	check(m.cyberware_cooldown(CLOCK) == 999, "Clock uses literal 999-turn cooldown")
	check_piles(m, "Ordinary redraw")
	var after := m.snapshot()
	check(not m.activate_cyberware(CLOCK) and m.snapshot() == after, "Clock cannot redraw twice in the same turn")
	# An empty draw pile recycles the just-discarded hand through the usual rule.
	m = model_for()
	m.draw_cards(100)
	var count_before := m.hand.size()
	var seen_recycles: Array[int] = []
	m.discard_recycled.connect(func(size, _next): seen_recycles.append(size))
	check(m.activate_cyberware(CLOCK) and m.hand.size() == count_before, "Clock redraws full hand from an exhausted draw pile")
	check(seen_recycles == [count_before] and m.discard_pile.is_empty(), "Clock emits normal recycle notification exactly once")
	check_piles(m, "Recycled redraw")
	m = model_for()
	m.discard_pile.append_array(m.hand)
	m.hand.clear()
	var piles := [m.draw_pile.duplicate(), m.discard_pile.duplicate()]
	check(m.activate_cyberware(CLOCK) and m.hand.is_empty(), "Zero-card clock resolves as zero draw")
	check([m.draw_pile, m.discard_pile] == piles and m.cyberware_cooldown(CLOCK) == 999, "Empty-hand use starts cooldown without moving cards")
	check_piles(m, "Empty redraw")

func reversed(values: Array) -> Array:
	var result := values.duplicate()
	result.reverse()
	return result

func test_long_cooldown_and_terminal() -> void:
	var m := model_for()
	m.activate_cyberware(CLOCK)
	for index in 998: m.end_turn()
	check(m.turn == 999 and m.cyberware_cooldown(CLOCK) == 1 and not m.cyberware_available(CLOCK), "999-turn clock remains cooling through turn 999")
	var before := m.snapshot()
	check(not m.activate_cyberware(CLOCK) and m.snapshot() == before, "Clock cannot activate one turn early")
	m.end_turn()
	check(m.turn == 1000 and m.cyberware_cooldown(CLOCK) == 0 and m.activate_cyberware(CLOCK), "Clock becomes ready on turn 1000 and starts fresh cooldown")
	check_piles(m, "999-turn cycle")
	m = model_for()
	m.profile.erase("ruleset")
	before = m.snapshot()
	check(not m.activate_cyberware(POCKET) and not m.activate_cyberware(ENERGY) and m.snapshot() == before, "Stance and energy technologies are unavailable under legacy non-Noren rules without mutation")
	check(m.activate_cyberware(CLOCK) and m.hand.size() == before.hand.size(), "Generic redraw remains available under legacy rules")
	for outcome in ["win", "lose"]:
		m = model_for()
		m.outcome = outcome
		before = m.snapshot()
		check(not m.activate_cyberware(POCKET) and not m.activate_cyberware(CLOCK) and not m.activate_cyberware(ENERGY) and m.snapshot() == before, "Terminal battle rejects all technology: " + outcome)
	m = model_for()
	m.player_hp = 0
	before = m.snapshot()
	check(not m.activate_cyberware(ENERGY) and m.snapshot() == before, "Zero-HP player cannot restore energy")

func test_snapshot_and_validation() -> void:
	var m := model_for()
	m.activate_cyberware(POCKET)
	m.activate_cyberware(CLOCK)
	m.activate_cyberware(ENERGY)
	m.end_turn()
	var snapshot := m.snapshot()
	var restored := CombatModel.new()
	restored.restore(JSON.parse_string(JSON.stringify(snapshot)))
	check(same(restored.snapshot(), snapshot), "All effects and remaining cooldowns survive JSON roundtrip")
	check(restored.cyberware_cooldown(CLOCK) == 998 and restored.cyberware_cooldown(POCKET) == 2, "Reload retains partial multi-turn cooldowns")
	check(not restored.activate_cyberware(ENERGY), "Reload cannot bypass cooldown")
	snapshot.cyberwareCooldowns[ENERGY] = 1
	check(m.cyberware_cooldown(ENERGY) == 2 and restored.cyberware_cooldown(ENERGY) == 2, "Snapshot and restore dictionaries are independent")
	Game.state.battleStart = {}
	Game.commit_combat(m)
	check(Game.valid_save(Game.state) and Game.save_game(), "Legacy live-save path accepts new technologies")
	Game.state = {}
	check(Game.load_game(), "Isolated disk save reloads")
	restored.restore(Game.state.combat)
	check(same(restored.snapshot(), m.snapshot()), "Disk roundtrip retains complete multi-turn effect state")
	for bad in [[], "bad", {}, {POCKET:2}, {"missing":1}, {POCKET:2, CLOCK:998, ENERGY:2, "missing":1}]:
		var corrupt := m.snapshot()
		corrupt.cyberwareCooldowns = bad
		check(not Game.valid_combat(corrupt), "Reject malformed cooldown mapping " + str(bad))
	for bad in [0, -1, 0.5, "2", 4]:
		var corrupt := m.snapshot()
		corrupt.cyberwareCooldowns[POCKET] = bad
		check(not Game.valid_combat(corrupt), "Reject malformed remaining cooldown with all IDs intact: " + str(bad))
	var missing_mapping := m.snapshot()
	missing_mapping.erase("cyberwareCooldowns")
	check(not Game.valid_combat(missing_mapping), "New multi-turn used IDs cannot load without remaining cooldowns")
	var inconsistent := m.snapshot()
	inconsistent.usedCyberware = []
	check(not Game.valid_combat(inconsistent), "Reject cooldown IDs inconsistent with used IDs")
	# The original one-turn legacy fields still load without a new mapping.
	var old := model_for().snapshot()
	old.profile.cyberware.cards = [Game.cyberware_definition("test_cyberware_01").duplicate(true)]
	old.profile.playerCyberwareIds = ["test_cyberware_01"]
	old.erase("cyberwareCooldowns")
	old.usedCyberware = ["test_cyberware_01"]
	old.nextAttackBonus = 1
	check(Game.valid_combat(old), "Legacy snapshot without mapping validates")
	restored.restore(old)
	check(restored.cyberware_cooldown("test_cyberware_01") == 1 and not restored.activate_cyberware("test_cyberware_01"), "Legacy used ID restores one-turn cooldown")
	restored.end_turn()
	check(restored.cyberware_available("test_cyberware_01") and restored.activate_cyberware("test_cyberware_01") and restored.next_attack_bonus == 2, "Legacy cooldown and carried attack bonus remain compatible")

func test_definition_validation() -> void:
	var original: Dictionary = Game.prototype_rules.cyberware.duplicate(true)
	var original_ids: Array = Game.player_characters.noren.cyberwareIds.duplicate()
	Game.player_characters.noren.cyberwareIds = [POCKET, CLOCK, ENERGY]
	for change in [{"cooldownTurns":0}, {"cooldownTurns":-1}, {"cooldownTurns":1.5}, {"cooldownTurns":"3"}, {"effect":"unknown"}, {"amount":0}, {"amount":0.5}]:
		var definition := Game.cyberware_definition(ENERGY)
		for key in change: definition[key] = change[key]
		check(not Game.valid_player_character("noren"), "Reject invalid referenced technology definition: " + str(change))
		Game.prototype_rules.cyberware = original.duplicate(true)
	check(Game.valid_player_character("noren"), "Valid definitions remain available after invalid fixtures")
	Game.player_characters.noren.cyberwareIds = original_ids

func test_battle_start_reset() -> void:
	var m := model_for()
	var initial: Dictionary = Game.state.battleStart.duplicate(true)
	m.activate_cyberware(POCKET)
	m.activate_cyberware(CLOCK)
	m.activate_cyberware(ENERGY)
	Game.commit_combat(m)
	check(Game.save_game(), "New-format technology battle saves")
	Game.state = {}
	check(Game.load_game(), "New-format battle reloads from its opening")
	check(same(Game.state.combat, initial), "BattleStart resets technology effects and cooldowns to frozen opening")
	var restored := CombatModel.new()
	restored.restore(Game.state.combat)
	check(restored.available_cyberware_count() == 3 and restored.energy == 3 and restored.stance == "melee", "Restart restores all three ready technologies and opening resources")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://technology_effects_test_checkpoint.json"
	Game.meta_path = "user://technology_effects_test_meta.json"
	seed(20261023)
	test_authored_loadout()
	test_pocket_and_energy()
	test_redraw()
	test_long_cooldown_and_terminal()
	test_snapshot_and_validation()
	test_definition_validation()
	test_battle_start_reset()
	for path in [Game.save_path, Game.save_path + ".bak", Game.save_path + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("TECHNOLOGY EFFECTS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
