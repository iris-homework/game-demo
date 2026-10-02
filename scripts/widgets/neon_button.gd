extends Button
## Lightweight feedback keeps the hit area stationary while its light animates.
var accent := false
var hover_amount := 0.0
var press_amount := 0.0
var feedback: Tween
var halo := StyleBoxFlat.new()

func _ready() -> void:
	halo.bg_color = Color.TRANSPARENT
	halo.shadow_size = 7
	halo.set_corner_radius_all(7)
	set_process(false)
	mouse_entered.connect(refresh_feedback)
	mouse_exited.connect(refresh_feedback)
	focus_entered.connect(refresh_feedback)
	focus_exited.connect(refresh_feedback)
	button_down.connect(refresh_feedback)
	button_up.connect(refresh_feedback)

func refresh_feedback() -> void:
	if feedback: feedback.kill()
	set_process(true)
	feedback = create_tween().set_parallel(true)
	feedback.tween_property(self, "hover_amount", 1.0 if not disabled and (is_hovered() or has_focus()) else 0.0, 0.12)
	feedback.tween_property(self, "press_amount", 1.0 if not disabled and button_pressed else 0.0, 0.07)
	feedback.finished.connect(func():
		queue_redraw()
		set_process(false))

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if disabled: return
	var ink := Color("ffe9f2") if accent else Color("58e1eb")
	ink.a = 0.25 + hover_amount * 0.65
	var inset := 5.0 + press_amount * 2.0
	var length := 9.0 + hover_amount * 15.0
	for p in [Vector2(inset, inset), size - Vector2(inset, inset)]:
		var direction := 1.0 if p.x < size.x * 0.5 else -1.0
		draw_line(p, p + Vector2(length * direction, 0), ink, 1.5, true)
		draw_line(p, p + Vector2(0, 5 * direction), ink, 1.5, true)
	if hover_amount > 0.01:
		var glow := ink
		glow.a = hover_amount * 0.09
		halo.shadow_color = glow
		draw_style_box(halo, Rect2(Vector2.ZERO, size))
