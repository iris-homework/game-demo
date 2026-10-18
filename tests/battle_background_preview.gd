extends Control
## Independent fitting bench. Never registered in main scenes, assets, or save data.
const PreviewBattle = preload("res://tests/battle_background_preview_view.gd")
const Guides = preload("res://tests/battle_background_preview_guides.gd")
const Profiles = preload("res://tests/battle_background_profiles.gd")
# Preserve the previous slider calibration rather than fitting the full canvas.
# Generated architectural landmarks are an approximate visual match only.
const REFERENCE_SPAN_RATIO := 0.50
const VISIBLE_BUILDING_RATIO := 0.46
# Mirrored margins are an off-camera guard, not additional buildings facing inward.
const CAMERA_PADDING := Vector2(512, 256)
@export var profile_path: String = Profiles.DEFAULT_PATH
var profiles = Profiles.new()
var SAMPLE: Texture2D
var DEFAULTS: Dictionary = {}
var settings: Dictionary = {}
var view: Control
var backdrop: Sprite2D
var guides: Node2D
var fade: TextureRect
var controls: PanelContainer
var hint: Label
var status: Label
var sliders: Dictionary = {}
var captions: Dictionary = {}
var scene_picker: OptionButton
var profile_state: Label
var feedback: Label
var restore_button: Button
var close_dialog: ConfirmationDialog
var guides_toggle: CheckBox
var action_buttons: Array[Button] = []
var enemy_count := 1
var ready_for_preview := false
var rebuilding := false
var finished := false
var preview_camera_busy := false
var capturing := false

func _ready() -> void:
	Game.save_enabled = false
	# Even accidental direct calls target test files, never the adventure paths.
	Game.save_path = "user://battle_background_preview_unused.json"
	Game.meta_path = "user://battle_background_preview_meta_unused.json"
	get_tree().auto_accept_quit = false
	profiles.initialize(profile_path)
	settings = profiles.current()
	DEFAULTS = profiles.scene(profiles.current_id).defaults.duplicate(true)
	SAMPLE = load(profiles.scene(profiles.current_id).image) as Texture2D
	_build_tools()
	if not profiles.error_message.is_empty(): feedback.text = profiles.error_message
	await rebuild(1)

func rebuild(count: int) -> void:
	if rebuilding or Game.battle_busy or preview_camera_busy: return
	rebuilding = true
	ready_for_preview = false
	finished = false
	enemy_count = count
	if is_instance_valid(view):
		remove_child(view)
		view.queue_free()
		await get_tree().process_frame
	Game.training_mode = false
	Game.training_backup.clear()
	Game.state.clear()
	Game.transition_locked = false
	Game.battle_busy = false
	Game.start_training("B04")
	Game.initialize_combat()
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	var template: Dictionary = model.enemies[0].duplicate(true)
	model.enemies.clear()
	for i in count:
		var enemy := template.duplicate(true)
		enemy.id = "background_preview_%d" % i
		enemy.displayName = "试装对手"
		enemy.hp = 20
		enemy.maxHp = 20
		model.enemies.append(enemy)
	Game.state.combat = model.snapshot()
	view = PreviewBattle.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	move_child(view, 0)
	view.preview_finished.connect(_on_finished)
	_install_backdrop()
	while Game.battle_busy or not view.initialized:
		await get_tree().process_frame
	ready_for_preview = true
	rebuilding = false
	status.text = "%s · 每名 20 HP · 可正常出牌" % ("单敌" if count == 1 else "三敌")
	view.set_preview_location(profiles.scene(profiles.current_id).label)

func _install_backdrop() -> void:
	var stage: Control = view.stage
	for child in view.get_children():
		if child is Button and child.text == "调试结果": child.text = "重建演练"
	# A larger outer clip exposes the artwork above the original action strip.
	# Preserve the stage's logical size, foot coordinates and framing calculations.
	var clip := Control.new()
	clip.name = "PreviewBattlefieldClip"
	clip.position = Vector2(0, 76)
	clip.size = Vector2(1440, 824)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(clip)
	view.move_child(clip, stage.get_index())
	stage.reparent(clip, false)
	stage.position.y -= clip.position.y
	stage.clip_contents = false
	stage.world.get_child(0).hide()
	backdrop = Sprite2D.new()
	backdrop.name = "PreviewArtwork"
	backdrop.centered = false
	backdrop.texture = SAMPLE
	backdrop.region_enabled = true
	backdrop.region_rect = Rect2(-CAMERA_PADDING, SAMPLE.get_size() + CAMERA_PADDING * 2.0)
	backdrop.region_filter_clip_enabled = false
	backdrop.texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform float brightness = 1.05; uniform float saturation = 0.75; uniform float contrast = 0.92; void fragment(){ vec4 c = texture(TEXTURE,UV); float gray = dot(c.rgb,vec3(0.2126,0.7152,0.0722)); vec3 toned = (mix(vec3(gray),c.rgb,saturation)-vec3(0.25))*contrast+vec3(0.25); COLOR = vec4(clamp(toned*brightness,vec3(0.0),vec3(1.0)),c.a); }"
	material.shader = shader
	backdrop.material = material
	stage.world.add_child(backdrop)
	stage.world.move_child(backdrop, 0)
	guides = Guides.new()
	guides.stage = stage
	guides.backdrop = backdrop
	guides.rear_edge_ratio = settings.rear_edge_ratio
	guides.source_padding = CAMERA_PADDING
	stage.world.add_child(guides)
	guides.z_index = 15
	guides.visible = guides_toggle.button_pressed
	fade = TextureRect.new()
	fade.name = "PreviewHandFade"
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(fade)
	_apply_settings()

