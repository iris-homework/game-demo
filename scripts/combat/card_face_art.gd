extends RefCounted
## Presentation-only bindings. Never substitutes today's rules for a frozen card.
const CONFIG_PATH := "res://data/cards/card_faces.json"
const TEMPLATE_ID := "noren-fixed-card-v1"
const CANVAS := Vector2(1086, 1448)
static var cached_config: Dictionary = {}

static func config() -> Dictionary:
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
	if settings.get("schemaVersion") != 1 or settings.get("templateId") != TEMPLATE_ID: return {}
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
	return {"texture": texture, "font": font, "path": path}
