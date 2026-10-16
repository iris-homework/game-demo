extends Control
## Screen-space health and statuses, anchored to the actor's projected feet.
const Badge = preload("res://scripts/combat/status_badge.gd")
const WIDTH := 196.0
var hp := 0
var max_hp := 1
var block := 0
var statuses: Array = []
var badges: Array[Control] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(WIDTH,38)

func update_values(health: int, maximum: int, guard: int, effects: Array) -> void:
	hp = health
	max_hp = maxi(1,maximum)
	block = maxi(0,guard)
	if statuses != effects:
		statuses = effects.duplicate(true)
		for badge in badges:
			remove_child(badge)
			badge.queue_free()
		badges.clear()
		for i in effects.size():
			var effect: Dictionary = effects[i]
			var badge := Badge.new()
			add_child(badge)
			badge.position = Vector2(2+(i%6)*32,34+floori(i/6.0)*33)
			badge.setup(effect.id,effect.count,Color(effect.color),effect.description)
			badges.append(badge)
	size.y = 34+ceilf(effects.size()/6.0)*33
	queue_redraw()

func bar_shape(left: float, right: float, top: float, bottom: float) -> PackedVector2Array:
	var bevel := minf(5,(right-left)/2)
	return PackedVector2Array([Vector2(left, (top+bottom)/2),Vector2(left+bevel,top),Vector2(right-bevel,top),Vector2(right,(top+bottom)/2),Vector2(right-bevel,bottom),Vector2(left+bevel,bottom)])

func outlined_text(text: String, center: Vector2, font_size: int, color: Color, outline_size: int = 6) -> void:
	var font := get_theme_font("font")
	var at := center-Vector2(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x/2,0)
	if outline_size > 0: draw_string_outline(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,outline_size,Color("081019"))
	draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw() -> void:
	var protected := block > 0
	var end := 3+(WIDTH-6)*clampf(float(hp)/max_hp,0,1)
	if protected:
		# Cool rim, recessed navy track and a softly lit blue fill.
		draw_colored_polygon(bar_shape(-1,WIDTH+1,7,25),Color("203e53"))
		draw_colored_polygon(bar_shape(0,WIDTH,8,24),Color("92cce5"))
		draw_colored_polygon(bar_shape(2,WIDTH-2,10,22),Color("15374d"))
		if end > 3:
			draw_polygon(bar_shape(3,end,11,21),PackedColorArray([Color("477fa5"),Color("76b1d2"),Color("76b1d2"),Color("477fa5"),Color("305e84"),Color("305e84")]))
			if end > 14: draw_line(Vector2(8,11),Vector2(end-5,11),Color("96c5df"),1,true)
		draw_line(Vector2(6,9),Vector2(WIDTH-6,9),Color("c2e6f2"),1,true)
		draw_line(Vector2(6,23),Vector2(WIDTH-6,23),Color("6ca4c5"),1,true)
		draw_polyline(PackedVector2Array([Vector2(WIDTH-6,9),Vector2(WIDTH-1,16),Vector2(WIDTH-6,23)]),Color("acdaed"),1,true)
	else:
		draw_colored_polygon(bar_shape(0,WIDTH,8,24),Color("542b38"))
		draw_colored_polygon(bar_shape(3,WIDTH-3,11,21),Color("0c1c25"))
		if end > 3:
			draw_colored_polygon(bar_shape(3,end,11,21),Color("e92f50"))
			if end > 14: draw_line(Vector2(8,12),Vector2(end-5,12),Color("e92f50").lightened(0.3),1,true)
	outlined_text("%d/%d" % [hp,max_hp],Vector2(WIDTH/2,25),22,Color("fff5e8"))
	if protected:
		var shield := PackedVector2Array([Vector2(-13,3),Vector2(3,-1),Vector2(19,3),Vector2(16,23),Vector2(3,34),Vector2(-10,23)])
		draw_colored_polygon(shield,Color("28668c"))
		# Facets retain a solid face: brighter upper-left, shaded right, light lower tip.
		draw_colored_polygon(PackedVector2Array([Vector2(-13,3),Vector2(3,-1),Vector2(3,32),Vector2(-10,23)]),Color("438fab"))
		draw_colored_polygon(PackedVector2Array([Vector2(3,-1),Vector2(19,3),Vector2(16,23),Vector2(3,32)]),Color("286b96"))
		draw_colored_polygon(PackedVector2Array([Vector2(-13,3),Vector2(3,-1),Vector2(-5,10)]),Color("70b4cf"))
		draw_colored_polygon(PackedVector2Array([Vector2(3,-1),Vector2(19,3),Vector2(13,9)]),Color("4c98be"))
		draw_colored_polygon(PackedVector2Array([Vector2(-10,23),Vector2(3,26),Vector2(3,34)]),Color("83c1d7"))
		draw_colored_polygon(PackedVector2Array([Vector2(3,26),Vector2(16,23),Vector2(3,34)]),Color("387ba0"))
		draw_polyline(PackedVector2Array([Vector2(-10,23),Vector2(-13,3),Vector2(3,-1),Vector2(19,3)]),Color("b2ddec"),1.2,true)
		draw_polyline(PackedVector2Array([Vector2(19,3),Vector2(16,23),Vector2(3,34),Vector2(-10,23)]),Color("76b4d1"),1,true)
		draw_line(Vector2(3,0),Vector2(3,8),Color("a2d3e5"),1,true)
		# Three digits may reach the silhouette; avoid a thick text outline.
		var text := str(block)
		var font := get_theme_font("font")
		var font_size := 18
		while font_size > 1 and font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > 28:
			font_size -= 1
		outlined_text(text,Vector2(3,14+font_size*0.375),font_size,Color("e5f6f3"),1)
