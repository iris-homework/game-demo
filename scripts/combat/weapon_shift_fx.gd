extends Node
## Whole-character stance presentation. Historical weapon_shift path retained.
## Never reads/writes the combat model or save.
signal finished
signal phase_changed(phase: String)

const SHADER := preload("res://shaders/weapon_shift.gdshader")
const OUT_TIME := 0.14
const GLITCH_TIME := 0.16
const REVEAL_TIME := 0.30
const DURATION := OUT_TIME + GLITCH_TIME + REVEAL_TIME
var source: Sprite2D
var previous_material: Material
var materials: Array[ShaderMaterial] = []
var echoes: Array[Sprite2D] = []
var swap_pose: Callable
var elapsed := 0.0
var phase := "out"
var stopped := false

func start(target: Sprite2D, swap: Callable) -> void:
	source = target
	previous_material = source.material
	swap_pose = swap
	for layer in [0.0,-1.0,1.0]:
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("layer",layer)
		materials.append(material)
		if layer == 0.0:
			source.material = material
		else:
			var echo := Sprite2D.new()
			echo.centered = source.centered
			echo.material = material
			source.add_child(echo)
			echoes.append(echo)
	refresh_textures()
	update_shader(1.0,0.7)
	phase_changed.emit(phase)

func refresh_textures() -> void:
	for echo in echoes: echo.texture = source.texture

func update_shader(visibility: float, intensity: float) -> void:
	for material in materials:
		material.set_shader_parameter("progress",elapsed)
		material.set_shader_parameter("visibility",visibility)
		material.set_shader_parameter("intensity",intensity)

func _process(delta: float) -> void:
	if stopped or not is_instance_valid(source): return
	elapsed += delta
	if phase == "out" and elapsed >= OUT_TIME:
		swap_pose.call()
		refresh_textures()
		phase = "glitch"
		# Hold the newly swapped full pose invisible for this render frame even
		# when delta overshoots OUT_TIME, so its body cannot snap into view.
		update_shader(0.0,0.0)
		phase_changed.emit(phase)
		return
	if phase == "glitch" and elapsed >= OUT_TIME + GLITCH_TIME:
		phase = "reveal"
		phase_changed.emit(phase)
	if elapsed >= DURATION:
		cancel()
	elif elapsed < OUT_TIME:
		update_shader(1.0-elapsed/OUT_TIME,clampf((OUT_TIME-elapsed)/0.04,0.0,1.0))
	else:
		var reveal := clampf((elapsed-OUT_TIME-GLITCH_TIME)/REVEAL_TIME,0.0,1.0)
		var arrival := clampf((elapsed-OUT_TIME)/0.04,0.0,1.0)
		update_shader(reveal,(1.0-reveal)*arrival)

func restore_sprite() -> void:
	if is_instance_valid(source) and not materials.is_empty() and source.material == materials[0]:
		source.material = previous_material
	for echo in echoes:
		if is_instance_valid(echo):
			echo.hide()
			echo.queue_free()
	echoes.clear()

func cancel() -> void:
	if stopped: return
	stopped = true
	restore_sprite()
	finished.emit()
	queue_free()

func _exit_tree() -> void:
	restore_sprite()
