extends Node2D
## Existing pose textures, calibrated by body proportions and soles (not canvas bounds).
var sprite := Sprite2D.new()
var home := Vector2.ZERO
var facing := -1.0
var kind := "noren"
var pose := "idle"
var alive := true
var combat_stance := "melee"
var tint := Color("ff4c9b")
var poses: Dictionary = {}
var weapon_shift: Node
const WeaponShift := preload("res://scripts/combat/weapon_shift_fx.gd")
const NOREN := {
	"idle": [Vector2(710,1240),0.099], "move": [Vector2(920,1048),0.103],
	"slash": [Vector2(725,1110),0.103], "pierce": [Vector2(1000,941),0.132],
	"block": [Vector2(550,1140),0.103], "damaged": [Vector2(700,1230),0.099],
	"gun_idle": [Vector2(660,1230),0.099], "shoot": [Vector2(945,980),0.126], "retreat": [Vector2(560,1155),0.099],
	"gun_block": [Vector2(550,1140),0.103], "gun_damaged": [Vector2(700,1230),0.099]
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
	for key in (NOREN if kind == "noren" else FINN):
		poses[key] = load("res://assets/combat_test/%s_%s.%s" % [kind,key,"png" if kind == "noren" else "webp"])
	set_pose("idle")

func set_pose(value: String) -> void:
	if kind == "noren" and combat_stance == "ranged" and value in ["idle","block","damaged"]:
		value = "gun_"+value
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
		points.append(Vector2(cos(angle)*32,sin(angle)*9+2))
	draw_colored_polygon(points,Color(0,0,0,0.7))

func set_combat_stance(value: String) -> void:
	# Initial load / restore / turn sync must never replay the presentation.
	if is_instance_valid(weapon_shift): weapon_shift.cancel()
	weapon_shift = null
	combat_stance = value
	set_pose("idle")

func transition_combat_stance(value: String) -> void:
	if kind != "noren" or value == combat_stance or not is_inside_tree():
		set_combat_stance(value)
		return
	if is_instance_valid(weapon_shift): weapon_shift.cancel()
	set_pose("idle")
	var effect := WeaponShift.new()
	weapon_shift = effect
	add_child(effect)
	effect.start(sprite,func():
		combat_stance = value
		set_pose("idle"))
	await effect.finished
	if weapon_shift == effect: weapon_shift = null
