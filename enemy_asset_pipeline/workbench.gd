extends "res://tests/combat/workbench/battle_background_preview.gd"
## F6 entry: actual combat preview and an optional local XSXB editor.
const Pipeline = preload("res://enemy_asset_pipeline/runtime/pipeline_catalog.gd")
@export var test_mode := false
var editor_request: HTTPRequest
var pipeline_label: Label
var owned_server := -1
var editor_opening := false
var server_conflict := false
var audio_lab: Control
var audio_bank: Node
var audio_hooks: Node
var audio_previous_process_mode := Node.PROCESS_MODE_INHERIT
var audio_close_pending := false

func _ready() -> void:
	profile_path = "res://enemy_asset_pipeline/test/background_profiles.json" if test_mode else "res://enemy_asset_pipeline/background_profiles.json"
	if test_mode: Pipeline.set_published_path("res://enemy_asset_pipeline/test/session/published/catalog.json")
	else: Pipeline.clear_published_path()
	Pipeline.clear_preview()
	await super._ready()
	var strip := PanelContainer.new()
	strip.position = Vector2(340,116)
	strip.size = Vector2(744,69)
	strip.z_index = 110
	add_child(strip)
	var column := VBoxContainer.new()
	strip.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_button(row,"打开PNG制作工具",open_editor,false)
	_button(row,"刷新草稿",refresh_draft)
	_button(row,"查看正式版本",refresh_published)
	_button(row,"音效与场景模拟",open_audio_lab)
	var mode_text := "测试版 · 应用只写测试目录" if test_mode else "正式制作台 · 先保存草稿，再预览或应用"
	if character_mipmaps: mode_text += " · 角色Mipmap平滑"
	pipeline_label = _text(column,mode_text,13,DemoUI.CYAN)
	editor_request = HTTPRequest.new()
	editor_request.timeout = 3.0
	add_child(editor_request)
	_sync_actor_tabs()
	audio_bank = preload("res://enemy_asset_pipeline/runtime/audio_preview_bank.gd").new()
	audio_bank.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(audio_bank)
	_load_audio_bindings()
	audio_hooks = preload("res://enemy_asset_pipeline/runtime/audio_scene_hooks.gd").new()
	audio_hooks.bank = audio_bank
	add_child(audio_hooks)
	audio_hooks.attach(view)

