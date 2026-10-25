extends Control
## Persistent turn indicator. The battle supplies all phase/round changes.
const DIMENSIONS := Vector2(300,56)
const PLAYER := Color("70b7ff")
const ENEMY := Color("ff647d")
var round_number := 1
var phase := "player"
var round_label: Label
var phase_label: Label
var caption_label: Label
var accent := PLAYER
var pulse := 0.0
var transition: Tween

func _init() -> void:
	size = DIMENSIONS
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	var eyebrow := make_label("回合",Vector2(18,5),Vector2(56,16),10,Color("9aaabd"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label = make_label("",Vector2(12,18),Vector2(68,37),26,Color("f4f7ff"))
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label = make_label("",Vector2(96,5),Vector2(196,28),19,PLAYER)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label = make_label("",Vector2(96,33),Vector2(196,16),10,Color("9aaabd"))
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_state(round_number,phase)

func make_label(text: String, origin: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var line := Label.new()
	line.text = text
	line.position = origin
	line.size = dimensions
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override("font_size",font_size)
	line.add_theme_color_override("font_color",color)
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(line)
	return line

func set_state(number: int, next_phase: String = "player") -> void:
	var changed := round_number != number or phase != next_phase
	round_number = number
	phase = next_phase
	if not is_instance_valid(round_label): return
	accent = ENEMY if phase == "enemy" else (Color("ffc77c") if phase == "save" else PLAYER)
	if phase == "reveal": accent = Color("d4b5ff")
	round_label.text = "%02d" % round_number
	var font_size := 26
	while font_size > 10 and round_label.get_theme_font("font").get_string_size(round_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > 64:
		font_size -= 1
	round_label.add_theme_font_size_override("font_size",font_size)
	phase_label.text = {"player":"你的回合","enemy":"敌方回合","reveal":"第二幕","save":"等待保存"}.get(phase,"你的回合")
	caption_label.text = {"reveal":"双人舞者 / 揭幕","save":"战后结算 / 请重试"}.get(phase,"")
	caption_label.visible = not caption_label.text.is_empty()
	phase_label.position.y = 5.0 if caption_label.visible else 14.0
	phase_label.add_theme_color_override("font_color",accent)
	if changed:
		if transition: transition.kill()
		pulse = 1.0
		transition = create_tween()
		transition.tween_method(set_pulse,1.0,0.0,0.48).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	queue_redraw()

func set_pulse(value: float) -> void:
	pulse = value
	queue_redraw()

func _draw() -> void:
	var frame := PackedVector2Array([Vector2(12,0),Vector2(300,0),Vector2(300,44),Vector2(288,56),Vector2(0,56),Vector2(0,12),Vector2(12,0)])
	draw_colored_polygon(frame,Color("0d1724"))
	draw_rect(Rect2(1,1,86,54),Color(accent,0.08))
	draw_polyline(frame,Color(accent,0.30+0.24*pulse),1.0,true)
	draw_line(Vector2(88,9),Vector2(88,47),Color(accent,0.25),1,true)
	draw_line(Vector2(18,55),Vector2(282,55),Color(accent,0.7),2,true)
	var marker_y := 20.0 if is_instance_valid(caption_label) and caption_label.visible else 28.0
	var diamond := PackedVector2Array([Vector2(101,marker_y-4),Vector2(105,marker_y),Vector2(101,marker_y+4),Vector2(97,marker_y)])
	draw_colored_polygon(diamond,accent)
	if pulse > 0.0:
		draw_polyline(frame,Color(accent,pulse*0.12),6.0,true)
		draw_rect(Rect2(89,1,210,54),Color(accent,pulse*0.09))
