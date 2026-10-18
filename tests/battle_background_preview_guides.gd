extends Node2D
## World-space guides remain aligned with feet and the preview artwork at every zoom.
var stage: Control
var backdrop: Sprite2D
var rear_edge_ratio := 0.53
var source_padding := Vector2.ZERO

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(stage) or not is_instance_valid(backdrop): return
	var floor_bounds := Rect2(180, stage.floor_y - 165, 1080, 265)
	draw_rect(floor_bounds, Color(0.25, 0.95, 1.0, 0.035))
	draw_rect(floor_bounds, Color(0.25, 0.95, 1.0, 0.6), false, 1.0)
	var wall_y := backdrop.position.y + (source_padding.y + backdrop.texture.get_height() * rear_edge_ratio) * backdrop.scale.y
	draw_line(Vector2(-200, wall_y), Vector2(1640, wall_y), Color(1, 0.65, 0.25, 0.8), 1.0)
	for actor in stage.actors_root.get_children():
		draw_circle(actor.home, 8, Color(0.25, 0.95, 1.0, 0.8), false, 1.0)
		draw_line(actor.home - Vector2(14, 0), actor.home + Vector2(14, 0), Color.CYAN, 1.0)
		draw_circle(actor.position, 3, Color.WHITE)
