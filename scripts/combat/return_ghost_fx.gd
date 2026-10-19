extends Node2D
## Temporary copies of the calibrated idle silhouette. No actor/model ownership.
var progress := 0.0
var echoes: Array[Sprite2D] = []
var origins: Array[Vector2] = []
const COLORS := [Color("46ffef",0.44),Color("ff4dbc",0.42),Color("afa0ff",0.70)]
const OFFSETS := [-8.0,7.0,0.0]

func setup(source: Sprite2D, white_key_enabled: bool = false) -> void:
	for i in 3:
		var echo := Sprite2D.new()
		echo.texture = source.texture
		echo.centered = source.centered
		echo.position = source.position
		echo.scale = source.scale
		var shader_material := ShaderMaterial.new()
		shader_material.shader = preload("res://shaders/return_ghost.gdshader")
		shader_material.set_shader_parameter("neon_color",COLORS[i])
		shader_material.set_shader_parameter("seed",float(i)*13.0)
		shader_material.set_shader_parameter("white_key_enabled",white_key_enabled)
		echo.material = shader_material
		add_child(echo)
		echoes.append(echo)
		origins.append(source.position)
	set_progress(0.0)

func set_progress(value: float) -> void:
	progress = value
	for i in echoes.size():
		echoes[i].position = origins[i]+Vector2(OFFSETS[i]*(1-progress),0)
		echoes[i].material.set_shader_parameter("progress",progress)
	queue_redraw()

func _draw() -> void:
	var fade := sin(PI*progress)*0.7
	for i in 7:
		var y := -12.0-i*17.0
		var jitter := sin(floor(progress*20)*2.4+i*9.1)
		var x := (-34 if i%2 == 0 else 27)+jitter*9
		var tint: Color = COLORS[i%3]
		tint.a = fade*0.60
		draw_rect(Rect2(x,y,8+absf(jitter)*14,1.5),tint)
