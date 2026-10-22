class_name PipelineTrailAdapter
extends Node2D
## Thin binding/transform adapter around the upstream XSXB trail renderer.

const TrailRenderer := preload("res://enemy_asset_pipeline/runtime/xsxb_attack_trail_renderer.gd")

var actor: Node
var profile_id := ""
var bindings: Dictionary = {}
var behind: Node2D
var front: Node2D


func configure(owner_actor: Node, source_profile_id: String, xsxb_profile: Dictionary, explicit_trails: Dictionary = {}) -> void:
	actor = owner_actor
	profile_id = source_profile_id
	bindings = derive_bindings(source_profile_id,xsxb_profile,explicit_trails)
	_clear_renderers()
	if bindings.is_empty():
		return
	behind = _create_renderer("behind",TRAIL_LAYER_BEHIND)
	front = _create_renderer("front",TRAIL_LAYER_FRONT)


func sync(owner_transform: Transform2D, animation_name: String, animation_time_s: float, playing: bool = true) -> void:
	for renderer in [behind,front]:
		if not is_instance_valid(renderer):
			continue
		# Group-space trail coordinates use the XSXB owner origin, which is the
		# sprite centre after the manifest anchor/transform has been applied.
		renderer.transform = owner_transform
		if not playing:
			if renderer.has_method("hide_all"):
				renderer.call("hide_all")
			continue
		if renderer.has_method("update_for_animation"):
			renderer.call("update_for_animation",animation_name,animation_time_s)


func has_renderers() -> bool:
	return is_instance_valid(behind) or is_instance_valid(front)


func _create_renderer(name_value: String, layer_value: String) -> Node2D:
	var renderer := TrailRenderer.new() as Node2D
	renderer.name = "Trail"+name_value.capitalize()
	renderer.z_index = -2 if layer_value == TRAIL_LAYER_BEHIND else 2
	add_child(renderer)
	renderer.call("configure",actor,bindings,layer_value)
	return renderer


func _clear_renderers() -> void:
	for child in get_children():
		child.free()
	behind = null
	front = null


static func derive_bindings(source_profile_id: String, xsxb_profile: Dictionary, explicit_trails: Dictionary = {}) -> Dictionary:
	## Accepts buildRuntimeData's single-profile wrapper:
	## {profiles:[{id, animations:[{id, attackTrails:[...]}]}]}
	## and also a bare runtime profile or the older top-level attackTrails map.
	var result: Dictionary = {}
	var runtime_profile := _runtime_profile(source_profile_id,xsxb_profile)
	var profile_key := String(runtime_profile.get("id",source_profile_id))
	var animation_ids: Array[String] = []
	for animation_value in _array_value(runtime_profile.get("animations",[])):
		if not animation_value is Dictionary:
			continue
		var animation: Dictionary = animation_value
		var animation_id := String(animation.get("id",animation.get("name","")))
		if animation_id.is_empty():
			continue
		animation_ids.append(animation_id)
		var trails := _segment_array(animation.get("attackTrails",animation.get("attack_trails",null)))
		if not trails.is_empty():
			result[_binding_key(source_profile_id,animation_id)] = trails
	_merge_binding_source(result,source_profile_id,profile_key,animation_ids,xsxb_profile.get("attackTrails",xsxb_profile.get("attack_trails",null)))
	_merge_binding_source(result,source_profile_id,profile_key,animation_ids,explicit_trails)
	return result


static func _runtime_profile(source_profile_id: String, xsxb_profile: Dictionary) -> Dictionary:
	if not xsxb_profile is Dictionary:
		return {}
	var profiles_value = xsxb_profile.get("profiles",null)
	if profiles_value is Array:
		var first: Dictionary = {}
		for profile_value in profiles_value:
			if not profile_value is Dictionary:
				continue
			if String(profile_value.get("id","")) == source_profile_id:
				return profile_value
			if first.is_empty():
				first = profile_value
		return first
	if profiles_value is Dictionary:
		var selected = profiles_value.get(source_profile_id,null)
		if selected is Dictionary:
			return selected
		for profile_value in profiles_value.values():
			if profile_value is Dictionary:
				return profile_value
	var nested = xsxb_profile.get("profile",null)
	if nested is Dictionary:
		return nested
	return xsxb_profile


static func _merge_binding_source(result: Dictionary, source_profile_id: String, profile_key: String, animation_ids: Array[String], value) -> void:
	if value == null:
		return
	if value is Dictionary:
		var bindings_value = value.get("bindings",null)
		if bindings_value is Dictionary or bindings_value is Array:
			_merge_binding_source(result,source_profile_id,profile_key,animation_ids,bindings_value)
			if value.size() == 1:
				return
		var animations_value = value.get("animations",null)
		if animations_value is Array:
			for animation_value in animations_value:
				if not animation_value is Dictionary:
					continue
				var animation_id := String(animation_value.get("id",animation_value.get("name","")))
				var trails := _segment_array(animation_value.get("attackTrails",animation_value.get("attack_trails",null)))
				if not animation_id.is_empty() and not trails.is_empty():
					result[_binding_key(source_profile_id,animation_id)] = trails
			return
		var added := false
		for raw_key in value:
			if not raw_key is String or raw_key in ["bindings","animations","profile","profiles","presets","presetTexture"]:
				continue
			var segments := _segment_array(value[raw_key])
			if segments.is_empty():
				continue
			var animation_id: String = String(raw_key)
			if animation_id.contains("/"):
				animation_id = animation_id.split("/")[-1]
			elif animation_ids.size() != 1 and not animation_ids.has(animation_id):
				continue
			result[_binding_key(source_profile_id,animation_id)] = segments
			added = true
		if not added and animation_ids.size() == 1:
			var direct := _segment_array(value)
			if not direct.is_empty():
				result[_binding_key(source_profile_id,animation_ids[0])] = direct
		return
	if value is Array:
		var animation_entries := 0
		for entry in value:
			if entry is Dictionary and entry.has("id") and (entry.has("attackTrails") or entry.has("attack_trails")):
				animation_entries += 1
				var animation_id := String(entry.get("id",entry.get("name","")))
				var trails := _segment_array(entry.get("attackTrails",entry.get("attack_trails",null)))
				if not animation_id.is_empty() and not trails.is_empty():
					result[_binding_key(source_profile_id,animation_id)] = trails
		if animation_entries > 0:
			return
		var direct := _segment_array(value)
		if not direct.is_empty() and animation_ids.size() == 1:
			result[_binding_key(source_profile_id,animation_ids[0])] = direct


static func _segment_array(value) -> Array:
	if value == null:
		return []
	if value is Dictionary:
		if value.get("segments",null) is Array:
			return _segment_array(value.segments)
		if value.has("sticks") or value.has("enabled") or value.has("generated"):
			return [value.duplicate(true)]
		return []
	if not value is Array:
		return []
	var result: Array = []
	for entry in value:
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result


static func _array_value(value) -> Array:
	return value if value is Array else []


static func _binding_key(source_profile_id: String, animation_id: String) -> String:
	return "%s/%s" % [source_profile_id,animation_id]


const TRAIL_LAYER_BEHIND := "behind"
const TRAIL_LAYER_FRONT := "front"
