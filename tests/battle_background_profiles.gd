extends RefCounted

## Test-only persistence for the battle background fitting bench.
## The shipped JSON is the initial catalog; runtimes should pass an isolated copy
## when exercising save_current() outside the default fixture.

const DEFAULT_PATH := "res://tests/fixtures/battle_background/scene_profiles.json"
const SCHEMA_VERSION := 1
const DIRTY_EPSILON := 0.00001
const PARAM_KEYS := [
	"scale", "x", "y", "brightness", "saturation", "contrast",
	"fade_start", "fade_strength", "rear_edge_ratio",
]
const PARAM_RANGES := {
	"scale": [0.40, 1.30],
	"x": [-360.0, 360.0],
	"y": [-700.0, 500.0],
	"brightness": [0.30, 1.30],
	"saturation": [0.0, 1.30],
	"contrast": [0.0, 1.50],
	"fade_start": [480.0, 800.0],
	"fade_strength": [0.0, 1.0],
	"rear_edge_ratio": [0.25, 0.75],
}
const EXPECTED_IDS := [
	"alley", "daylight_court", "hive", "harbor", "pump",
	"scrapyard", "hotel", "voss", "block5", "church",
]

# [id, label, image, rear_edge_ratio, has_confirmed_save]. This is also the
# recovery catalog when the profile cannot be read. Save is blocked for an
# existing damaged file so the original bytes are never replaced.
const FALLBACK_SCENES := [
	["alley", "后巷", "res://tests/fixtures/battle_background/alley_sample_v4_detail.png", 0.46, true],
	["daylight_court", "白昼庭院", "res://assets/backgrounds/Battle/白昼庭院_战斗背景_v1.png", 0.44, false],
	["hive", "蜂巢城寨", "res://assets/backgrounds/Battle/蜂巢城寨_战斗背景_v1.png", 0.48, false],
	["harbor", "港口", "res://assets/backgrounds/Battle/港口_战斗背景_v1.png", 0.48, false],
	["pump", "黑潮泵站", "res://assets/backgrounds/Battle/黑潮泵站_战斗背景_v1.png", 0.48, false],
	["scrapyard", "垃圾场", "res://assets/backgrounds/Battle/垃圾场_战斗背景_v1.png", 0.45, false],
	["hotel", "末班车旅馆", "res://assets/backgrounds/Battle/末班车旅馆_战斗背景_v1.png", 0.49, false],
	["voss", "沃斯大楼内部", "res://assets/backgrounds/Battle/沃斯大楼内部_战斗背景_v2.png", 0.46, false],
	["block5", "五号街区", "res://assets/backgrounds/Battle/五号街区_战斗背景_v1.png", 0.43, false],
	["church", "义体教会", "res://assets/backgrounds/Battle/义体教会_战斗背景_v2.png", 0.47, false],
]

var path: String = DEFAULT_PATH
var error_message: String = ""
var scenes: Array = []
var drafts: Dictionary = {}
var saved: Dictionary = {}
var current_id: String = ""

var _blocked_reason: String = ""


func initialize(profile_path: String = DEFAULT_PATH) -> bool:
	path = profile_path
	error_message = ""
	_blocked_reason = ""
	_clear_memory()

	if path.is_empty():
		_blocked_reason = "背景参数路径为空"
		_install_fallback()
		error_message = _blocked_reason
		return false

	var profile_file := FileAccess.open(path, FileAccess.READ)
	if profile_file == null:
		var open_error := FileAccess.get_open_error()
		var existed := FileAccess.file_exists(path)
		_install_fallback()
		if existed:
			_blocked_reason = "无法读取背景参数文件（错误 %d）" % open_error
		else:
			error_message = "背景参数文件不存在（错误 %d），使用初始目录" % open_error
			return false
		error_message = _blocked_reason
		return false

	var source_text := profile_file.get_as_text()
	var read_error := profile_file.get_error()
	profile_file = null
	if read_error != OK:
		_blocked_reason = "读取背景参数文件失败（错误 %d）" % read_error
		_install_fallback()
		error_message = _blocked_reason
		return false

	var parser := JSON.new()
	var parse_error := parser.parse(source_text)
	if parse_error != OK:
		_blocked_reason = "背景参数 JSON 解析失败（第 %d 行：%s）" % [
			parser.get_error_line(), parser.get_error_message()
		]
		_install_fallback()
		error_message = _blocked_reason
		return false

	var document_error := _document_error(parser.data)
	if not document_error.is_empty():
		_blocked_reason = document_error
		_install_fallback()
		error_message = document_error
		return false

	_install_from_document(parser.data as Dictionary)
	return true


