extends Node2D
## A copied fish silhouette breaks apart into green liquid. Presentation only.
signal finished

const BURST_TIME := 0.035
const DURATION := 0.48
const SPRAY_SPREAD := 1.7
const COLUMNS := 5
const ROWS := 4
const OUTLINE := Color("253319")
const SHADOW := Color("4c7628")
const SLIME := Color("91ba42")
const HIGHLIGHT := Color("d3e883")

var elapsed := 0.0
var prepared := false
var silhouette: Sprite2D
var fragments: Array[Sprite2D] = []
var origins: Array[Vector2] = []
var velocities: Array[Vector2] = []
var spins: Array[float] = []
var fragment_scale := Vector2.ONE
var source_rotation := 0.0
var source_position := Vector2.ZERO
var center := Vector2(0, -58)
var body_size := Vector2(140, 110)
var liquid_scale := 1.0

func _ready() -> void:
	z_index = 9
	add_to_group("fish_death_burst_fx")

func setup_sprite(source: Sprite2D) -> void:
	if prepared or not is_instance_valid(source) or source.texture == null:
		return
	texture_filter = source.texture_filter
	fragment_scale = source.scale
	source_rotation = source.rotation
	source_position = source.position
	silhouette = Sprite2D.new()
	silhouette.texture = source.texture
	silhouette.centered = source.centered
	silhouette.offset = source.offset
	silhouette.transform = source.transform
	silhouette.flip_h = source.flip_h
	silhouette.flip_v = source.flip_v
	silhouette.region_enabled = source.region_enabled
	silhouette.region_rect = source.region_rect
	silhouette.hframes = source.hframes
	silhouette.vframes = source.vframes
	silhouette.frame = source.frame
	silhouette.z_index = -1
	add_child(silhouette)
	# Pose sprites use the entire image. Trim transparent canvas only for dividing
	# the silhouette, so the burst originates across the body, fins and head.
	var texture_rect := Rect2(Vector2.ZERO, source.texture.get_size())
	if source.region_enabled:
		texture_rect = source.region_rect
	elif source.hframes > 1 or source.vframes > 1:
		var frame_size := source.texture.get_size() / Vector2(source.hframes, source.vframes)
		texture_rect = Rect2(Vector2(source.frame_coords) * frame_size, frame_size)
	var used_rect := texture_rect
	var source_image := source.texture.get_image()
	if source_image != null:
		var opaque_rect := Rect2(source_image.get_used_rect()).intersection(texture_rect)
		if opaque_rect.has_area():
			used_rect = opaque_rect
	var draw_rect := source.get_rect()
	var local_center := _texture_to_local(used_rect.get_center(), texture_rect, draw_rect, source)
	center = source.transform * local_center
	body_size = used_rect.size * source.scale.abs()
	liquid_scale = clampf(maxf(body_size.x / 160.0, body_size.y / 125.0), 0.65, 1.65)
	for row in ROWS:
		for column in COLUMNS:
			var index := row * COLUMNS + column
			var cell_size := used_rect.size / Vector2(COLUMNS, ROWS)
			var cell := Rect2(used_rect.position + Vector2(column, row) * cell_size, cell_size)
			var fragment := Sprite2D.new()
			fragment.texture = source.texture
			fragment.region_enabled = true
			fragment.region_rect = cell
			fragment.region_filter_clip_enabled = true
			fragment.flip_h = source.flip_h
			fragment.flip_v = source.flip_v
			fragment.scale = fragment_scale
			fragment.rotation = source_rotation
			fragment.position = source.transform * _texture_to_local(cell.get_center(), texture_rect, draw_rect, source)
			fragment.visible = false
			fragment.z_index = -1
			add_child(fragment)
			fragments.append(fragment)
			origins.append(fragment.position)
			var ray := (fragment.position - center).normalized()
			if ray.length_squared() < 0.01:
				ray = Vector2.from_angle(_noise(index + 12) * TAU)
			velocities.append((ray * (200.0 + _noise(index + 60) * 170.0) + Vector2(0, -58)) * liquid_scale)
			spins.append((_noise(index + 110) - 0.5) * 17.0)
	prepared = true
	_update_visuals()

