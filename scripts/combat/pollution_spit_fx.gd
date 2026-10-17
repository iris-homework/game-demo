extends Node2D
## Opaque, outlined slime. Presentation only; impact timing never applies rules.
signal impacted
signal finished

var start := Vector2.ZERO
var end := Vector2.ZERO
var target_actor: Node2D
var target_offset := Vector2(0, -62)
var flight_time := 0.30
var splash_time := 0.40
var elapsed := 0.0
var size_factor := 1.0
var impact_emitted := false

const OUTLINE := Color("253319")
const SHADOW := Color("4c7628")
const SLIME := Color("91ba42")
const HIGHLIGHT := Color("d3e883")

func _ready() -> void:
	z_index = 9
	add_to_group("pollution_spit_fx")
	queue_redraw()

func _process(delta: float) -> void:
	if is_instance_valid(target_actor):
		end = get_parent().to_local(target_actor.to_global(target_offset))
	elapsed += delta
	if not impact_emitted and elapsed >= maxf(0.0, flight_time):
		impact_emitted = true
		impacted.emit()
	if elapsed >= maxf(0.0, flight_time) + maxf(0.0, splash_time):
		finished.emit()
		queue_free()
		return
	queue_redraw()

func _noise(index: int) -> float:
	# A local deterministic sequence must not consume combat's random stream.
	return fposmod(sin(float(index * 127 + 41)) * 43758.5453, 1.0)

func _arc(progress: float) -> Vector2:
	var distance := start.distance_to(end)
	return start.lerp(end, progress) + Vector2(0, -sin(progress * PI) * minf(34.0, distance * 0.08))

func _drop(center: Vector2, direction: Vector2, length: float, width: float, alpha: float, seed_index: int) -> void:
	if alpha <= 0.0 or width <= 0.0:
		return
	var axis := direction.normalized() if direction.length_squared() > 0.001 else Vector2.DOWN
	var normal := Vector2(-axis.y, axis.x)
	var points := PackedVector2Array()
	for i in 16:
		var angle := TAU * float(i) / 16.0
		var forward := cos(angle)
		# Rounded leading end and a tapering tail; avoid circles or light rays.
		var side := sin(angle) * width * lerpf(0.47, 1.0, (forward + 1.0) * 0.5)
		var wobble := 1.0 + (_noise(seed_index + i) - 0.5) * 0.16
		points.append(center + axis * forward * length * 0.5 + normal * side * wobble)
	draw_colored_polygon(points, Color(SHADOW, alpha))
	points.append(points[0])
	draw_polyline(points, Color(OUTLINE, alpha), maxf(1.0, size_factor * 1.6), true)
	var fill := PackedVector2Array()
	for i in 12:
		var angle := TAU * float(i) / 12.0
		fill.append(center - normal * width * 0.17 + axis * cos(angle) * length * 0.37 + normal * sin(angle) * width * 0.66)
	draw_colored_polygon(fill, Color(SLIME, alpha))
	draw_line(center - axis * length * 0.15 - normal * width * 0.36,
		center + axis * length * 0.13 - normal * width * 0.40,
		Color(HIGHLIGHT, alpha * 0.85), maxf(0.8, size_factor * 1.3), true)