func _apply_settings() -> void:
	if not is_instance_valid(backdrop): return
	backdrop.texture = SAMPLE
	backdrop.region_rect = Rect2(-CAMERA_PADDING, SAMPLE.get_size() + CAMERA_PADDING * 2.0)
	var factor: float = 1440.0 / (SAMPLE.get_width() * REFERENCE_SPAN_RATIO) * settings.scale
	backdrop.scale = Vector2.ONE * factor
	# Match the user's 46/54 guide inside the visible battlefield at wide framing.
	# Y is now an offset from this composition, rather than an asset-specific origin.
	var wall_y: float = 824.0 * VISIBLE_BUILDING_RATIO - view.stage.position.y
	var origin_y: float = wall_y - SAMPLE.get_height() * settings.rear_edge_ratio * factor
	backdrop.position = Vector2(720.0 - SAMPLE.get_width() * factor * 0.5 + settings.x, origin_y + settings.y) - CAMERA_PADDING * factor
	backdrop.material.set_shader_parameter("brightness", settings.brightness)
	backdrop.material.set_shader_parameter("saturation", settings.saturation)
	backdrop.material.set_shader_parameter("contrast", settings.contrast)
	guides.rear_edge_ratio = settings.rear_edge_ratio
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.025, 0.03, 0.045, 0), Color(0.025, 0.03, 0.045, settings.fade_strength)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(0, 1)
	fade.texture = texture
	fade.position = Vector2(0, settings.fade_start - 76)
	fade.size = Vector2(1440, 900 - settings.fade_start)
	if is_instance_valid(status): status.tooltip_text = JSON.stringify(settings, "  ")
	_update_profile_state()

func reset_settings() -> void:
	profiles.restore_initial()
	settings = profiles.current()
	_sync_widgets()
	_apply_settings()
	feedback.text = "已恢复初始参数；需要保存才会写入配置。"

func restore_settings() -> void:
	if not profiles.restore_saved(): return
	settings = profiles.current()
	_sync_widgets()
	_apply_settings()
	feedback.text = "已恢复当前地点上次保存的参数。"

func save_settings() -> bool:
	if tools_locked(): return false
	var success: bool = profiles.save_current()
	feedback.text = ("已保存：%s\n重启后读取；其他地点草稿未写入。" % profiles.scene(profiles.current_id).label) if success else profiles.error_message
	_update_profile_state()
	return success

func switch_scene(id: String) -> bool:
	if tools_locked(): return false
	var record: Dictionary = profiles.scene(id)
	if record.is_empty(): return false
	var texture := load(record.image) as Texture2D
	if texture == null:
		feedback.text = "背景无法读取：" + record.label
		return false
	view.cancel_selection()
	if not profiles.select(id): return false
	settings = profiles.current()
	DEFAULTS = record.defaults.duplicate(true)
	SAMPLE = texture
	_sync_widgets()
	_apply_settings()
	view.set_preview_location(record.label)
	feedback.text = "已切换：%s；各地点草稿分别保留。" % record.label
	return true

func _step_scene(direction: int) -> void:
	var index := scene_picker.selected
	index = posmod(index + direction, profiles.scenes.size())
	switch_scene(profiles.scenes[index].id)

func _sync_widgets() -> void:
	for key in sliders:
		sliders[key].set_value_no_signal(settings[key])
		captions[key].node.text = "%s  %.2f" % [captions[key].title, settings[key]]
	for i in profiles.scenes.size():
		if profiles.scenes[i].id == profiles.current_id: scene_picker.select(i)

