extends Node
const FaceArt = preload("res://scripts/combat/card_face_art.gd")
var checks := 0
var failures: Array[String] = []
var available_art := 0
var synthetic_texture: Texture2D

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func fixture(number: int, form: String = "melee") -> CombatModel:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	rules.shuffleInitialDeck = false
	rules.deck = ["noren_%02d" % number, "noren_01"]
	var model := CombatModel.new()
	model.initialize("B04", 100, 100, rules, [{"id": "face_test", "displayName": "测试", "maxHp": 10000, "intentSequence": []}], Game.card_catalog)
	model.stance = form
	model.draw_pile.erase("card_000")
	model.hand = ["card_000"]
	model.opening_draw_done = true
	return model

func make_card(definition: Dictionary, use_fixture_art: bool = false, read_only: bool = true) -> CombatCard:
	var card := CombatCard.new()
	card.allow_zoom_preview = false
	card.setup("card_000", definition, read_only)
	if use_fixture_art:
		# In-memory neutral pixels exercise overlays before production art is delivered.
		# They are never written to assets, accepted, or presented as authored artwork.
		card.face_texture = synthetic_texture
		card.face_font = load("res://assets/fonts/NotoSerifCJKsc-Bold.otf")
	add_child(card)
	return card

func test_bindings() -> void:
	var settings := FaceArt.config()
	check(FaceArt.matches_canvas(settings.canvas), "JSON float dimensions match the fixed canvas")
	check(FaceArt.matches_canvas([1086, 1448]), "Integer dimensions match the fixed canvas")
	for invalid_canvas in [[1086, 1447], [1086], [1086, 1448, 0], ["1086", 1448], null, Vector2(1086, 1448)]:
		check(not FaceArt.matches_canvas(invalid_canvas), "Malformed or wrong canvas is rejected: " + str(invalid_canvas))
	check(settings.cards.size() == 40, "Exactly forty explicit art bindings")
	for id in Game.card_catalog:
		var definition: Dictionary = Game.card_catalog[id]
		check(FaceArt.matches_definition(definition, settings.cards[id]), id + " binds the complete current definition")
		check(FaceArt.matches_definition(JSON.parse_string(JSON.stringify(definition)), settings.cards[id]), id + " survives snapshot JSON round-trip")
		check(settings.cards[id].path == "res://assets/cards/noren_no_character_v3/%s.png" % id, id + " has the agreed path")
		var art := FaceArt.resolve(definition)
		if not art.is_empty():
			available_art += 1
			check(art.texture.get_size() == Vector2(1086, 1448), id + " production art dimensions")
		for field in ["name", "cardText", "description", "cost", "rarity", "type", "effects", "target"]:
			var old := definition.duplicate(true)
			old[field] = "changed" if field != "cost" else 99
			check(not FaceArt.matches_definition(old, settings.cards[id]), id + " rejects frozen mismatch in " + field)
	var changed := settings.duplicate(true)
	changed.cards.noren_01.path = "res://assets/cards/does_not_exist.png"
	check(FaceArt.resolve(Game.card_catalog.noren_01, changed).is_empty(), "Missing artwork falls back")
	changed.cards.noren_01.path = "res://assets/icon.svg"
	check(FaceArt.resolve(Game.card_catalog.noren_01, changed).is_empty(), "Wrong artwork dimensions fall back")
	changed.font = "res://assets/fonts/does_not_exist.otf"
	check(FaceArt.resolve(Game.card_catalog.noren_01, changed).is_empty(), "Missing fixed typeface falls back without substituting")
	changed.templateId = "unknown"
	check(FaceArt.resolve(Game.card_catalog.noren_01, changed).is_empty(), "Unknown template does not use hardcoded geometry")
	if "--require-art" in OS.get_cmdline_user_args(): check(available_art == 40, "All forty production textures load")

