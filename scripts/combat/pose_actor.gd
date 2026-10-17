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
var calibrations: Dictionary = {}
var pose_aliases: Dictionary = {}
var target_bounds := Rect2(-58,-130,116,145)
var attack_style_override := ""
var hit_effect_texture: Texture2D
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

func setup(actor_kind: String, origin: Vector2, direction: float) -> void:
	kind = actor_kind
	home = origin
	position = origin
	facing = direction
	tint = Color("ff4c9b") if kind == "noren" else Color("6ae4f2")
	add_child(sprite)
	sprite.centered = false
	if kind == "noren":
		calibrations = NOREN.duplicate(true)
		for key in calibrations:
			poses[key] = load("res://assets/combat_test/noren_%s.png" % key)
		# Match gun idle's planted feet; retain the original lunge artwork as a source.
		poses["shoot"] = preload("res://assets/combat_test/noren_shoot_planted.png")
	else:
		if not Game.enemy_visual_catalog.has(kind):
			push_warning("Unknown combat visual '%s'; using Finn placeholder." % kind)
			kind = "finn"
		var visual: Dictionary = Game.enemy_visual_catalog[kind]
		pose_aliases = visual.get("poseAliases", {}).duplicate(true)
		attack_style_override = visual.get("attackStyleOverride", "")
		var bounds: Array = visual.targetRect
		target_bounds = Rect2(bounds[0],bounds[1],bounds[2],bounds[3])
		var effect_path: String = visual.get("hitEffectTexture", "")
		if not effect_path.is_empty(): hit_effect_texture = load(effect_path)
		for key in visual.poses:
			var entry: Dictionary = visual.poses[key]
			calibrations[key] = [Vector2(entry.anchor[0],entry.anchor[1]),float(entry.scale)]
			poses[key] = load(entry.texture)
	set_pose("idle")

func set_pose(value: String) -> void:
	value = pose_aliases.get(value, value)
	if kind == "noren" and combat_stance == "ranged" and value in ["idle","block","damaged"]:
		value = "gun_"+value
	pose = value if poses.has(value) else "idle"
	var calibration: Array = pose_calibrations()[pose]
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
