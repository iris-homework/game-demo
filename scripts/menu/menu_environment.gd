class_name MidnightMenuEnvironment
extends Control
## Approved GIF decoded to lossless frames; menu-local playback and resource ownership.
## The clock pauses for static mode, focus loss and minimization.

const CANVAS := Vector2(1440, 900)
const SOURCE_GIF := "res://assets/menu/noren-bar-idle-motion-v2-neon.gif"
const FRAME_DIRECTORY := "res://assets/menu/noren_idle_frames"
@export_range(0.1, 3.0, 0.05) var playback_speed: float = 1.5

var frames: Array[Texture2D] = []
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
	for index in frame_count:
		var texture: Texture2D = load(FRAME_DIRECTORY.path_join("frame_%03d.png" % index))
		if texture == null:
			push_error("Approved menu animation frame is missing: %d" % index)
			return
		frames.append(texture)
	var scale_factor := maxf(CANVAS.x / frames[0].get_width(), CANVAS.y / frames[0].get_height())
	var artwork_size := Vector2(frames[0].get_size()) * scale_factor
	artwork_rect = Rect2((CANVAS - artwork_size) * 0.5, artwork_size)
	background = TextureRect.new()
	background.name = "tavern_art"
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.position = artwork_rect.position
	background.size = artwork_rect.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_show_frame(0)

func _process(delta: float) -> void:
	focused = DisplayServer.window_is_focused() and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED
	if motion_enabled and focused and frames.size() == frame_count:
		animation_time += minf(delta, 0.1)
		var cycle_time := fposmod(animation_time * playback_speed, loop_duration)
		_show_frame(mini(frame_count - 1, int(floor(cycle_time / frame_duration))))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true

func _show_frame(index: int) -> void:
	if index == frame_index or frames.is_empty() or not is_instance_valid(background):
		return
	frame_index = index
	background.texture = frames[index]

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
	frames.clear()