func _draw_flight() -> void:
	var progress := clampf(elapsed / maxf(0.001, flight_time), 0.0, 1.0)
	var scale_value := maxf(0.1, size_factor)
	var direction := (end - start).normalized()
	var normal := Vector2(-direction.y, direction.x)
	# A short, uneven liquid body travels as a packet, with detached trailing drops.
	for i in 5:
		var delay := float(i) * 0.044
		var sample := maxf(0.0, progress - delay)
		if progress < delay:
			continue
		var point := _arc(sample) + normal * sin(float(i) * 2.1 + progress * 7.0) * 2.8 * scale_value
		var tangent := _arc(minf(1.0, sample + 0.02)) - _arc(maxf(0.0, sample - 0.02))
		_drop(point, tangent, (24.0 - float(i) * 3.3) * scale_value,
			(6.7 - float(i) * 0.8) * scale_value, 1.0 - float(i) * 0.075, 20 + i * 17)
	for i in 5:
		var delay := 0.07 + float(i) * 0.038
		if progress < delay:
			continue
		var sample := maxf(0.0, progress - delay)
		var scatter := (6.0 + _noise(i + 140) * 7.0) * sin(sample * PI)
		var point := _arc(sample) + normal * scatter * (-1.0 if i % 2 == 0 else 1.0) * scale_value
		_drop(point, direction, (6.0 + _noise(i + 160) * 5.0) * scale_value,
			(1.8 + _noise(i + 180) * 1.4) * scale_value, 0.85, 200 + i * 17)

func _draw_splash() -> void:
	var age := maxf(0.0, elapsed - maxf(0.0, flight_time))
	var progress := clampf(age / maxf(0.001, splash_time), 0.0, 1.0)
	var scale_value := maxf(0.1, size_factor)
	var fade := 1.0 - smoothstep(0.40, 1.0, progress)
	var expansion := 1.0 - pow(1.0 - progress, 3.0)
	var direction := (end - start).normalized()
	if direction.length_squared() < 0.001:
		direction = Vector2.LEFT
	# Close bite contacts retain only a short remnant of the spit at the target.
	if flight_time <= 0.0 and age < 0.10:
		var trace_alpha := (1.0 - age / 0.10) * 0.85
		var trace_length := minf(34.0 * scale_value, start.distance_to(end))
		_drop(end - direction * trace_length * 0.48, direction, trace_length,
			3.8 * scale_value, trace_alpha, 290)
	# Uneven small lobes wet the torso rather than covering it with a round flash.
	for i in 7:
		var angle := float(i) * 2.39996 + 0.3
		var ray := Vector2.from_angle(angle)
		var offset := ray * (3.0 + _noise(i + 320) * 9.0) * (0.68 + expansion * 0.32)
		offset.y += progress * (3.0 + _noise(i + 340) * 5.0)
		_drop(end + offset * scale_value, ray,
			(13.0 + _noise(i + 360) * 9.0) * scale_value,
			(3.8 + _noise(i + 380) * 2.4) * scale_value, fade * 0.94, 400 + i * 17)
	# Detached splash droplets arc outwards and fall, with no radial glow.
	for i in 11:
		var angle := float(i) * 2.39996 + 0.7
		var ray := Vector2.from_angle(angle)
		var speed := 21.0 + _noise(i + 550) * 19.0
		var offset := ray * (7.0 + expansion * speed)
		offset.y += progress * progress * 24.0
		var motion := ray + Vector2(0, progress * 0.9)
		var radius := (1.8 + _noise(i + 580) * 1.6) * (1.0 - progress * 0.35)
		_drop(end + offset * scale_value, motion, radius * 3.0 * scale_value,
			radius * scale_value, fade * 0.95, 610 + i * 17)
	# Hanging drips extend downward on the clothing and fade with the stain.
	for i in 4:
		var point := end + Vector2(-11.0 + float(i) * 7.0, 6.0 + _noise(i + 820) * 5.0) * scale_value
		var drip_length := (5.0 + expansion * (8.0 + _noise(i + 840) * 12.0)) * scale_value
		var bottom := point + Vector2(0, drip_length)
		draw_line(point, bottom, Color(OUTLINE, fade * 0.92), 4.0 * scale_value, true)
		draw_line(point, bottom, Color(SLIME, fade * 0.95), 2.0 * scale_value, true)
		_drop(bottom, Vector2.DOWN, 6.0 * scale_value, 2.5 * scale_value, fade, 870 + i * 17)

func _draw() -> void:
	if flight_time > 0.0 and elapsed < flight_time:
		_draw_flight()
	else:
		_draw_splash()
