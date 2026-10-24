extends Node
## Single card-art set and read-only scene coverage, with isolated persistence.
const FaceArt = preload("res://scripts/combat/card_face_art.gd")
const Menu = preload("res://scripts/menu.gd")
const Library = preload("res://scripts/card_library.gd")
const OUTPUT := "res://artifacts/qa/card-title-2026-10-24/"
const PREFERENCES := "user://card_faces.cfg"
const STYLES := ["no_character"]
const TEMPLATE_IDS := {"no_character":"neon-comic-title-v3"}
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var loaded_art := 0
var protected_paths: Array[String] = []
var protected_bytes: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message, "passed":ok})
	if not ok:
		failures.append(message)
		push_error("CARD FACE STYLE: " + message)

func write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Create isolated fixture " + path.get_file())
	if file != null:
		file.store_string(content)
		file.close()

func file_snapshot(path: String) -> Dictionary:
	return {"exists":FileAccess.file_exists(path), "bytes":FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func make_menu() -> Control:
	var menu := Menu.new()
	add_child(menu)
	return menu

func make_model(number: int, form: String) -> CombatModel:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	rules.shuffleInitialDeck = false
	rules.deck = ["noren_%02d" % number, "noren_01"]
	var model := CombatModel.new()
	model.initialize("B04", 100, 100, rules, [{"id":"face_style_test", "displayName":"测试", "maxHp":10000, "intentSequence":[]}], Game.card_catalog)
	model.stance = form
	model.draw_pile.erase("card_000")
	model.hand = ["card_000"]
	model.opening_draw_done = true
	return model

func test_preferences() -> void:
	var original := file_snapshot(PREFERENCES)
	for content in ["[cards]\nstyle=\"character\"\n", "[cards]\nstyle=\"no_character\"\n", "corrupt legacy preference"]:
		write_text(PREFERENCES, content)
		var before := file_snapshot(PREFERENCES)
		FaceArt.cached_config.clear()
		check(FaceArt.resolve(Game.card_catalog.noren_01).get("template_id") == "neon-comic-title-v3", "Legacy preference never selects character artwork")
		var menu := make_menu()
		check(menu.find_child("card_face_style", true, false) == null, "Legacy preference cannot restore the menu toggle")
		menu.free()
		check(file_snapshot(PREFERENCES) == before, "Retired preference is never read or rewritten by card rendering")
	DirAccess.remove_absolute(PREFERENCES)
	FaceArt.cached_config.clear()
	check(FaceArt.resolve(Game.card_catalog.noren_01).get("template_id") == "neon-comic-title-v3", "Fresh installation uses no-character artwork")
	if original.exists:
		var file := FileAccess.open(PREFERENCES, FileAccess.WRITE)
		file.store_buffer(original.bytes)
		file.close()

func test_bindings() -> void:
	check(Game.card_catalog.size() == 40, "Current catalogue contains forty cards")
	var all_paths: Dictionary = {}
	for style in STYLES:
		var settings := FaceArt.config()
		check(settings.get("templateId") == TEMPLATE_IDS[style], "Style uses its own template " + style)
		check(settings.get("cards", {}).size() == 40, "Style binds all forty definitions " + style)
		for id in Game.card_catalog:
			var definition: Dictionary = Game.card_catalog[id]
			var entry: Dictionary = settings.get("cards", {}).get(id, {})
			check(FaceArt.matches_definition(definition, entry), style + ": complete definition matches " + id)
			var art := FaceArt.resolve(definition)
			check(not art.is_empty(), style + ": production texture loads " + id)
			if not art.is_empty():
				loaded_art += 1
				check(art.texture.get_size() == Vector2(1086, 1448), style + ": authored canvas " + id)
				check(art.get("template_id") == TEMPLATE_IDS[style], style + ": resolver retains template identity " + id)
				check(not all_paths.has(art.path), style + ": unique production file " + id)
				all_paths[art.path] = true
			var frozen := definition.duplicate(true)
			frozen.cardText += "（旧规则）"
			check(FaceArt.resolve(frozen).is_empty(), style + ": frozen mismatched text falls back " + id)
	check(loaded_art == 40 and all_paths.size() == 40, "The only set loads forty distinct production textures")
	var changed_settings := FaceArt.config().duplicate(true)
	changed_settings.cards.noren_01.path = "res://assets/cards/missing-no-character-card.png"
	check(FaceArt.resolve(Game.card_catalog.noren_01, changed_settings).is_empty(), "No-character configuration with missing image falls back")
	changed_settings = FaceArt.config().duplicate(true)
	changed_settings.font = "res://assets/fonts/missing-no-character-font.otf"
	check(FaceArt.resolve(Game.card_catalog.noren_01, changed_settings).is_empty(), "No-character configuration with missing font falls back")
	changed_settings = FaceArt.config().duplicate(true)
	changed_settings.templateId = "unknown-no-character-template"
	check(FaceArt.resolve(Game.card_catalog.noren_01, changed_settings).is_empty(), "Unknown template falls back without borrowing character geometry")

func test_menu() -> void:
	Game.page = "menu"
	var menu := make_menu()
	await settle()
	check(menu.find_child("card_face_style", true, false) == null, "Main menu has no card-art toggle")
	check(not menu.has_method("_toggle_card_face_style"), "Retired menu callback is removed")
	check(menu.motion_button != null and menu.quit_button != null, "Other bottom menu controls remain")
	menu._set_training_open(true)
	check(menu.training_open and menu.motion_button.disabled, "Training panel still locks background controls")
	menu.handle_escape()
	check(not menu.training_open and not menu.motion_button.disabled, "Closing training restores menu controls")
	menu.free()

func test_shared_views() -> void:
	for style in STYLES:
		var library := Library.new()
		library.owned_only = false
		add_child(library)
		check(library.card_views.size() == 40, style + ": full library retains forty read-only cards")
		for card in library.card_views:
			check(card.face_texture == FaceArt.resolve(card.data).get("texture") and card.preview_only, style + ": library reuses selected artwork " + str(card.data.id))
		library.free()
		var model := make_model(1, "melee")
		var snapshot := model.snapshot()
		var deck := Library.new()
		deck.setup_current_deck(snapshot)
		add_child(deck)
		check(not deck.card_views.is_empty(), style + ": current deck remains browsable")
		for card in deck.card_views:
			check(card.face_texture == FaceArt.resolve(card.data).get("texture") and card.preview_only, style + ": frozen current deck uses selected artwork")
		check(model.snapshot() == snapshot, style + ": browsing leaves frozen battle snapshot intact")
		deck.free()
		var card := CombatCard.new()
		card.allow_zoom_preview = true
		card.setup("test", Game.card_catalog.noren_01, false)
		add_child(card)
		card.set_enabled(true)
		card.show_cost(0)
		card.show_preview({"cardText":"造成99点伤害。", "description":"造成 99 点伤害。"})
		card.show_zoom_preview()
		check(is_instance_valid(card.zoom_card), style + ": enlarged card is created")
		if is_instance_valid(card.zoom_card):
			check(card.zoom_card.face_texture == card.face_texture, style + ": enlarged card retains selected texture")
			check(card.zoom_card.face_template_id == card.face_template_id and card.face_template_id == TEMPLATE_IDS[style], style + ": enlarged card keeps source template with the fixed no-character set")
			check(card.zoom_card.effect_label.text == "造成99点伤害。" and card.zoom_card.cost_label.text == "0", style + ": enlarged card retains dynamic values")
			check_geometry(card.zoom_card, style, style + " enlarged source")
		card.free()

func check_geometry(card: CombatCard, style: String, tag: String) -> void:
	var rules := Rect2(118, 956, 853, 369)
	var cost := Rect2(39, 79, 160, 180)
	var center := Vector2(119, 169)
	check(card.face_template_id == TEMPLATE_IDS[style], tag + ": source identifies the correct template")
	var c_grade: bool = card.data.rarity == "C"
	check(card.face_base_cost_color() == (Color("eeeee7") if c_grade else CombatCard.RARITY_COLORS[card.data.rarity]), tag + ": cost numeral follows the grade, preserving C colors")
	check(card.face_cost_background() == (Color("b53660") if c_grade else Color("101016")), tag + ": dynamic cost mask matches the new printed medallion")
	check(card.face_rules_rect() == rules and card.face_cost_rect() == cost and card.face_cost_center() == center, tag + ": authored rules and numeral regions match template")
	check(card.effect_label.position == rules.position and card.effect_label.size == rules.size, tag + ": effect label occupies its own template rules panel")
	var typeface := card.effect_label.get_theme_font("font")
	var font_size := card.effect_label.get_theme_font_size("font_size")
	var candidates := [70, 66, 62, 58, 54, 50, 46, 42, 38, 36]
	var measured := typeface.get_multiline_string_size(card.effect_label.text, HORIZONTAL_ALIGNMENT_CENTER, rules.size.x, font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var lines := maxi(1, ceili(measured.y / typeface.get_height(font_size)))
	var spacing := card.effect_label.get_theme_constant("line_spacing")
	check(font_size in candidates and spacing == 15 and measured.x <= rules.size.x and measured.y + (lines - 1) * spacing <= rules.size.y, tag + ": measured dynamic rules including line spacing fit their panel")
	check(card.effect_label.get_combined_minimum_size().y <= rules.size.y, tag + ": Godot label minimum height stays within rules panel")
	var cost_candidates := [152, 138, 124, 108]
	check(card.cost_label.get_theme_font_size("font_size") in cost_candidates and card.cost_label.size == cost.size, tag + ": numeral uses template font sizes and bounds")
	check(card.cost_ink_bounds.get_center().distance_to(center) < 0.01 and cost.encloses(card.cost_ink_bounds), tag + ": numeral ink is centered and contained in its template region")

func test_dynamic_cards() -> void:
	for style in STYLES:
		for form in ["melee", "ranged"]:
			for number in range(1, 41):
				var tag := "%s %s %02d" % [style, form, number]
				var model := make_model(number, form)
				model.next_attack_bonus = 3
				model.turn_damage_bonus = 4
				model.turn_discount = 1
				model.stance_discount = true
				model.ammo = 10
				model.enemies[0].bleed = 5
				var before := model.snapshot()
				var card := CombatCard.new()
				card.allow_zoom_preview = false
				card.setup("card_000", model.card("card_000"), true)
				add_child(card)
				check(card.face_texture != null and not card.cost_label.visible and not card.effect_label.visible, tag + ": base PNG does not duplicate printed text")
				var preview := model.card_preview("card_000", 0)
				card.show_preview(preview)
				card.show_cost(model.card_cost("card_000"))
				check(card.effect_label.text == preview.cardText and card.cost_label.text == str(model.card_cost("card_000")), tag + ": dynamic labels retain calculated rules and cost")
				check(card.rules_changed == (preview.cardText != card.data.cardText) and card.cost_changed == (model.card_cost("card_000") != int(card.data.cost)), tag + ": masks follow actual changes")
				check_geometry(card, style, tag)
				check(model.snapshot() == before, tag + ": dynamic presentation does not mutate battle snapshot")
				check(card.size == Vector2(180, 230) and card.pivot_offset == Vector2(90, 115), tag + ": input and animation footprint stays unchanged")
				card.show_preview({"cardText":card.data.cardText, "description":card.data.description})
				card.show_cost(int(card.data.cost))
				check(not card.rules_changed and not card.cost_changed and not card.effect_label.visible and not card.cost_label.visible, tag + ": returning to base values restores printed text")
				card.free()

func _ready() -> void:
	if not OS.get_user_data_dir().get_file().begins_with("MidnightSingleCardFaceQA-"):
		push_error("Refusing to write preference fixtures outside the isolated QA user directory")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for path in [Game.save_path, Game.save_path + ".bak", Game.save_path + ".tmp", Game.meta_path, PREFERENCES]:
		protected_paths.append(path)
		protected_bytes[path] = file_snapshot(path)
	Game.save_enabled = false
	Game.save_path = OUTPUT + "isolated-checkpoint.json"
	Game.meta_path = OUTPUT + "isolated-meta.json"
	Game.state = Game.initial_state()
	Game.page = "menu"
	Game.state.combat = make_model(1, "melee").snapshot()
	Game.state.battleStart = Game.state.combat.duplicate(true)
	for path in [Game.save_path, Game.save_path + ".bak", Game.save_path + ".tmp", Game.meta_path]:
		write_text(path, "isolated preservation sentinel: " + path.get_file())
		protected_paths.append(path)
		protected_bytes[path] = file_snapshot(path)
	var original_state: Dictionary = Game.state.duplicate(true)
	var original_catalog: Dictionary = Game.card_catalog.duplicate(true)
	var original_revision: int = Game.revision
	test_preferences()
	test_bindings()
	await test_menu()
	test_shared_views()
	test_dynamic_cards()
	await settle()
	check(Game.state == original_state, "All style operations preserve adventure state, deck, battle and opening snapshot")
	check(Game.revision == original_revision, "Style operations never advance gameplay revision")
	check(Game.card_catalog == original_catalog, "Style operations never rewrite authored card definitions")
	for path in protected_paths:
		check(file_snapshot(path) == protected_bytes[path], "Protected save or original preference remains byte-identical: " + path)
	var report := {"checks":checks, "failures":failures, "records":records, "loadedArt":loaded_art, "userDataDirectory":OS.get_user_data_dir(),  "scope":"isolated headless textures, synthetic modal signals and read-only dynamic cards; no visible window, mouse movement, physical-input or visual acceptance"}
	var file := FileAccess.open(OUTPUT + "result.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	print("CARD FACE STYLES: %d checks, %d failures; production artwork loaded %d/40" % [checks, failures.size(), loaded_art])
	get_tree().quit(0 if failures.is_empty() else 1)
