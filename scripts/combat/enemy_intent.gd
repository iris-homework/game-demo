extends Control
## Vector head icon and per-hit value. The caller supplies the model's read-only preview.
const DIMENSIONS := Vector2(96,66)
const ICON_PATHS := {
	"attack":"res://assets/icons/intents/attack.svg",
	"fortify":"res://assets/icons/intents/fortify.svg",
	"energy_suit":"res://assets/icons/intents/energy_suit.svg",
	"charge":"res://assets/icons/intents/charge.svg",
	"strength_allies":"res://assets/icons/intents/strength_allies.svg",
	"vulnerable":"res://assets/icons/intents/vulnerable.svg",
	"pollution":"res://assets/icons/intents/pollution.svg",
	"weak":"res://assets/icons/intents/weak.svg",
	"heal_ally":"res://assets/icons/intents/heal_ally.svg",
	"unknown":"res://assets/icons/intents/unknown.svg",
}
var icon_views: Array[TextureRect] = []
var kind := ""
var value_label: Label
var weak_amount := 0
var tooltip_data: Dictionary = {}

func _init() -> void:
	size = DIMENSIONS
	mouse_filter = Control.MOUSE_FILTER_PASS

func configure_tooltip(data: Dictionary) -> void:
	tooltip_data = data
	tooltip_text = data.plain

func _make_custom_tooltip(_text: String) -> Object:
	return preload("res://scripts/combat/intent_tooltip.gd").build(tooltip_data,get_theme_font("font")) if not tooltip_data.is_empty() else null

func setup(intent: Dictionary, description: String, font: Font) -> void:
	for child in get_children(): child.free()
	icon_views.clear()
	kind = str(intent.get("type",""))
	weak_amount = maxi(0,int(intent.get("onHitWeak",0))) if kind == "attack" else 0
	add_icon(kind,Vector2(4 if weak_amount > 0 else 28,0))
	if weak_amount > 0: add_icon("weak",Vector2(52,0))
	value_label = Label.new()
	value_label.position = Vector2(0,36)
	value_label.size = Vector2(DIMENSIONS.x,30)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.add_theme_font_override("font",font)
	value_label.add_theme_font_size_override("font_size",22)
	value_label.add_theme_color_override("font_color",Color("fff7e9"))
	value_label.add_theme_color_override("font_outline_color",Color("12131ee6"))
	value_label.add_theme_constant_override("outline_size",4)
	match kind:
		"attack": value_label.text = description.trim_prefix("攻击 ").replace(" ","")
		"strength_allies", "charge": value_label.text = "+%d" % int(intent.get("amount",0))
		"energy_suit", "fortify": value_label.text = "强化"
		"pollution", "vulnerable", "weak": value_label.text = str(int(intent.get("amount",0)))
		"heal_ally": value_label.text = "+%d" % int(intent.get("amount",0))
		_:
			value_label.text = description
			value_label.add_theme_font_size_override("font_size",14)
	add_child(value_label)
	if weak_amount > 0:
		# The attack and its debuff are separate visible intentions. Preserve the
		# existing 96x66 HUD footprint and the numeric damage preview.
		value_label.size.x = DIMENSIONS.x / 2
		var number_size := 22
		while number_size > 14 and font.get_string_size(value_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,number_size).x > value_label.size.x-4:
			number_size -= 1
		value_label.add_theme_font_size_override("font_size",number_size)
		var weak_label := value_label.duplicate() as Label
		weak_label.name = "IntentWeakAmount"
		weak_label.position.x = DIMENSIONS.x / 2
		weak_label.text = str(weak_amount)
		weak_label.add_theme_color_override("font_color",Color("f4c79f"))
		add_child(weak_label)

func add_icon(symbol: String, origin: Vector2) -> void:
	var icon := TextureRect.new()
	icon.name = "IntentIcon_"+symbol
	icon.position = origin
	icon.size = Vector2(40,40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.texture = load(ICON_PATHS.get(symbol,ICON_PATHS.unknown))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	icon_views.append(icon)