func test_dynamic_faces() -> void:
	for form in ["melee", "ranged"]:
		for number in range(1, 41):
			var model := fixture(number, form)
			model.next_attack_bonus = 3
			model.turn_damage_bonus = 4
			model.turn_discount = 1
			model.stance_discount = true
			model.ammo = 10
			model.enemies[0].bleed = 5
			var before := model.snapshot()
			var card := make_card(model.card("card_000"), true)
			check(not card.cost_label.visible and not card.effect_label.visible, "%02d base PNG has no duplicate labels" % number)
			check(is_equal_approx(CombatCard.FACE_RECT.size.x / CombatCard.FACE_RECT.size.y, 0.75), "Artwork retains 3:4 ratio")
			check(card.size == Vector2(180, 230) and card.pivot_offset == Vector2(90, 115), "Input and animation footprint unchanged")
			var preview := model.card_preview("card_000", 0)
			card.show_preview(preview)
			card.show_cost(model.card_cost("card_000"))
			check(card.effect_label.text == preview.cardText, "%02d %s preserves calculated rules" % [number, form])
			check(card.cost_label.text == str(model.card_cost("card_000")), "%02d %s preserves calculated cost" % [number, form])
			check(card.rules_changed == (preview.cardText != card.data.cardText), "Rule mask appears exactly when printed rules change")
			check(card.cost_changed == (model.card_cost("card_000") != int(card.data.cost)), "Cost mask appears exactly when printed cost changes")
			var font := card.effect_label.get_theme_font("font")
			var font_size := card.effect_label.get_theme_font_size("font_size")
			var measured := font.get_multiline_string_size(card.effect_label.text, HORIZONTAL_ALIGNMENT_CENTER, card.effect_label.size.x, font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
			var lines := maxi(1, ceili(measured.y / font.get_height(font_size)))
			check(font_size in [70, 66, 62, 58, 54, 50, 46, 42, 38, 36] and measured.y + (lines - 1) * 15 <= 369, "%02d %s calculated rules fit fixed template" % [number, form])
			check(card.effect_label.get_combined_minimum_size().y <= 369, "%02d %s label stays within rule panel" % [number, form])
			check(card.cost_label.get_combined_minimum_size().y <= 180, "Cost label stays within cost circle region")
			check(card.cost_ink_bounds.get_center().distance_to(Vector2(119, 169)) < 0.01, "Dynamic cost ink is centered like the template")
			check(Rect2(39, 79, 160, 180).encloses(card.cost_ink_bounds), "Dynamic cost visible ink stays within template region")
			check(model.snapshot() == before, "Rendering does not mutate battle snapshot")
			card.show_preview({"cardText": card.data.cardText, "description": card.data.description})
			card.show_cost(int(card.data.cost))
			check(not card.rules_changed and not card.cost_changed and not card.effect_label.visible and not card.cost_label.visible, "Returning to base values restores exact baked fields")
			check(card.card_button.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Test preview cannot intercept input")
			card.free()

func test_frozen_snapshot() -> void:
	var model := fixture(4)
	var snapshot := model.snapshot()
	snapshot.cardCatalog.noren_04.effects[0].amount = 4
	snapshot.cardCatalog.noren_04.cardText = "获得4点格挡，进入远程形态。"
	snapshot.cardCatalog.noren_04.description = "获得 4 点格挡，进入远程形态。"
	var restored := CombatModel.new()
	restored.restore(JSON.parse_string(JSON.stringify(snapshot)))
	var before := restored.snapshot()
	var card := make_card(restored.card("card_000"))
	check(card.face_texture == null, "Old frozen definition rejects today's baked face")
	check(card.effect_label.text == snapshot.cardCatalog.noren_04.cardText, "Fallback displays frozen rules")
	card.show_preview(restored.card_preview("card_000"))
	check(card.effect_label.text.contains("4点格挡"), "Fallback preview calculates frozen block")
	check(restored.snapshot() == before, "Old snapshot remains unchanged after fallback")
	check(Game.card_catalog.noren_04.effects[0].amount == 6, "Current catalogue remains distinct from old snapshot")
	card.free()
	var browser = preload("res://scripts/card_library.gd").new()
	browser.setup_current_deck(before)
	add_child(browser)
	var found := false
	for item in browser.card_views:
		if item.data.get("id") == "noren_04":
			found = true
			check(item.face_texture == null and item.effect_label.text == before.cardCatalog.noren_04.cardText, "Current-deck browser uses frozen fallback")
	check(found, "Frozen card remains in current-deck browser")
	browser.free()

func test_preview_and_input() -> void:
	var definition: Dictionary = Game.card_catalog.noren_01
	var card := make_card(definition, false, false)
	card.allow_zoom_preview = true
	card.set_enabled(true)
	card.show_cost(0)
	card.show_preview({"cardText": "造成99点伤害。", "description": "造成 99 点伤害。"})
	card.show_zoom_preview()
	check(is_instance_valid(card.zoom_card), "Readable enlarged card is created")
	check(card.zoom_card.effect_label.text == "造成99点伤害。" and card.zoom_card.cost_label.text == "0", "Zoom starts with current cost and damage")
	check(card.zoom_card.face_texture == card.face_texture, "Zoom resolves the same production artwork or fallback")
	check(card.zoom_card.card_button.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Enlarged card cannot steal clicks")
	card.show_preview({"cardText": "造成101点伤害。", "description": "造成 101 点伤害。"})
	check(card.zoom_card.effect_label.text == "造成101点伤害。", "Open zoom updates when target preview changes")
	card.process_mode = Node.PROCESS_MODE_DISABLED
	check(not is_instance_valid(card.zoom_layer), "A modal disabling the source view clears its zoom layer")
	card.process_mode = Node.PROCESS_MODE_INHERIT
	card.show_zoom_preview()
	card.set_selected(true)
	check(not is_instance_valid(card.zoom_card), "Selecting a card clears zoom before aiming")
	check(card.card_button.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS, "Hand still selects on mouse down")
	card.set_enabled(false)
	check(card.card_button.disabled, "Disabled card keeps original input lock")
	card.set_selected(false)
	card.hover(true)
	await get_tree().create_timer(0.5).timeout
	check(not is_instance_valid(card.zoom_layer), "A pending hover cannot create a preview for a disabled hand card")
	card.free()
	var console = preload("res://scripts/card_console.gd").new()
	add_child(console)
	check(console.card_buttons.size() == 40, "Console retains all forty add-one buttons")
	var tooltip: Control = console.card_buttons.noren_01._make_custom_tooltip("")
	add_child(tooltip)
	var tip_card: CombatCard = tooltip.get_child(0)
	check(tip_card.data == definition and tip_card.preview_only and not tip_card.allow_zoom_preview, "Console tooltip reuses a read-only CombatCard")
	check(tip_card.face_texture == FaceArt.resolve(definition).get("texture"), "Console uses the same face binding")
	var original_deck: Array = Game.state.deck.duplicate()
	console.card_buttons.noren_01.pressed.emit()
	console.card_buttons.noren_01.pressed.emit()
	check(Game.state.deck.size() == original_deck.size() + 2 and Game.state.deck[-1] == "noren_01", "Console still adds exactly one copy per button activation")
	check(console.owned_labels.noren_01.text == "已有 6", "Console still refreshes ownership after repeated activation")
	Game.state.deck = original_deck
	tooltip.free()
	console.free()

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://fixed_card_face_test.json"
	Game.meta_path = "user://fixed_card_face_test_meta.json"
	Game.state = Game.initial_state()
	var image := Image.create(1086, 1448, false, Image.FORMAT_RGBA8)
	image.fill(Color("1c1c25"))
	synthetic_texture = ImageTexture.create_from_image(image)
	test_bindings()
	test_dynamic_faces()
	test_frozen_snapshot()
	await test_preview_and_input()
	await get_tree().process_frame
	print("FIXED CARD FACES: %d checks, %d failures; production artwork loaded %d/40" % [checks, failures.size(), available_art])
	get_tree().quit(0 if failures.is_empty() else 1)
