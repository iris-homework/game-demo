extends RefCounted
## Presentation contracts shared by the workbench and production actors.
const Images := preload("res://enemy_asset_pipeline/runtime/pipeline_image.gd")
const STYLES := ["hit", "slash", "pierce", "bite", "shoot", "laser"]

static func parse(value, poses, aliases, problems: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	if not poses is Dictionary or not aliases is Dictionary:
		problems.append("attack pose catalog and aliases must be objects")
		return result
	if not value is Dictionary:
		problems.append("pipelineAttacks must be an object")
		return result
	for key in value:
		if not key in STYLES or not value[key] is Dictionary:
			problems.append("pipelineAttacks: unsupported action " + str(key))
			return {}
		var entry: Dictionary = value[key].duplicate(true)
		if not entry.get("type") in ["hit", "bite", "shoot", "laser"]:
			problems.append("%s: invalid attack type" % key)
			return {}
		if not entry.get("movement") in ["approach", "stationary", "retreat"]:
			problems.append("%s: invalid attack movement" % key)
			return {}
		if entry.type in ["shoot", "laser"] and entry.movement == "approach":
			problems.append("%s: ranged attacks cannot approach the target" % key)
			return {}
		for field in ["windupPose", "strikePose", "recoveryPose"]:
			var pose_name = entry.get(field)
			if not pose_name is String or not poses.has(aliases.get(pose_name, pose_name)):
				problems.append("%s: missing %s pose %s" % [key, field, str(pose_name)])
				return {}
		for field in ["windup", "impactDelay", "recovery", "flightTime"]:
			var number = entry.get(field)
			if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or number > 10:
				problems.append("%s: %s must be between 0 and 10 seconds" % [key, field])
				return {}
		for field in ["muzzle", "contact"]:
			var point = entry.get(field)
			if not point is Array or point.size() != 2:
				problems.append("%s: invalid %s point" % [key, field])
				return {}
			for number in point:
				if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 100000:
					problems.append("%s: invalid %s coordinates" % [key, field])
					return {}
			entry[field] = Vector2(float(point[0]), float(point[1]))
		for field in ["muzzleTexture", "projectileTexture", "impactTexture"]:
			var path = entry.get(field, "")
			if not path is String:
				problems.append("%s: %s must be a resource path" % [key, field])
				return {}
			entry[field] = null
			if not path.is_empty():
				entry[field] = Images.load_texture(path)
				if entry[field] == null:
					problems.append("%s: missing or unsafe %s" % [key, field])
					return {}
		result[key] = entry
	return result
