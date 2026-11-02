extends Node2D
## Noss's second-phase backdrop, in the same 1440×900 artwork coordinates as combat.
## One cached mesh / material, no textures, global randomness, input or global TIME.
## Tween reveal_progress linearly over ~4.2 seconds; the first large eyes open slowly.
## The owner chooses the layer and camera transform; this node never reparents itself.

const EYE_SHADER := preload("res://shaders/noss_eye_wall.gdshader")
const ENVIRONMENT_SHADER := preload("res://shaders/noss_eye_environment.gdshader")
const ART_SIZE := Vector2(1440.0, 900.0)
const TARGET_EYE_COUNT := 82
const LAYOUT_SEED := 20461102

@export_range(0.0, 1.0) var reveal_progress: float = 0.0:
	set(value):
		reveal_progress = clampf(value, 0.0, 1.0)
		if _eye_material != null:
			_eye_material.set_shader_parameter("reveal_progress", reveal_progress)
		_update_environment()

@export var wall_mode: bool = false:
	set(value):
		wall_mode = value
		if _eye_material != null:
			_eye_material.set_shader_parameter("wall_mode", wall_mode)
		_update_environment()

## Same artwork-space horizon used by the original battle scenery.
var floor_horizon := 402.0:
	set(value):
		floor_horizon = value
		if _eye_material != null: _eye_material.set_shader_parameter("floor_horizon",value)
		_update_environment()

## Local clock; the owner may copy it when handing the reveal to the battle wall.
var ambient_time: float = 0.0:
	get:
		return _ambient_time
	set(value):
		_ambient_time = maxf(value, 0.0)
		if _eye_material != null:
			_eye_material.set_shader_parameter("ambient_time", _ambient_time)
		_update_environment()
var glitch_strength := 0.0
var eye_count: int = 0:
	get:
		return _eyes.size()

var _ambient_time: float = 0.0
var _eye_material: ShaderMaterial
var _environment_material: ShaderMaterial
var _eyes: Array[Dictionary] = []
## Artwork-space presentation target, supplied by the stage after camera transforms.
var gaze_target := Vector2(720.0, 280.0)
var gaze_position := Vector2(720.0, 280.0)
var _summary_region := Rect2()
var _intent_region := Rect2()

func set_readability_regions(summary: Rect2, intent: Rect2) -> void:
	_summary_region = summary
	_intent_region = intent
	refresh_readability_regions()

func refresh_readability_regions() -> void:
	if _eye_material == null: return
	var inverse := get_global_transform().affine_inverse()
	var summary_local: Rect2 = inverse * _summary_region
	var intent_local: Rect2 = inverse * _intent_region
	_eye_material.set_shader_parameter("summary_region", Vector4(summary_local.position.x, summary_local.position.y, summary_local.size.x, summary_local.size.y))
	_eye_material.set_shader_parameter("intent_region", Vector4(intent_local.position.x, intent_local.position.y, intent_local.size.x, intent_local.size.y))

func _ready() -> void:
	# Inherit scene pause even if the component is placed below an always-running UI.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process_input(false)
	set_process_unhandled_input(false)
	_build_layout()
	_build_environment()
	_build_mesh()
	_update_environment()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or get_tree().paused:
		return
	# The dummy/headless backend reports minimized without an actual window.
	if DisplayServer.get_name() != "headless" and get_window().mode == Window.MODE_MINIMIZED:
		return
	var step := clampf(delta, 0.0, 0.1)
	ambient_time += step
	if wall_mode:
		gaze_position = gaze_position.lerp(gaze_target, 1.0-exp(-step/0.65))
		_eye_material.set_shader_parameter("gaze_position", gaze_position)

static func glitch_envelope_at(seconds: float) -> float:
	# Several short broken strips, followed by a long quiet interval. No RNG.
	var cycle := floorf(seconds/5.2)
	var local := fposmod(seconds,5.2)-(0.75+fposmod(cycle*0.618034,1.0)*1.1)
	if local < 0.0 or local > 0.42: return 0.0
	if local < 0.12: return 0.85
	if local > 0.17 and local < 0.25: return 0.62
	if local > 0.31 and local < 0.40: return 0.45
	return 0.0

func _build_environment() -> void:
	_environment_material = ShaderMaterial.new()
	_environment_material.shader = ENVIRONMENT_SHADER
	var background := ColorRect.new()
	background.name = "EyeWallEnvironment"
	background.size = ART_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.material = _environment_material
	add_child(background)

func _update_environment() -> void:
	glitch_strength = glitch_envelope_at(_ambient_time)*smoothstep(0.20,0.75,reveal_progress)
	if _environment_material == null: return
	_environment_material.set_shader_parameter("ambient_time",_ambient_time)
	_environment_material.set_shader_parameter("wall_mode",wall_mode)
	_environment_material.set_shader_parameter("floor_horizon",floor_horizon)
	_environment_material.set_shader_parameter("glitch_strength",glitch_strength)

