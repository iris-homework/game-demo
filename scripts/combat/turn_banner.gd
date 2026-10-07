extends Control
## Modal presentation only. The battle owns the action lock and round number.
var title := ""
var reveal := 0.0
var erase := 0.0
var elapsed := 0.0
var screen_material: ShaderMaterial

func play(text: String, font: Font, enemy: bool) -> void:
	title = text
	size = Vector2(1440,900)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	var accent := Color("ff3158") if enemy else Color("3d9eff")
	var text_color := Color("f5f3eb") if enemy else Color("8fcaff")
	var echo_color := Color("a371ff") if enemy else Color("597bff")
	var screen := SubViewport.new()
	screen.size = Vector2i(1000,220)
	screen.transparent_bg = true
	screen.disable_3d = true
	screen.gui_disable_input = true
	screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(screen)
	var plate := Polygon2D.new()
	plate.polygon = PackedVector2Array([Vector2(35,25),Vector2(982,25),Vector2(965,195),Vector2(18,195)])
	plate.color = Color("090b12e8")
	screen.add_child(plate)
	for y in [25,193]:
		var rail := ColorRect.new()
		rail.position = Vector2(90,y)
		rail.size = Vector2(820,2)
		rail.color = Color(accent,0.65)
		screen.add_child(rail)
	var font_size := 94
	while font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > 800.0:
		font_size -= 2
	for offset in [Vector2(-3,1),Vector2(3,-1),Vector2.ZERO]:
		var word := Label.new()
		word.text = text
		word.position = Vector2(50,30)+offset
		word.size = Vector2(900,160)
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		word.add_theme_font_override("font",font)
		word.add_theme_font_size_override("font_size",font_size)
		word.add_theme_color_override("font_color",text_color if offset == Vector2.ZERO else (accent if offset.x < 0 else echo_color))
		word.add_theme_color_override("font_outline_color",Color(accent,0.3))
		word.add_theme_constant_override("outline_size",4)
		screen.add_child(word)
	var display := TextureRect.new()
	display.texture = screen.get_texture()
	display.position = Vector2(220,340)
	display.size = Vector2(1000,220)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_material = ShaderMaterial.new()
	screen_material.shader = preload("res://shaders/turn_banner.gdshader")
	screen_material.set_shader_parameter("accent",accent)
	display.material = screen_material
	add_child(display)
	var tween := create_tween()
	tween.tween_method(set_reveal,0.0,1.0,0.34)
	tween.tween_interval(0.44)
	tween.tween_method(set_erase,0.0,1.0,0.32)
	await tween.finished

func set_reveal(value: float) -> void:
	reveal = value
	screen_material.set_shader_parameter("reveal",value)

func set_erase(value: float) -> void:
	erase = value
	screen_material.set_shader_parameter("erase",value)

func _process(delta: float) -> void:
	elapsed += delta
	if screen_material: screen_material.set_shader_parameter("clock",elapsed)
