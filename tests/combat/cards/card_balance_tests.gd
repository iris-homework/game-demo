extends Node
const Fixtures = preload("res://tests/combat/cards/noren_cards_tests.gd")
const FaceArt = preload("res://scripts/combat/card_face_art.gd")
var fixtures := Fixtures.new()
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func fixture(ids: Array, form: String = "melee", count: int = 1) -> CombatModel:
	var model: CombatModel = fixtures.fixture(ids, form, count)
	model.buffs.apply(model, "melee_attack_bleed")
	return model

func play(model: CombatModel, index: int = 0, target: int = 0) -> Dictionary:
	return model.play_card("card_%03d" % index, target)

func test_card_values() -> void:
	var starters := {1:[1,"damage",6],2:[1,"block",5],3:[1,"parry",1],4:[1,"block",6]}
	for number in starters:
		var card: Dictionary = Game.card_catalog["noren_%02d" % number]
		var expected: Array = starters[number]
		check(card.cost == expected[0] and card.effects[0].type == expected[1] and card.effects[0].amount == expected[2], "Starter unchanged: %02d" % number)
	check(Game.card_catalog.noren_03.effects[1].value == "melee" and Game.card_catalog.noren_04.effects[1].value == "ranged", "Starter stance effects unchanged")
	var exact := {5:["ammo",2],6:["block",8],11:["block",11],12:["ammo",3],13:["damage",10],14:["damage",6],15:["next_damage",5],16:["damage",9],17:["damage",16],18:["next_damage",4],19:["damage",8],21:["damage",8],25:["damage",14],27:["damage",6],29:["damage",14],31:["block",8],32:["block",14],33:["block",16],37:["damage",6],38:["damage",6]}
	for number in exact:
		var effects: Array = Game.card_catalog["noren_%02d" % number].effects
		var expected: Array = exact[number]
		check(effects.any(func(e): return e.type == expected[0] and e.get("amount") == expected[1]), "Approved exact value: %02d" % number)
	check(Game.card_catalog.noren_21.effects[0].lastAmmoBonus == 4, "Last-ammo bonus four")
	check(Game.card_catalog.noren_25.effects[0].executeBonus == 8, "Execute bonus eight")
	check(Game.card_catalog.noren_40.effects == [{"type":"power","value":"melee_attack_bleed"}], "Forty grants the new ability")
	check(Game.card_catalog.noren_35.effects[0].amount == 2 and Game.card_catalog.noren_35.effects[0].hits == 3, "Triple attack remains two times three")
	for card in Game.card_catalog.values():
		check(FaceArt.matches_definition(card, FaceArt.config().cards[card.id]), "Art binds current definition: " + card.id)

func test_one_cost_skills() -> void:
	for form in ["melee", "ranged"]:
		for number in [7,24,39]:
			for bleed in ([2,3] if number == 39 else [0]):
				var model: CombatModel = fixtures.fixture([number], form)
				model.enemies[0].bleed = bleed
				var before := model.snapshot()
				var preview := model.card_preview("card_000",0)
				check(model.snapshot() == before and not preview.is_empty(), "Skill preview stays read only: %d %s" % [number,form])
				var expected := (2 if number == 24 else 3) + (1 if number == 39 and bleed >= 3 else 0)
				var result := play(model)
				check(result.drawn.size() == expected and model.hand.size() == expected and model.energy == 2, "One-cost skill exact total draw: %d %s bleed %d" % [number,form,bleed])
				check(Game.valid_combat(model.snapshot()), "Extra draw preserves card zones: %d" % number)
	# Restore old frozen definitions without substituting today's catalogue or art.
	for number in [6,7,11,24,31,39]:
		var model: CombatModel = fixtures.fixture([number])
		var id := "noren_%02d" % number
		var definition: Dictionary = model.card_catalog[id]
		var kind := "block" if number in [6,11,31] else "draw"
		for effect in definition.effects:
			if effect.type == kind:
				effect.amount -= 2 if kind == "block" else 1
				break
		var saved: Dictionary = JSON.parse_string(JSON.stringify(model.snapshot()))
		check(Game.valid_combat(saved), "Old frozen skill is valid: " + id)
		var restored := CombatModel.new()
		restored.restore(saved)
		check(restored.card_catalog[id] == saved.cardCatalog[id] and FaceArt.resolve(restored.card_catalog[id]).is_empty(), "Restore preserves old rules and rejects mismatched current art: " + id)
		var result := play(restored)
		var expected := 9 if number == 11 else (6 if kind == "block" else (1 if number == 24 else 2))
		check((restored.block if kind == "block" else result.drawn.size()) == expected, "Old frozen skill retains original value: " + id)

