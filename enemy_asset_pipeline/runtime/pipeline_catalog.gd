class_name PipelineCatalog
extends RefCounted
## Read-only merged catalog: published profiles first, optional preview by id.
## Bindings map a formal enemy id to the visual/profile that should render it.

const PUBLISHED_PATH := "res://enemy_asset_pipeline/published/catalog.json"
const SCHEMA_VERSION := 1

static var preview_path_override: String = ""
static var published_path_override: String = ""

static var _cache: Dictionary = {}
static var _diagnostics: Array[String] = []
static var _revision := 0
static var _source_signature := ""


static func reload() -> void:
	_cache.clear()
	_diagnostics.clear()
	_revision += 1
	_source_signature = _catalog_signature()


static func refresh() -> void:
	reload()


static func refresh_if_changed() -> bool:
	## Called at a new-battle resolution boundary. A content signature also
	## detects same-size publications within one filesystem timestamp tick.
	var signature := _catalog_signature()
	if signature == _source_signature and not _cache.is_empty():
		return false
	reload()
	return true


static func load_profiles() -> Dictionary:
	## Entry points use this when files may have changed since the previous read.
	reload()
	return get_profiles()


static func set_preview_path(path: String) -> void:
	preview_path_override = path
	reload()


static func clear_preview() -> void:
	preview_path_override = ""
	reload()


static func set_published_path(path: String) -> void:
	## Test isolation hook. Production keeps PUBLISHED_PATH.
	published_path_override = path
	reload()


static func clear_published_path() -> void:
	published_path_override = ""
	reload()


static func published_path() -> String:
	return published_path_override if not published_path_override.is_empty() else PUBLISHED_PATH


static func revision() -> int:
	return _revision


static func get_diagnostics() -> Array[String]:
	_load_if_needed()
	return _diagnostics.duplicate()


static func get_catalog() -> Dictionary:
	_load_if_needed()
	var key := _cache_key()
	return _cache.get(key, {}).duplicate(true)


static func get_profiles() -> Dictionary:
	var data := get_catalog()
	var profiles = data.get("profiles", {})
	return profiles.duplicate(true) if profiles is Dictionary else {}


static func get_bindings() -> Dictionary:
	var data := get_catalog()
	var bindings = data.get("bindings", {})
	return bindings.duplicate(true) if bindings is Dictionary else {}


static func has_profile(id: String) -> bool:
	return get_profiles().has(id)


static func get_profile(id: String) -> Dictionary:
	var value = get_profiles().get(id)
	return value.duplicate(true) if value is Dictionary else {}


static func get_profile_source(id: String) -> String:
	_load_if_needed()
	var data: Dictionary = _cache.get(_cache_key(), {})
	var sources = data.get("sources", {})
	return String(sources.get(id, "")) if sources is Dictionary else ""


static func get_bound_profile_id(enemy_id: String, fallback_id: String) -> String:
	## A binding only wins when it points at a profile in the same merged catalog.
	if enemy_id.is_empty():
		return fallback_id
	var data := get_catalog()
	var bindings = data.get("bindings", {})
	if not bindings is Dictionary:
		return fallback_id
	var target := String(bindings.get(enemy_id, ""))
	var profiles = data.get("profiles", {})
	if target.is_empty() or not profiles is Dictionary or not profiles.has(target):
		return fallback_id
	return target


static func _cache_key() -> String:
	return published_path()+"|"+preview_path_override


static func _catalog_signature() -> String:
	var published := published_path()
	var preview := preview_path_override
	var published_hash := FileAccess.get_sha256(published) if FileAccess.file_exists(published) else "missing"
	var preview_hash := FileAccess.get_sha256(preview) if FileAccess.file_exists(preview) else "missing"
	return published+":"+published_hash+"|"+preview+":"+preview_hash


static func _load_if_needed() -> void:
	var key := _cache_key()
	if _cache.has(key):
		return
	var problems: Array[String] = []
	var profiles: Dictionary = {}
	var sources: Dictionary = {}
	var bindings: Dictionary = {}
	var binding_sources: Dictionary = {}
	var published := _read_catalog(published_path(), "published", problems)
	for id in published.profiles:
		profiles[id] = published.profiles[id]
		sources[id] = "published"
	for enemy_id in published.bindings:
		bindings[enemy_id] = published.bindings[enemy_id]
		binding_sources[enemy_id] = "published"
	if not preview_path_override.is_empty():
		if not _valid_override_path(preview_path_override):
			problems.append("Preview catalog path must stay inside res:// or user://: "+preview_path_override)
		else:
			var preview := _read_catalog(preview_path_override, "preview", problems)
			for id in preview.profiles:
				profiles[id] = preview.profiles[id]
				sources[id] = "preview"
			# Preview bindings replace published ones only for the same enemy.
			for enemy_id in preview.bindings:
				bindings[enemy_id] = preview.bindings[enemy_id]
				binding_sources[enemy_id] = "preview"
	for enemy_id in bindings.keys():
		var target := String(bindings[enemy_id])
		if not profiles.has(target):
			problems.append("Binding %s -> %s has no profile; falling back." % [enemy_id, target])
			bindings.erase(enemy_id)
			binding_sources.erase(enemy_id)
	_cache[key] = {
		"schemaVersion": SCHEMA_VERSION,
		"profiles": profiles,
		"sources": sources,
		"bindings": bindings,
		"bindingSources": binding_sources,
		"publishedPath": published_path(),
		"previewPath": preview_path_override,
		"diagnostics": problems.duplicate(),
		"revision": _revision,
	}
	_diagnostics = problems


static func _read_catalog(path: String, label: String, problems: Array[String]) -> Dictionary:
	var empty := {"profiles": {}, "bindings": {}}
	if not _valid_override_path(path):
		problems.append("%s catalog path must stay inside res:// or user://: %s" % [label,path])
		return empty
	if not FileAccess.file_exists(path):
		return empty
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		problems.append("%s catalog is not a JSON object: %s" % [label, path])
		return empty
	var data: Dictionary = parser.data
	if not _is_number(data.get("schemaVersion")) or int(data.schemaVersion) != SCHEMA_VERSION:
		problems.append("%s catalog schemaVersion must be %d: %s" % [label, SCHEMA_VERSION, path])
		return empty
	if not data.get("profiles") is Dictionary:
		problems.append("%s catalog profiles must be an object: %s" % [label, path])
		return empty
	var result := {"profiles": {}, "bindings": {}}
	for id in data.profiles:
		if not id is String or id.is_empty() or not data.profiles[id] is Dictionary:
			problems.append("%s catalog contains an invalid profile key/value: %s" % [label, path])
			continue
		result.profiles[id] = data.profiles[id].duplicate(true)
	var raw_bindings = data.get("bindings", {})
	if not raw_bindings is Dictionary:
		problems.append("%s catalog bindings must be an object: %s" % [label, path])
		return result
	for enemy_id in raw_bindings:
		var target = raw_bindings[enemy_id]
		if not enemy_id is String or enemy_id.is_empty() or not target is String or target.is_empty():
			problems.append("%s catalog contains an invalid binding: %s" % [label, path])
			continue
		result.bindings[enemy_id] = target
	return result


static func _valid_override_path(path: String) -> bool:
	if not (path.begins_with("res://") or path.begins_with("user://")):
		return false
	if path.contains("\\"):
		return false
	for part in path.split("/"):
		if part == "..":
			return false
	return true


static func _is_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))
