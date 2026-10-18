extends Node2D
## User-selected red slash/thrust artwork, animated only in presentation space.
const TEXTURE := preload("res://assets/combat_fx/noren_red_slash.png")
const PIERCE_TEXTURE := preload("res://assets/combat_fx/noren_red_thrust_triangle_clean.png")
const PIERCE_OPACITY_REFERENCE := preload("res://assets/combat_fx/noren_red_thrust_triangle_light.png")
const PIERCE_OPACITY_SHADER := preload("res://shaders/noren_thrust_opacity.gdshader")
const LAYER_SHADER := preload("res://shaders/noren_slash_layers.gdshader")
const DRAW_SIZE := Vector2(270, 135)
const PIERCE_DRAW_SIZE := Vector2(420, 104)
# Align the crescent's cutting edge itself with the body, not its trailing flash.
const SLASH_CONTACT := Vector2(0.18, 0.52)
# Put the leading body of the enlarged thrust through the target, not just its tip.
const PIERCE_CONTACT := Vector2(0.38, 0.51)
const STRIKE_CONTACT := Vector2(0.62, 0.59)
const LIGHT_GAIN := 1.35
const PIERCE_LIGHT_GAIN := 1.0
var mode := "slash"
var direction := 1.0
var progress := 0.0
var duration := 0.34
var manual := false
var blocked := false
var impact_flash: Sprite2D

func _ready() -> void:
	z_index = 8
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if mode == "slash":
		var blade_material := ShaderMaterial.new()
		blade_material.shader = LAYER_SHADER
		material = blade_material
		impact_flash = Sprite2D.new()
		impact_flash.texture = TEXTURE
		impact_flash.centered = false
		impact_flash.z_index = 1
		var flash_material := ShaderMaterial.new()
		flash_material.shader = LAYER_SHADER
		flash_material.set_shader_parameter("impact_only", true)
		impact_flash.material = flash_material
		add_child(impact_flash)
	elif mode == "pierce":
		var thrust_material := ShaderMaterial.new()
		thrust_material.shader = PIERCE_OPACITY_SHADER
		thrust_material.set_shader_parameter("opacity_reference", PIERCE_OPACITY_REFERENCE)
		material = thrust_material
	queue_redraw()

func _process(delta: float) -> void:
	if not manual:
		progress = minf(1.0, progress + delta / duration)
		if progress >= 1.0:
			queue_free()
			return
	queue_redraw()

func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	# Normal alpha preserves both the red light and the source's black trails.
	# Animate around the contact, not the image center, so hits stay on the target.
	var release := smoothstep(0.0, 0.12, progress)
	var dissolve := smoothstep(0.44, 1.0, progress)
	var opacity := (0.35 + 0.65 * release) * (1.0 - dissolve)
	var piercing := mode == "pierce"
	var gain := PIERCE_LIGHT_GAIN if piercing else LIGHT_GAIN
	var light := Color(gain, gain, gain, opacity)
	var turn := 0.0 if piercing else lerpf(-0.08, 0.0, release) + dissolve * 0.08
	var growth := lerpf(0.86, 1.0, release) + dissolve * 0.06
	var draw_size := PIERCE_DRAW_SIZE if piercing else DRAW_SIZE
	var contact := PIERCE_CONTACT if piercing else SLASH_CONTACT
	var texture := PIERCE_TEXTURE if piercing else TEXTURE
	# Both source images have their leading edge on the left (crescent / tip).
	# Mirror around the source contact point, keeping the hit fixed on the target.
	var mirror := -direction
	var drift := Vector2(direction * dissolve * 10.0, 0.0) if piercing else Vector2(0.0, dissolve * 7.0)
	draw_set_transform(drift, turn * mirror, Vector2(mirror, 1.0) * growth)
	draw_texture_rect(texture, Rect2(-draw_size * contact, draw_size), false, light)
	if is_instance_valid(impact_flash):
		# The complete diagonal cut and burst share a pivot on the defender's chest.
		var flash_scale := Vector2(mirror, 1.0) * growth
		impact_flash.position = (-STRIKE_CONTACT * draw_size * flash_scale).rotated(turn * mirror)
		impact_flash.rotation = turn * mirror
		impact_flash.scale = draw_size / TEXTURE.get_size() * flash_scale
		impact_flash.modulate = light
