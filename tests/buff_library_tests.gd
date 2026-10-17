extends Node
var Buffs := preload("res://scripts/combat/effects/buff_library.gd").new()
const Fixtures = preload("res://tests/noren_cards_tests.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	Game.buffs = Buffs
	Game.save_enabled = false
	Game.save_path = "user://buff_library_qa.json"
	Game.meta_path = "user://buff_library_meta_qa.json"
	var fixtures := Fixtures.new()
	check(Buffs.definitions().size() == 10, "Ten existing statuses registered")
	check(Buffs.definitions(Buffs.POSITIVE).size() == 8, "Eight positive statuses")
	check(Buffs.definitions(Buffs.NEGATIVE).map(func(d): return d.id) == ["bleed", "weak"], "Two negative statuses")
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string(Buffs.CATALOG_PATH))
	check(Buffs.catalog_errors(catalog).is_empty(), "Authored catalog valid")
	var invalid_catalog := catalog.duplicate(true)
	invalid_catalog[0].category = "neutral"
	check(not Buffs.catalog_errors(invalid_catalog).is_empty(), "Unsupported category rejected")
	invalid_catalog = catalog.duplicate(true)
	invalid_catalog[0].handler = "unimplemented"
	check(not Buffs.catalog_errors(invalid_catalog).is_empty(), "Unimplemented handler rejected")
	var copy := Buffs.definition("weak")
	copy.maxStacks = 123
	check(Buffs.definition("weak").maxStacks == 999, "Catalog query cannot mutate definitions")
	for entry in Buffs.definitions():
		check(not entry.name.is_empty() and not entry.description.is_empty(), entry.id + " has name and description")
		check(entry.target in ["both", "player", "enemy"] and entry.category in ["positive", "negative"], entry.id + " target and category")
	var m: CombatModel = fixtures.fixture([1, 36], "ranged", 2)
	m.buffs = Buffs
	var original := m.snapshot()
	check(not Buffs.apply(m, "missing", 5) and m.snapshot() == original, "Unknown buff rejected without mutation")
	check(not Buffs.apply(m, "weak", 1) and not Buffs.apply(m, "parry", 1, 0) and m.snapshot() == original, "Wrong recipient rejected")
	check(not Buffs.apply(m, "bleed", 1, 99) and m.snapshot() == original, "Missing enemy rejected")
	Buffs.apply(m, "weak", 3, 0)
	Buffs.apply(m, "weak", 3, 0)
	check(m.enemies[0].weak == 6 and Buffs.enemy_attack_damage(m.enemies[0], 9) == 7, "Weak stacks beyond five without increasing damage reduction")
	Buffs.apply(m, "parry", 1, -1, {"cap":1})
	Buffs.apply(m, "parry", 1, -1, {"cap":1})
	check(m.parry == 1, "Parry card-specific pre-add guard")
	Buffs.apply(m, "parry", 2, -1, {"fill":true})
	Buffs.apply(m, "parry", 1, -1, {"fill":true})
	check(m.parry == 2, "Parry fill never reduces stacks")
	Buffs.apply(m, "next_damage", 4)
	Buffs.apply(m, "next_discount", 1)
	m.activate_cyberware(m.cyberware_cards()[0].id)
	m.activate_cyberware(m.cyberware_cards()[1].id)
	check(not Buffs.valid_card_effect({"type":"buff", "id":"technology", "amount":1}), "Technology bonus uses its activation/cooldown contract")
	Buffs.apply(m, "stance_discount")
	Buffs.apply(m, "high_pressure")
	Buffs.apply(m, "high_pressure")
	Buffs.apply(m, "dissection")
	check(m.powers == ["high_pressure", "dissection"], "Abilities unique and ordered")
	var state := m.snapshot()
	var badges := Buffs.player_badges(m, 1)
	check(badges.map(func(b): return b.id) == ["parry", "damage", "technology", "discount", "stance_discount", "high_pressure", "dissection"], "Existing badge order and icons")
	check(badges[0].count == 1 and m.parry == 2, "Animation display parry does not mutate authoritative state")
	check(badges.all(func(b): return b.category == "positive") and m.snapshot() == state, "Display read-only and positive classification")
	check(Buffs.enemy_badges(m.enemies[0])[0].description.contains("固定降低 25%"), "Weak tooltip values")
	Buffs.player_turn_end(m)
	check(m.turn_damage_bonus == 0 and m.turn_discount == 0 and m.next_attack_bonus == 2 and m.stance_discount and m.parry == 2, "Exact expiration boundaries")
	check(m.enemies[0].weak == 6 and m.powers.size() == 2, "Weak waits for enemy turn end; abilities retained")
	Buffs.apply(m, "bleed", 5, 0)
	Buffs.apply(m, "block", 100, 0)
	var hit := m.enemy_damage(0, 2, true)
	Buffs.after_attack_hit(m, 0, "ranged", hit)
	check(hit.attackDamage == 2 and hit.bleedDamage == 0 and hit.blocked == 5 and m.enemies[0].bleed == 4, "Piercing main hit does not bypass block for bleed")
	m.enemies[1].hp = 0
	check(not Buffs.apply(m, "bleed", 9, 1) and m.enemies[1].bleed == 0, "Dead enemy does not gain statuses")
	# JSON-shaped old snapshot remains byte-shape compatible and independent.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(m.snapshot()))
	check(Game.valid_combat(saved), "Fully populated original status snapshot is valid before corruption tests")
	var restored := CombatModel.new()
	restored.buffs = Buffs
	restored.restore(saved)
	check(JSON.parse_string(JSON.stringify(restored.snapshot())) == saved and not saved.has("buffs"), "Existing snapshot exact roundtrip with no extra key")
	for key in ["parry", "turnDamageBonus", "turnDiscount", "block"]:
		var broken := saved.duplicate(true)
		broken.norenState[key] = -1
		check(not Game.valid_combat(broken), "Negative status rejected: " + key)
	var broken := saved.duplicate(true)
	broken.norenState.powers.append("unknown")
	check(not Game.valid_combat(broken), "Unknown saved power rejected")
	broken = saved.duplicate(true)
	broken.buffs = {"weak":3}
	check(not Game.valid_combat(broken), "Extra state cannot shadow legacy fields")
	# Register fixtures only in memory: proves new simple definitions need no model,
	# HUD, snapshot or Game whitelist changes. These are never shipped as game buffs.
	var extra := Buffs.definition("next_damage")
	extra.id = "qa_focus"
	extra.erase("field")
	extra.erase("saveKey")
	extra.maxStacks = 6
	Buffs._catalog[extra.id] = extra
	m = fixtures.fixture([1], "melee")
	m.buffs = Buffs
	m.card_catalog.noren_01.effects.push_front({"type":"buff", "id":"qa_focus", "amount":4})
	# A skill grants the new buff before a later attack consumes it.
	m.card_catalog.noren_02.effects = [{"type":"buff", "id":"qa_focus", "amount":4}]
	m.instances.card_000 = "noren_02"
	check(not m.play_card("card_000").is_empty() and m.buff_state == {"qa_focus":4}, "Generic card effect grants a new definition")
	Buffs.apply(m, "qa_focus", 4)
	check(Buffs.count(m, "qa_focus") == 6, "New buff uses data-defined stacking cap")
	check(Buffs.player_badges(m)[0].buffId == "qa_focus", "New buff automatically shown")
	saved = JSON.parse_string(JSON.stringify(m.snapshot()))
	check(Game.valid_combat(saved), "New buff passes shared save validation")
	restored = CombatModel.new()
	restored.buffs = Buffs
	restored.restore(saved)
	check(restored.buff_state == {"qa_focus":6} and JSON.parse_string(JSON.stringify(restored.snapshot())) == saved, "New buff JSON roundtrip")
	Buffs.clear(m, "qa_focus")
	check(restored.buff_state == {"qa_focus":6}, "Restore does not alias source state")
	check(Buffs.begin_attack(restored, "melee") == 6 and restored.buff_state.is_empty(), "New buff participates in attack hook and consumption")
	Buffs.apply(restored, "qa_focus", 2)
	restored.end_turn()
	check(restored.buff_state.is_empty(), "New buff expires at specified turn boundary")
	broken = saved.duplicate(true)
	broken.buffs.qa_focus = 7
	check(not Game.valid_combat(broken), "New buff saved cap validated")
	m = fixtures.fixture([1])
	m.buffs = Buffs
	m.card_catalog.noren_01.effects = [{"type":"buff", "id":"does_not_exist", "amount":1}]
	original = m.snapshot()
	check(m.play_card("card_000", 0).is_empty() and m.snapshot() == original, "Unknown generic buff fails before payment")
	m.card_catalog.noren_01.effects = [{"type":"buff", "id":"qa_focus", "amount":1, "buffTarget":"enemy"}]
	original = m.snapshot()
	check(m.play_card("card_000", 0).is_empty() and m.snapshot() == original, "Invalid generic recipient fails before payment")
	var marker := Buffs.definition("bleed")
	marker.id = "qa_mark"
	marker.erase("field")
	marker.erase("saveKey")
	marker.handler = "none"
	marker.duration = "player_turn_end"
	Buffs._catalog[marker.id] = marker
	m = fixtures.fixture([1], "melee", 2)
	m.buffs = Buffs
	m.card_catalog.noren_01.target = "all"
	m.card_catalog.noren_01.effects = [{"type":"buff", "id":"qa_mark", "amount":3}]
	check(not m.play_card("card_000").is_empty() and m.enemies.all(func(e): return e.buffs == {"qa_mark":3}), "New negative effect applies to all live targets")
	check(Buffs.enemy_badges(m.enemies[0])[0].category == "negative", "New negative effect appears in HUD data")
	saved = JSON.parse_string(JSON.stringify(m.snapshot()))
	check(Game.valid_combat(saved), "New enemy effect validates")
	restored = CombatModel.new()
	restored.buffs = Buffs
	restored.restore(saved)
	check(Buffs.count(restored, "qa_mark", 0) == 3 and restored.enemies[0].buffs.qa_mark is int, "Enemy effect restores integer stacks")
	check(JSON.parse_string(JSON.stringify(restored.snapshot())) == saved, "Enemy effect exact JSON roundtrip")
	Buffs.player_turn_end(restored)
	check(restored.enemies.all(func(e): return not e.has("buffs")), "Timed enemy effect expires without empty saved containers")
	Buffs._catalog.erase("qa_mark")
	Buffs._catalog.erase("qa_focus")
	fixtures.free()
	print("BUFF LIBRARY: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
