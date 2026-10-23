extends Control
## Read-only ammunition display; hit callbacks supply the presentation count.
const DIMENSIONS := Vector2(112,64)
const SLOT_COUNT := 10
const COLUMNS := 5
const BULLET_SCALE := 0.5
const ORANGE := Color("ffab52")
var current := 0
var capacity := 10
var stance := "melee"
var hovered := false
var value_label: Label

func _init() -> void:
	size = DIMENSIONS
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(func(): hovered = true; queue_redraw())
	mouse_exited.connect(func(): hovered = false; queue_redraw())

func filled_slot_count() -> int:
	return clampi(current,0,SLOT_COUNT)

func set_ammo(value: int, limit: int, form: String) -> void:
	current = value
	capacity = limit
	stance = form
	value_label.text = "弹药"
	tooltip_text = "弹药 %d / %d · 当前%s状态\n远程状态需要消耗弹药才能攻击；通常每张攻击牌消耗 1 发，特殊消耗以卡牌说明为准。\n近战状态每段攻击恢复 1 发弹药，最多储存 %d 发。" % [current,capacity,"近战" if stance == "melee" else "远程",capacity]
	queue_redraw()

func _make_custom_tooltip(_text: String) -> Object:
	return preload("res://scripts/combat/intent_tooltip.gd").build({
		"enemy":"弹药", "node_name":"AmmoTooltip", "eyebrow":"战斗资源 / 弹药", "title":"弹药", "accent":ORANGE,
		"value":"%d / %d" % [current,capacity], "unit":"发",
		"summary":"当前状态：%s" % ("近战" if stance == "melee" else "远程"),
		"notes":[
			{"title":"远程状态 · 消耗","body":"需要消耗弹药才能攻击。通常每张攻击牌消耗 1 发；特殊消耗以卡牌说明为准。弹药不足时无法进行远程攻击。"},
			{"title":"近战状态 · 恢复","body":"每段攻击恢复 1 发弹药，最多储存 %d 发。群体攻击的同一段只恢复 1 发。" % capacity}
		], "footer":"橙色子弹表示当前可用弹药"
	},get_theme_font("font"))

func slot_origin(index: int) -> Vector2:
	return Vector2(22 + (index % COLUMNS)*14,21 + (index / COLUMNS)*17)

func _draw() -> void:
	var frame := Rect2(Vector2.ZERO,DIMENSIONS)
	draw_style_box(_panel_style(),frame)
	for i in SLOT_COUNT:
		var origin := slot_origin(i)
		# Keep each slot's center while halving the bullet and its glow.
		draw_set_transform(origin+Vector2(12,24)*(1.0-BULLET_SCALE)*0.5,0,Vector2.ONE*BULLET_SCALE)
		var lit := i < filled_slot_count()
		var bullet := PackedVector2Array([Vector2(0,24),Vector2(0,8),Vector2(2,3),Vector2(6,0),Vector2(10,3),Vector2(12,8),Vector2(12,24)])
		if lit:
			draw_rect(Rect2(Vector2(-3,-2),Vector2(18,29)),Color(ORANGE,0.07))
		draw_colored_polygon(bullet,ORANGE if lit else Color("2b2624"))
		bullet.append(bullet[0])
		draw_polyline(bullet,Color("ffd09a") if lit else Color("70543d"),1,true)
		draw_line(Vector2(1,19),Vector2(11,19),Color("986130") if lit else Color("584334"),1,true)
		if lit: draw_line(Vector2(3,9),Vector2(3,16),Color("ffe1b8"),1,true)
	draw_set_transform(Vector2.ZERO)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17131a")
	style.border_color = ORANGE.darkened(0.25 if hovered else 0.65)
	style.set_border_width_all(1)
	style.border_width_left = 2
	style.set_corner_radius_all(4)
	return style
