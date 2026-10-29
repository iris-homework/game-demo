extends Control
## One-shot title curtain. The main scene owns input, sound and the session guard.
## SubViewport and its texture are owned here and released with this node.

signal finished
signal slash_started

const CANVAS := Vector2(1440.0, 900.0)
const DURATION := 3.0
const SLASH_TIME := 1.50
const MENU_LOGO := preload("res://scripts/menu/menu_logo.gd")
const CUT_SHADER := preload("res://shaders/startup_splash.gdshader")
const BACKDROP := Color("070610")
const RENDER_SCALE := 2

var elapsed := 0.0
var source_viewport: SubViewport
var title: Control
var curtain: TextureRect
var cut_material: ShaderMaterial
var completed := false
var slash_emitted := false

func _ready() -> void:
	name = "startup_splash"
	size = CANVAS
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	z_index = 200
	# A SubViewport breaks theme inheritance. Copy the actual menu theme explicitly;
	# retain the bundled font when the component is previewed without a menu parent.
	var title_theme := theme
	if title_theme == null:
		title_theme = Theme.new()
		title_theme.default_font = preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	source_viewport = SubViewport.new()
	source_viewport.name = "title_source"
	# Supersample the title before the cut/dissolve shader samples it. This avoids
	# magnifying a 1440px intermediate texture on the larger desktop window.
	source_viewport.size = Vector2i(CANVAS) * RENDER_SCALE
	source_viewport.disable_3d = true
	source_viewport.gui_disable_input = true
	source_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(source_viewport)
	var stage := Control.new()
	stage.size = CANVAS
	stage.scale = Vector2.ONE * RENDER_SCALE
	stage.theme = title_theme
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_viewport.add_child(stage)
	var backdrop := ColorRect.new()
	backdrop.size = CANVAS
	backdrop.color = BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(backdrop)
	title = MENU_LOGO.new()
	title.name = "startup_title"
	title.theme = title_theme
	title.size = Vector2(410.0, 170.0)
	title.scale = Vector2.ONE * 1.85
	title.position = (CANVAS - title.size * title.scale) * 0.5
	stage.add_child(title)
	title.set_motion_enabled(false)
	# MENU_LOGO duplicates its FontFile; oversampling is private to this title.
	# The glyphs must remain sharp through the 1.85x logo and 2x target transforms.
	if title.logo_font.base_font is FontFile:
		title.logo_font.base_font.oversampling = 4.0
	curtain = TextureRect.new()
	curtain.name = "split_curtain"
	curtain.size = CANVAS
	curtain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	curtain.texture = source_viewport.get_texture()
	cut_material = ShaderMaterial.new()
	cut_material.shader = CUT_SHADER
	cut_material.set_shader_parameter("title_texture", source_viewport.get_texture())
	curtain.material = cut_material
	add_child(curtain)
	set_timeline(elapsed)

func _process(delta: float) -> void:
	if completed:
		return
	if DisplayServer.get_name() != "headless" and (not DisplayServer.window_is_focused() or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED):
		return
	set_timeline(elapsed + minf(delta, 0.1))
	if elapsed >= SLASH_TIME and not slash_emitted:
		slash_emitted = true
		slash_started.emit()
	if elapsed >= DURATION:
		_finish()

func set_timeline(time: float) -> void:
	# Deterministic preview/QA seek: no sound, completion signal or save mutation.
	elapsed = clampf(time, 0.0, DURATION)
	if not is_instance_valid(title) or cut_material == null:
		return
	var light := smoothstep(0.10, 0.72, elapsed)
	# One restrained ignition pulse, followed by an uninterrupted readable hold.
	light *= 1.0 - 0.24 * exp(-pow((elapsed - 0.49) / 0.045, 2.0))
	title.modulate.a = light
	cut_material.set_shader_parameter("timeline", elapsed)

func skip() -> void:
	_finish()

func _finish() -> void:
	if completed:
		return
	completed = true
	set_process(false)
	hide()
	finished.emit()
	queue_free()