func _load_audio_bindings() -> void:
	var path := "res://enemy_asset_pipeline/test/session/audio_preview_bindings.json" if test_mode else "res://enemy_asset_pipeline/audio_preview_bindings.json"
	if not FileAccess.file_exists(path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("schemaVersion") != 1 or not data.get("bindings") is Dictionary: return
	for cue in data.bindings:
		if data.bindings[cue] is String: audio_bank.bind(str(cue),data.bindings[cue])
	var level: Variant = data.get("volumeDb",-12.0)
	if (level is float or level is int) and is_finite(float(level)): audio_bank.master_volume_db = clampf(float(level),-40,0)

func _replace_view() -> void:
	await super._replace_view()
	if is_instance_valid(audio_hooks): audio_hooks.attach(view)

func open_audio_lab() -> void:
	if tools_locked() or is_instance_valid(audio_lab): return
	audio_hooks.attach(null)
	audio_lab = preload("res://enemy_asset_pipeline/audio_scene_simulator.tscn").instantiate()
	audio_lab.bank = audio_bank
	if test_mode: audio_lab.config_path = "res://enemy_asset_pipeline/test/session/audio_preview_bindings.json"
	audio_lab.closed.connect(_audio_lab_closed)
	audio_previous_process_mode = process_mode
	process_mode = Node.PROCESS_MODE_DISABLED
	add_child(audio_lab)

func _audio_lab_closed() -> void:
	process_mode = audio_previous_process_mode
	audio_hooks.attach(view)
	audio_lab = null

func request_close() -> void:
	if audio_close_pending: return
	if is_instance_valid(audio_lab):
		if audio_lab.route_busy or Game.battle_busy or Game.transition_locked:
			audio_lab.status.text = "请等待当前动作完成，再关闭测试台。"
			return
		audio_close_pending = true
		await audio_lab.close_preview()
	else: audio_close_pending = true
	await preload("res://scripts/combat/audio_cleanup.gd").release(self,get_tree())
	audio_close_pending = false
	super.request_close()

func _build_enemy_choices() -> void:
	super._build_enemy_choices()
	for id in Pipeline.load_profiles():
		var key := str(id)
		var normalized := key.to_lower()
		if normalized == "noren": continue
		var found := false
		for choice in enemy_choices:
			if str(choice.id).to_lower() == "visual:"+normalized: found = true
		if not found:
			enemy_choices.append({"id":"visual:"+key,"name":CharacterNames.name_for_visual(key),"tooltip":"visual:"+key})

func _reload_pipeline(use_draft: bool) -> void:
	if tools_locked(): return
	if use_draft:
		var file := "res://enemy_asset_pipeline/test/preview_catalog.json" if test_mode else "res://enemy_asset_pipeline/authoring/preview_catalog.json"
		if not FileAccess.file_exists(file):
			pipeline_label.text = "请先在网页保存调参，并点击「送入战斗预览」。"
			return
		Pipeline.set_preview_path(file)
	else: Pipeline.clear_preview()
	var records: Dictionary = Pipeline.load_profiles()
	# Keep the workbench's numbered-folder path repairs and idle-only profiles.
	# Pipeline.load_profiles() already invalidates only the overlay cache.
	# Recreate the picker list because imported profiles may be new to this session.
	enemy_choices.clear()
	_build_enemy_choices()
	_refresh_enemy_picker()
	if use_draft:
		var selection_file := "res://enemy_asset_pipeline/test/selection.json" if test_mode else "res://enemy_asset_pipeline/authoring/selection.json"
		var selected = JSON.parse_string(FileAccess.get_file_as_string(selection_file))
		if selected is Dictionary:
			var id := str(selected.get("profileId",""))
			if records.has(id) and id.to_lower() != "noren":
				roster[0] = "visual:"+id
				selected_actor = 1
			else: selected_actor = 0
	await rebuild()
	pipeline_label.text = "草稿已载入 · 仅预览" if use_draft else "已读取正式配置 · 重开战斗使用"

func refresh_draft() -> void:
	await _reload_pipeline(true)

func refresh_published() -> void:
	await _reload_pipeline(false)

func _editor_url() -> String:
	return "http://127.0.0.1:%d" % (5193 if test_mode else 5191)

func open_editor() -> void:
	if editor_opening: return
	editor_opening = true
	var started := await _server_alive()
	if server_conflict:
		pipeline_label.text = "制作端口已被另一工程或旧版服务占用。请关闭原制作台服务后重试。"
		editor_opening = false
		return
	if not started:
		var node := "node"
		var config_path := "res://tools/local_paths.json"
		if FileAccess.file_exists(config_path):
			var local = JSON.parse_string(FileAccess.get_file_as_string(config_path))
			if local is Dictionary: node = str(local.get("node",node))
		var arguments := PackedStringArray([ProjectSettings.globalize_path("res://enemy_asset_pipeline/server.cjs")])
		if test_mode: arguments.append("--test")
		owned_server = OS.create_process(node,arguments,false)
		if owned_server < 0:
			pipeline_label.text = "无法启动Node，请核对 tools/local_paths.json 的node路径。"
			editor_opening = false
			return
		for attempt in 20:
			await get_tree().create_timer(0.2).timeout
			if await _server_alive():
				started = true
				break
	if started:
		OS.shell_open(_editor_url())
		pipeline_label.text = "制作工具已打开 · 保存后送入预览，再刷新草稿"
	elif server_conflict: pipeline_label.text = "端口上的制作服务不属于当前工程。请关闭原服务后重试。"
	else: pipeline_label.text = "制作服务未启动，请检查端口5191—5194和Node输出。"
	editor_opening = false

func _matches_server(data: Variant) -> bool:
	# Old servers have no identity and must not be reused across project copies.
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	return data is Dictionary and data.get("service", "") == "midnight-enemy-pipeline" \
		and data.get("projectRoot", "") == project_root and data.get("test") == test_mode

func _server_alive() -> bool:
	server_conflict = false
	var error := editor_request.request(_editor_url()+"/pipeline/status")
	if error != OK:
		server_conflict = true
		return false
	var response: Array = await editor_request.request_completed
	if int(response[0]) == HTTPRequest.RESULT_CANT_CONNECT: return false
	server_conflict = true
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200: return false
	var data = JSON.parse_string(response[3].get_string_from_utf8())
	var matches := _matches_server(data)
	server_conflict = not matches
	return matches

func _exit_tree() -> void:
	Pipeline.clear_preview()
	Pipeline.clear_published_path()
	if owned_server > 0 and OS.is_process_running(owned_server): OS.kill(owned_server)
