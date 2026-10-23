extends Node2D
## Cosmetic card rewards, attached to the actor so camera/pose movement stays aligned.
signal finished
var kind := "block"
var amount := 1
var duration := 0.82
var progress := 0.0

func _ready() -> void:
	add_to_group("card_gain_fx")
	z_index = 20

func _process(delta: float) -> void:
	progress = minf(1.0, progress + delta / duration)
	queue_redraw()
	if progress >= 1.0:
		finished.emit()
		queue_free()

func _draw() -> void:
	var appear := clampf(progress / 0.16, 0.0, 1.0)
	var fade := 1.0 - smoothstep(0.52, 1.0, progress)
	var opacity := appear * fade
	if kind == "block":
		draw_shield(opacity)
	else:
		draw_cards(opacity)
	draw_set_transform(Vector2.ZERO)

func draw_shield(opacity: float) -> void:
	var growth := 0.72 + 0.28 * (1.0 - pow(1.0 - minf(progress / 0.22, 1.0), 3.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * growth)
	var shield := PackedVector2Array([Vector2(0,-38),Vector2(30,-25),Vector2(26,9),Vector2(16,25),Vector2(0,37),Vector2(-16,25),Vector2(-26,9),Vector2(-30,-25)])
	var outline := shield.duplicate()
	outline.append(shield[0])
	draw_colored_polygon(shield, Color(0.04,0.20,0.36,0.62 * opacity))
	draw_polyline(outline, Color(0.16,0.63,1.0,0.16 * opacity), 12.0, true)
	draw_polyline(outline, Color(0.28,0.78,1.0,opacity), 3.0, true)
	draw_polyline(outline, Color(0.82,0.98,1.0,0.85 * opacity), 1.0, true)
	var inset := PackedVector2Array([Vector2(0,-27),Vector2(20,-18),Vector2(17,7),Vector2(10,17),Vector2(0,25),Vector2(-10,17),Vector2(-17,7),Vector2(-20,-18),Vector2(0,-27)])
	draw_polyline(inset, Color(0.30,0.75,1.0,0.48 * opacity), 1.0, true)
	draw_line(Vector2(-10,-4),Vector2(10,-4),Color(0.8,0.98,1.0,opacity),3.0,true)
	draw_line(Vector2(0,-14),Vector2(0,6),Color(0.8,0.98,1.0,opacity),3.0,true)
	for i in 6:
		var angle := float(i) * TAU / 6.0 + 0.2
		var point := Vector2.from_angle(angle) * (40.0 + progress * 18.0)
		draw_line(point, point + Vector2.from_angle(angle) * 5.0, Color(0.38,0.84,1.0,opacity * 0.65), 2.0, true)

func draw_cards(opacity: float) -> void:
	# A single centered cue represents any successful card draw batch.
	var growth := smoothstep(0.0, 0.35, progress)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * (0.75 + 0.25 * growth))
	var face := Rect2(-14,-21,28,42)
	draw_rect(face.grow(3), Color(0.25,0.84,1.0,0.12 * opacity))
	draw_rect(face, Color(0.04,0.10,0.22,0.82 * opacity))
	draw_rect(face, Color(0.40,0.91,1.0,opacity), false, 2.0)
	draw_rect(face.grow(-4), Color(0.60,0.50,1.0,0.65 * opacity), false, 1.0)
	var diamond := PackedVector2Array([Vector2(0,-9),Vector2(6,0),Vector2(0,9),Vector2(-6,0),Vector2(0,-9)])
	draw_polyline(diamond, Color(0.83,0.95,1.0,opacity), 1.5, true)
	draw_line(Vector2(-8,28),Vector2(-8,34 + progress * 12),Color(0.36,0.85,1.0,opacity * 0.6),1.5,true)
	draw_line(Vector2(7,27),Vector2(7,31 + progress * 8),Color(0.67,0.54,1.0,opacity * 0.6),1.5,true)