func test_each_attack_segment() -> void:
	var model := fixture([35,1])
	var result := play(model)
	check(result.hits.size() == 3 and result.hits.map(func(h): return h.bleedAfter) == [1,2,3], "Every melee segment applies a layer")
	check(model.enemies[0].bleed == 3 and result.damage == 6, "Normal melee adds layers without ticking them")
	result = play(model,1)
	check(model.enemies[0].bleed == 4, "A second attack in the same turn also applies bleed")
	model.end_turn()
	check(model.buffs.count(model,"melee_attack_bleed") == 1 and model.enemies[0].bleed == 4, "Ability and bleed persist across turns")
	model = fixture([35])
	model.enemies[0].block = 100
	result = play(model)
	check(result.damage == 0 and model.enemies[0].bleed == 3, "Fully blocked segments each apply bleed")
	model = fixture([35])
	model.enemies[0].hp = 1
	result = play(model)
	check(result.hits.size() == 1 and model.enemies[0].bleed == 0, "Lethal segment does not add bleed or execute later segments")
	model = fixture([35])
	model.enemies[0].bleed = 999
	play(model)
	check(model.enemies[0].bleed == 1002 and Game.valid_combat(model.snapshot()), "Per-hit bleed preserves existing uncapped stacking and snapshot validity")

func test_targets_and_card_bleed() -> void:
	var model := fixture([38],"melee",3)
	model.enemies[1].hp = 0
	var result := play(model)
	check(result.hits.map(func(h): return h.target) == [0,2], "AoE skips defeated targets")
	check(result.hits.map(func(h): return h.bleedAfter) == [1,1], "AoE applies the ability to every hit target")
	check(model.enemies.map(func(e): return e.bleed) == [4,0,4], "AoE card's own three layers apply after attack layers")
	model = fixture([28])
	play(model)
	check(model.enemies[0].bleed == 4, "Two melee hits plus two authored layers")
	for number in [30,34]:
		model = fixture([number])
		play(model)
		check(model.enemies[0].bleed == 3 and not model.dissection_used, "Skill receives no new ability bonus: %d" % number)
	model = fixture([30])
	model.enemies[0].bleed = 2
	play(model)
	check(model.enemies[0].bleed == 8, "Wounded skill adds its authored six only")
	model = fixture([2])
	model.card_catalog.noren_02.effects = [{"type":"damage","amount":1}]
	model.card_catalog.noren_02.target = "enemy"
	play(model)
	check(model.enemies[0].bleed == 0, "A skill with damage is not an attack")

func test_stance_and_other_damage() -> void:
	var model := fixture([9,1],"ranged")
	play(model)
	check(model.stance == "melee" and model.enemies[0].bleed == 0, "Ranged Cut In does not gain melee bleed before switching")
	play(model,1)
	check(model.enemies[0].bleed == 1, "Next attack in melee gains bleed")
	model = fixture([35],"ranged")
	model.enemies[0].bleed = 5
	var result := play(model)
	check(model.enemies[0].bleed == 2 and result.damage == 21, "Ranged attack still only consumes existing bleed")
	model = fixture([1])
	model.parry = 1
	model.end_turn()
	check(model.enemies[0].bleed == 0, "Parry never applies new ability bleed")
	model.enemy_damage(0,3)
	check(model.enemies[0].bleed == 0, "Ordinary non-attack damage never applies ability bleed")

