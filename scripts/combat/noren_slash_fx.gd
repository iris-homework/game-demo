extends Node2D
## Original rose crescent artwork, animated only in presentation space.
const TEXTURE := preload("res://assets/combat_fx/noren_slash.png")
const DRAW_SIZE := Vector2(210, 210.0 * 941.0 / 1672.0)
var direction := 1.0
var progress := 0.0
var duration := 0.30
var manual := false
var blocked := false

func _ready() -> void:
	z_index = 8
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	# A fast release, readable contact, then a short downward follow-through.
	# Normal alpha preserves the artwork's dark wine strokes and ivory edge.
	var release := smoothstep(0.0, 0.14, progress)
	var dissolve := smoothstep(0.38, 1.0, progress)
	var opacity := (0.35 + 0.65 * release) * (1.0 - dissolve)
	var turn := lerpf(-0.17, 0.0, release) + dissolve * 0.12
	var growth := lerpf(0.86, 1.0, release) + dissolve * 0.06
	draw_set_transform(Vector2(-32.0 * direction, dissolve * 9.0), turn * direction, Vector2(direction, 1.0) * growth)
	draw_texture_rect(TEXTURE, Rect2(-DRAW_SIZE * 0.5, DRAW_SIZE), false, Color(1, 1, 1, opacity))
