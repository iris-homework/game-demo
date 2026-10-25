extends Node2D
## Three foot-anchored pools and softly layered theatrical beams; presentation only.
const REVEAL_DURATION := 0.65

var actors: Array[Node2D] = []
var reveal_progress := 1.0
var _reveal_tween: Tween

func flash_on() -> Tween:
	if is_instance_valid(_reveal_tween):
		_reveal_tween.kill()
	# Switch on at peak intensity; only the excess light fades back to the steady look.
	reveal_progress = 0.0
	queue_redraw()
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(self, "reveal_progress", 1.0, REVEAL_DURATION).set_trans(Tween.TRANS_LINEAR)
	return _reveal_tween

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var progress := clampf(reveal_progress, 0.0, 1.0)
	var surge := (1.0 - progress) * (1.0 - progress)
	for i in actors.size():
		var actor := actors[i]
		if not is_instance_valid(actor) or not actor.visible or not actor.alive: continue
		var foot := to_local(actor.to_global(Vector2.ZERO))
		var tint := Color("c9dbff") if i == 0 else (Color("fff0ce") if i == 1 else Color("efdcff"))
		var lamp := Vector2(foot.x + (-110.0 if i == 0 else 110.0), -170)
		for layer in range(8, 0, -1):
			var width := (76.0 + layer * 7.0) * (1.0 + 0.22 * surge)
			var color := Color(tint, (0.028 + 0.030 * surge) * actor.modulate.a)
			draw_colored_polygon(PackedVector2Array([lamp-Vector2(7,0),lamp+Vector2(7,0),foot+Vector2(width,9),foot-Vector2(width,-9)]),color)
		for layer in range(10, 0, -1):
			var radius := Vector2(69 + layer * 4, 13 + layer * 2)
			draw_colored_polygon(_ellipse_points(foot, radius),Color(tint,(0.040 + 0.028 * surge) * actor.modulate.a))
		if surge > 0.0:
			_draw_reveal(foot, lamp, progress, surge, actor.modulate.a)

func _draw_reveal(foot: Vector2, lamp: Vector2, progress: float, surge: float, actor_alpha: float) -> void:
	# A translucent warm core keeps the ink silhouettes readable beneath the light.
	for layer in range(3, 0, -1):
		var core_width := (38.0 + layer * 12.0) * (1.0 + 0.12 * surge)
		var core := PackedVector2Array([lamp-Vector2(4,0),lamp+Vector2(4,0),foot+Vector2(core_width,8),foot-Vector2(core_width,-8)])
		draw_colored_polygon(core, Color(1.0, 0.96, 0.84, 0.032 * surge * actor_alpha))
	# One soft ring expands on the floor, while its intensity falls from the first frame.
	var ring_radius := Vector2(94.0, 22.0).lerp(Vector2(184.0, 43.0), progress)
	var ring := _ellipse_points(foot, ring_radius)
	ring.append(ring[0])
	for layer in range(5, 0, -1):
		draw_polyline(ring, Color(1.0, 0.94, 0.79, 0.040 * surge * actor_alpha), 2.0 + layer * 2.8, true)

func _ellipse_points(center: Vector2, radius: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in 48:
		points.append(center + Vector2(cos(step*TAU/48), sin(step*TAU/48))*radius)
	return points
