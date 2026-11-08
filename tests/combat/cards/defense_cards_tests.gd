extends Node
## Run only in a copied project with an isolated QA user directory.
const Fixtures = preload("res://tests/combat/cards/noren_cards_tests.gd")
const FaceArt = preload("res://scripts/combat/card_face_art.gd")
const NEW_IDS := ["noren_41", "noren_42", "noren_43"]
var fixtures := Fixtures.new()
var checks := 0
var failures: Array[String] = []
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("DEFENSE CARDS: " + message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func conserved(model: CombatModel, context: String) -> void:
	var zones: Array = []
	zones.append_array(model.hand)
	zones.append_array(model.draw_pile)
	zones.append_array(model.discard_pile)
	zones.append_array(model.exhaust_pile)
	var unique := {}
	for uid in zones: unique[uid] = true
	check(zones.size() == model.instances.size() and unique.size() == zones.size() and unique.keys().all(func(uid): return model.instances.has(uid)), context + ": every instance occurs in exactly one zone")
	check(Game.valid_combat(model.snapshot()), context + ": shared snapshot validation passes")

func test_both_forms() -> void:
	var block_values := {41:14, 42:8, 43:7}
	for form in ["melee", "ranged"]:
		for number in [41,42,43]:
			var model: CombatModel = fixtures.fixture([number], form, 2)
			model.ammo = 0
			model.turn_discount = 1
			model.stance_discount = true
			var before := model.snapshot()
			var preview := model.card_preview("card_000", 1 if number == 43 else -1)
			var label := "%d %s" % [number,form]
			check(same(before, model.snapshot()) and not preview.is_empty(), label + ": preview leaves live state untouched")
			check(preview.cardText == model.card("card_000").cardText and preview.effects.any(func(row): return row.type == "buff" and row.id == "block" and row.samples == [[block_values[number]]]), label + ": dynamic preview agrees with authored block")
			check(model.card_cost("card_000") == 1 and model.play_error("card_000").is_empty(), label + ": skill costs one even with attack discounts and zero ammo")
			var result := model.play_card("card_000", 1 if number == 43 else -1)
			check(not result.is_empty() and model.energy == 2 and model.block == block_values[number], label + ": pays once and grants exact player block")
			check(model.ammo == 0 and model.stance == form and model.stance_discount and model.turn_discount == 1, label + ": preserves ammo, stance and pending attack discounts")
			check(result.damage == 0 and result.hits.is_empty() and not result.exhausted and model.discard_pile.has("card_000") and not model.exhaust_pile.has("card_000"), label + ": nonattack resolves to ordinary discard")
			check(result.drawn.size() == (1 if number == 42 else 0), label + ": exact draw count")
			check(model.enemies[0].weak == 0 and model.enemies[1].weak == (2 if number == 43 else 0) and model.enemies.all(func(enemy): return enemy.hp == 1000), label + ": only chosen enemy receives weakness; no enemy HP damage")
			conserved(model, label)
			var saved: Dictionary = JSON.parse_string(JSON.stringify(model.snapshot()))
			var restored := CombatModel.new()
			restored.restore(saved)
			check(same(saved, restored.snapshot()), label + ": new definitions and resolved zones survive JSON restoration")
			model = fixtures.fixture([number], form)
			model.energy = 0
			before = model.snapshot()
			check(model.play_card("card_000",0).is_empty() and same(before,model.snapshot()), label + ": insufficient energy rejects without mutation")

func test_target_rejections() -> void:
	for target in [-1, 2, 1]:
		var model: CombatModel = fixtures.fixture([43], "ranged", 2)
		model.enemies[1].hp = 0
		var before := model.snapshot()
		check(model.card_target("card_000") == "enemy" and model.play_card("card_000", target).is_empty() and same(before,model.snapshot()), "Interference rejects missing, out-of-range or dead target atomically: %d" % target)
		conserved(model, "Rejected interference %d" % target)

func test_draw_recycle() -> void:
	var model: CombatModel = fixtures.fixture([42])
	model.discard_pile = model.draw_pile.duplicate()
	model.draw_pile.clear()
	var recycled: Array = []
	model.discard_recycled.connect(func(count: int, _top: String): recycled.append(count))
	seed(20261108)
	var result := model.play_card("card_000", -1)
	check(recycled == [12] and result.drawn.size() == 1 and model.hand == result.drawn, "Defensive draw recycles the existing discard pile exactly once")
	check(not result.drawn.has("card_000") and model.discard_pile == ["card_000"] and model.draw_pile.size() == 11, "Resolving card enters discard after the recycled draw and cannot draw itself")
	conserved(model, "Recycled defensive draw")
	model = fixtures.fixture([42])
	model.exhaust_pile = model.draw_pile.duplicate()
	model.draw_pile.clear()
	var before := model.snapshot()
	var empty_preview := model.card_preview("card_000",-1)
	var card := CombatCard.new()
	card.setup("card_000",model.card("card_000"))
	add_child(card)
	card.show_preview(empty_preview)
	check(empty_preview.cardText.contains("抽0张牌") and card.face_texture != null and card.rules_changed and is_instance_valid(card.effect_label) and card.effect_label.visible and card.effect_label.text == empty_preview.cardText and same(before,model.snapshot()), "No drawable cards uses the actual dynamic rules overlay on the new baked face without changing model state")
	card.free()
	result = model.play_card("card_000", -1)
	check(result.drawn.is_empty() and model.hand.is_empty() and model.discard_pile == ["card_000"] and model.block == 8 and model.energy == 2, "Empty drawable zones retain block and cost without drawing the resolving card")
	conserved(model, "No drawable cards")

func test_weakness_and_block_lifetime() -> void:
	var model: CombatModel = fixtures.fixture([43])
	model.enemies[0].intentSequence = [{"type":"attack","amount":10,"hits":2}]
	model.enemies[0].intent = model.enemies[0].intentSequence[0].duplicate(true)
	model.play_card("card_000",0)
	var round_result := model.end_turn()
	# roundi(10 * .75) = 8 per hit; seven block absorbs the first hit.
	check(round_result.attacks[0].hits.map(func(hit): return hit.damage) == [1,8] and model.player_hp == 91 and model.enemies[0].weak == 1, "Two weakness layers reduce both first-turn hits; seven player block absorbs once")
	check(model.block == 0, "Remaining player block clears when the next player turn starts")
	round_result = model.end_turn()
	check(round_result.attacks[0].damage == 16 and model.enemies[0].weak == 0, "Second enemy turn retains 25 percent weakness then expires")
	round_result = model.end_turn()
	check(round_result.attacks[0].damage == 20, "Third enemy turn returns to ordinary damage")
	conserved(model, "Weakness expiry")
	model = fixtures.fixture([41])
	model.play_card("card_000",-1)
	round_result = model.end_turn()
	check(round_result.attacks[0].damage == 0 and model.player_hp == 100 and model.block == 0, "Fourteen block protects the enemy phase and unused four does not carry into the next player turn")

func test_catalog_rewards_and_faces() -> void:
	var library: Array = Game.library_cards()
	check(Game.card_catalog.size() == 43 and library.size() == 43, "Formal catalog and all-cards library enumerate forty-three definitions")
	var expected_names := ["固守掩体","见招拆招","干扰屏障"]
	for index in NEW_IDS.size():
		var id: String = NEW_IDS[index]
		var definition: Dictionary = Game.card_catalog[id]
		check(definition.name == expected_names[index] and definition.cost == 1 and definition.rarity == "B" and definition.type == "skill" and not definition.get("exhaust",false), id + ": exact new identity and shared card classification")
		check(library.filter(func(card): return card.id == id).size() == 1 and Game.reward_rules.cards.get(id) == definition, id + ": listed once and merged into formal reward definitions")
		var binding: Dictionary = FaceArt.config().get("cards",{}).get(id,{})
		check(FaceArt.matches_definition(definition,binding), id + ": registered face matches the complete current definition")
		var art := FaceArt.resolve(definition)
		check(not art.is_empty() and art.get("template_id") == FaceArt.TEMPLATE_ID and art.texture.get_size() == FaceArt.CANVAS, id + ": current v3 PNG and font load at the required canvas size")
		var model: CombatModel = fixtures.fixture([41+index])
		var before := model.snapshot()
		var card := CombatCard.new()
		card.setup("card_000",definition)
		add_child(card)
		var preview := model.card_preview("card_000",0)
		card.show_cost(model.card_cost("card_000"))
		card.show_preview(preview)
		check(card.face_texture != null and is_instance_valid(card.cost_label) and is_instance_valid(card.effect_label) and card.cost_label.text == "1" and card.effect_label.text == preview.cardText and not card.cost_changed and not card.rules_changed and same(before,model.snapshot()), id + ": actual card view binds the PNG and model preview without unnecessary overlay or model mutation")
		card.free()
		var changed := definition.duplicate(true)
		changed.effects[0].amount += 1
		check(FaceArt.resolve(changed).is_empty(), id + ": frozen mismatched effects reject today's baked face")
	var catalog_before: Dictionary = Game.card_catalog.duplicate(true)
	var observed := {}
	seed(2026110843)
	for attempt in 512:
		var options: Array[String] = Game.card_reward_sampler.sample(Game.card_catalog,{"B":100,"A":0,"S":0})
		if options.size() != 3:
			check(false,"B-only reward sampler returns complete three-card offers")
			break
		for id in options: observed[id] = true
	check(NEW_IDS.all(func(id): return observed.has(id)) and same(catalog_before,Game.card_catalog), "All three cards are reachable through the full B reward pool without catalog mutation")

func _enter_tree() -> void:
	Game.save_enabled = false

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("DEFENSE CARDS require absolute QA_OUT_DIR and an isolated user directory containing QA")
		fixtures.free()
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-defense-checkpoint.json")
	Game.meta_path = output.path_join("unused-defense-meta.json")
	var available := NEW_IDS.all(func(id): return Game.card_catalog.has(id))
	check(available,"All three new definitions are present before exercising them")
	if available:
		test_both_forms()
		test_target_rejections()
		test_draw_recycle()
		test_weakness_and_block_lifetime()
		test_catalog_rewards_and_faces()
	fixtures.free()
	var report := {"checks":checks,"failures":failures,"scope":"model, in-memory JSON restoration, reward eligibility, PNG loading and card-view bindings","physicalInput":false,"pixelAcceptance":false,"balanceAcceptance":false}
	FileAccess.open(output.path_join("defense-cards-results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DEFENSE CARDS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
