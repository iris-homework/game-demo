extends Button
## Visual brackets only; the full button rectangle remains the hit area.
const BLUE := Color("3d9eff")
var armed := false

func _ready() -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for changed in [mouse_entered, mouse_exited, button_down, button_up, resized]:
		changed.connect(queue_redraw)

func _draw() -> void:
	if disabled or (not armed and not is_hovered()): return
	var highlighted := is_hovered() or is_pressed()
	var color := Color(BLUE, 1.0 if highlighted else 0.55)
	var width := 3.0 if highlighted else 2.0
	var inset := width * 0.5
	var length := minf(18.0, minf(size.x, size.y) * 0.25)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var corner := Vector2(inset if x < 0 else size.x-inset, inset if y < 0 else size.y-inset)
			draw_polyline(PackedVector2Array([corner-Vector2(x*length, 0), corner, corner-Vector2(0, y*length)]), color, width, true)