func scene(id: String) -> Dictionary:
	for scene_record in scenes:
		if typeof(scene_record) == TYPE_DICTIONARY and String(scene_record.get("id", "")) == id:
			return scene_record
	return {}


func current() -> Dictionary:
	if drafts.has(current_id) and typeof(drafts[current_id]) == TYPE_DICTIONARY:
		return drafts[current_id]
	return {}


func select(id: String) -> bool:
	if not drafts.has(id):
		error_message = "未知背景地点：%s" % id
		return false
	current_id = id
	return true


func is_dirty(id: String = "") -> bool:
	var target_id := current_id if id.is_empty() else id
	if not drafts.has(target_id):
		return false
	var baseline: Dictionary = _baseline_for(target_id)
	return not _params_near(drafts[target_id], baseline)


func unsaved_count() -> int:
	var count := 0
	for scene_record in scenes:
		if typeof(scene_record) != TYPE_DICTIONARY:
			continue
		if is_dirty(String(scene_record.get("id", ""))):
			count += 1
	return count


func has_saved(id: String = "") -> bool:
	var target_id := current_id if id.is_empty() else id
	return saved.has(target_id) and typeof(saved[target_id]) == TYPE_DICTIONARY


func restore_saved() -> bool:
	if not has_saved():
		error_message = "当前背景地点没有已保存参数"
		return false
	var target: Dictionary = saved[current_id]
	var validation_error := _params_error(target, "%s.saved" % current_id)
	if not validation_error.is_empty():
		error_message = validation_error
		return false
	_replace_dictionary(drafts[current_id], target)
	return true


func restore_initial() -> void:
	if not drafts.has(current_id):
		return
	var defaults := _defaults_for(current_id)
	if not defaults.is_empty():
		_replace_dictionary(drafts[current_id], defaults)


func save_current() -> bool:
	error_message = ""
	if not _blocked_reason.is_empty():
		error_message = "读取失败，禁止覆盖原文件：%s" % _blocked_reason
		return false
	if not drafts.has(current_id):
		error_message = "当前背景地点无效，无法保存"
		return false

	var candidate := _build_document_for_save()
	if candidate.is_empty():
		return false
	var candidate_error := _document_error(candidate)
	if not candidate_error.is_empty():
		error_message = candidate_error
		return false

	var output_text := JSON.stringify(candidate, "\t")
	var temp_path := path + ".tmp"
	var backup_path := path + ".bak"
	var output_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if output_file == null:
		error_message = "无法写入临时背景参数文件（错误 %d）" % FileAccess.get_open_error()
		return false
	output_file.store_string(output_text)
	output_file.flush()
	var write_error := output_file.get_error()
	output_file = null
	if write_error != OK:
		_remove_file_if_present(temp_path)
		error_message = "写入临时背景参数文件失败（错误 %d）" % write_error
		return false

	var verification := _read_and_verify(temp_path, candidate)
	if not verification.is_empty():
		_remove_file_if_present(temp_path)
		error_message = verification
		return false

	var target_absolute := ProjectSettings.globalize_path(path)
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	var target_existed := FileAccess.file_exists(path)
	if target_existed:
		if FileAccess.file_exists(backup_path):
			var backup_remove_error := DirAccess.remove_absolute(backup_absolute)
			if backup_remove_error != OK:
				_remove_file_if_present(temp_path)
				error_message = "无法更新背景参数备份（错误 %d）" % backup_remove_error
				return false
		var backup_error := DirAccess.rename_absolute(target_absolute, backup_absolute)
		if backup_error != OK:
			_remove_file_if_present(temp_path)
			error_message = "无法备份现有背景参数文件（错误 %d）" % backup_error
			return false

	var replace_error := DirAccess.rename_absolute(temp_absolute, target_absolute)
	if replace_error != OK:
		_remove_file_if_present(temp_path)
		if target_existed:
			var restore_error := DirAccess.rename_absolute(backup_absolute, target_absolute)
			if restore_error != OK:
				error_message = "替换背景参数失败（错误 %d），恢复原文件也失败（错误 %d）" % [replace_error, restore_error]
				return false
		error_message = "替换背景参数文件失败（错误 %d）" % replace_error
		return false

	var committed: Dictionary = (candidate["scenes"] as Array)[_scene_index(current_id)]
	var committed_saved: Dictionary = (committed["saved"] as Dictionary).duplicate(true)
	saved[current_id] = committed_saved
	var current_scene := scene(current_id)
	if not current_scene.is_empty():
		current_scene["saved"] = committed_saved.duplicate(true)
	error_message = ""
	return true


func _clear_memory() -> void:
	scenes = []
	drafts = {}
	saved = {}
	current_id = ""


func _install_fallback() -> void:
	_install_records(_fallback_records())
	current_id = "alley"