func _texture_to_local(point: Vector2, texture_rect: Rect2, draw_rect: Rect2, source: Sprite2D) -> Vector2:
	var relative := (point - texture_rect.position) / texture_rect.size
	if source.flip_h:
		relative.x = 1.0 - relative.x
	if source.flip_v:
		relative.y = 1.0 - relative.y
	return draw_rect.position + relative * draw_rect.size

func _process(delta: float) -> void:
	if not prepared:
		return
	elapsed += delta
	if elapsed >= DURATION:
		finished.emit()
		queue_free()
		return
	_update_visuals()

func _update_visuals() -> void:
	var swelling := 1.0 + 0.15 * clampf(elapsed / BURST_TIME, 0.0, 1.0)
	silhouette.visible = elapsed < BURST_TIME
	silhouette.scale = fragment_scale * swelling
	silhouette.position = center + (source_position - center) * swelling
	var age := maxf(0.0, elapsed - BURST_TIME)
	var progress := age / (DURATION - BURST_TIME)
	for i in fragments.size():
		var fragment := fragments[i]
		fragment.visible = elapsed >= BURST_TIME
		fragment.position = center + (origins[i] - center) * 1.15 + velocities[i] * age + Vector2(0, 155.0 * age * age * liquid_scale)
		fragment.rotation = source_rotation + spins[i] * age
		fragment.scale = fragment_scale * lerpf(1.15, 0.05, smoothstep(0.0, 0.58, progress))
		fragment.modulate = Color.WHITE.lerp(SLIME, smoothstep(0.02, 0.24, progress) * 0.66)
		fragment.modulate.a = 1.0 - smoothstep(0.06, 0.52, progress)
	queue_redraw()

func _noise(index: int) -> float:
	# Do not advance the battle's shared RNG for particles.
	return fposmod(sin(float(index * 127 + 41)) * 43758.5453, 1.0)

func _fill_fan(polygon: PackedVector2Array, pivot: Vector2, color: Color) -> void:
	# Every drop is radial around its pivot. Explicit triangles avoid unstable
	# polygon triangulation as thin droplets approach subpixel dimensions.
	var colors := PackedColorArray([color, color, color])
	for i in polygon.size():
		draw_primitive(PackedVector2Array([pivot, polygon[i], polygon[(i + 1) % polygon.size()]]), colors, PackedVector2Array())

func _drop(point: Vector2, motion: Vector2, length: float, width: float, alpha: float, seed_index: int) -> void:
	if alpha <= 0.0:
		return
	var axis := motion.normalized() if motion.length_squared() > 0.001 else Vector2.DOWN
	var normal := Vector2(-axis.y, axis.x)
	var polygon := PackedVector2Array()
	for i in 14:
		var angle := TAU * float(i) / 14.0
		var side := sin(angle) * width * lerpf(0.46, 1.0, (cos(angle) + 1.0) * 0.5)
		polygon.append(point + axis * cos(angle) * length * 0.5 + normal * side * (0.90 + _noise(seed_index + i) * 0.20))
	_fill_fan(polygon, point, Color(SHADOW, alpha))
	polygon.append(polygon[0])
	draw_polyline(polygon, Color(OUTLINE, alpha), clampf(width * 0.32, 0.35 * liquid_scale, 0.85 * liquid_scale), true)
	var inner := PackedVector2Array()
	for i in 12:
		var angle := TAU * float(i) / 12.0
		inner.append(point - normal * width * 0.16 + axis * cos(angle) * length * 0.36 + normal * sin(angle) * width * 0.69)
	_fill_fan(inner, point - normal * width * 0.16, Color(SLIME, alpha))
	draw_line(point - normal * width * 0.32 - axis * length * 0.13,
		point - normal * width * 0.40 + axis * length * 0.10,
		Color(HIGHLIGHT, alpha * 0.90), clampf(width * 0.22, 0.25 * liquid_scale, 0.65 * liquid_scale), true)

