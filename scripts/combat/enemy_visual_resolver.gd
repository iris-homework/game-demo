class_name EnemyVisualResolver
extends RefCounted
## The only boundary between authored enemy visuals and render-ready actor data.
const CATALOG_PATH := "res://data/enemies/combat_visuals.json"
const EMERGENCY_IDLE := preload("res://assets/combat_test/finn_idle.webp")
const ATTACK_STYLES := ["", "slash", "pierce", "bite", "shoot"]
const FORMATION_SLOTS := ["", "triangle_left_back", "triangle_left_front", "triangle_right"]

class Visual extends RefCounted:
	var id := ""
	var poses: Dictionary = {}
	var calibrations: Dictionary = {}
	var pose_aliases: Dictionary = {}
	var target_bounds := Rect2(-58,-130,116,145)
	var attack_style_override := ""
	var hit_effect_texture: Texture2D
	var white_key_poses: Dictionary = {}
	var source_facing := -1.0
	var formation_slot := ""
	var diagnostics: Array[String] = []

var catalog: Dictionary = {}
var load_error := ""

func _init(path: String = CATALOG_PATH) -> void:
	if not FileAccess.file_exists(path):
		load_error = "Missing visual catalog: "+path
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		load_error = "Visual catalog must be a JSON object: "+path
		return
	catalog = parser.data

func resolve(enemy: Dictionary, enemies: Dictionary) -> Visual:
	var problems: Array[String] = []
	if not load_error.is_empty(): problems.append(load_error)
	var candidates: Array = []
	if enemy.has("combatVisualId"): candidates.append(enemy.combatVisualId)
	var current = enemies.get(enemy.get("id", ""), {})
	if current is Dictionary and current.has("combatVisualId"):
		candidates.append(current.combatVisualId)
	candidates.append("finn")
	var visited: Array[String] = []
	for id in candidates:
		if not id is String or id.is_empty():
			problems.append("combatVisualId must be a non-empty string")
			continue
		if id in visited: continue
		visited.append(id)
		var visual := _parse(id, catalog.get(id), problems)
		if visual != null: return _finish(visual, problems, enemy, current)
	# This single code-owned pose survives a missing/broken Finn catalog entry.
	var emergency := Visual.new()
	emergency.id = "fallback_finn"
	emergency.poses = {"idle":EMERGENCY_IDLE}
	emergency.calibrations = {"idle":[Vector2(150,237),0.495]}
	return _finish(emergency, problems, enemy, current)

func _finish(visual: Visual, problems: Array[String], enemy: Dictionary, current) -> Visual:
	# Formation belongs to the encounter's enemy instance, never to the art profile.
	var slot = enemy.get("formationSlot", current.get("formationSlot", "") if current is Dictionary else "")
	if slot is String and slot in FORMATION_SLOTS:
		visual.formation_slot = slot
	else:
		problems.append("unsupported formationSlot")
	visual.diagnostics = problems.duplicate()
	if not problems.is_empty():
		push_warning("Enemy '%s' visual -> '%s': %s" % [enemy.get("id", ""), visual.id, "; ".join(problems)])
	return visual

func _invalid(problems: Array[String], id: String, reason: String) -> Visual:
	problems.append("%s: %s" % [id, reason])
	return null

func _parse(id: String, raw, problems: Array[String]) -> Visual:
	if not raw is Dictionary: return _invalid(problems,id,"missing profile/object")
	if raw.get("id") != id: return _invalid(problems,id,"profile id differs from catalog key")
	var bounds = raw.get("targetRect")
	if not _numbers(bounds,4): return _invalid(problems,id,"targetRect needs four finite numbers")
	if bounds[2] <= 0 or bounds[3] <= 0: return _invalid(problems,id,"targetRect needs positive dimensions")
	var poses = raw.get("poses")
	if not poses is Dictionary or not poses.has("idle"):
		return _invalid(problems,id,"poses must include idle")
	var aliases = raw.get("poseAliases", {})
	if not aliases is Dictionary: return _invalid(problems,id,"poseAliases must be an object")
	for alias in aliases:
		if not alias is String or alias.is_empty() or not aliases[alias] is String or not poses.has(aliases[alias]):
			return _invalid(problems,id,"poseAliases must point directly to an existing pose")
	var style = raw.get("attackStyleOverride", "")
	if not style is String or not style in ATTACK_STYLES:
		return _invalid(problems,id,"unsupported attackStyleOverride")
	var source_facing = raw.get("sourceFacing", "left")
	if not source_facing is String or not source_facing in ["left", "right"]:
		return _invalid(problems,id,"sourceFacing must be left or right")
	var visual := Visual.new()
	visual.id = id
	visual.source_facing = 1.0 if source_facing == "right" else -1.0
	visual.target_bounds = Rect2(bounds[0],bounds[1],bounds[2],bounds[3])
	if not visual.target_bounds.position.is_finite() or not visual.target_bounds.size.is_finite() or visual.target_bounds.size.x <= 0 or visual.target_bounds.size.y <= 0:
		return _invalid(problems,id,"targetRect exceeds vector range")
	visual.pose_aliases = aliases.duplicate(true)
	visual.attack_style_override = style
	for pose in poses:
		if not pose is String or pose.is_empty() or not poses[pose] is Dictionary:
			return _invalid(problems,id,"each pose must be a named object")
		var entry: Dictionary = poses[pose]
		if not entry.get("whiteKey", false) is bool:
			return _invalid(problems,id,"whiteKey must be a boolean for "+pose)
		if not _numbers(entry.get("anchor"),2) or not _number(entry.get("scale")) or entry.scale <= 0:
			return _invalid(problems,id,"invalid anchor/scale for "+pose)
		var anchor := Vector2(entry.anchor[0],entry.anchor[1])
		var factor := float(entry.scale)
		var sprite_scale := Vector2.ONE*factor
		if not anchor.is_finite() or not (anchor*factor).is_finite() or not sprite_scale.is_finite() or sprite_scale.x <= 0:
			return _invalid(problems,id,"calibration exceeds vector range for "+pose)
		var texture := _texture(entry.get("texture"))
		if texture == null: return _invalid(problems,id,"missing/non-texture resource for "+pose)
		visual.poses[pose] = texture
		visual.calibrations[pose] = [anchor,factor]
		visual.white_key_poses[pose] = entry.get("whiteKey", false)
	var effect = raw.get("hitEffectTexture", "")
	if not effect is String: return _invalid(problems,id,"hitEffectTexture must be a path string")
	if not effect.is_empty():
		visual.hit_effect_texture = _texture(effect)
		if visual.hit_effect_texture == null: return _invalid(problems,id,"missing/non-texture hit effect")
	var required: Array = ["bite","bite_close"] if style == "bite" else (["shoot"] if style == "shoot" else [])
	for pose in required:
		if not visual.poses.has(aliases.get(pose,pose)):
			return _invalid(problems,id,"attack style requires pose "+pose)
	if style == "bite" and visual.hit_effect_texture == null:
		return _invalid(problems,id,"bite requires a hit effect texture")
	return visual

func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _numbers(value, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number in value:
		if not _number(number): return false
	return true

func _texture(path) -> Texture2D:
	if not path is String or not path.begins_with("res://") or not ResourceLoader.exists(path): return null
	var resource = load(path)
	if not resource is Texture2D or resource.get_width() <= 0 or resource.get_height() <= 0: return null
	return resource