func _fallback_records() -> Array:
	var records: Array = []
	for row in FALLBACK_SCENES:
		var id := String(row[0])
		var defaults := _initial_defaults(id, float(row[3]))
		var saved_value: Variant = null
		if bool(row[4]):
			saved_value = defaults.duplicate(true)
		records.append({
			"id": id,
			"label": String(row[1]),
			"image": String(row[2]),
			"defaults": defaults,
			"saved": saved_value,
		})
	return records


func _initial_defaults(id: String, rear_edge_ratio: float) -> Dictionary:
	var params := {
		"scale": 0.53,
		"x": 0.0,
		"y": 0.0,
		"brightness": 1.0,
		"saturation": 1.0,
		"contrast": 1.0,
		"fade_start": 610.0,
		"fade_strength": 0.94,
		"rear_edge_ratio": rear_edge_ratio,
	}
	if id == "alley":
		params["y"] = -61.0
		params["brightness"] = 1.05
		params["saturation"] = 1.15
		params["contrast"] = 0.92
	return params


func _install_from_document(document: Dictionary) -> void:
	_install_records(document["scenes"] as Array)
	current_id = String(document["last_scene"])


func _install_records(records: Array) -> void:
	_clear_memory()
	for record in records:
		var id := String(record["id"])
		var defaults: Dictionary = (record["defaults"] as Dictionary).duplicate(true)
		var saved_value: Variant = _copy_saved_value(record["saved"])
		scenes.append({
			"id": id,
			"label": String(record["label"]),
			"image": String(record["image"]),
			"defaults": defaults.duplicate(true),
			"saved": _copy_saved_value(saved_value),
		})
		drafts[id] = _copy_saved_value(saved_value) if saved_value != null else defaults.duplicate(true)
		saved[id] = _copy_saved_value(saved_value)


func _copy_saved_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).duplicate(true)
	return value


func _baseline_for(id: String) -> Dictionary:
	if saved.has(id) and typeof(saved[id]) == TYPE_DICTIONARY:
		return saved[id]
	var defaults := _defaults_for(id)
	return defaults


func _defaults_for(id: String) -> Dictionary:
	var scene_record := scene(id)
	if scene_record.is_empty() or typeof(scene_record.get("defaults")) != TYPE_DICTIONARY:
		return {}
	return scene_record["defaults"]


func _replace_dictionary(target: Dictionary, source: Dictionary) -> void:
	var replacement := source.duplicate(true)
	target.clear()
	for key in replacement:
		target[key] = replacement[key]


func _params_near(left: Variant, right: Variant) -> bool:
	if typeof(left) != TYPE_DICTIONARY or typeof(right) != TYPE_DICTIONARY:
		return false
	if left.size() != PARAM_KEYS.size() or right.size() != PARAM_KEYS.size():
		return false
	for key in PARAM_KEYS:
		if not left.has(key) or not right.has(key):
			return false
		var left_value: Variant = left[key]
		var right_value: Variant = right[key]
		if not _is_number(left_value) or not _is_number(right_value):
			return false
		if absf(float(left_value) - float(right_value)) > DIRTY_EPSILON:
			return false
	return true


func _is_number(value: Variant) -> bool:
	var value_type := typeof(value)
	if value_type != TYPE_INT and value_type != TYPE_FLOAT:
		return false
	return is_finite(float(value))


func _params_error(value: Variant, context: String) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "%s 必须是参数对象" % context
	var params: Dictionary = value
	for key in params.keys():
		if not PARAM_KEYS.has(key):
			return "%s 含未知参数 %s" % [context, String(key)]
	for key in PARAM_KEYS:
		if not params.has(key):
			return "%s 缺少参数 %s" % [context, key]
		if not _is_number(params[key]):
			return "%s.%s 必须是有限数值" % [context, key]
		var bounds: Array = PARAM_RANGES[key]
		var number := float(params[key])
		if number < float(bounds[0]) or number > float(bounds[1]):
			return "%s.%s 超出范围 %.2f..%.2f" % [context, key, float(bounds[0]), float(bounds[1])]
	return ""