func _update_profile_state() -> void:
	if not is_instance_valid(profile_state): return
	var state := "有未保存修改" if profiles.is_dirty() else ("已保存" if profiles.has_saved() else "初始参数 · 尚未保存")
	profile_state.text = "%s · %s\n未保存草稿：%d 处" % [profiles.scene(profiles.current_id).label, state, profiles.unsaved_count()]
	profile_state.modulate = Color("ffc982") if profiles.is_dirty() else Color("9ae8dd")

func tools_locked() -> bool:
	return not ready_for_preview or Game.battle_busy or rebuilding or preview_camera_busy or capturing or (is_instance_valid(view) and is_instance_valid(view.pile_overlay))

func modal_open() -> bool:
	return capturing or (is_instance_valid(close_dialog) and close_dialog.visible) or (is_instance_valid(scene_picker) and scene_picker.get_popup().visible)

func tool_contains(point: Vector2) -> bool:
	return modal_open() or (is_instance_valid(controls) and controls.visible and controls.get_global_rect().has_point(point))

func _build_tools() -> void:
	var ui := DemoUI.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.z_index = 90
	add_child(ui)
	hint = ui.label(ui, "Tab 隐藏／显示面板 · Ctrl+S 保存当前地点", Vector2(400, 100), Vector2(580, 28), 14, Color("a8f4ff"))
	controls = PanelContainer.new()
	controls.position = Vector2(18, 100)
	controls.size = Vector2(356, 0)
	controls.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.025, 0.045, 0.07, 0.97)
	box.border_color = Color("3d879b")
	box.set_border_width_all(1)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	controls.add_theme_stylebox_override("panel", box)
	ui.add_child(controls)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	controls.add_child(column)
	var title := Label.new()
	title.text = "战斗背景调试台 · 仅测试"
	title.add_theme_font_size_override("font_size", 17)
	column.add_child(title)
	var selector_row := HBoxContainer.new()
	column.add_child(selector_row)
	_add_action(selector_row, "‹", func(): _step_scene(-1)).custom_minimum_size.x = 30
	scene_picker = OptionButton.new()
	scene_picker.custom_minimum_size = Vector2(242, 30)
	scene_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_picker.add_theme_font_size_override("font_size", 15)
	for record in profiles.scenes: scene_picker.add_item(record.label)
	selector_row.add_child(scene_picker)
	scene_picker.item_selected.connect(func(index: int):
		if not switch_scene(profiles.scenes[index].id): _sync_widgets())
	_add_action(selector_row, "›", func(): _step_scene(1)).custom_minimum_size.x = 30
	profile_state = Label.new()
	profile_state.add_theme_font_size_override("font_size", 13)
	column.add_child(profile_state)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	_add_slider(grid, "scale", "原图尺度", 0.40, 1.30, 0.01)
	_add_slider(grid, "x", "水平偏移", -360, 360, 1)
	_add_slider(grid, "y", "垂直偏移", -700, 500, 1)
	_add_slider(grid, "brightness", "亮度", 0.30, 1.30, 0.01)
	_add_slider(grid, "saturation", "饱和度", 0, 1.30, 0.01)
	_add_slider(grid, "contrast", "对比度", 0, 1.50, 0.01)
	_add_slider(grid, "fade_start", "渐暗起点", 480, 800, 1)
	_add_slider(grid, "fade_strength", "渐暗强度", 0, 1, 0.01)
	_add_slider(grid, "rear_edge_ratio", "原图地面分界", 0.25, 0.75, 0.01)
	sliders.rear_edge_ratio.tooltip_text = "标定原图中的地面起点，会影响背景垂直位置；与橙色辅助线对照。"
	var save_row := HBoxContainer.new()
	column.add_child(save_row)
	_add_action(save_row, "保存当前", save_settings).tooltip_text = "仅保存当前地点。配置：" + profile_path
	restore_button = _add_action(save_row, "恢复已保存", restore_settings)
	_add_action(save_row, "恢复初始", reset_settings)
	guides_toggle = CheckBox.new()
	guides_toggle.text = "辅助线：青色站位／橙色场地后沿"
	guides_toggle.add_theme_font_size_override("font_size", 13)
	guides_toggle.toggled.connect(func(value: bool):
		if is_instance_valid(guides): guides.visible = value)
	column.add_child(guides_toggle)
	var row := HBoxContainer.new()
	column.add_child(row)
	_add_action(row, "单敌重建", func(): rebuild(1))
	_add_action(row, "三敌重建", func(): rebuild(3))
	row = HBoxContainer.new()
	column.add_child(row)
	_add_action(row, "全景", func(): preview_camera(false))
	_add_action(row, "近景", func(): preview_camera(true))
	_add_action(row, "截图", capture_current)
	status = Label.new()
	status.text = "正在准备独立演练…"
	status.add_theme_font_size_override("font_size", 12)
	column.add_child(status)
	feedback = Label.new()
	feedback.custom_minimum_size = Vector2(330, 42)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 12)
	feedback.text = "配置保存在 tests 中；切换保留草稿。\n镜像边缘仅为试装保险，正式接入前复核。"
	column.add_child(feedback)
	close_dialog = ConfirmationDialog.new()
	close_dialog.title = "仍有未保存的背景参数"
	close_dialog.ok_button_text = "直接关闭"
	close_dialog.cancel_button_text = "返回调整"
	close_dialog.confirmed.connect(func(): get_tree().quit())
	add_child(close_dialog)
	_sync_widgets()
	_update_profile_state()

