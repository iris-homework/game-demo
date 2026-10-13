extends Node2D
## Existing pose textures, calibrated by body proportions and soles (not canvas bounds).
var sprite := Sprite2D.new()
var home := Vector2.ZERO
var facing := -1.0
var kind := "noren"
var pose := "idle"
var alive := true
var tint := Color("ff4c9b")
var poses: Dictionary = {}
const NOREN := {
	"idle": [Vector2(710,1232),0.099], "move": [Vector2(920,1048),0.103],
	"slash": [Vector2(725,1110),0.103], "pierce": [Vector2(1000,941),0.132],
	"block": [Vector2(550,1140),0.103], "damaged": [Vector2(700,1230),0.099]
}
const FINN := {
	"idle": [Vector2(150,237),0.495], "move": [Vector2(132,222),0.495],
	"slash": [Vector2(70,196),0.495], "pierce": [Vector2(190,184),0.495],
	"block": [Vector2(80,237),0.495], "damaged": [Vector2(74,230),0.495]
}

func setup(actor_kind: String, origin: Vector2, direction: float) -> void:
	kind = actor_kind
	home = origin
	position = origin
	facing = direction
	tint = Color("ff4c9b") if kind == "noren" else Color("6ae4f2")
	add_child(sprite)
	sprite.centered = false
	for key in NOREN:
		poses[key] = load("res://assets/combat_test/%s_%s.%s" % [kind,key,"png" if kind == "noren" else "webp"])
	set_pose("idle")

func set_pose(value: String) -> void:
	pose = value if poses.has(value) else "idle"
	var calibration: Array = (NOREN if kind == "noren" else FINN)[pose]
	var anchor: Vector2 = calibration[0]
	var factor: float = calibration[1]
	sprite.texture = poses[pose]
	# Source artwork faces left. Mirror texture and anchor together.
	sprite.scale = Vector2(-facing,1)*factor
	sprite.position = -anchor*sprite.scale

func face_toward(point: Vector2) -> void:
	facing = 1.0 if point.x >= position.x else -1.0
	set_pose(pose)

func _draw() -> void:
	var points := PackedVector2Array()
	for i in 40:
		var angle := i*TAU/40.0
		points.append(Vector2(cos(angle)*32,sin(angle)*4+2))
	draw_colored_polygon(points,Color(0,0,0,0.7))
