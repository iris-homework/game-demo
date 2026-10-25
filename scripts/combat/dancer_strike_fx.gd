extends Node2D
## Noren's layered attack artwork with dancer-specific ink/white palettes; presentation only.
const TEXTURE := preload("res://assets/combat_fx/noren_red_slash.png")
const PIERCE_TEXTURE := preload("res://assets/combat_fx/noren_red_thrust_triangle_clean.png")
const PIERCE_OPACITY_REFERENCE := preload("res://assets/combat_fx/noren_red_thrust_triangle_light.png")
const PALETTE_SHADER := preload("res://shaders/dancer_strike_palette.gdshader")
const DRAW_SIZE := Vector2(340, 170)
const PIERCE_DRAW_SIZE := Vector2(480, 132)
const SLASH_CONTACT := Vector2(0.18, 0.52)
const PIERCE_CONTACT := Vector2(0.38, 0.51)
const STRIKE_CONTACT := Vector2(0.62, 0.59)

var mode := "pierce"
var direction := 1.0
var blocked := false
var duration := 0.36
var progress := 0.0
var manual := false
var impact_flash: Sprite2D

func _ready() -> void:
	z_index = 8
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material = _palette_material(mode == "pierce", false)
	if mode == "slash":
		impact_flash = Sprite2D.new()
		impact_flash.texture = TEXTURE
		impact_flash.centered = false
		impact_flash.z_index = 1
		impact_flash.material = _palette_material(false, true)
		add_child(impact_flash)
	queue_redraw()

func _palette_material(piercing: bool, impact_only: bool) -> ShaderMaterial:
	var palette := ShaderMaterial.new()
	palette.shader = PALETTE_SHADER
	palette.set_shader_parameter("piercing", piercing)
	palette.set_shader_parameter("impact_only", impact_only)
	palette.set_shader_parameter("opacity_reference", PIERCE_OPACITY_REFERENCE)
	return palette

func _process(delta: float) -> void:
	if not manual:
		progress = minf(1.0, progress + delta / maxf(duration, 0.001))
		if progress >= 1.0:
			queue_free()
			return
	queue_redraw()

func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var t: float = clampf(progress, 0.0, 1.0)
	var release: float = smoothstep(0.0, 0.12, t)
	var dissolve: float = smoothstep(0.44, 1.0, t)
	var opacity: float = (0.35 + 0.65 * release) * (1.0 - dissolve)
	var piercing: bool = mode == "pierce"
	var turn: float = 0.0 if piercing else lerpf(-0.08, 0.0, release) + dissolve * 0.08
	var growth: float = lerpf(0.86, 1.0, release) + dissolve * 0.06
	if blocked:
		growth *= 0.85
		opacity *= 0.86
	var draw_size: Vector2 = PIERCE_DRAW_SIZE if piercing else DRAW_SIZE
	var contact: Vector2 = PIERCE_CONTACT if piercing else SLASH_CONTACT
	var attack_texture: Texture2D = PIERCE_TEXTURE if piercing else TEXTURE
	var mirror: float = -direction
	var light := Color(1.0, 1.0, 1.0, opacity)
	# Source edges face left. Both layers scale/turn around their own fixed body contact.
	# Unlike the source animation, no tail-end drift displaces the target's hit point.
	draw_set_transform(Vector2.ZERO, turn * mirror, Vector2(mirror, 1.0) * growth)
	draw_texture_rect(attack_texture, Rect2(-draw_size * contact, draw_size), false, light)
	if is_instance_valid(impact_flash):
		var flash_scale: Vector2 = Vector2(mirror, 1.0) * growth
		impact_flash.position = (-STRIKE_CONTACT * draw_size * flash_scale).rotated(turn * mirror)
		impact_flash.rotation = turn * mirror
		impact_flash.scale = draw_size / TEXTURE.get_size() * flash_scale
		impact_flash.modulate = light
