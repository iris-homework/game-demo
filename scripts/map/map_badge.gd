class_name MidnightMapBadge
extends Control
## 用户提供的任务／锁定符号，置于固定直径圆框中；完成勾保持既有样式。

const DIAMETER := 28.0
const STATUS_ICONS := {
	"main": preload("res://assets/icons/map/exclamation-mark-64.png"),
	"optional": preload("res://assets/icons/map/question-mark-52.png"),
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
	queue_redraw()

func badge_size() -> Vector2:
	return _size

func _measure() -> Vector2:
	match kind:
		"main", "optional":
			var width := DIAMETER
			if count > 1:
				var font := _font if _font != null else get_theme_default_font()
				width += 4.0 + font.get_string_size(str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			return Vector2(width, DIAMETER)
		"lock":
			return Vector2(DIAMETER, DIAMETER)
		"check":
			return Vector2(22.0, 22.0)
	return Vector2(0.0, 0.0)

func _draw() -> void:
	match kind:
		"main", "optional", "lock":
			_draw_icon_frame()
		"check":
			_draw_check()

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
	_icon.size = Vector2(18.0, 18.0)
	_icon.position = Vector2.ONE * (DIAMETER - 18.0) * 0.5
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.modulate = accent
	var material := ShaderMaterial.new()
	material.shader = ICON_SHADER
	_icon.material = material
	add_child(_icon)

func _draw_icon_frame() -> void:
	var center := Vector2.ONE * DIAMETER * 0.5
	var radius := DIAMETER * 0.5 - 0.75
	draw_circle(center, radius, Color(0.03, 0.05, 0.09, 0.94), true, -1.0, true)
	draw_arc(center, radius, 0.0, TAU, 128, accent, 1.5, true)
	# Additional event counts sit beside the circle; they never stretch its shape.
	if kind in ["main", "optional"] and count > 1:
		var font := _font if _font != null else get_theme_default_font()
		var baseline := DIAMETER * 0.5 + 17.0 * 0.36
		draw_string_outline(font, Vector2(DIAMETER + 4.0, baseline), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, 4, Color(0.03, 0.05, 0.09, 0.94))
		draw_string(font, Vector2(DIAMETER + 4.0, baseline), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, accent)

func _draw_check() -> void:
	var back := Rect2(0.5, 0.5, _size.x - 1.0, _size.y - 1.0)
	draw_style_box(_round(back, Color(0.04, 0.06, 0.10, 0.88), Color(accent, 0.70), 3), back)
	draw_line(Vector2(_size.x * 0.24, _size.y * 0.54), Vector2(_size.x * 0.44, _size.y * 0.74), accent, 2.4, true)
	draw_line(Vector2(_size.x * 0.44, _size.y * 0.74), Vector2(_size.x * 0.78, _size.y * 0.28), accent, 2.4, true)

func _round(rect: Rect2, fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	return s
