class_name MidnightMenuEnvironment
extends Control
## Full-color native PNG with local shader animation; no downscaled GIF textures.
## The clock pauses for static mode, focus loss and minimization.

const CANVAS := Vector2(1440, 900)
const SOURCE_ART := "res://assets/menu/noren-bar-seated-v1.png"
const ART_SHADER := preload("res://shaders/menu_native_art.gdshader")
# Same neon keyframes as tools/render_noren_neon_patch.mjs, before GIF quantization.
const LEFT_SIGN_KEYS := [Vector2(0,1),Vector2(9,1),Vector2(10,.28),Vector2(11,.15),Vector2(12,.85),Vector2(13,1),Vector2(20,1),Vector2(21,.4),Vector2(22,.18),Vector2(23,.18),Vector2(24,.75),Vector2(25,1),Vector2(44,1),Vector2(45,.30),Vector2(46,1),Vector2(59,1)]
const RIGHT_SIGN_KEYS := [Vector2(0,1),Vector2(15,1),Vector2(16,.2),Vector2(18,.2),Vector2(19,1),Vector2(33,1),Vector2(34,.15),Vector2(35,.65),Vector2(36,.2),Vector2(37,.2),Vector2(38,1),Vector2(50,1),Vector2(51,.4),Vector2(52,1),Vector2(59,1)]
@export_range(0.1, 3.0, 0.05) var playback_speed: float = 1.5

var source_texture: Texture2D
var artwork_material: ShaderMaterial
var frame_count: int = 60
var frame_duration: float = 0.08
var loop_duration: float = 4.8
var frame_index: int = -1
var background: TextureRect
var artwork_rect := Rect2()
var animation_time: float = 0.0
var focused: bool = true
var motion_enabled: bool = true

func _ready() -> void:
	name = "menu_environment"
	add_to_group("menu_environment")
	position = Vector2.ZERO
	size = CANVAS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	focused = DisplayServer.window_is_focused()
	motion_enabled = bool(get_tree().root.get_meta("menu_motion_enabled", true))
	source_texture = load(SOURCE_ART)
	if source_texture == null:
		push_error("Native menu artwork is missing: " + SOURCE_ART)
		return
	# Retain the approved cover mapping; source aspect differs by under one pixel.
	artwork_rect = Rect2(Vector2(-80, 0), Vector2(1600, 900))
	artwork_material = ShaderMaterial.new()
	artwork_material.shader = ART_SHADER
	background = TextureRect.new()
	background.name = "tavern_art"
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.position = artwork_rect.position
	background.size = artwork_rect.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture = source_texture
	background.material = artwork_material
	add_child(background)
	_show_frame(0)

func _process(delta: float) -> void:
	focused = DisplayServer.window_is_focused() and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED
	if motion_enabled and focused and source_texture != null:
		animation_time += minf(delta, 0.1)
		var cycle_time := fposmod(animation_time * playback_speed, loop_duration)
		_show_frame(mini(frame_count - 1, int(floor(cycle_time / frame_duration))))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true

func _show_frame(index: int) -> void:
	if index == frame_index or source_texture == null or artwork_material == null:
		return
	frame_index = index
	var phase := TAU * float(index) / float(frame_count)
	# Same "motion" preset angles/pivots as render_noren_idle.mjs.
	artwork_material.set_shader_parameter("motion_angles", Vector3(
		deg_to_rad(1.65 * 3.0) * sin(phase),
		deg_to_rad(1.65 * 2.6) * sin(phase + 0.2),
		deg_to_rad(1.25 * 2.6) * sin(phase + 0.8)))
	artwork_material.set_shader_parameter("light_gains", Vector2(0.032 * sin(phase), 0.045 * sin(phase + 0.65)))
	artwork_material.set_shader_parameter("sign_gains", Vector2(_sign_gain(index, LEFT_SIGN_KEYS), _sign_gain(index, RIGHT_SIGN_KEYS)))

func _sign_gain(index: int, keys: Array) -> float:
	for i in range(1, keys.size()):
		var a: Vector2 = keys[i - 1]
		var b: Vector2 = keys[i]
		if index <= b.x:
			return lerpf(a.y, b.y, (float(index) - a.x) / (b.x - a.x))
	return 1.0

func set_motion_enabled(value: bool) -> void:
	motion_enabled = value
	get_tree().root.set_meta("menu_motion_enabled", value)
	if not value:
		_show_frame(0)

func get_motion_enabled() -> bool:
	return motion_enabled

func _exit_tree() -> void:
	set_process(false)
	if is_instance_valid(background):
		background.texture = null
		background.material = null
	source_texture = null
	artwork_material = null
