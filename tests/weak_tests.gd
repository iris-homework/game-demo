extends Node
const Fixtures = preload("res://tests/noren_cards_tests.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://weak_qa.json"
	Game.meta_path = "user://weak_meta_qa.json"
	var helper := Fixtures.new()
	for layers in range(6):
		var m: CombatModel = helper.fixture([1])
		m.enemies[0].weak = layers
		m.enemies[0].intent = {"type":"attack", "amount":12, "hits":3}
		var expected := 9 if layers > 0 else 12
		check(m.buffs.enemy_attack_damage(m.enemies[0], 12) == expected, "Intent fixed reduction at %d stacks" % layers)
		var result := m.end_turn()
		check(result.attacks[0].hits.size() == 3 and result.attacks[0].hits.all(func(h): return h.damage == expected), "All segments use same reduction at %d stacks" % layers)
		check(m.player_hp == 100 - expected * 3, "Actual total damage at %d stacks" % layers)
		check(m.enemies[0].weak == maxi(0, layers - 1), "One decay per turn, not per hit, at %d stacks" % layers)
		check(Game.valid_combat(m.snapshot()), "Snapshot valid after decay at %d stacks" % layers)
	var m: CombatModel = helper.fixture([1])
	m.enemies[0].weak = 1
	m.enemies[0].intent = {"type":"attack", "amount":12, "hits":1}
	check(m.end_turn().attacks[0].damage == 9 and m.enemies[0].weak == 0, "Last layer protects current enemy turn before expiring")
	# Reinstall the same intent after the existing intent sequence advances.
	m.enemies[0].intent = {"type":"attack", "amount":12, "hits":1}
	check(m.end_turn().attacks[0].damage == 12, "No reduction after expiration")
	m = helper.fixture([1], "melee", 3)
	for i in 3:
		m.enemies[i].weak = i + 1
		m.enemies[i].intent = {"type":"attack", "amount":12, "hits":1}
	var result := m.end_turn()
	check(result.attacks.size() == 3 and m.player_hp == 73, "All enemies use fixed reduction independently")
	check(m.enemies.map(func(e): return e.weak) == [0,1,2], "Each enemy decays once, independent of enemy count")
	m = helper.fixture([1])
	m.enemies[0].weak = 2
	m.enemies[0].intent = {"type":"wait"}
	check(m.end_turn().attacks.is_empty() and m.enemies[0].weak == 1, "Non-attacking enemy turn still decays")
	m = helper.fixture([1])
	m.enemies[0].weak = 2
	m.enemies[0].intent = {"type":"attack", "amount":12, "hits":2}
	m.block = 100
	m.parry = 2
	result = m.end_turn()
	check(m.player_hp == 100 and result.attacks[0].hits[0].blocked == 9, "Weak applies before player block")
	check(result.attacks[0].counters.size() == 2 and result.attacks[0].counters.all(func(h): return h.damage == 5), "Parry uses weakened total 18, rounds 25 percent to 5")
	check(m.parry == 1 and m.enemies[0].weak == 1, "Parry and weakness each consume their own one layer")
	check(m.buffs.enemy_attack_damage({"weak":1}, 10) == 8 and m.buffs.enemy_attack_damage({"weak":5}, 9) == 7, "Preserve per-segment rounding")
	m = helper.fixture([19])
	m.enemies[0].weak = 2
	var saved: Dictionary = JSON.parse_string(JSON.stringify(m.snapshot()))
	var restored := CombatModel.new()
	restored.restore(saved)
	check(Game.valid_combat(saved) and restored.enemies[0].weak == 2, "Existing stored layers load without migration")
	helper.play(restored)
	check(restored.enemies[0].weak == 3, "Reapplying extends duration by one stack")
	restored.end_turn()
	check(restored.enemies[0].weak == 2, "Restored/reapplied stacks decay once")
	check(restored.buffs.enemy_badges(restored.enemies[0]).filter(func(b): return b.buffId == "weak")[0].description.contains("固定降低 25%"), "Tooltip describes fixed percentage")
	var stopped := restored.snapshot()
	restored.outcome = "win"
	check(restored.end_turn().is_empty() and restored.enemies == stopped.enemies, "Finished battles do not tick again")
	helper.free()
	print("WEAK: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
