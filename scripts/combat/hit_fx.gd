extends Node2D
var progress := 0.0
var color := Color("ff609e")

func _ready() -> void:
	var tween := create_tween()
	tween.tween_property(self, "progress", 1.0, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(queue_free)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var ink := Color(color, 1.0-progress)
	draw_arc(Vector2.ZERO, 12+progress*48, 0, TAU, 40, ink, 2.0, true)
	for i in range(8):
		var direction := Vector2.from_angle(i*TAU/8+0.2)
		draw_line(direction*(10+progress*30), direction*(28+progress*61), ink, 2.0, true)
	draw_line(Vector2(-42,28)*(0.3+progress), Vector2(42,-28)*(0.3+progress), ink, 4.0, true)
