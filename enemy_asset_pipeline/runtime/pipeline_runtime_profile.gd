class_name PipelineRuntimeProfile
extends RefCounted
## Validated playback data from catalog.profiles[id].

const PipelineImageScript := preload("res://enemy_asset_pipeline/runtime/pipeline_image.gd")

class Frame:
	var texture: Texture2D
	var transform: Transform2D = Transform2D.IDENTITY
	var duration := 0.1
	var loop := false
	var source_index := -1
	var audio: Array[AudioStream] = []
	var audio_paths: Array[String] = []
	var attachments: Array = []
	var xsxb: Dictionary = {}


class Attachment:
	var texture: Texture2D
	var use_affine := false
	var transform: Transform2D = Transform2D.IDENTITY
	var offset := Vector2.ZERO
	var visual_scale := Vector2.ONE
	var rotation_degrees := 0.0
	var layer_order := 1.0
	var centered := true
	var xsxb: Dictionary = {}


var id := ""
var frames: Dictionary = {}
var shadow: Dictionary = {}
var motion: Dictionary = {}
var effects: Dictionary = {}
var xsxb: Dictionary = {}
var attack_trails: Dictionary = {}
var attacks: Dictionary = {}
var source_facing := 0.0
var has_pipeline := false


static func parse(raw, expected_id: String, problems: Array[String]) -> PipelineRuntimeProfile:
	if not raw is Dictionary:
		problems.append("%s: pipeline profile must be an object" % expected_id)
		return null
	var data: Dictionary = raw
	if data.has("id") and (not data.id is String or data.id != expected_id):
		problems.append("%s: pipeline profile id differs from catalog key" % expected_id)
		return null
	var profile = load("res://enemy_asset_pipeline/runtime/pipeline_runtime_profile.gd").new()
	profile.id = expected_id
	if data.has("pipelineXsxb"):
		profile.has_pipeline = true
		if not data.pipelineXsxb is Dictionary:
			problems.append("%s: pipelineXsxb must be an object" % expected_id)
			return null
		profile.xsxb = data.pipelineXsxb.duplicate(true)
	if data.has("pipelineAttackTrails"):
		profile.has_pipeline = true
		if not data.pipelineAttackTrails is Dictionary:
			problems.append("%s: pipelineAttackTrails must be an object" % expected_id)
			return null
		profile.attack_trails = data.pipelineAttackTrails.duplicate(true)
	if data.has("sourceFacing"):
		if not data.sourceFacing is String or not data.sourceFacing in ["left", "right"]:
			problems.append("%s: sourceFacing must be left or right" % expected_id)
			return null
		profile.source_facing = 1.0 if data.sourceFacing == "right" else -1.0
	if data.has("pipelineFrames"):
		profile.has_pipeline = true
		if not data.pipelineFrames is Dictionary:
			problems.append("%s: pipelineFrames must be an object" % expected_id)
			return null
		for pose in data.pipelineFrames:
			if not pose is String or pose.is_empty():
				problems.append("%s: pipelineFrames pose names must be non-empty strings" % expected_id)
				return null
			var parsed := _parse_pose_frames(expected_id, pose, data.pipelineFrames[pose], problems)
			if parsed.is_empty():
				if problems.is_empty():
					problems.append("%s/%s: frame sequence could not be parsed" % [expected_id, pose])
				return null
			profile.frames[pose] = parsed
	if data.has("pipelineShadow"):
		profile.has_pipeline = true
		var parsed_shadow := _parse_shadow(expected_id, data.pipelineShadow, problems)
		if not problems.is_empty():
			return null
		profile.shadow = parsed_shadow
	if data.has("pipelineMotion"):
		profile.has_pipeline = true
		var parsed_motion := _parse_motion(expected_id, data.pipelineMotion, problems)
		if not problems.is_empty():
			return null
		profile.motion = parsed_motion
	if data.has("pipelineEffects"):
		profile.has_pipeline = true
		var parsed_effects := _parse_effects(expected_id, data.pipelineEffects, problems)
		if not problems.is_empty():
			return null
		profile.effects = parsed_effects
	if data.has("pipelineAttacks"):
		profile.has_pipeline = true
		profile.attacks = preload("res://enemy_asset_pipeline/runtime/pipeline_attack_config.gd").parse(
			data.pipelineAttacks, data.get("poses", {}), data.get("poseAliases", {}), problems)
	return profile if problems.is_empty() else null