func _drop_pair(point: Vector2, motion: Vector2, length: float, width: float, alpha: float, seed_index: int) -> void:
	_drop(point, motion, length, width, alpha, seed_index)
	# Mirror the entire droplet, including shape and shading, about the fish body.
	draw_set_transform_matrix(Transform2D(Vector2(-1,0),Vector2(0,1),Vector2(center.x*2.0,0)))
	_drop(point, motion, length, width, alpha, seed_index)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw() -> void:
	if not prepared or elapsed < BURST_TIME:
		return
	var age := elapsed - BURST_TIME
	var progress := clampf(age / (DURATION - BURST_TIME), 0.0, 1.0)
	var fade := 1.0 - smoothstep(0.55, 1.0, progress)
	# A few small wet splashes punctuate the body before the finer spray scatters.
	for i in 3:
		var origin := center + Vector2(_noise(i + 200) * body_size.x * 0.36, (_noise(i + 230) - 0.5) * body_size.y * 0.72)
		var ray := Vector2.from_angle(_noise(i + 245) * TAU)
		ray.x = absf(ray.x)
		var spread := (1.0 - pow(1.0 - progress, 3.0)) * (18.0 + _noise(i + 250) * 24.0) * liquid_scale * SPRAY_SPREAD
		var width := (1.7 + _noise(i + 260) * 1.3) * liquid_scale * (1.0 - progress * 0.55)
		_drop_pair(origin + ray * spread + Vector2(0, age * age * 95.0 * liquid_scale), ray,
			width * 2.6, width, (1.0 - smoothstep(0.08, 0.38, progress)) * 0.97, 300 + i * 17)
	# Uneven trajectories within each side, with identical mirrored pairs (74 drops).
	for i in 37:
		var delay := _noise(i + 600) * 0.025
		var drop_age := age - delay
		if drop_age < 0.0:
			continue
		var origin := center + Vector2(_noise(i + 660) * body_size.x * 0.45, (_noise(i + 720) - 0.5) * body_size.y * 0.82)
		var ray := Vector2.from_angle(_noise(i + 1500) * TAU)
		var velocity := (ray * (140.0 + _noise(i + 780) * 290.0) + Vector2((_noise(i + 1600) - 0.5) * 95.0, -25.0 - _noise(i + 1680) * 65.0)) * liquid_scale * SPRAY_SPREAD
		velocity.x = absf(velocity.x)
		# Strong initial spray loses speed rapidly, letting gravity turn the fine
		# drops down within the same short burst instead of leaving them afloat.
		var drag := exp(-4.0 * drop_age)
		var point := origin + velocity * ((1.0 - drag) / 4.0) + Vector2(0, 1200.0 * drop_age * drop_age * liquid_scale)
		var motion := velocity * drag + Vector2(0, 2400.0 * drop_age * liquid_scale)
		var width := (0.7 + _noise(i + 840) * 1.8) * liquid_scale * (1.0 - progress * 0.25)
		var length := (2.0 + _noise(i + 1900) * 6.0) * liquid_scale * (1.0 - progress * 0.15)
		var drop_fade := fade * (1.0 - smoothstep(0.40 + _noise(i + 2000) * 0.26, 1.0, progress))
		var floor_y := 2.0 + _noise(i + 2100) * 5.0
		if point.y > floor_y and motion.y > 0.0:
			drop_fade *= 1.0 - smoothstep(0.0, 28.0 * liquid_scale, point.y - floor_y)
			point.y = floor_y
			motion = Vector2.RIGHT
			length *= 1.4
			width *= 0.45
		_drop_pair(point, motion, length, width, drop_fade, 900 + i * 17)
	# Short downward splashes collect at the original foot level, then dissolve.
	var floor_progress := clampf((age - 0.12) / 0.18, 0.0, 1.0)
	if floor_progress > 0.0:
		for i in 4:
			var point := Vector2(center.x + _noise(i + 1700) * body_size.x * 0.725 * SPRAY_SPREAD, 2.0 + _noise(i + 1720) * 5.0)
			var width := (0.6 + _noise(i + 1740) * 0.8) * liquid_scale
			_drop_pair(point, Vector2.RIGHT, (3.0 + _noise(i + 1760) * 6.0) * liquid_scale * floor_progress,
				width * floor_progress, fade * 0.82, 1800 + i * 17)
