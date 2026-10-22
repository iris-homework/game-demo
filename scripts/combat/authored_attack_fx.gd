extends Node2D
## Small presentation-only effects. PNGs can replace each procedural component.
var mode := "hit"
var texture: Texture2D
var duration := 0.24
var elapsed := 0.0
var end := Vector2.ZERO
var blocked := false
var beam_width := 8.0

func _ready() -> void:
	z_index = 12
	add_to_group("authored_attack_fx")

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var t := clampf(elapsed / maxf(duration, 0.001), 0, 1)
	var fade := 1.0 - t
	var color := Color("8bdfff") if blocked else Color("ffd79b")
	color.a = fade
	if texture != null:
		var dimensions := texture.get_size() * (100.0 / maxf(texture.get_width(), texture.get_height()))
		draw_texture_rect(texture, Rect2(-dimensions * 0.5, dimensions), false, Color(1, 1, 1, fade))
		return
	match mode:
		"projectile":
			draw_line(Vector2(-26, 0), Vector2(7, 0), Color(0.4, 0.9, 1, 0.6), 5, true)
			draw_line(Vector2(-13, 0), Vector2(7, 0), Color.WHITE, 2, true)
		"laser":
			var width := beam_width * sin(PI * t)
			draw_line(Vector2.ZERO, end, Color(0.4, 0.85, 1, 0.35), maxf(0.1, width * 2), true)
			draw_line(Vector2.ZERO, end, Color(0.8, 1, 1, 0.95), maxf(0.1, width), true)
		"bite":
			# Two opposing rows close together rather than drawing a sword slash.
			var gap := lerpf(14, 3, minf(1, t * 3))
			for side in [-1, 1]:
				draw_arc(Vector2(0, side * gap), 26, 0 if side == 1 else PI, PI if side == 1 else TAU, 20, color, 2, true)
				for x in [-18, -6, 6, 18]:
					var points := PackedVector2Array([Vector2(x - 4, side * gap), Vector2(x, side * (gap - 7)), Vector2(x + 4, side * gap)])
					draw_colored_polygon(points, color)
		_:
			draw_arc(Vector2.ZERO, 7 + 24 * t, 0, TAU, 28, color, 2, true)
			for i in 7:
				var direction := Vector2.from_angle(i * TAU / 7)
				draw_line(direction * (6 + t * 14), direction * (13 + t * 32), color, 2, true)
