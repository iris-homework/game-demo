extends Node2D
## Existing pose textures, calibrated by body proportions and soles (not canvas bounds).
var sprite := Sprite2D.new()
var home := Vector2.ZERO
var facing := -1.0
var kind := "noren"
var is_player := false
var pose := "idle"
var alive := true
var combat_stance := "melee"
var tint := Color("ff4c9b")
var poses: Dictionary = {}
var calibrations: Dictionary = {}
var pose_aliases: Dictionary = {}
var target_bounds := Rect2(-58,-130,116,145)
var attack_style_override := ""
var laser_muzzle := Vector2.ZERO
var laser_palm_width := 0.0
var hit_effect_texture: Texture2D
var white_key_poses: Dictionary = {}
var source_facing := -1.0
var white_key_material: ShaderMaterial
var weapon_shift: Node
const WeaponShift := preload("res://scripts/combat/weapon_shift_fx.gd")
const NOREN := {
	"idle": [Vector2(710,1240),0.099], "move": [Vector2(920,1048),0.103],
	"slash": [Vector2(725,1110),0.103], "pierce": [Vector2(1000,941),0.132],
	"block": [Vector2(550,1140),0.103], "damaged": [Vector2(700,1230),0.099],
	"gun_idle": [Vector2(660,1230),0.099], "shoot": [Vector2(714,1210),0.099], "retreat": [Vector2(560,1155),0.099],
	"gun_block": [Vector2(550,1140),0.103], "gun_damaged": [Vector2(700,1230),0.099]
}

func pose_calibrations() -> Dictionary:
	return calibrations

func setup_player(origin: Vector2, direction: float) -> void:
	is_player = true
	kind = "noren"
	calibrations = NOREN.duplicate(true)
	for key in calibrations:
		poses[key] = load("res://assets/combat_test/noren/noren_%s.png" % key)
	poses["shoot"] = preload("res://assets/combat_test/noren/noren_shoot_planted.png")
	_place(origin,direction)

func setup_enemy(visual: EnemyVisualResolver.Visual, origin: Vector2, direction: float) -> void:
	# All parsing, resource loading and fallback have already finished at the boundary.
	is_player = false
	kind = visual.id
	poses = visual.poses.duplicate()
	calibrations = visual.calibrations.duplicate(true)
	pose_aliases = visual.pose_aliases.duplicate(true)
	target_bounds = visual.target_bounds
	attack_style_override = visual.attack_style_override
	laser_muzzle = visual.laser_muzzle
	laser_palm_width = visual.laser_palm_width
	hit_effect_texture = visual.hit_effect_texture
	white_key_poses = visual.white_key_poses.duplicate()
	source_facing = visual.source_facing
	if true in white_key_poses.values():
		white_key_material = ShaderMaterial.new()
		white_key_material.shader = preload("res://shaders/white_key.gdshader")
	_place(origin,direction)

func _place(origin: Vector2, direction: float) -> void:
	home = origin
	position = origin
	facing = direction
	tint = Color("ff4c9b") if is_player else Color("6ae4f2")
	add_child(sprite)
	sprite.centered = false
	set_pose("idle")

func set_pose(value: String) -> void:
	value = pose_aliases.get(value, value)
	if is_player and combat_stance == "ranged" and value in ["idle","block","damaged"]:
		value = "gun_"+value
	pose = value if poses.has(value) else "idle"
	var calibration: Array = pose_calibrations()[pose]
	var anchor: Vector2 = calibration[0]
	var factor: float = calibration[1]
	sprite.texture = poses[pose]
	# Player stance transitions temporarily own the sprite's material.
	if not is_player:
		sprite.material = white_key_material if white_key_poses.get(pose, false) else null
	# Mirror the source art and its soles together; each profile declares its facing.
	sprite.scale = Vector2(facing*source_facing,1)*factor
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
	if not is_player or value == combat_stance or not is_inside_tree():
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
