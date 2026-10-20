extends Node2D
## A continuous ray through the target to beyond the viewport. Presentation only.
signal finished
const CHARGE_TIME := 0.22
const GROW_TIME := 0.20
const HOLD_TIME := 0.13
const FADE_TIME := 0.17
const DURATION := CHARGE_TIME + GROW_TIME + HOLD_TIME + FADE_TIME
var start := Vector2.ZERO
var target := Vector2.ZERO
# Total visible diameter, including glow, never exceeds the calibrated palm width.
var max_width := 16.0
var elapsed := 0.0
var blocked := false
var manual := false

func _ready() -> void:
	z_index = 10
	add_to_group("palm_laser_fx")
	queue_redraw()

func width_at(time: float) -> float:
	var thin := minf(0.8, max_width * 0.06)
	if time < CHARGE_TIME: return thin
	if time < CHARGE_TIME + GROW_TIME:
		var t := clampf((time - CHARGE_TIME) / GROW_TIME, 0.0, 1.0)
		return lerpf(thin, max_width, t * t * (3.0 - 2.0 * t))
	if time < CHARGE_TIME + GROW_TIME + HOLD_TIME: return max_width
	return max_width * pow(clampf((DURATION - time) / FADE_TIME, 0.0, 1.0), 1.5)

func ray_end() -> Vector2:
	# More than two screen diagonals at the widest camera; never stop at the target.
	return start + (target - start).normalized() * maxf(4096.0, start.distance_to(target) + 2048.0)

func _process(delta: float) -> void:
	if not manual:
		elapsed += delta
		if elapsed >= DURATION:
			finished.emit()
			queue_free()
			return
	queue_redraw()

func _draw() -> void:
	if start.is_equal_approx(target): return
	var end := ray_end()
	var axis := (target - start).normalized()
	var normal := axis.orthogonal()
	var width := width_at(elapsed)
	var firing := elapsed >= CHARGE_TIME
	var fade := clampf((DURATION - elapsed) / FADE_TIME, 0.0, 1.0)
	var alpha := fade if firing else 0.22 + 0.24 * elapsed / CHARGE_TIME
	# All glow layers stay inside the width cap; no broad bloom outside the palm.
	for layer in [[1.0, Color("ff259f"), 0.30], [0.72, Color("ff37c8"), 0.80], [0.44, Color("ffb8f1"), 0.95], [0.20, Color.WHITE, 1.0]]:
		draw_line(start, end, Color(layer[1], alpha * layer[2]), maxf(0.15, width * layer[0]), true)
	if firing:
		# Two restrained moving filaments give the body energy without widening it.
		for sign_value in [-1.0, 1.0]:
			var points := PackedVector2Array()
			for i in 65:
				var distance := float(i) / 64.0 * start.distance_to(end)
				var ripple := sin(distance * 0.08 - elapsed * 42.0 + sign_value) * width * 0.045
				points.append(start + axis * distance + normal * (width * 0.28 * sign_value + ripple))
			draw_polyline(points, Color(1.0, 0.7, 0.94, alpha * 0.6), maxf(0.25, width * 0.035), true)
	var charge := clampf(elapsed / CHARGE_TIME, 0.0, 1.0)
	var radius := max_width * (0.16 + charge * 0.31) * fade
	draw_circle(start, radius, Color(1.0, 0.09, 0.63, alpha * 0.40))
	draw_arc(start, radius * 0.85, elapsed * 7.0, elapsed * 7.0 + TAU * 0.86, 32, Color(1.0, 0.6, 0.93, alpha), maxf(0.6, max_width * 0.045), true)
	draw_circle(start, radius * 0.36, Color(1.0, 0.95, 1.0, alpha))
	if elapsed >= CHARGE_TIME + GROW_TIME:
		var impact := clampf((elapsed - CHARGE_TIME - GROW_TIME) / (HOLD_TIME + FADE_TIME), 0.0, 1.0)
		var color := Color("a3dfff") if blocked else Color("ff86d9")
		# A compact contact flare leaves the continuing beam visible beyond the body.
		for i in 10:
			var angle := float(i) * 2.39996
			var ray := Vector2.from_angle(angle)
			var point := target + ray * max_width * (0.15 + impact * 0.75)
			draw_line(point, point + ray * max_width * 0.24 * (1.0 - impact), Color(color, (1.0 - impact) * 0.85), 1.0, true)