func test_hunt_order_and_preview() -> void:
	for persistent in [false,true]:
		var model := fixture([37])
		model.enemies[0].bleed = 3
		if persistent: model.buffs.apply(model,"persistent_bleed")
		var before := model.snapshot()
		var preview := model.card_preview("card_000",0)
		check(model.snapshot() == before, "New ability preview leaves source snapshot unchanged")
		var ticks: Array = preview.effects.filter(func(row): return row.type == "bleed_damage")[0].samples[0]
		check(ticks == ([4,4] if persistent else [4,3]), "Preview applies attack bleed before Hunt ticks")
		check(preview.text.contains("剖解经验追加1层裂伤"), "Preview explains implicit ability bleed")
		var result := play(model)
		check(result.damage == (14 if persistent else 13), "Execution matches body then new bleed then two ticks")
		check(model.enemies[0].bleed == (4 if persistent else 2), "Persistent bleed retains added layer through Hunt")
	var model := fixture([37])
	var result := play(model)
	check(result.damage == 7 and model.enemies[0].bleed == 0, "Hunt can tick the new first layer on an unwounded target")
	model = fixture([35])
	var before := model.snapshot()
	var preview := model.card_preview("card_000",0)
	check(preview.text.contains("剖解经验追加3层裂伤") and model.snapshot() == before, "Triple attack preview includes three layers without mutation")
	model = fixture([38],"melee",2)
	preview = model.card_preview("card_000",-1)
	check(preview.effects.filter(func(row): return row.type == "buff" and row.id == "bleed")[0].samples == [[3],[3]], "AoE preview keeps authored three layers separate from implicit one")

func test_save_duplicate_and_legacy() -> void:
	var model: CombatModel = fixtures.fixture([40,40,35])
	play(model)
	play(model,1)
	check(model.powers == ["melee_attack_bleed"] and model.energy == 1 and model.exhaust_pile.size() == 2, "Duplicate new ability pays cost without stacking")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(model.snapshot()))
	check(Game.valid_combat(saved), "New ability snapshot passes shared validation")
	var restored := CombatModel.new()
	restored.restore(saved)
	check(JSON.parse_string(JSON.stringify(restored.snapshot())) == saved, "New ability survives exact JSON roundtrip")
	play(restored,2)
	check(restored.enemies[0].bleed == 3, "Restored ability still applies exactly once per segment")
	var badges := restored.buffs.player_badges(restored)
	var badge: Dictionary = badges.filter(func(b): return b.buffId == "melee_attack_bleed")[0]
	check(badge.id == "dissection" and not badge.description.contains("本回合："), "New badge reuses icon and has no once-per-turn marker")
	model = fixtures.fixture([40,30,35])
	model.card_catalog.noren_40.effects = [{"type":"power","value":"dissection"}]
	model.card_catalog.noren_40.description = "每回合首次以近战形态用单体卡牌施加裂伤时，额外施加1层。"
	model.card_catalog.noren_40.cardText = model.card_catalog.noren_40.description
	play(model)
	saved = JSON.parse_string(JSON.stringify(model.snapshot()))
	check(Game.valid_combat(saved), "Frozen legacy ability remains loadable")
	restored.restore(saved)
	play(restored,1)
	check(restored.enemies[0].bleed == 4 and restored.dissection_used, "Legacy skill keeps its first-application bonus")
	play(restored,2)
	check(restored.enemies[0].bleed == 4, "Legacy ability does not gain the new attack hook")

func _ready() -> void:
	Game.save_enabled = false
	test_card_values()
	test_one_cost_skills()
	test_each_attack_segment()
	test_targets_and_card_bleed()
	test_stance_and_other_damage()
	test_hunt_order_and_preview()
	test_save_duplicate_and_legacy()
	fixtures.free()
	print("CARD BALANCE: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
