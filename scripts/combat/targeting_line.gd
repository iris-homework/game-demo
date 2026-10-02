extends Node2D
## Canvas coordinates; no input surface, so the pointer can still click targets.
var origin := Vector2.ZERO
var tip := Vector2.ZERO
var target_center := Vector2.ZERO
var locked := false
var phase := 0.0

func _process(delta: float) -> void:
	if visible:
		phase = fmod(phase + delta * 0.8, 1.0)
		queue_redraw()

func curve(t: float) -> Vector2:
	var bend := Vector2(origin.x, minf(origin.y, tip.y) - minf(170.0, origin.distance_to(tip) * 0.3))
	return origin * (1.0-t) * (1.0-t) + bend * 2.0 * (1.0-t) * t + tip * t * t

func _draw() -> void:
	if origin.distance_to(tip) < 18: return
	var color := Color("ff609e") if locked else Color("58e1eb")
	var points := PackedVector2Array()
	for i in range(41): points.append(curve(i / 40.0))
	draw_polyline(points, Color(color, 0.08), 15.0, true)
	draw_polyline(points, Color(color, 0.22), 7.0, true)
	draw_polyline(points, color, 2.3, true)
	for i in range(4):
		var p := curve(fmod(phase + i * 0.25, 1.0))
		draw_circle(p, 3.0, Color("e6ffff"))
	var direction := (tip - curve(0.96)).normalized()
	var normal := direction.orthogonal()
	var head := PackedVector2Array([tip, tip-direction*22+normal*10, tip-direction*16, tip-direction*22-normal*10])
	draw_colored_polygon(head, color)
	draw_circle(origin, 5, color)
	if locked:
		var radius := 33.0 + sin(phase * TAU) * 2.0
		for i in range(4):
			var angle := PI * 0.5 * i + 0.16
			draw_arc(target_center, radius, angle, angle + 0.9, 12, color, 2, true)
		draw_line(target_center-Vector2(9,0), target_center+Vector2(9,0), Color(color,0.7),1.5,true)
		draw_line(target_center-Vector2(0,9), target_center+Vector2(0,9), Color(color,0.7),1.5,true)
