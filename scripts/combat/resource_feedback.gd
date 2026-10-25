extends Control
## One reusable, non-modal resource warning; no combat or persistence writes.
const DIMENSIONS := Vector2(440,76)
const REST_POSITION := Vector2(500,548)
var resource := ""
var title_label: Label
var detail_label: Label
var accent := Color("70b7ff")
var lifetime: Tween

func _init() -> void:
	size = DIMENSIONS
	position = REST_POSITION
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 60
	visible = false

func _ready() -> void:
	title_label = make_label(Vector2(68,8),Vector2(350,31),21)
	detail_label = make_label(Vector2(68,41),Vector2(350,22),14)
	detail_label.add_theme_color_override("font_color",Color("b8c6d7"))

func make_label(origin: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var line := Label.new()
	line.position = origin
	line.size = dimensions
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size",font_size)
	add_child(line)
	return line

func present(kind: String, cost: int = 0, available: int = 0) -> void:
	if lifetime: lifetime.kill()
	resource = kind
	accent = Color("70b7ff") if resource == "energy" else Color("ffb467")
	title_label.text = "能量不足" if resource == "energy" else "弹药不足"
	detail_label.text = "需要 %d 点 · 当前 %d 点，恢复能量后再出牌" % [cost,available] if resource == "energy" else "远程攻击需要弹药，先补弹或切回近战"
	title_label.add_theme_color_override("font_color",accent.lightened(0.3))
	position = REST_POSITION+Vector2(0,9)
	modulate.a = 0.0
	show()
	queue_redraw()
	lifetime = create_tween().set_parallel(true)
	lifetime.tween_property(self,"position",REST_POSITION,0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	lifetime.tween_property(self,"modulate:a",1.0,0.12)
	lifetime.chain().tween_interval(1.25)
	lifetime.chain().tween_property(self,"modulate:a",0.0,0.22)
	lifetime.parallel().tween_property(self,"position",REST_POSITION-Vector2(0,5),0.22)
	lifetime.chain().tween_callback(dismiss)

func dismiss() -> void:
	if lifetime: lifetime.kill()
	lifetime = null
	hide()
	resource = ""
	position = REST_POSITION
	modulate.a = 1.0

func _draw() -> void:
	var frame := PackedVector2Array([Vector2(10,0),Vector2(440,0),Vector2(440,66),Vector2(430,76),Vector2(0,76),Vector2(0,10),Vector2(10,0)])
	draw_polyline(frame,Color(accent,0.08),8,true)
	draw_colored_polygon(frame,Color("0b1422f5"))
	draw_polyline(frame,Color(accent,0.5),1,true)
	draw_line(Vector2(1,12),Vector2(1,64),accent,3,true)
	draw_rect(Rect2(12,12,42,52),Color(accent,0.07))
	if resource == "energy":
		draw_colored_polygon(PackedVector2Array([Vector2(35,21),Vector2(23,40),Vector2(32,40),Vector2(29,55),Vector2(44,33),Vector2(35,33)]),accent)
	else:
		var bullet := PackedVector2Array([Vector2(27,52),Vector2(27,31),Vector2(30,24),Vector2(34,21),Vector2(38,24),Vector2(41,31),Vector2(41,52),Vector2(27,52)])
		draw_polyline(bullet,accent,1.5,true)
		draw_line(Vector2(22,55),Vector2(46,23),accent,2,true)
	draw_line(Vector2(68,72),Vector2(418,72),Color(accent,0.18),1,true)