func _build_layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = LAYOUT_SEED
	# These first witnesses establish a readable reveal before the crowd wakes up.
	var anchors := [
		Vector4(722.0, 216.0, 125.0, 62.0),
		Vector4(393.0, 294.0, 103.0, 51.0),
		Vector4(1094.0, 188.0, 111.0, 55.0),
		Vector4(166.0, 167.0, 92.0, 46.0),
		Vector4(1222.0, 389.0, 98.0, 49.0),
	]
	for anchor in anchors:
		_eyes.append(_eye(Vector2(anchor.x, anchor.y), Vector2(anchor.z, anchor.w), rng))
	var attempts := 0
	while _eyes.size() < TARGET_EYE_COUNT and attempts < 20000:
		attempts += 1
		var index := _eyes.size()
		var half_width: float
		if index < 12:
			half_width = rng.randf_range(78.0, 108.0)
		elif index < 40:
			half_width = rng.randf_range(58.0, 82.0)
		else:
			half_width = rng.randf_range(46.0, 62.0)
		var half_height := half_width * rng.randf_range(0.44, 0.54)
		var center: Vector2
		var region := rng.randf()
		if region < 0.66:
			center = Vector2(rng.randf_range(12.0, 1428.0), 12.0 + pow(rng.randf(), 1.25) * 535.0)
		elif region < 0.90:
			var edge_x := rng.randf_range(4.0, 290.0)
			center = Vector2(edge_x if rng.randf() < 0.5 else 1440.0 - edge_x, rng.randf_range(320.0, 815.0))
		else:
			center = Vector2(rng.randf_range(22.0, 1418.0), rng.randf_range(565.0, 881.0))
		# Elliptical rejection yields an organic cloud, with no row/grid scaffold.
		var clear := true
		var spacing := 0.80 if attempts < 9000 else 0.62
		for previous in _eyes:
			var old_center: Vector2 = previous["center"]
			var old_size: Vector2 = previous["size"]
			var distance := (center - old_center) / (Vector2(half_width, half_height) + old_size)
			if distance.length() < spacing:
				clear = false
				break
		if clear:
			_eyes.append(_eye(center, Vector2(half_width, half_height), rng))
	# Separate the three similar green eyes identified in the fixed layout.
	# Keep the other 79 eyes and the opening order exactly as authored.
	var cluster_adjustments := [
		{"index":14,"center":Vector2(774,389),"size":Vector2(61,28),"angle":-0.32,"hue":0.52},
		{"index":48,"center":Vector2(939,355),"size":Vector2(49,25),"angle":0.24,"hue":0.10},
		{"index":81,"center":Vector2(843,317),"size":Vector2(52,25),"angle":0.08,"hue":0.33},
	]
	for adjustment in cluster_adjustments:
		var eye: Dictionary = _eyes[adjustment.index]
		eye.center = adjustment.center
		eye.size = adjustment.size
		eye.angle = adjustment.angle
		var palette_band := floorf(float(eye.seed)*8.37+0.07)
		eye.seed = (palette_band+float(adjustment.hue)-0.07)/8.37
	# Fisher–Yates on only the crowd: first five positions remain deliberately staged.
	var order: Array[int] = []
	for i in range(5, _eyes.size()):
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var other := rng.randi_range(0, i)
		var saved := order[i]
		order[i] = order[other]
		order[other] = saved
	for i in range(_eyes.size()):
		var slot: int = i if i < 5 else order[i - 5]
		# pow(p, 2.25) reveal clock + these ranks leave the first eye alone initially.
		_eyes[slot]["rank"] = float(i) / float(maxi(1, _eyes.size() - 1)) * 0.935

func _eye(center: Vector2, half_size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	return {"center": center, "size": half_size, "angle": rng.randf_range(-0.30, 0.30),
		"seed": rng.randf(), "rank": 0.0, "depth": rng.randf_range(0.67, 1.0)}

func _build_mesh() -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var corners := [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]
	for eye in _eyes:
		var base := vertices.size()
		var center: Vector2 = eye["center"]
		var half_size: Vector2 = eye["size"]
		var angle: float = eye["angle"]
		var packed := Color(float(eye["seed"]), float(eye["rank"]), float(eye["depth"]), half_size.y/half_size.x)
		for corner in corners:
			var point: Vector2 = center + (corner * half_size).rotated(angle)
			vertices.append(Vector3(point.x, point.y, 0.0))
			uvs.append(corner * 0.5 + Vector2(0.5, 0.5))
			colors.append(packed)
		for offset in [0, 1, 2, 0, 2, 3]:
			indices.append(base + offset)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_eye_material = ShaderMaterial.new()
	_eye_material.shader = EYE_SHADER
	_eye_material.set_shader_parameter("reveal_progress", reveal_progress)
	_eye_material.set_shader_parameter("ambient_time", _ambient_time)
	_eye_material.set_shader_parameter("wall_mode", wall_mode)
	_eye_material.set_shader_parameter("floor_horizon",floor_horizon)
	_eye_material.set_shader_parameter("gaze_position", gaze_position)
	var tracking_frames := PackedVector4Array()
	for i in 5:
		var eye: Dictionary = _eyes[i]
		var center: Vector2 = eye.center
		tracking_frames.append(Vector4(center.x, center.y, cos(float(eye.angle)), sin(float(eye.angle))))
	_eye_material.set_shader_parameter("tracking_frames", tracking_frames)
	var surface := MeshInstance2D.new()
	surface.name = "CachedEyes"
	surface.mesh = mesh
	surface.material = _eye_material
	add_child(surface)
