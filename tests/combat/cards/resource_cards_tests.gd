extends Node
## Rules and resource presentation only; run in a copied project and QA user dir.
const Fixtures = preload("res://tests/combat/cards/noren_cards_tests.gd")
const FaceArt = preload("res://scripts/combat/card_face_art.gd")
const EnergyHUD = preload("res://scripts/combat/energy_hud.gd")
const Market = preload("res://scripts/black_market_model.gd")
const IDS := ["noren_44","noren_45"]
var fixtures := Fixtures.new()
var checks := 0
var failures: Array[String] = []
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("RESOURCE CARDS: " + message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func conserved(model: CombatModel, context: String) -> void:
	var zones: Array = model.hand + model.draw_pile + model.discard_pile + model.exhaust_pile
	var unique := {}
	for uid in zones: unique[uid] = true
	check(zones.size() == model.instances.size() and unique.size() == zones.size() and unique.keys().all(func(uid): return model.instances.has(uid)) and Game.valid_combat(model.snapshot()), context + ": each instance belongs to one zone and frozen snapshot validates")

func test_zero_cost_resources() -> void:
	for form in ["melee","ranged"]:
		for starting_energy in [0,3]:
			var model: CombatModel = fixtures.fixture([44],form)
			model.energy = starting_energy
			model.ammo = 0
			model.turn_discount = 1
			model.stance_discount = true
			var before := model.snapshot()
			var preview := model.card_preview("card_000",-1)
			var label := "Emergency energy %s from %d" % [form,starting_energy]
			check(same(before,model.snapshot()) and preview.cardText == model.card("card_000").cardText and preview.effects.any(func(row): return row.type == "energy" and row.samples == [[2]]), label + ": read-only preview promises exactly two energy")
			check(model.card_cost("card_000") == 0 and model.play_error("card_000").is_empty(), label + ": playable with no energy or ammo")
			var result := model.play_card("card_000",-1)
			check(not result.is_empty() and model.energy == starting_energy + 2 and int(model.profile.energyPerTurn) == 3, label + ": increases current energy without changing three-per-turn recovery or capping at three")
			check(model.ammo == 0 and model.stance == form and model.stance_discount and model.turn_discount == 1 and result.hits.is_empty(), label + ": skill preserves unrelated combat resources")
			check(model.discard_pile == ["card_000"] and model.exhaust_pile.is_empty() and not result.exhausted, label + ": reusable supply enters ordinary discard")
			conserved(model,label)
			var saved: Dictionary = JSON.parse_string(JSON.stringify(model.snapshot()))
			var restored := CombatModel.new()
			restored.restore(saved)
			check(same(saved,restored.snapshot()) and restored.energy == starting_energy + 2, label + ": exact JSON roundtrip retains legal bonus energy")
			restored.end_turn()
			check(restored.energy == 3 and int(restored.profile.energyPerTurn) == 3, label + ": next player turn resets current energy to authored recovery")
		var model: CombatModel = fixtures.fixture([45],form)
		model.energy = 0
		model.ammo = 0
		var result := model.play_card("card_000",-1)
		check(not result.is_empty() and result.drawn.size() == 2 and model.hand == result.drawn and model.energy == 0 and model.ammo == 0, "Instant calculation %s draws exactly two at zero resources" % form)
		check(result.exhausted and model.exhaust_pile == ["card_000"] and model.discard_pile.is_empty(), "Instant calculation %s exhausts itself after its draw" % form)
		conserved(model,"Instant calculation " + form)

func test_recycling_and_order() -> void:
	var model: CombatModel = fixtures.fixture([44,45])
	model.exhaust_pile = model.draw_pile.duplicate()
	model.draw_pile.clear()
	check(not model.play_card("card_000",-1).is_empty() and model.energy == 5, "Supply first grants two energy immediately")
	var result := model.play_card("card_001",-1)
	check(result.drawn == ["card_000"] and model.hand == ["card_000"] and model.exhaust_pile.has("card_001"), "Calculation recycles discarded supply but cannot draw itself while resolving")
	check(not model.play_card("card_000",-1).is_empty() and model.energy == 7, "Same supply instance can grant energy again after being redrawn")
	check(model.draw_cards(2) == ["card_000"] and not model.hand.has("card_001"), "Exhausted calculation stays outside later recycle draws")
	check(not model.play_card("card_000",-1).is_empty() and model.energy == 9, "Repeated supply uses remain cumulative without a hard turn cap")
	conserved(model,"Repeated reusable supply")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(model.snapshot()))
	var restored := CombatModel.new()
	restored.restore(saved)
	check(same(saved,restored.snapshot()) and restored.energy == 9, "Repeated gains retain exact energy through snapshot restoration")
	model = fixtures.fixture([44])
	model.energy = 0
	model.discard_pile = model.draw_pile.duplicate()
	model.draw_pile.clear()
	model.card_catalog.noren_44.effects = [{"type":"energy","amount":2},{"type":"draw","amount":1},{"type":"energy","amount":1}]
	var energy_at_shuffle: Array = []
	var model_ref: WeakRef = weakref(model)
	model.discard_recycled.connect(func(_count: int, _top: String): energy_at_shuffle.append(model_ref.get_ref().energy))
	result = model.play_card("card_000",-1)
	check(energy_at_shuffle == [2] and model.energy == 3 and result.drawn.size() == 1, "Energy and draw effects execute in authored array order rather than being grouped")
	conserved(model,"Ordered immediate energy effects")