static func _parse_pose_frames(expected_id: String, pose: String, value, problems: Array[String]) -> Array:
	var source = value
	var pose_loop := false
	if value is Dictionary:
		source = value.get("frames", [])
		if not value.get("loop", false) is bool:
			problems.append("%s/%s: pose loop must be a boolean" % [expected_id, pose])
			return []
		pose_loop = bool(value.get("loop", false))
	if not source is Array or source.is_empty():
		problems.append("%s/%s: pipelineFrames must be a non-empty array" % [expected_id, pose])
		return []
	var result: Array = []
	for index in source.size():
		var entry = source[index]
		if not entry is Dictionary:
			problems.append("%s/%s[%d]: frame must be an object" % [expected_id, pose, index])
			return []
		var frame := Frame.new()
		var path: String = _string_value(entry.get("texture", entry.get("path", "")))
		frame.texture = PipelineImageScript.load_texture(path)
		if frame.texture == null:
			problems.append("%s/%s[%d]: missing or unsafe texture %s" % [expected_id, pose, index, path])
			return []
		if not _numbers(entry.get("transform"), 6):
			problems.append("%s/%s[%d]: transform needs six finite numbers" % [expected_id, pose, index])
			return []
		var values: Array = entry.transform
		frame.transform = _transform_from_values(values)
		if not _number(entry.get("duration")) or float(entry.duration) <= 0.0:
			problems.append("%s/%s[%d]: duration must be positive seconds" % [expected_id, pose, index])
			return []
		frame.duration = float(entry.duration)
		if entry.has("loop") and not entry.loop is bool:
			problems.append("%s/%s[%d]: loop must be a boolean" % [expected_id, pose, index])
			return []
		frame.loop = bool(entry.get("loop", pose_loop))
		var audio_value = entry.get("audio", [])
		if not audio_value is Array:
			problems.append("%s/%s[%d]: audio must be an array" % [expected_id, pose, index])
			return []
		for audio_entry in audio_value:
			var audio_path := _audio_path(audio_entry)
			if audio_path.is_empty():
				continue
			# Reject paths that could escape res://, but keep the visual usable
			# when an optional SFX file was removed, matching the native tuner.
			if not PipelineImageScript.is_project_path(audio_path):
				problems.append("%s/%s[%d]: unsafe audio path %s" % [expected_id, pose, index, audio_path])
				return []
			var stream: AudioStream = PipelineImageScript.load_audio(audio_path)
			if stream == null:
				# The native tuner silently skips a missing optional clip.
				continue
			frame.audio.append(stream)
			frame.audio_paths.append(audio_path)
		var attachment_value = entry.get("attachments", [])
		if not attachment_value is Array:
			problems.append("%s/%s[%d]: attachments must be an array" % [expected_id, pose, index])
			return []
		for attachment_index in attachment_value.size():
			var attachment := _parse_attachment(expected_id, pose, index, attachment_index, attachment_value[attachment_index], problems)
			if attachment == null:
				return []
			frame.attachments.append(attachment)
		if entry.get("xsxb", entry.get("xsxbFrame", {})) is Dictionary:
			frame.xsxb = entry.get("xsxb", entry.get("xsxbFrame", {})).duplicate(true)
			if frame.xsxb.has("index") and _number(frame.xsxb.index):
				frame.source_index = int(frame.xsxb.index)
			elif frame.xsxb.has("frame") and _number(frame.xsxb.frame):
				frame.source_index = int(frame.xsxb.frame)
		elif _number(entry.get("index")):
			frame.source_index = int(entry.index)
		if frame.source_index < 0:
			frame.source_index = index
		result.append(frame)
	return result


