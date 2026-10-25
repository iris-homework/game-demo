extends Node
## Special encounter definitions, real fallback nodes and frozen-card compatibility.
const FaceArt = preload("res://scripts/combat/card_face_art.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DANCER SPECIAL CARD: " + message)

func phase_two() -> CombatModel:
	Game.state = Game.initial_state()
	Game.transition_locked = false
	Game.battle_busy = false
	Game.start_training("B16")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	model.enemy_damage(0,999)
	model.resolve_outcome()
	check(model.advance_encounter_phase(),"fixture reaches the real encounter's second phase")
	return model

func card_in_hand(model: CombatModel, id: String) -> String:
	var uid := "encounter_" + id
	for zone in [model.draw_pile,model.hand,model.discard_pile]: zone.erase(uid)
	model.hand.append(uid)
	return uid

func card_node(definition: Dictionary, fallback: bool) -> CombatCard:
	var card := CombatCard.new()
	card.allow_zoom_preview = false
	card.setup("qa_special",definition,true)
	if fallback: card.face_texture = null
	add_child(card)
	return card

func test_presentation(definition: Dictionary, color: String) -> void:
	var card := card_node(definition,true)
	var labels: Array = card.find_children("*","Label",true,false).map(func(node): return node.text)
	check(is_instance_valid(card.cost_label) and card.cost_label.text == "1" and card.cost_label.visible,color+" fallback shows its one-energy cost")
	check("特殊" in labels and definition.name in labels,color+" fallback displays the exact title and special type")
	check(not labels.any(func(text): return "LEGACY" in text or "无费用" in text),color+" fallback is a costed special card")
	check(not is_instance_valid(card.rank_label),color+" special card has no invented rarity rank")
	card.show_cost(0)
	check(card.cost_label.text == "0",color+" fallback accepts live cost changes")
	card.queue_free()
	if not "--require-art" in OS.get_cmdline_user_args(): return
	var art := FaceArt.resolve(definition)
	check(not art.is_empty(),color+" current definition resolves an authored special face")
	if art.is_empty(): return
	check(art.texture.get_size() == Vector2(1086,1448) and art.template_id == "neon-comic-special-v1",color+" face uses the declared special template and canvas")
	card = card_node(definition,false)
	check(card.face_texture != null and card.fixed_layer != null,color+" real card node uses the authored face")
	check(not card.cost_label.visible and not card.effect_label.visible,color+" unmodified face does not duplicate baked cost or rules")
	var expected := Color("d6dae3") if color == "black" else Color("e8e5dc")
	check(card.face_base_cost_color() == expected and card.face_cost_background() == Color("101016"),color+" dynamic cost uses the registered variant ink and backing")
	card.show_cost(0)
	check(card.cost_changed and card.cost_label.visible and card.cost_label.text == "0",color+" fixed face displays a discounted cost without replacing the artwork")
	card.show_cost(1)
	check(not card.cost_changed and not card.cost_label.visible,color+" returning to authored cost restores the exact face")
	var old := definition.duplicate(true)
	old.type = "skill"
	old.name = "黑卡" if color == "black" else "白卡"
	check(FaceArt.resolve(old).is_empty(),color+" legacy skill definition retains its own fallback instead of receiving new text art")
	card.queue_free()

func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(func(): get_tree().quit(2))
	Game.save_enabled = false
	Game.save_path = "user://dancer_special_card_unused.json"
	Game.meta_path = "user://dancer_special_card_meta_unused.json"
	var definitions: Dictionary = Game.read_data("cards/dancer_encounter_cards.json")
	check(definitions.size() == 2 and Game.card_catalog.size() == 40,"two encounter-only definitions leave the forty-card permanent catalog intact")
	var model := phase_two()
	var original := model.snapshot()
	for color in ["black","white"]:
		var id: String = "dancer_" + color + "_card"
		var definition: Dictionary = definitions[id]
		var expected_name := "灵魂链接 黑" if color == "black" else "灵魂链接 白"
		check(definition.name == expected_name and definition.type == "special",color+" authored title and actual type are special")
		check(not definition.has("rarity") and definition.cost == 1 and definition.target == "self",color+" definition remains unranked, one-cost and automatically targeted")
		check(not Game.card_catalog.has(id) and not Game.reward_rules.cards.has(id),color+" stays outside permanent ownership and reward pools")
		check(model.card_catalog[id] == definition and Game.valid_frozen_card(definition),color+" generated combat card freezes the new special definition")
		var uid := card_in_hand(model,id)
		var target := 1 if color == "black" else 0
		var energy: int = model.energy
		var layers: int = model.buffs.count(model,"soul_link",target)
		var result := model.play_card(uid)
		check(not result.is_empty() and model.energy == energy-1 and uid in model.discard_pile,color+" special card executes once for one energy and normally discards")
		check(model.buffs.count(model,"soul_link",target) == layers-1,color+" special card removes one opposing dancer connection")
		test_presentation(definition,color)
	check(Game.valid_combat(model.snapshot()),"special-card plays preserve a valid encounter snapshot")
	for color in ["black","white"]:
		var id: String = "dancer_" + color + "_card"
		var old: Dictionary = original.cardCatalog[id].duplicate(true)
		old.type = "skill"
		old.name = "黑卡" if color == "black" else "白卡"
		original.cardCatalog[id] = old
		original.profile.phaseTwoCards[id] = old.duplicate(true)
	check(Game.valid_combat(original),"older frozen skill definitions and their original titles remain valid")
	var restored := CombatModel.new()
	restored.restore(JSON.parse_string(JSON.stringify(original)))
	check(restored.card_catalog.dancer_black_card.type == "skill" and restored.card_catalog.dancer_black_card.name == "黑卡","restoring an older battle never rewrites its frozen definitions")
	var old_uid := card_in_hand(restored,"dancer_black_card")
	check(not restored.play_card(old_uid).is_empty() and restored.buffs.count(restored,"soul_link",1) == 1,"older skill-version encounter card still resolves its original effect")
	await get_tree().process_frame
	print("DANCER SPECIAL CARDS: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
