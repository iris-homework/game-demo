class_name MidnightMapBadge
extends Control
## 事件难度／锁定符号，置于固定直径圆框中。

const DIAMETER := 28.0
const STATUS_ICONS := {
	"normal": preload("res://assets/icons/map/exclamation-mark-64.png"),
	"elite": preload("res://assets/icons/map/exclamation-mark-64.png"),
	"boss": preload("res://assets/icons/map/boss-skull.svg"),
	"lock": preload("res://assets/icons/map/lock-60.png"),
}
const ICON_SHADER := preload("res://scripts/map/badge_icon.gdshader")

var kind := "none"
var count := 0
var accent := Color("58e1eb")
var _font: Font
var _size := Vector2(20.0, 18.0)
var _icon: TextureRect

func setup(kind_value: String, count_value: int, accent_value: Color, font_value: Font) -> void:
	kind = kind_value
	count = count_value
	accent = accent_value
	_font = font_value
	_size = _measure()
	size = _size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_icon()
	set_process(kind == "boss")
	queue_redraw()

func badge_size() -> Vector2:
	return _size

func _measure() -> Vector2:
	match kind:
		"normal", "elite", "boss":
			var width := DIAMETER
			if count > 1:
				var font := _font if _font != null else get_theme_default_font()
				width += 4.0 + font.get_string_size(str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			return Vector2(width, DIAMETER)
		"lock":
			return Vector2(DIAMETER, DIAMETER)
	return Vector2(0.0, 0.0)

func _draw() -> void:
	match kind:
		"normal", "elite", "boss", "lock":
			_draw_icon_frame()

func _build_icon() -> void:
	if is_instance_valid(_icon):
		remove_child(_icon)
		_icon.queue_free()
	if not STATUS_ICONS.has(kind):
		return
	var source: Texture2D = STATUS_ICONS[kind]
	# Trim transparent padding only in the view, preserving the supplied PNG.
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(source.get_image().get_used_rect())
	_icon = TextureRect.new()
	_icon.name = "status_icon"
	_icon.texture = atlas
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var icon_size := 20.0 if kind == "boss" else 18.0
	_icon.size = Vector2.ONE * icon_size
	_icon.position = Vector2.ONE * (DIAMETER - icon_size) * 0.5
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.modulate = Color.WHITE if kind == "boss" else accent
	var material := ShaderMaterial.new()
	material.shader = ICON_SHADER
	material.set_shader_parameter("boss_effect", kind == "boss")
	_icon.material = material
	add_child(_icon)

func _draw_icon_frame() -> void:
	var center := Vector2.ONE * DIAMETER * 0.5
	var radius := DIAMETER * 0.5 - 0.75
	draw_circle(center, radius, Color(0.03, 0.05, 0.09, 0.94), true, -1.0, true)
	if kind == "boss":
		var phase := Time.get_ticks_msec() * 0.001
		for segment in range(24):
			var angle := TAU * segment / 24.0
			var neon := Color.from_hsv(fposmod(segment / 24.0 + phase * 0.18, 1.0), 0.72, 1.0)
			draw_arc(center, radius, angle, angle + TAU / 24.0, 5, Color(neon, 0.18), 5.0, true)
			draw_arc(center, radius, angle, angle + TAU / 24.0, 5, neon, 1.5, true)
	else:
		draw_arc(center, radius, 0.0, TAU, 128, accent, 1.5, true)
	# Additional event counts sit beside the circle; they never stretch its shape.
	if kind in ["normal", "elite", "boss"] and count > 1:
		var font := _font if _font != null else get_theme_default_font()
		var baseline := DIAMETER * 0.5 + 17.0 * 0.36
		draw_string_outline(font, Vector2(DIAMETER + 4.0, baseline), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, 4, Color(0.03, 0.05, 0.09, 0.94))
		draw_string(font, Vector2(DIAMETER + 4.0, baseline), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, accent)


func _process(_delta: float) -> void:
	queue_redraw()