func _add_slider(parent: Node, key: String, title: String, minimum: float, maximum: float, step_value: float) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	parent.add_child(column)
	var caption := Label.new()
	caption.add_theme_font_size_override("font_size", 12)
	column.add_child(caption)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(156, 18)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_value
	slider.value = settings[key]
	column.add_child(slider)
	sliders[key] = slider
	captions[key] = {"node":caption, "title":title}
	caption.text = "%s  %.2f" % [title, settings[key]]
	slider.value_changed.connect(func(value: float):
		settings[key] = value
		caption.text = "%s  %.2f" % [title, value]
		_apply_settings())

func _add_action(parent: Node, title: String, callback: Callable) -> Button:
	var action := Button.new()
	action.text = title
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action.add_theme_font_size_override("font_size", 13)
	action.pressed.connect(callback)
	parent.add_child(action)
	action_buttons.append(action)
	return action

func request_close() -> void:
	if profiles.unsaved_count() == 0:
		get_tree().quit()
		return
	close_dialog.dialog_text = "还有 %d 个地点的草稿未保存。返回后可逐个保存，或直接关闭并放弃草稿。" % profiles.unsaved_count()
	close_dialog.popup_centered(Vector2i(520, 160))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: request_close()

func capture_current() -> void:
	if tools_locked(): return
	capturing = true
	var panel_visible := controls.visible
	controls.hide()
	hint.hide()
	await RenderingServer.frame_post_draw
	var directory := "res://artifacts/qa/background-fitting-captures/"
	var result := DirAccess.make_dir_recursive_absolute(directory)
	var filename := "%s-%s-%d" % [profiles.current_id, Time.get_datetime_string_from_system().replace(":", "-"), Time.get_ticks_msec()]
	var destination := directory + filename + ".png"
	if result == OK:
		result = get_viewport().get_texture().get_image().save_png(destination)
		if result == OK:
			var info := FileAccess.open(directory + filename + ".json", FileAccess.WRITE)
			if info:
				info.store_string(JSON.stringify({"scene":profiles.current_id,"settings":settings,"enemies":enemy_count,"cameraZoom":view.stage.zoom,"image":profiles.scene(profiles.current_id).image}, "\t"))
				info.flush()
				result = info.get_error()
				info.close()
			else: result = FileAccess.get_open_error()
	controls.visible = panel_visible
	hint.visible = panel_visible
	capturing = false
	feedback.text = ("截图及参数已保存：\n" + filename) if result == OK else "截图保存失败：" + error_string(result)
	feedback.tooltip_text = destination

func preview_camera(close: bool) -> void:
	if not ready_for_preview or Game.battle_busy or rebuilding or preview_camera_busy or finished or is_instance_valid(view.pile_overlay): return
	view.cancel_selection()
	preview_camera_busy = true
	view.set_busy(true)
	var stage: Control = view.stage
	if close:
		var opponent: Node2D
		for actor in stage.enemies:
			if actor.alive:
				opponent = actor
				break
		if is_instance_valid(opponent):
			# Static fitting frames actual feet; attack framing assumes the lunge landed.
			stage.frame_attack(stage.player, opponent, stage.player.position)
			await stage.camera_tween.finished
	else:
		await stage.wide()
	view.set_busy(false)
	preview_camera_busy = false

func _on_finished(result: String) -> void:
	finished = true
	status.text = "演练结束：%s；点击单敌／三敌重建" % result
	view.end_button.disabled = true
	view.cyberware_button.disabled = true
	view.initialized = false
	for card in view.cards.values(): card.set_enabled(false)

func _process(_delta: float) -> void:
	var locked := tools_locked()
	for action in action_buttons:
		action.disabled = locked
	if is_instance_valid(restore_button): restore_button.disabled = locked or not profiles.has_saved()
	if is_instance_valid(scene_picker): scene_picker.disabled = locked
	for slider in sliders.values(): slider.editable = not locked

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		controls.visible = not controls.visible
		hint.visible = controls.visible
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode == KEY_S:
		save_settings()
		get_viewport().set_input_as_handled()
