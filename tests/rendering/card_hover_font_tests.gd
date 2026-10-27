extends Node
## Production hover signals and delay; no system pointer movement or saves.
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message,"passed":ok})
	if not ok:
		failures.append(message)
		push_error("CARD HOVER FONT: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func inspect_description(card: CombatCard, expected: String, context: String) -> void:
	check(is_instance_valid(card.zoom_description), context + ": hover description exists")
	if not is_instance_valid(card.zoom_description): return
	var description := card.zoom_description
	var font := description.get_theme_font("font")
	check(description.text == expected, context + ": authored or dynamic description is preserved")
	check(font == card.base_font, context + ": CanvasLayer description uses the bundled UI font")
	var missing := ""
	for character in expected:
		if character.strip_edges().is_empty(): continue
		if not font.has_char(character.unicode_at(0)) and not missing.contains(character): missing += character
	check(missing.is_empty(), context + ": all visible characters have glyphs; missing=" + missing)
	check(font.has_char("远".unicode_at(0)), context + ": reported remote-form character has a glyph")

func exercise_card(definition: Dictionary) -> void:
	var card := CombatCard.new()
	card.setup("hover_font_" + str(definition.id), definition, true)
	add_child(card)
	card.position = Vector2(500,600)
	card.home = card.position
	var context := str(definition.name)
	# Emit the same signals connected by production setup, including its 0.45s delay.
	card.card_button.mouse_entered.emit()
	check(not is_instance_valid(card.zoom_description), context + ": hover opens after its delay")
	await get_tree().create_timer(0.5).timeout
	await settle()
	inspect_description(card, definition.description, context + " authored")
	var dynamic := "造成 12 点伤害。远程形态：额外触发 3 次裂伤。"
	card.show_preview({"cardText":"造成12点伤害。", "description":dynamic})
	inspect_description(card, dynamic, context + " dynamic")
	card.card_button.mouse_exited.emit()
	await settle()
	check(not is_instance_valid(card.zoom_description) and not is_instance_valid(card.zoom_layer), context + ": leaving removes the hover layer")
	card.card_button.mouse_entered.emit()
	await get_tree().create_timer(0.5).timeout
	await settle()
	inspect_description(card, dynamic, context + " reopened")
	card.card_button.mouse_exited.emit()
	card.queue_free()
	await settle()

func _ready() -> void:
	if not OS.get_user_data_dir().to_lower().contains("qa") or OS.get_user_data_dir().ends_with("/MidnightCommissionDemo"):
		push_error("Run card hover font QA only in a copied project with a QA user directory")
		get_tree().quit(2)
		return
	Game.save_enabled = false
	var output := OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "user://card-hover-font-qa"
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	var definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/cards/cards.json"))
	var selected := 0
	for definition in definitions:
		if definition.name not in ["伤口追猎", "拉开距离"]: continue
		selected += 1
		await exercise_card(definition)
	check(selected == 2, "both reported card and another remote-form card are exercised")
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "suite did not write adventure or meta saves")
	var file := FileAccess.open(output.path_join("card-hover-font-results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"scope":"production hover signals and delay; static/dynamic text and reopen; no pixels or physical input"},"\t"))
	file.close()
	print("CARD HOVER FONT TESTS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
