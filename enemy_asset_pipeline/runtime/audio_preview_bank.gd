extends "res://scripts/audio/sfx_player.gd"
## Developer-only scanner; released audio never reads incoming or preview plans.

const PipelineImageScript := preload("res://enemy_asset_pipeline/runtime/pipeline_image.gd")
const CANDIDATE_ROOT := "res://assets/audio/incoming"
var entries: Array[Dictionary] = []

func _ready() -> void:
	super._ready()
	scan()

func scan(root: String = CANDIDATE_ROOT) -> Array:
	var scan_root := _valid_scan_root(root)
	if scan_root.is_empty():
		return []

	var found: Array[Dictionary] = []
	_scan_directory(scan_root, scan_root, found)
	found.sort_custom(_entry_before)
	entries = found
	_prune_bindings()
	for cue in DEFAULT_BINDINGS:
		if not bindings.has(cue):
			if DEFAULT_BINDINGS[cue].is_empty():
				bindings[cue] = ""
				continue
			var path := scan_root.path_join(DEFAULT_BINDINGS[cue])
			if _has_entry(path):
				bindings[cue] = path
	library_changed.emit()
	return entries


func _valid_scan_root(root: String) -> String:
	var cleaned := root.strip_edges().trim_suffix("/")
	if not PipelineImageScript.is_project_path(cleaned):
		return ""
	if cleaned != CANDIDATE_ROOT and not cleaned.begins_with(CANDIDATE_ROOT+"/"):
		return ""
	var suffix := cleaned.trim_prefix(CANDIDATE_ROOT).trim_prefix("/")
	if not suffix.is_empty():
		for part in suffix.split("/"):
			if part.begins_with(".") or part.to_lower() == "_originals":
				return ""
	return cleaned


func _scan_directory(directory: String, scan_root: String, found: Array[Dictionary]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var item := dir.get_next()
	while not item.is_empty():
		var lower := item.to_lower()
		var hidden := item.begins_with(".")
		var excluded := lower == "_originals" or lower == ".import"
		if not hidden and not excluded:
			var path := directory.path_join(item)
			if dir.current_is_dir():
				_scan_directory(path, scan_root, found)
			elif _is_audio_file(path):
				found.append({
					"path": path,
					"category": _category_for(path, scan_root),
					"label": _display_label(path),
				})
		item = dir.get_next()
	dir.list_dir_end()


func _is_audio_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return path.get_extension().to_lower() in SUPPORTED_EXTENSIONS


func _category_for(path: String, scan_root: String) -> String:
	var relative := path.trim_prefix(scan_root).trim_prefix("/")
	var slash := relative.find("/")
	return relative.left(slash) if slash >= 0 else "root"


func _display_label(path: String) -> String:
	return path.get_file().get_basename().replace("_", " ").strip_edges()


func _entry_before(a: Dictionary, b: Dictionary) -> bool:
	return a.path.naturalnocasecmp_to(b.path) < 0


func _has_entry(path: String) -> bool:
	for entry in entries:
		if entry.path == path:
			return true
	return false


func _prune_bindings() -> void:
	for cue in bindings.keys():
		var path = bindings[cue]
		if not CUE_NAMES.has(cue) or not path is String:
			bindings.erase(cue)
		elif not path.is_empty() and not _has_entry(path):
			bindings.erase(cue)


func _load_stream(path: String) -> AudioStream:
	return PipelineImageScript.load_audio(path)