func test_invalid_energy_effects() -> void:
	var invalid: Array = [
		{"type":"energy"}, {"type":"energy","amount":0},
		{"type":"energy","amount":-1}, {"type":"energy","amount":0.5},
		{"type":"energy","amount":INF}, {"type":"energy","amount":-INF},
		{"type":"energy","amount":"2"}, {"type":"energy","amount":true}]
	for effect in invalid:
		var model: CombatModel = fixtures.fixture([44])
		model.card_catalog.noren_44.cost = 1
		# A preceding legal effect must also remain unapplied if a later effect is bad.
		model.card_catalog.noren_44.effects = [{"type":"block","amount":3},effect.duplicate(true)]
		var before := model.snapshot()
		var definition: Dictionary = model.card("card_000")
		check(not Game.valid_frozen_card(definition) and not Game.valid_combat(before), "Frozen definition and snapshot reject malformed energy amount: " + str(effect))
		check(model.play_card("card_000",-1).is_empty() and before == model.snapshot() and model.energy == 3 and model.block == 0 and model.hand == ["card_000"], "Invalid energy rejects the whole card before spending, block or pile changes: " + str(effect))

func test_draw_exhaustion_and_legacy() -> void:
	var model: CombatModel = fixtures.fixture([45])
	model.discard_pile = model.draw_pile.duplicate()
	model.draw_pile.clear()
	var recycled: Array = []
	model.discard_recycled.connect(func(count: int, _top: String): recycled.append(count))
	var control := CombatModel.new()
	control.restore(model.snapshot())
	seed(2026110845)
	model.card_preview("card_000",-1)
	var result := model.play_card("card_000",-1)
	seed(2026110845)
	var control_result := control.play_card("card_000",-1)
	check(result.drawn == control_result.drawn and same(model.snapshot(),control.snapshot()), "Reading calculation preview before a real shuffle preserves the gameplay RNG sequence")
	check(recycled == [12] and result.drawn.size() == 2 and model.draw_pile.size() == 10 and model.exhaust_pile == ["card_000"], "Calculation performs one real shuffle and draws two before exhausting")
	conserved(model,"Calculation shuffle")
	model = fixtures.fixture([45])
	model.exhaust_pile = model.draw_pile.duplicate()
	model.draw_pile.clear()
	var before := model.snapshot()
	var preview := model.card_preview("card_000",-1)
	check(preview.cardText.contains("抽0张牌") and same(before,model.snapshot()), "Empty-pile preview shows actual zero draw without consuming the card")
	result = model.play_card("card_000",-1)
	check(result.drawn.is_empty() and result.exhausted and model.exhaust_pile.has("card_000") and model.hand.is_empty(), "Calculation exhausts even when no other card can be drawn")
	conserved(model,"Calculation with empty drawable zones")
	# initialize() merges prototype profile.cards (including test_attack), so
	# erasing only 44/45 would leave 44 entries, not a 43-definition legacy catalog.
	model = fixtures.fixture([41])
	var legacy_catalog: Dictionary = {}
	for number in range(1,44):
		var id := "noren_%02d" % number
		legacy_catalog[id] = Game.card_catalog[id].duplicate(true)
	model.card_catalog = legacy_catalog.duplicate(true)
	model.profile.cards = {}
	var saved: Dictionary = JSON.parse_string(JSON.stringify(model.snapshot()))
	check(saved.cardCatalog.size() == 43 and Game.valid_combat(saved), "Old frozen 43-card battle remains loadable")
	var restored := CombatModel.new()
	restored.restore(saved)
	check(same(saved,restored.snapshot()) and same(legacy_catalog,restored.card_catalog) and restored.card_catalog.size() == 43 and not restored.card_catalog.has("noren_44") and not restored.card_catalog.has("noren_45"), "Restoration preserves the complete old snapshot and all 43 definitions instead of injecting new cards")
	check(not restored.play_card("card_000",-1).is_empty() and restored.block == 14, "Old frozen defensive card keeps its exact behavior")
	saved.norenState.energy = 5
	check(not Game.valid_combat(saved), "Old battle without an energy-card instance retains the previous excess-energy rejection")
	model = fixtures.fixture([41])
	model.energy = 5
	check(not Game.valid_combat(model.snapshot()), "Having energy in today's catalog alone cannot relax an old deck's energy limit")

