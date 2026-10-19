extends Control
## Compact vector symbols; rules and quantities come from the battle display snapshot.
var symbol := ""
var amount := 0
var tint := Color.WHITE
var hovered := false

func setup(kind: String, count: int, color: Color, description: String) -> void:
	symbol = kind
	amount = count
	tint = color
	size = Vector2(32,32)
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = description
	mouse_entered.connect(func(): hovered = true; queue_redraw())
	mouse_exited.connect(func(): hovered = false; queue_redraw())
	queue_redraw()

func poly(points: Array, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points),color)

func _draw() -> void:
	if hovered: draw_circle(Vector2(14,14),16,Color(tint,0.16))
	match symbol:
		"strength":
			poly([Vector2(2,15),Vector2(7,15),Vector2(10,9),Vector2(14,10),Vector2(14,3),Vector2(19,3),Vector2(23,12),Vector2(23,23),Vector2(17,27),Vector2(5,26)],tint)
			draw_line(Vector2(6,21),Vector2(17,21),Color("503622"),2,true)
		"vulnerable":
			poly([Vector2(3,5),Vector2(13,1),Vector2(24,5),Vector2(22,19),Vector2(13,28),Vector2(5,21)],tint)
			draw_polyline(PackedVector2Array([Vector2(14,3),Vector2(10,12),Vector2(17,13),Vector2(11,25)]),Color("402445"),3,true)
		"pollution":
			draw_circle(Vector2(13,15),11,tint)
			for center in [Vector2(9,12),Vector2(17,12),Vector2(13,20)]:
				draw_circle(center,3,Color("233520"))
			draw_circle(Vector2(3,3),2,tint)
			draw_circle(Vector2(23,4),2,tint)
		"bleed":
			poly([Vector2(13,1),Vector2(4,15),Vector2(3,21),Vector2(8,27),Vector2(18,27),Vector2(23,21),Vector2(22,15)],tint)
			draw_line(Vector2(9,16),Vector2(7,21),Color("ffbdc5"),2,true)
		"weak":
			poly([Vector2(3,3),Vector2(12,3),Vector2(10,12),Vector2(19,10),Vector2(16,21),Vector2(24,20),Vector2(13,29),Vector2(4,21),Vector2(10,22),Vector2(11,16),Vector2(3,17)],tint)
		"parry":
			poly([Vector2(2,5),Vector2(12,1),Vector2(23,5),Vector2(21,19),Vector2(12,27),Vector2(4,20)],tint)
			draw_polyline(PackedVector2Array([Vector2(7,17),Vector2(15,9),Vector2(15,15),Vector2(20,10)]),Color("133c35"),2,true)
		"damage", "technology":
			poly([Vector2(18,1),Vector2(24,2),Vector2(23,9),Vector2(11,21),Vector2(6,16)],tint)
			draw_line(Vector2(3,15),Vector2(13,25),tint,4,true)
			draw_line(Vector2(8,21),Vector2(2,27),tint,4,true)
			if symbol == "technology": draw_circle(Vector2(22,22),4,Color("a980ff"))
		"discount", "stance_discount":
			poly([Vector2(14,1),Vector2(3,16),Vector2(12,16),Vector2(8,29),Vector2(24,10),Vector2(15,10),Vector2(20,1)],tint)
			if symbol == "stance_discount": draw_line(Vector2(3,28),Vector2(23,28),tint,2,true)
		"high_pressure":
			for x in [4,14]:
				poly([Vector2(x,8),Vector2(x+4,2),Vector2(x+8,8),Vector2(x+8,25),Vector2(x,25)],tint)
				draw_line(Vector2(x,20),Vector2(x+8,20),Color("65402b"),2,true)
		"dissection":
			draw_arc(Vector2(13,14),10,0,TAU,28,tint,2,true)
			draw_line(Vector2(13,0),Vector2(13,28),tint,2,true)
			draw_line(Vector2(0,14),Vector2(26,14),tint,2,true)
			draw_circle(Vector2(13,14),3,tint)
	var font := get_theme_font("font")
	var text := str(amount)
	var at := Vector2(32-font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x,31)
	draw_string_outline(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,5,Color("080d16"))
	draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff6df"))

func _make_custom_tooltip(text: String) -> Object:
	var box := PanelContainer.new()
	box.name = "CombatStatusTooltip"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101823")
	style.border_color = tint
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	box.add_theme_stylebox_override("panel",style)
	var content := Label.new()
	content.custom_minimum_size.x = 300
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_theme_font_override("font",get_theme_font("font"))
	content.add_theme_font_size_override("font_size",16)
	content.add_theme_color_override("font_color",Color("f5f3eb"))
	content.text = text
	box.add_child(content)
	return box
