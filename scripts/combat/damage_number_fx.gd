extends Node2D
## Local neon typography only; combat has already resolved before this spawns.
const CYAN := Color("64ffe1")
const WHITE := Color("fff7ef")
var font: Font
var value := ""
var suffix := ""
var accent := Color("ff3158")
var elapsed := 0.0
var duration := 0.64
var anchor := Vector2.ZERO
var drift := 0.0
var text_width := 0.0
const FONT_SIZE := 64

func start(text: String, typeface: Font, color: Color, origin: Vector2, lane: int) -> void:
	font = typeface
	value = text.trim_suffix(" HP")
	suffix = "HP" if text.ends_with(" HP") else ""
	accent = color
	anchor = origin
	drift = float(lane)*72.0
	text_width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,FONT_SIZE).x
	position = origin+Vector2(drift,-18)
	z_index = 52
	add_to_group("combat_damage_numbers")
	update_pose()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	update_pose()

func update_pose() -> void:
	# One bright attack pulse, then a stable reading phase and upward decay.
	var pop := clampf(elapsed/0.075,0.0,1.0)
	var settle := smoothstep(0.075,0.19,elapsed)
	var zoom := lerpf(0.65,1.24,1.0-pow(1.0-pop,3.0))-settle*0.24
	scale = Vector2.ONE*zoom
	rotation = lerpf(-0.10,0.0,smoothstep(0.0,0.20,elapsed))
	position = anchor+Vector2(drift*(1.0+elapsed*0.35),-18.0-76.0*(1.0-pow(1.0-elapsed/duration,2.0)))
	modulate.a = 1.0-smoothstep(0.37,duration,elapsed)
	queue_redraw()

func _draw() -> void:
	if font == null: return
	var baseline := Vector2(-text_width*0.5,22)
	var pulse := 1.0-smoothstep(0.02,0.15,elapsed)
	var split := (1.0-smoothstep(0.04,0.19,elapsed))*7.0
	var radius := text_width*0.5+12.0
	# Short slash glints and sparks sit behind the glyph, preserving its shape.
	for i in range(8):
		var direction := Vector2.from_angle(float(i)*TAU/8.0+0.18)
		var start := direction*(radius+elapsed*64.0)
		var end := start+direction*(9.0+18.0*pulse)
		draw_line(start,end,Color(CYAN if i%2 == 0 else accent,(1.0-smoothstep(0.08,0.33,elapsed))*0.8),2.0,true)
	if pulse > 0.0:
		draw_line(Vector2(-radius-32,13),Vector2(radius+30,-13),Color(accent,pulse*0.13),13.0,true)
		draw_line(Vector2(-radius-32,13),Vector2(radius+30,-13),Color(WHITE,pulse*0.75),2.0,true)
	# Layered font outlines provide glow in Compatibility without bloom.
	font.draw_string_outline(get_canvas_item(),baseline,value,HORIZONTAL_ALIGNMENT_LEFT,-1,FONT_SIZE,14,Color(accent,0.10+0.08*pulse))
	font.draw_string_outline(get_canvas_item(),baseline,value,HORIZONTAL_ALIGNMENT_LEFT,-1,FONT_SIZE,8,Color(accent,0.25))
	font.draw_string(get_canvas_item(),baseline+Vector2(-split-2,1),value,HORIZONTAL_ALIGNMENT_LEFT,-1,FONT_SIZE,Color(CYAN,0.8))
	font.draw_string(get_canvas_item(),baseline+Vector2(split+2,-1),value,HORIZONTAL_ALIGNMENT_LEFT,-1,FONT_SIZE,Color(accent,0.8))
	font.draw_string_outline(get_canvas_item(),baseline,value,HORIZONTAL_ALIGNMENT_LEFT,-1,FONT_SIZE,3,accent)
	font.draw_string(get_canvas_item(),baseline,value,HORIZONTAL_ALIGNMENT_LEFT,-1,FONT_SIZE,WHITE)
	var underline_y := 30.0
	draw_line(Vector2(-radius*0.65,underline_y),Vector2(radius*0.65,underline_y-3),Color(CYAN,0.7),1.5,true)
	if not suffix.is_empty():
		var width := font.get_string_size(suffix,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
		font.draw_string_outline(get_canvas_item(),Vector2(-width*0.5,48),suffix,HORIZONTAL_ALIGNMENT_LEFT,-1,15,3,Color("090b12"))
		font.draw_string(get_canvas_item(),Vector2(-width*0.5,48),suffix,HORIZONTAL_ALIGNMENT_LEFT,-1,15,CYAN)
