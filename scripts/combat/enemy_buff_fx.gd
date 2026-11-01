extends Node2D
## One cosmetic upward arrow, in actor space so formation and camera motion stay aligned.
var body_bounds := Rect2(-58, -130, 116, 145)
var duration := 0.9
var progress := 0.0
var surface := GradientTexture2D.new()

func _ready() -> void:
	add_to_group("enemy_buff_fx")
	z_index = 20
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE])
	surface.gradient = gradient
	var soft_gold := ShaderMaterial.new()
	soft_gold.shader = preload("res://shaders/enemy_buff_arrow.gdshader")
	material = soft_gold

func _process(delta: float) -> void:
	# A defeated actor can remain on stage during its death animation.
	if not get_parent().alive:
		queue_free()
		return
	progress = minf(1.0, progress + delta / duration)
	queue_redraw()
	if progress >= 1.0: queue_free()

func restart(bounds: Rect2) -> void:
	body_bounds = bounds
	progress = 0.0
	queue_redraw()

func _draw() -> void:
	var center := body_bounds.get_center()
	var rise := clampf(body_bounds.size.y * 0.32, 34.0, 65.0)
	var arrow_scale := clampf(body_bounds.size.y / 150.0, 0.8, 1.2)
	var t := progress
	var opacity := smoothstep(0.0, 0.28, t) * (1.0 - smoothstep(0.42, 1.0, t))
	var origin := center + Vector2(0, rise * (0.50 - t) - 12.0)
	draw_set_transform(origin, 0.0, Vector2.ONE * arrow_scale)
	draw_texture_rect(surface, Rect2(-36,-44,72,88), false, Color(1,1,1,opacity))
	draw_set_transform(Vector2.ZERO)