static func _parse_attachment(expected_id: String, pose: String, frame_index: int, attachment_index: int, value, problems: Array[String]) -> Attachment:
	var where := "%s/%s[%d].attachments[%d]" % [expected_id, pose, frame_index, attachment_index]
	if not value is Dictionary:
		problems.append(where+": attachment must be an object")
		return null
	var data: Dictionary = value
	var path := _attachment_path(data)
	var attachment := Attachment.new()
	attachment.texture = PipelineImageScript.load_texture(path)
	if attachment.texture == null:
		problems.append(where+": missing or unsafe attachment texture "+path)
		return null
	var transform_value = data.get("transform", null)
	if transform_value is Array:
		if not _numbers(transform_value, 6):
			problems.append(where+": transform needs six finite numbers")
			return null
		var t: Array = transform_value
		attachment.use_affine = true
		attachment.centered = false
		attachment.transform = _transform_from_values(t)
	elif transform_value is Dictionary:
		data = _merge_dictionaries(data, transform_value)
	elif transform_value != null:
		problems.append(where+": transform must be an array or object")
		return null
	if not attachment.use_affine:
		var offset_value = data.get("offset", [0, 0])
		if not _vector(offset_value):
			problems.append(where+": offset must contain two finite numbers")
			return null
		attachment.offset = _vector_value(offset_value)
		var scale_value = data.get("visual_scale", data.get("scale", 1.0))
		if not _scale_value(scale_value):
			problems.append(where+": scale must be finite")
			return null
		attachment.visual_scale = _scale_vector(scale_value)
		var rotation_value = data.get("rotation", 0.0)
		if not _number(rotation_value):
			problems.append(where+": rotation must be finite degrees")
			return null
		attachment.rotation_degrees = float(rotation_value)
		if data.get("centered", true) is bool:
			attachment.centered = bool(data.get("centered", true))
	var layer_value = data.get("layerOrder", null)
	if layer_value != null:
		if not _number(layer_value):
			problems.append(where+": layerOrder must be finite")
			return null
		if absf(float(layer_value)) > 0.0001:
			attachment.layer_order = float(layer_value)
		elif data.get("layer", "above") is String:
			attachment.layer_order = -1.0 if data.layer == "below" else 1.0
	elif data.get("layer", "above") is String:
		attachment.layer_order = -1.0 if data.layer == "below" else 1.0
	var xsxb_value = data.get("xsxb", {})
	if xsxb_value is Dictionary:
		attachment.xsxb = xsxb_value.duplicate(true)
	return attachment


static func _parse_shadow(expected_id: String, value, problems: Array[String]) -> Dictionary:
	if not value is Dictionary:
		problems.append(expected_id+": pipelineShadow must be an object")
		return {}
	var data: Dictionary = value
	var result := {"enabled": true, "size": Vector2(32, 9), "offset": Vector2(0, 2), "opacity": 0.7}
	if data.has("enabled"):
		if not data.enabled is bool:
			problems.append(expected_id+": pipelineShadow.enabled must be boolean")
			return {}
		result.enabled = data.enabled
	if data.has("size"):
		if not _vector(data.size) or float(data.size[0]) < 0.0 or float(data.size[1]) < 0.0:
			problems.append(expected_id+": pipelineShadow.size needs non-negative finite numbers")
			return {}
		result.size = _vector_value(data.size)
	if data.has("offset"):
		if not _vector(data.offset):
			problems.append(expected_id+": pipelineShadow.offset needs two finite numbers")
			return {}
		result.offset = _vector_value(data.offset)
	if data.has("opacity"):
		if not _number(data.opacity) or float(data.opacity) < 0.0 or float(data.opacity) > 1.0:
			problems.append(expected_id+": pipelineShadow.opacity must be within 0..1")
			return {}
		result.opacity = float(data.opacity)
	return result


