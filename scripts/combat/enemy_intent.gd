extends Control
## Head icon and per-hit value. The caller supplies the model's read-only preview.
const DIMENSIONS := Vector2(96,66)
var kind := ""
var value_label: Label
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
	kind = str(intent.get("type",""))
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
	queue_redraw()

func silhouette(points: Array, color: Color) -> void:
	var polygon := PackedVector2Array(points)
	var edge := polygon.duplicate()
	edge.append(polygon[0])
	draw_polyline(edge,Color("1c1729"),5,true)
	draw_colored_polygon(polygon,color)
	draw_polyline(edge,color.darkened(0.25),1.2,true)

func _draw() -> void:
	draw_set_transform(Vector2((DIMENSIONS.x-40)/2,1))
	match kind:
		"attack":
			# Curved red blade, point upper-left and hilt lower-right.
			silhouette([Vector2(4,1),Vector2(4,11),Vector2(8,20),Vector2(15,27),Vector2(26,30),Vector2(30,25),Vector2(21,20),Vector2(15,14),Vector2(11,6)],Color("f74e76"))
			draw_polyline(PackedVector2Array([Vector2(6,6),Vector2(8,15),Vector2(14,23),Vector2(23,27)]),Color("ffacb8"),2,true)
			draw_line(Vector2(25,29),Vector2(34,36),Color("25172c"),8,true)
			draw_line(Vector2(25,29),Vector2(34,36),Color("ea4870"),4,true)
			draw_line(Vector2(22,33),Vector2(32,23),Color("25172c"),8,true)
			draw_line(Vector2(22,33),Vector2(32,23),Color("ff6b8b"),4,true)
			draw_circle(Vector2(35,36),3,Color("f96586"))
		"fortify":
			silhouette([Vector2(5,5),Vector2(20,1),Vector2(35,5),Vector2(32,24),Vector2(20,36),Vector2(8,24)],Color("73cafa"))
			draw_line(Vector2(20,27),Vector2(20,10),Color("ffe2a1"),4,true)
			draw_polyline(PackedVector2Array([Vector2(13,17),Vector2(20,10),Vector2(27,17)]),Color("ffe2a1"),4,true)
		"energy_suit":
			silhouette([Vector2(12,2),Vector2(4,8),Vector2(9,18),Vector2(9,35),Vector2(31,35),Vector2(31,18),Vector2(36,8),Vector2(28,2),Vector2(25,10),Vector2(15,10)],Color("81e4d4"))
			draw_polyline(PackedVector2Array([Vector2(22,14),Vector2(16,23),Vector2(24,23),Vector2(18,31)]),Color("245e6d"),3,true)
		"charge":
			silhouette([Vector2(22,1),Vector2(6,21),Vector2(18,21),Vector2(14,37),Vector2(35,13),Vector2(23,13),Vector2(28,1)],Color("75dfff"))
			draw_line(Vector2(21,9),Vector2(14,18),Color("ddfaff"),2,true)
		"strength_allies":
			silhouette([Vector2(9,34),Vector2(9,18),Vector2(2,18),Vector2(20,2),Vector2(38,18),Vector2(31,18),Vector2(31,34)],Color("f3bb56"))
			draw_polyline(PackedVector2Array([Vector2(9,16),Vector2(20,6),Vector2(31,16)]),Color("ffe7a5"),2,true)
			draw_line(Vector2(15,23),Vector2(25,23),Color("a36339"),2,true)
		"vulnerable":
			silhouette([Vector2(4,7),Vector2(20,2),Vector2(36,7),Vector2(32,26),Vector2(20,36),Vector2(8,26)],Color("c78dea"))
			draw_polyline(PackedVector2Array([Vector2(22,4),Vector2(16,15),Vector2(24,18),Vector2(17,32)]),Color("4e285e"),4,true)
			draw_line(Vector2(8,9),Vector2(16,6),Color("f1ccff"),2,true)
		"pollution":
			silhouette([Vector2(20,2),Vector2(10,15),Vector2(6,24),Vector2(8,31),Vector2(14,36),Vector2(26,36),Vector2(33,30),Vector2(34,23),Vector2(29,14)],Color("a6d76c"))
			draw_arc(Vector2(20,24),9,2.6,4.0,12,Color("e2f5ab"),2,true)
			for center in [Vector2(16,23),Vector2(25,24),Vector2(20,30)]:
				draw_circle(center,2.5,Color("456046"))
		"weak":
			silhouette([Vector2(7,3),Vector2(10,17),Vector2(18,25),Vector2(27,27),Vector2(32,33),Vector2(37,28),Vector2(29,21),Vector2(25,14),Vector2(18,10),Vector2(18,2),Vector2(13,13)],Color("e5a06b"))
			draw_line(Vector2(4,31),Vector2(17,31),Color("f4c79f"),3,true)
			draw_line(Vector2(9,26),Vector2(9,36),Color("f4c79f"),3,true)
		"heal_ally":
			silhouette([Vector2(13,2),Vector2(27,2),Vector2(27,13),Vector2(38,13),Vector2(38,27),Vector2(27,27),Vector2(27,38),Vector2(13,38),Vector2(13,27),Vector2(2,27),Vector2(2,13),Vector2(13,13)],Color("81d6a5"))
			draw_line(Vector2(16,7),Vector2(24,7),Color("d4ffe3"),2,true)
		_:
			draw_circle(Vector2(20,19),12,Color("1c1729"))
			for x in [12,20,28]: draw_circle(Vector2(x,19),2,Color("e8d4ff"))
