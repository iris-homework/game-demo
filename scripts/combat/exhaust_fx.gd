extends Node2D
## Owns a retired visual only; the model has already moved its UID to exhaust.
const SELECT_DURATION := 0.18
const HOLD_DURATION := 0.08
const DISSOLVE_DURATION := 0.52
const RESIDUE_DURATION := 0.12
const CYAN := Color("64ffe1")
const PINK := Color("ff398e")
const MARGIN := Vector2(22, 22)
const SURFACE_SIZE := Vector2i(224, 274)
var card: CombatCard
var surface: SubViewport
var image: Sprite2D
var ink: ShaderMaterial
var elapsed := 0.0
var progress := 0.0
var origin := Vector2.ZERO
var original_scale := Vector2.ONE
var original_rotation := 0.0

func _ready() -> void:
	add_to_group("card_exhaust_fx")
	z_index = 40
	set_process(false)

func start(view: CombatCard) -> void:
	card = view
	if view.hover_tween: view.hover_tween.kill()
	view.set_enabled(false)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.card_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.hovered = false
	view.dragging = false
	# Disabled selection supplies the normal highlight without starting a pose tween.
	view.set_selected(true)
	origin = view.position + view.pivot_offset
	original_scale = view.scale
	original_rotation = view.rotation
	position = origin
	scale = original_scale
	rotation = original_rotation
	# Composite the entire live card so dynamic text dissolves with its artwork.
	# This private viewport never receives input and requires no screen capture.
	surface = SubViewport.new()
	surface.size = SURFACE_SIZE
	surface.transparent_bg = true
	surface.disable_3d = true
	surface.gui_disable_input = true
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(surface)
	view.reparent(surface, false)
	view.position = MARGIN
	view.rotation = 0.0
	view.scale = Vector2.ONE
	view.z_index = 0
	image = Sprite2D.new()
	image.texture = surface.get_texture()
	ink = ShaderMaterial.new()
	ink.shader = preload("res://shaders/card_exhaust.gdshader")
	image.material = ink
	add_child(image)
	update_effect()
	set_process(true)

func _process(delta: float) -> void:
	elapsed += delta
	update_effect()
	if elapsed >= SELECT_DURATION + HOLD_DURATION + DISSOLVE_DURATION + RESIDUE_DURATION:
		# battle.gd waits for this retired card to hide before replenishing the hand.
		card.hide()
		queue_free()

func update_effect() -> void:
	var selected_amount := 1.0 - pow(1.0 - clampf(elapsed / SELECT_DURATION, 0.0, 1.0), 3.0)
	progress = clampf((elapsed - SELECT_DURATION - HOLD_DURATION) / DISSOLVE_DURATION, 0.0, 1.0)
	position = origin + Vector2(0, -30.0 * selected_amount)
	scale = original_scale.lerp(Vector2.ONE * 1.08, selected_amount)
	rotation = lerpf(original_rotation, 0.0, selected_amount)
	ink.set_shader_parameter("progress", progress)
	ink.set_shader_parameter("clock", elapsed)
	queue_redraw()

func _draw() -> void:
	var highlight := smoothstep(0.0, 0.08, elapsed) * (1.0 - smoothstep(0.12, 0.78, progress))
	# Four locking brackets, rather than a flight trail or a pile arrival ring.
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var corner := Vector2(x * 96, y * 121)
			var points := PackedVector2Array([corner - Vector2(x * 20, 0), corner, corner - Vector2(0, y * 20)])
			var hue := CYAN if x == y else PINK
			draw_polyline(points, Color(hue, highlight * 0.16), 9.0, true)
			draw_polyline(points, Color(hue, highlight), 2.0, true)
	if progress <= 0.0: return
	var residue := 1.0 - clampf((elapsed - SELECT_DURATION - HOLD_DURATION - DISSOLVE_DURATION) / RESIDUE_DURATION, 0.0, 1.0)
	# Deterministic, short digital splinters: cosmetic effects never consume deck RNG.
	for i in 30:
		var onset := float(i % 10) / 12.0
		var age := clampf((progress - onset) / 0.30, 0.0, 1.0)
		if age <= 0.0 or age >= 1.0: continue
		var direction := -1.0 if i % 2 == 0 else 1.0
		var point := Vector2(float((i * 71) % 164) - 82.0, 106.0 - onset * 246.0)
		point += Vector2(direction * age * (22 + i % 5 * 8), -age * 12.0)
		var hue := CYAN if i % 3 else PINK
		var alpha := sin(age * PI) * residue
		var fragment := Rect2(point, Vector2(4 + i % 4 * 4, 1 + i % 2))
		draw_rect(fragment.grow(2), Color(hue, alpha * 0.12))
		draw_rect(fragment, Color(hue, alpha))
