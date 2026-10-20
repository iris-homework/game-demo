extends Panel
## Read-only energy slots; the battle model remains the only resource owner.
const DIMENSIONS := Vector2(170,56)
const BLUE := Color("5aa9ff")
const MUTED := Color("718594")
const SLOT_AREA := Rect2(12,35,146,12)
const GLITCH := preload("res://shaders/energy_glitch.gdshader")
var current := 3
var per_turn := 3
var phase := 0.0
var value_label: Label
var title_label: Label
var slot_effects: Array[ColorRect] = []

func _init() -> void:
	size = DIMENSIONS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	set_process(false)

func filled_slot_count() -> int:
	return clampi(current,0,per_turn)

func is_overclocked() -> bool:
	return current > per_turn

func set_energy(value: int, recovery: int) -> void:
	var changed := current != value or per_turn != recovery
	current = value
	per_turn = maxi(1,recovery)
	if slot_effects.size() != per_turn:
		build_slot_effects()
	if not is_overclocked(): phase = 0.0
	for effect in slot_effects:
		effect.visible = is_overclocked()
		effect.material.set_shader_parameter("phase",phase)
	set_process(is_overclocked() and is_visible_in_tree())
	value_label.text = "%d / %d" % [current, per_turn]
	value_label.add_theme_color_override("font_color", Color("95a2b0") if current <= 0 else Color("f5f3eb"))
	title_label.text = "能量·超频" if is_overclocked() else "能量"
	title_label.add_theme_color_override("font_color", MUTED if current <= 0 else BLUE)
	# Keep unusual bonus values readable inside the same footprint.
	var font_size := 23
	while font_size > 10 and value_label.get_theme_font("font").get_string_size(value_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > 70:
		font_size -= 1
	value_label.add_theme_font_size_override("font_size", font_size)
	value_label.size = Vector2(70,34)
	if changed: queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(is_overclocked() and is_visible_in_tree())

func _process(delta: float) -> void:
	phase = fposmod(phase + delta,60.0)
	for effect in slot_effects:
		effect.material.set_shader_parameter("phase",phase)
	queue_redraw()

func slot_rect(index: int) -> Rect2:
	var gap := minf(4.0,SLOT_AREA.size.x / (per_turn * 4.0))
	var width := (SLOT_AREA.size.x - gap * (per_turn - 1)) / per_turn
	return Rect2(SLOT_AREA.position + Vector2(index * (width + gap),0),Vector2(width,SLOT_AREA.size.y))

func build_slot_effects() -> void:
	for effect in slot_effects:
		remove_child(effect)
		effect.queue_free()
	slot_effects.clear()
	for i in per_turn:
		var effect := ColorRect.new()
		var bounds := slot_rect(i).grow(-1)
		effect.position = bounds.position
		effect.size = bounds.size
		effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = GLITCH
		material.set_shader_parameter("seed",float(i))
		effect.material = material
		add_child(effect)
		slot_effects.append(effect)

func _draw() -> void:
	var overclocked := is_overclocked()
	var accent := MUTED if current <= 0 else BLUE
	if overclocked:
		accent = Color("0ae6f0") if int(phase * 9) % 3 == 0 else (Color("eb1a8f") if int(phase * 9) % 3 == 1 else Color("7d40ff"))
	var frame := PackedVector2Array([Vector2(0,11),Vector2(11,0),Vector2(159,0),Vector2(170,11),Vector2(170,45),Vector2(159,56),Vector2(0,56)])
	draw_colored_polygon(frame, Color("0c1520"))
	var edge := frame.duplicate()
	edge.append(frame[0])
	draw_polyline(edge, Color(accent, 0.08 if current <= 0 else (0.24 if overclocked else 0.12)), 5.0, true)
	draw_polyline(edge, accent.darkened(0.6), 1.0, true)
	draw_polyline(PackedVector2Array([Vector2(0,26),Vector2(0,11),Vector2(11,0),Vector2(43,0)]), accent, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(153,55),Vector2(159,55),Vector2(169,45)]),accent,1.5,true)
	var bolt := PackedVector2Array([Vector2(22,8),Vector2(12,20),Vector2(18,20),Vector2(15,29),Vector2(26,15),Vector2(20,15)])
	draw_colored_polygon(bolt,accent)
	for i in per_turn:
		var slot := slot_rect(i)
		var lit := i < filled_slot_count()
		var color := BLUE
		if overclocked: color = accent
		draw_rect(slot,Color("172735"))
		draw_rect(slot,Color("354858"),false,1)
		if not lit: continue
		draw_rect(slot.grow(-1),color.darkened(0.25))
		draw_rect(Rect2(slot.position + Vector2(1,1),Vector2(maxf(0,slot.size.x-2),3)),color)
		draw_line(slot.position + Vector2(2,slot.size.y+1),slot.end + Vector2(-2,1),Color(color,0.28),1,true)