func test_catalog_faces_and_resource_hud() -> void:
	var distribution := {"C":0,"B":0,"A":0,"S":0}
	for definition in Game.card_catalog.values(): distribution[definition.rarity] += 1
	check(Game.library_cards().size() == 45 and Game.card_catalog.size() == 45 and distribution == {"C":4,"B":27,"A":10,"S":4}, "Formal library contains 45 cards with the intended rarity counts")
	for number in [44,45]:
		var id := "noren_%02d" % number
		var definition: Dictionary = Game.card_catalog[id]
		check(definition.name == ("应急供能" if number == 44 else "瞬时演算") and definition.cost == 0 and definition.type == "skill" and definition.target == "self" and definition.rarity == ("A" if number == 44 else "B") and definition.get("exhaust",false) == (number == 45), id + ": exact current identity, zero cost and exhaustion flag")
		check(Game.valid_frozen_card(definition) and Game.reward_rules.cards.get(id) == definition and FaceArt.matches_definition(definition,FaceArt.config().get("cards",{}).get(id,{})), id + ": valid formal definition, reward entry and complete baked-face binding")
		var art := FaceArt.resolve(definition)
		check(not art.is_empty() and art.get("template_id") == FaceArt.TEMPLATE_ID and art.texture.get_size() == FaceArt.CANVAS, id + ": current v3 card PNG and font load successfully")
		var model: CombatModel = fixtures.fixture([number])
		var before := model.snapshot()
		var card := CombatCard.new()
		card.setup("card_000",definition)
		add_child(card)
		var preview := model.card_preview("card_000",-1)
		card.show_cost(model.card_cost("card_000"))
		card.show_preview(preview)
		check(card.face_texture != null and is_instance_valid(card.cost_label) and is_instance_valid(card.effect_label) and card.cost_label.text == "0" and card.effect_label.text == preview.cardText and not card.cost_changed and not card.rules_changed and same(before,model.snapshot()), id + ": actual card node displays zero cost and unchanged preview on baked face")
		if number == 45:
			model.exhaust_pile = model.draw_pile.duplicate()
			model.draw_pile.clear()
			preview = model.card_preview("card_000",-1)
			card.show_preview(preview)
			check(card.rules_changed and is_instance_valid(card.effect_label) and card.effect_label.visible and card.effect_label.text.contains("抽0张牌") and card.effect_label.text.contains("消耗"), "Calculation dynamic rules overlay preserves exhaustion when actual draw falls to zero")
		card.free()
		var changed := definition.duplicate(true)
		changed.effects[0].amount += 1
		check(FaceArt.resolve(changed).is_empty(), id + ": altered frozen value rejects mismatched modern card art")
	var model: CombatModel = fixtures.fixture([44])
	model.play_card("card_000",-1)
	var hud = EnergyHUD.new()
	hud.value_label = Label.new()
	hud.title_label = Label.new()
	hud.add_child(hud.value_label)
	hud.add_child(hud.title_label)
	add_child(hud)
	var before := model.snapshot()
	hud.set_energy(model.energy,int(model.profile.energyPerTurn))
	check(hud.value_label.text == "5 / 3" and hud.title_label.text == "能量·超频" and hud.is_overclocked() and hud.filled_slot_count() == 3 and same(before,model.snapshot()), "Existing resource HUD displays legal five-of-three energy without clamping or mutating model")
	model.end_turn()
	hud.set_energy(model.energy,int(model.profile.energyPerTurn))
	check(hud.value_label.text == "3 / 3" and not hud.is_overclocked() and hud.title_label.text == "能量", "HUD returns to ordinary recovery after turn reset")
	hud.free()

