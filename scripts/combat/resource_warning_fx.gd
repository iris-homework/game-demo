extends Control
## Short local outline emphasis, independent of the resource HUD's own animation.
var accent := Color("70b7ff")
var elapsed := 0.0
const DURATION := 0.52

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1
	set_process(false)

func flash(color: Color, dimensions: Vector2) -> void:
	accent = color
	size = dimensions
	elapsed = 0.0
	show()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= DURATION:
		hide()
		set_process(false)
	queue_redraw()

func _draw() -> void:
	var strength := 1.0-smoothstep(0.06,DURATION,elapsed)
	var bounds := Rect2(Vector2.ZERO,size).grow(2)
	draw_rect(bounds,Color(accent,strength*0.12))
	draw_rect(bounds.grow(2),Color(accent,strength*0.14),false,5,true)
	draw_rect(bounds,Color(accent,strength*0.95),false,1.5,true)
