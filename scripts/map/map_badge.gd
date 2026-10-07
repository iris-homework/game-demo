class_name MidnightMapBadge
extends Control
## 地点标记角标：任务数量（!/?）、锁定锁形、完成勾。
## 轻量矢量绘制，避免为每种状态再增加美术文件。

var kind := "none"
var count := 0
var accent := Color("58e1eb")
var _font: Font
var _size := Vector2(20.0, 18.0)

func setup(kind_value: String, count_value: int, accent_value: Color, font_value: Font) -> void:
	kind = kind_value
	count = count_value
	accent = accent_value
	_font = font_value
	_size = _measure()
	size = _size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func badge_size() -> Vector2:
	return _size

func _task_text() -> String:
	var text := "!" if kind == "main" else "?"
	if count > 1:
		text += str(count)
	return text

func _measure() -> Vector2:
	match kind:
		"main", "optional":
			var text := _task_text()
			var width := 27.0
			if _font != null:
				width = maxf(27.0, _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 14.0)
			return Vector2(width, 24.0)
		"lock":
			return Vector2(22.0, 25.0)
		"check":
			return Vector2(22.0, 22.0)
	return Vector2(0.0, 0.0)

func _draw() -> void:
	match kind:
		"main", "optional":
			_draw_task()
		"lock":
			_draw_lock()
		"check":
			_draw_check()

func _draw_task() -> void:
	var rect := Rect2(Vector2.ZERO, _size)
	draw_style_box(_pill(rect, Color(0.03, 0.05, 0.09, 0.92), accent), rect)
	var font := _font if _font != null else get_theme_default_font()
	if font == null:
		return
	var font_size := 17
	draw_string(font, Vector2(0.0, _size.y * 0.5 + font_size * 0.36), _task_text(), HORIZONTAL_ALIGNMENT_CENTER, _size.x, font_size, accent)

func _draw_lock() -> void:
	var w := _size.x
	var h := _size.y
	var back := Rect2(0.5, 0.5, w - 1.0, h - 1.0)
	draw_style_box(_pill(back, Color(0.04, 0.06, 0.10, 0.90), accent), back)
	draw_arc(Vector2(w * 0.5, h * 0.47), w * 0.20, PI, TAU, 14, accent, 2.0, true)
	draw_rect(Rect2(w * 0.30, h * 0.47, w * 0.40, h * 0.36), accent, true)

func _draw_check() -> void:
	var back := Rect2(0.5, 0.5, _size.x - 1.0, _size.y - 1.0)
	draw_style_box(_round(back, Color(0.04, 0.06, 0.10, 0.88), Color(accent, 0.70), 3), back)
	draw_line(Vector2(_size.x * 0.24, _size.y * 0.54), Vector2(_size.x * 0.44, _size.y * 0.74), accent, 2.4, true)
	draw_line(Vector2(_size.x * 0.44, _size.y * 0.74), Vector2(_size.x * 0.78, _size.y * 0.28), accent, 2.4, true)

func _pill(rect: Rect2, fill: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(int(maxf(1.0, rect.size.y * 0.5)))
	return s

func _round(rect: Rect2, fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	return s