func test_reward_and_market_reachability() -> void:
	var before: Dictionary = Game.card_catalog.duplicate(true)
	var seen_rewards := {}
	seed(2026110845)
	for attempt in 512:
		for id in Game.card_reward_sampler.sample(Game.card_catalog,Game.card_reward_rates.normal): seen_rewards[id] = true
	var market := Market.new()
	market.rng.seed = 2026110845
	var seen_market := {}
	var valid_stock := true
	for attempt in 128:
		var stock: Dictionary = market.generate(1,1,Game.card_catalog,Game.black_market_rules)
		valid_stock = valid_stock and market.valid(stock,Game.card_catalog,Game.black_market_rules)
		for slot in stock.get("slots",[]): seen_market[slot.cardId] = true
	check(IDS.all(func(id): return seen_rewards.has(id)), "Both new rarities are reachable through configured normal rewards")
	check(valid_stock and IDS.all(func(id): return seen_market.has(id)), "Both new cards are reachable through valid nine-slot black-market inventories")
	check(same(before,Game.card_catalog), "Reward and market sampling leave formal definitions untouched")

func _enter_tree() -> void:
	Game.save_enabled = false

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("RESOURCE CARDS require absolute QA_OUT_DIR and isolated user directory containing QA")
		fixtures.free()
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-resource-checkpoint.json")
	Game.meta_path = output.path_join("unused-resource-meta.json")
	var available := IDS.all(func(id): return Game.card_catalog.has(id))
	check(available,"Both new resource definitions are present")
	if available:
		test_zero_cost_resources()
		test_recycling_and_order()
		test_invalid_energy_effects()
		test_draw_exhaustion_and_legacy()
		test_catalog_faces_and_resource_hud()
		test_reward_and_market_reachability()
	fixtures.free()
	var report := {"checks":checks,"failures":failures,"scope":"model effects, atomic rejection, in-memory frozen snapshots, resource/card nodes, rewards and black market","physicalInput":false,"pixelAcceptance":false,"balanceAcceptance":false}
	FileAccess.open(output.path_join("resource-cards-results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RESOURCE CARDS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
