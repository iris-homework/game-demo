extends RefCounted
## Presentation-only bindings. Never substitutes today's rules for a frozen card.
const CONFIG_PATH := "res://data/cards/card_faces.json"
const NO_CHARACTER_CONFIG_PATH := "res://data/cards/card_faces_no_character.json"
const TEMPLATE_ID := "noren-fixed-card-v1"
const NO_CHARACTER_TEMPLATE_ID := "neon-comic-all-v1"
const CANVAS := Vector2(1086, 1448)
static var cached_config: Dictionary = {}
static var cached_no_character_config: Dictionary = {}
static var preferences_path := "user://card_faces.cfg"
static var preferences_loaded := false
static var selected_style := "character"

static func valid_style(style: String) -> bool:
	return style in ["character", "no_character"]

static func reset_preferences_cache() -> void:
	preferences_loaded = false
	selected_style = "character"

static func get_style() -> String:
	if not preferences_loaded:
		preferences_loaded = true
		var preferences := ConfigFile.new()
		if preferences.load(preferences_path) == OK:
			var saved = preferences.get_value("cards", "style", "character")
			if saved is String and valid_style(saved): selected_style = saved
	return selected_style

static func set_style(style: String) -> bool:
	if not valid_style(style): return false
	var previous := get_style()
	if previous == style: return true
	# Save a sibling temporary file first. A failed write never changes the live style
	# or the last valid preference; adventure checkpoints are not involved.
	var preferences := ConfigFile.new()
	preferences.set_value("cards", "style", style)
	var temporary := preferences_path + ".tmp"
	if preferences.save(temporary) != OK: return false
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(preferences_path))
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return false
	selected_style = style
	return true

static func config(style: String = "") -> Dictionary:
	if style.is_empty(): style = get_style()
	if not valid_style(style): return {}
	if style == "no_character":
		if cached_no_character_config.is_empty() and FileAccess.file_exists(NO_CHARACTER_CONFIG_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(NO_CHARACTER_CONFIG_PATH))
			if parsed is Dictionary: cached_no_character_config = parsed
		return cached_no_character_config
	if cached_config.is_empty() and FileAccess.file_exists(CONFIG_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary: cached_config = parsed
	return cached_config

static func matches_definition(definition: Dictionary, entry: Dictionary) -> bool:
	# Compare the complete authored definition, including effects and optional flags.
	# Dictionary equality ignores key order and JSON integer/float representation.
	return entry.get("definition") is Dictionary and entry.definition == definition

static func matches_canvas(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for dimension in value:
		if not dimension is int and not dimension is float: return false
	# JSON numbers are floats; Array equality against integer literals is strict.
	return value[0] == CANVAS.x and value[1] == CANVAS.y

static func resolve(definition: Dictionary, settings: Dictionary = {}) -> Dictionary:
	if settings.is_empty(): settings = config()
	if settings.get("schemaVersion") != 1 or not settings.get("templateId") in [TEMPLATE_ID, NO_CHARACTER_TEMPLATE_ID]: return {}
	if not matches_canvas(settings.get("canvas")) or not settings.get("cards") is Dictionary: return {}
	var entry = settings.cards.get(definition.get("id", ""), {})
	if not entry is Dictionary or not matches_definition(definition, entry): return {}
	var path = entry.get("path", "")
	var font_path = settings.get("font", "")
	if not path is String or not path.begins_with("res://") or not ResourceLoader.exists(path, "Texture2D"): return {}
	if not font_path is String or not font_path.begins_with("res://") or not ResourceLoader.exists(font_path, "Font"): return {}
	var texture := load(path) as Texture2D
	var font := load(font_path) as Font
	if texture == null or font == null or texture.get_size() != CANVAS: return {}
	return {"texture": texture, "font": font, "path": path, "template_id": settings.templateId}