func _document_error(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "背景参数根节点必须是对象"
	var document: Dictionary = value
	if not document.has("schema_version") or not _is_number(document["schema_version"]):
		return "schema_version 缺失或不是数值"
	if float(document["schema_version"]) != float(SCHEMA_VERSION):
		return "schema_version 必须为 %d" % SCHEMA_VERSION
	if not document.has("last_scene") or typeof(document["last_scene"]) != TYPE_STRING:
		return "last_scene 缺失或不是字符串"
	if not EXPECTED_IDS.has(document["last_scene"]):
		return "last_scene 指向未知地点：%s" % String(document["last_scene"])
	if not document.has("scenes") or typeof(document["scenes"]) != TYPE_ARRAY:
		return "scenes 缺失或不是数组"
	var scene_list: Array = document["scenes"]
	if scene_list.size() != EXPECTED_IDS.size():
		return "scenes 必须包含 %d 个地点" % EXPECTED_IDS.size()
	for index in EXPECTED_IDS.size():
		var record: Variant = scene_list[index]
		if typeof(record) != TYPE_DICTIONARY:
			return "scenes[%d] 必须是对象" % index
		var id := String(record.get("id", ""))
		if id != String(EXPECTED_IDS[index]):
			return "scenes[%d] 必须为 %s" % [index, EXPECTED_IDS[index]]
		if typeof(record.get("label")) != TYPE_STRING or String(record.get("label", "")).is_empty():
			return "%s.label 必须是非空字符串" % id
		if typeof(record.get("image")) != TYPE_STRING or String(record.get("image", "")).is_empty():
			return "%s.image 必须是非空字符串" % id
		if not record.has("defaults"):
			return "%s.defaults 缺失" % id
		var defaults_error := _params_error(record["defaults"], "%s.defaults" % id)
		if not defaults_error.is_empty():
			return defaults_error
		if not record.has("saved"):
			return "%s.saved 缺失" % id
		if record["saved"] != null:
			var saved_error := _params_error(record["saved"], "%s.saved" % id)
			if not saved_error.is_empty():
				return saved_error
	return ""


func _build_document_for_save() -> Dictionary:
	if scenes.size() != EXPECTED_IDS.size():
		error_message = "背景地点目录不完整，无法保存"
		return {}
	var output_scenes: Array = []
	for index in scenes.size():
		var record: Variant = scenes[index]
		if typeof(record) != TYPE_DICTIONARY:
			error_message = "背景地点目录第 %d 项无效" % index
			return {}
		var id := String(record.get("id", ""))
		if id != String(EXPECTED_IDS[index]):
			error_message = "背景地点目录顺序已改变：%s" % id
			return {}
		if not saved.has(id):
			error_message = "saved 目录缺少地点 %s" % id
			return {}
		var value: Variant = drafts[id] if id == current_id else saved[id]
		var raw_defaults: Variant = record.get("defaults")
		if typeof(raw_defaults) != TYPE_DICTIONARY:
			error_message = "%s.defaults 无效，无法保存" % id
			return {}
		output_scenes.append({
			"id": id,
			"label": String(record.get("label", "")),
			"image": String(record.get("image", "")),
			"defaults": (raw_defaults as Dictionary).duplicate(true),
			"saved": _copy_saved_value(value),
		})
	return {
		"schema_version": SCHEMA_VERSION,
		"last_scene": current_id,
		"scenes": output_scenes,
	}


func _read_and_verify(file_path: String, expected: Dictionary) -> String:
	var check_file := FileAccess.open(file_path, FileAccess.READ)
	if check_file == null:
		return "无法读回临时背景参数文件（错误 %d）" % FileAccess.get_open_error()
	var check_text := check_file.get_as_text()
	var check_error := check_file.get_error()
	check_file = null
	if check_error != OK:
		return "读回临时背景参数文件失败（错误 %d）" % check_error
	var parser := JSON.new()
	var parse_error := parser.parse(check_text)
	if parse_error != OK:
		return "临时背景参数 JSON 校验失败（第 %d 行：%s）" % [
			parser.get_error_line(), parser.get_error_message()
		]
	var document_error := _document_error(parser.data)
	if not document_error.is_empty():
		return "临时背景参数结构校验失败：%s" % document_error
	if not _values_equivalent(parser.data, expected):
		return "临时背景参数读回内容与待提交内容不一致"
	return ""


func _values_equivalent(left: Variant, right: Variant) -> bool:
	var left_type := typeof(left)
	var right_type := typeof(right)
	var left_is_number := left_type == TYPE_INT or left_type == TYPE_FLOAT
	var right_is_number := right_type == TYPE_INT or right_type == TYPE_FLOAT
	if left_is_number or right_is_number:
		# JSON's readable float formatting can remove sub-step binary noise from
		# HSlider values (for example 0.5300000000000001 becomes 0.53).
		return left_is_number and right_is_number and absf(float(left) - float(right)) <= 0.0000000001
	if left_type != right_type:
		return false
	if left_type == TYPE_DICTIONARY:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _values_equivalent(left[key], right[key]):
				return false
		return true
	if left_type == TYPE_ARRAY:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _values_equivalent(left[index], right[index]):
				return false
		return true
	return left == right


func _scene_index(id: String) -> int:
	for index in scenes.size():
		if String(scenes[index].get("id", "")) == id:
			return index
	return -1


func _remove_file_if_present(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
