extends RefCounted
## Test-only display names taken from the real assets/combat_test folders.
## The formal enemy catalog, visual catalog and saves stay untouched.

const ROOT := "res://assets/combat_test"
const SKIPPED_PREFIX := "reference"
const FIXED_NAMES := {"noren":"noren", "unillustrated":"无立绘"}

static var _names: Dictionary = {}
static var _scanned := false


static func reset_cache() -> void:
	_names.clear()
	_scanned = false


static func names() -> Dictionary:
	if not _scanned:
		_scan()
	return _names.duplicate()


static func name_for_visual(visual_id: String) -> String:
	# Match the web role ids: case-insensitive lookup, lower-case display.
	var id := visual_id.to_lower().trim_prefix("visual:")
	if id.is_empty():
		return visual_id.to_lower()
	if not _scanned:
		_scan()
	if FIXED_NAMES.has(id):
		return str(FIXED_NAMES[id])
	return str(_names.get(id, id))


static func visual_id_from_directory(directory_name: String) -> String:
	var name := directory_name.to_lower()
	if _has_numbered_prefix(name):
		return name.substr(4)
	return name


static func display_name_from_directory(directory_name: String) -> String:
	return directory_name.to_lower()


static func is_skipped_directory(directory_name: String) -> bool:
	# Match the web roleForDirectory rule: reference, reference_*, reference-*.
	var name := directory_name.to_lower()
	return name == SKIPPED_PREFIX or name.begins_with(SKIPPED_PREFIX+"_") or name.begins_with(SKIPPED_PREFIX+"-")


static func is_role_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	var first := value.unicode_at(0)
	if first < 97 or first > 122:
		return false
	for index in range(1,value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


static func is_ascii(value: String) -> bool:
	for index in value.length():
		if value.unicode_at(index) > 127:
			return false
	return true


static func _has_numbered_prefix(directory_name: String) -> bool:
	# Numbered art folders use two digits, one lowercase letter and an underscore.
	var name := directory_name.to_lower()
	if name.length() < 5:
		return false
	if not name.substr(0,2).is_valid_int():
		return false
	var letter := name.unicode_at(2)
	return letter >= 97 and letter <= 122 and name.unicode_at(3) == 95


static func _scan() -> void:
	_scanned = true
	_names = FIXED_NAMES.duplicate()
	var directory := DirAccess.open(ROOT)
	if directory == null:
		return
	var entries := directory.get_directories()
	entries.sort()
	for entry in entries:
		if entry.begins_with(".") or is_skipped_directory(entry) or not is_ascii(entry):
			continue
		var visual := visual_id_from_directory(entry)
		if not is_role_id(visual) or _names.has(visual):
			continue
		_names[visual] = display_name_from_directory(entry)