static func _parse_motion(expected_id: String, value, problems: Array[String]) -> Dictionary:
	if not value is Dictionary:
		problems.append(expected_id+": pipelineMotion must be an object")
		return {}
	var result: Dictionary = {}
	for key in ["speed", "reach", "windup", "recovery"]:
		if not value.has(key):
			continue
		if not _number(value[key]) or float(value[key]) < 0.0 or (key == "speed" and float(value[key]) <= 0.0):
			problems.append("%s: pipelineMotion.%s is invalid" % [expected_id, key])
			return {}
		result[key] = float(value[key])
	return result


static func _parse_effects(expected_id: String, value, problems: Array[String]) -> Dictionary:
	if not value is Dictionary:
		problems.append(expected_id+": pipelineEffects must be an object")
		return {}
	var result: Dictionary = {}
	if value.has("scale"):
		if not _number(value.scale) or float(value.scale) < 0.0:
			problems.append(expected_id+": pipelineEffects.scale must be non-negative")
			return {}
		result.scale = float(value.scale)
	if value.has("offset"):
		if not _vector(value.offset):
			problems.append(expected_id+": pipelineEffects.offset needs two finite numbers")
			return {}
		result.offset = _vector_value(value.offset)
	if value.has("hitStop"):
		if not _number(value.hitStop) or float(value.hitStop) < 0.0:
			problems.append(expected_id+": pipelineEffects.hitStop must be non-negative seconds")
			return {}
		result.hitStop = float(value.hitStop)
	if value.has("shake"):
		var shake = value.shake
		if shake is bool:
			result.shake = shake
		elif _number(shake):
			if float(shake) < 0.0:
				problems.append(expected_id+": pipelineEffects.shake strength must be non-negative")
				return {}
			result.shake = float(shake)
		elif shake is Dictionary:
			var parsed: Dictionary = {}
			for key in ["strength", "duration"]:
				if shake.has(key):
					if not _number(shake[key]) or float(shake[key]) < 0.0:
						problems.append("%s: pipelineEffects.shake.%s is invalid" % [expected_id, key])
						return {}
					parsed[key] = float(shake[key])
			result.shake = parsed
		else:
			problems.append(expected_id+": pipelineEffects.shake must be bool, number or object")
			return {}
	return result


static func _merge_dictionaries(base: Dictionary, overlay: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key in overlay:
		result[key] = overlay[key]
	return result


static func _transform_from_values(values: Array) -> Transform2D:
	return Transform2D(
		Vector2(float(values[0]),float(values[1])),
		Vector2(float(values[2]),float(values[3])),
		Vector2(float(values[4]),float(values[5]))
	)


static func _string_value(value) -> String:
	return value if value is String else ""


static func _audio_path(value) -> String:
	if value is String:
		return value
	if not value is Dictionary:
		return ""
	for key in ["path","file","audioPath","audio_path","streamPath"]:
		var candidate := _string_value(value.get(key,""))
		if not candidate.is_empty():
			return candidate
	return ""


static func _attachment_path(data: Dictionary) -> String:
	for key in ["path","texturePath","texture_path","assetPath","sourceAssetPath","texture","image"]:
		var candidate := _string_value(data.get(key,""))
		if not candidate.is_empty():
			return candidate
	return ""


static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _numbers(value, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number in value:
		if not _number(number):
			return false
	return true


static func _vector(value) -> bool:
	return _numbers(value, 2)


static func _vector_value(value) -> Vector2:
	if value is Array:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO


static func _scale_value(value) -> bool:
	if _number(value):
		return is_finite(float(value))
	if value is Array:
		return _numbers(value, 2)
	if value is Dictionary:
		return _number(value.get("x", 0.0)) and _number(value.get("y", 0.0))
	return false


static func _scale_vector(value) -> Vector2:
	if _number(value):
		return Vector2.ONE * float(value)
	if value is Array:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.x), float(value.y))
	return Vector2.ONE
