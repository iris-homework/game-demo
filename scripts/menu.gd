extends DemoUI
## 主菜单：右侧 350px 列放标题、委托入口与只读摘要，左侧交给环境组件的诺伦坐姿。
## 继续、新游戏、牌库、义体档案、演练都通过 Game 调用流程。
## 原生背景与诺伦局部动画由菜单环境组件提供，本脚本不绘制角色、背景或帧素材。

const MENU_ENVIRONMENT := preload("res://scripts/menu/menu_environment.gd")
const FACTION_LABELS := {"": "自由佣兵", "company": "公司特遣部", "resistance": "革命军"}
const COLUMN_X := 980.0
const COLUMN_WIDTH := 350.0
const MASK_LEFT := 920.0
const MASK_RIGHT := 1350.0

var environment: Node
var ui_layer: Control
var continue_button: Button
var new_button: Button
var cyberware_button: Button
var library_button: Button
var training_toggle: Button
var training_container: Control
var motion_button: Button
var progress_summary: Label
var confirm_dialog: Control
var confirm_ok: Button
var confirm_cancel: Button
var modal_button_states: Dictionary = {}
## 观测接口：演练子菜单展开状态，测试可与 training_container.visible 对照。
var training_open := false

func _ready() -> void:
	_add_environment()
	ui_layer = Control.new()
	ui_layer.name = "ui_layer"
	ui_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui_layer)
	_add_readability_mask()
	_build_right_column()
	_build_bottom_right()
	_fade_in_ui()
	new_button.grab_focus() if continue_button.disabled else continue_button.grab_focus()

func _add_environment() -> void:
	# 组件由主协调者维护；这里只负责最底层接入，不绘制背景或角色。
	environment = MENU_ENVIRONMENT.new()
	environment.name = "menu_environment"
	add_child(environment)
	move_child(environment, 0)
	# 组件通常自行定尺寸；仅在未定尺寸时兜底铺满逻辑画布。
	if environment is Control and environment.size == Vector2.ZERO:
		environment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _add_readability_mask() -> void:
	# 只在文字与按钮后 x≈920..1350 轻薄渐暗，边缘柔和；右侧 x≈1380 瓶形灯牌保持原亮度。
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.031, 0.027, 0.058, 0.0),
		Color(0.031, 0.027, 0.058, 0.55),
		Color(0.031, 0.027, 0.058, 0.55),
		Color(0.031, 0.027, 0.058, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.30, 0.78, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = int(MASK_RIGHT - MASK_LEFT)
	texture.height = 900
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0)
	var mask := TextureRect.new()
	mask.name = "readability_mask"
	mask.texture = texture
	mask.position = Vector2(MASK_LEFT, 0)
	mask.size = Vector2(MASK_RIGHT - MASK_LEFT, 900)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(mask)

func _build_right_column() -> void:
	rect(ui_layer, Vector2(COLUMN_X, 88), Vector2(56, 4), PINK)
	label(ui_layer, "MIDNIGHT COMMISSION", Vector2(COLUMN_X, 100), Vector2(380, 24), 15, CYAN)
	var title := label(ui_layer, "午夜委托", Vector2(COLUMN_X - 4, 132), Vector2(390, 112), 66)
	title.name = "menu_title"
	# 文字后已有局部渐暗；再给标题一层轻阴影，压暗不足时仍保持清楚。
	title.add_theme_color_override("font_shadow_color", Color(0.02, 0.015, 0.05, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	label(ui_layer, "霓虹之下，每条线索都有价码。", Vector2(COLUMN_X + 2, 252), Vector2(350, 30), 19, MUTED)

	continue_button = _menu_button("continue_commission", "继续委托", Vector2(COLUMN_X, 330), Vector2(COLUMN_WIDTH, 66), Game.resume, true)
	# 无内存进度且无存档时禁用；禁用按钮会被 Godot 焦点环自动跳过。
	continue_button.disabled = Game.state.is_empty() and not Game.has_save()
	if continue_button.disabled: continue_button.focus_mode = Control.FOCUS_NONE
	progress_summary = label(ui_layer, _summary_text(), Vector2(COLUMN_X + 2, 410), Vector2(COLUMN_WIDTH - 2, 26), 15, MUTED)
	progress_summary.name = "progress_summary"

	new_button = _menu_button("new_commission", "新的委托", Vector2(COLUMN_X, 446), Vector2(COLUMN_WIDTH, 66), request_new)

	library_button = _menu_button("card_library", "牌库", Vector2(COLUMN_X, 536), Vector2(COLUMN_WIDTH, 48), Game.open_card_library)
	cyberware_button = _menu_button("cyberware_archive", "义体档案", Vector2(COLUMN_X, 606), Vector2(165, 48), Game.open_cyberware, false, 17)
	training_toggle = _menu_button("training_toggle", "演练  展开", Vector2(COLUMN_X + 185, 606), Vector2(165, 48), _toggle_training, false, 17)

	training_container = Control.new()
	training_container.name = "training_menu"
	training_container.position = Vector2(COLUMN_X, 666)
	training_container.size = Vector2(COLUMN_WIDTH, 50)
	training_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	training_container.visible = false
	ui_layer.add_child(training_container)
	_menu_button("training_B04", "B04 战斗演练", Vector2(0, 0), Vector2(165, 50), func(): Game.start_training("B04"), false, 16, training_container)
	_menu_button("training_B12", "B12 机甲演练", Vector2(185, 0), Vector2(165, 50), func(): Game.start_training("B12"), false, 16, training_container)

func _build_bottom_right() -> void:
	motion_button = _menu_button("motion_toggle", _motion_label(), Vector2(COLUMN_X, 828), Vector2(200, 44), _toggle_motion, false, 16)
	var version := str(ProjectSettings.get_setting("application/config/version", "0.2.6-r1"))
	label(ui_layer, "v" + version, Vector2(COLUMN_X + 230, 838), Vector2(120, 24), 13, MUTED)

func _menu_button(node_name: String, text: String, pos: Vector2, dimensions: Vector2, action: Callable, accent: bool = false, font_size: int = 19, host: Node = null) -> Button:
	var b := button(host if host != null else ui_layer, text, pos, dimensions, action, accent)
	b.name = node_name
	b.focus_mode = Control.FOCUS_ALL
	if font_size != 19:
		b.add_theme_font_size_override("font_size", font_size)
	return b

func _summary_text() -> String:
	if not Game.state.is_empty():
		var place_name := str(Game.place_data(Game.state.get("currentPlaceId", "")).get("name", ""))
		var faction := str(FACTION_LABELS.get(Game.state.get("faction", ""), "自由佣兵"))
		if place_name.is_empty():
			return faction
		return "%s  ·  %s" % [place_name, faction]
	if Game.has_save():
		# 仅磁盘存档时只提示存在检查点，不触发读取、恢复或保存。
		return "已有检查点"
	return "暂无委托记录"

func request_new() -> void:
	if Game.has_save() or not Game.state.is_empty():
		_open_confirm()
	else:
		Game.new_game()

func _open_confirm() -> void:
	if is_instance_valid(confirm_dialog):
		confirm_dialog.queue_free()
	confirm_dialog = Control.new()
	confirm_dialog.name = "new_commission_confirm"
	confirm_dialog.size = Vector2(1440, 900)
	confirm_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(confirm_dialog)
	var shade := rect(confirm_dialog, Vector2.ZERO, Vector2(1440, 900), Color(0, 0, 0, 0.64))
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	panel(confirm_dialog, Vector2(414, 325), Vector2(612, 250), PANEL, CYAN)
	label(confirm_dialog, "开始新的委托", Vector2(446, 350), Vector2(548, 44), 29)
	label(confirm_dialog, "这会覆盖当前进度。是否开始新的委托？", Vector2(446, 411), Vector2(548, 45), 19, MUTED)
	confirm_cancel = _menu_button("confirm_cancel", "返回", Vector2(446, 497), Vector2(176, 48), _close_confirm, false, 19, confirm_dialog)
	confirm_ok = _menu_button("confirm_ok", "开始新的委托", Vector2(644, 497), Vector2(344, 48), _on_new_confirmed, true, 19, confirm_dialog)
	confirm_ok.focus_next = confirm_ok.get_path_to(confirm_cancel)
	confirm_ok.focus_previous = confirm_ok.focus_next
	confirm_cancel.focus_next = confirm_cancel.get_path_to(confirm_ok)
	confirm_cancel.focus_previous = confirm_cancel.focus_next
	modal_button_states.clear()
	for node in ui_layer.find_children("*", "Button", true, false):
		modal_button_states[node] = {"disabled": node.disabled, "focus": node.focus_mode}
		node.disabled = true
		node.focus_mode = Control.FOCUS_NONE
	confirm_cancel.grab_focus()

func _on_new_confirmed() -> void:
	Game.new_game()

func _close_confirm() -> void:
	confirm_dialog.hide()
	for node in modal_button_states:
		if is_instance_valid(node):
			node.disabled = modal_button_states[node].disabled
			node.focus_mode = modal_button_states[node].focus
	modal_button_states.clear()
	new_button.grab_focus()

func _toggle_training() -> void:
	_set_training_open(not training_open)

func _set_training_open(value: bool) -> void:
	training_open = value
	if is_instance_valid(training_container):
		training_container.visible = value
	if is_instance_valid(training_toggle):
		training_toggle.text = "演练  收起" if value else "演练  展开"

func _motion_enabled() -> bool:
	if is_instance_valid(environment) and environment.has_method("get_motion_enabled"):
		return environment.get_motion_enabled()
	return true

func _toggle_motion() -> void:
	# 开关只改环境静态状态，当前会话保持；不动文字与按钮位置。
	var value := not _motion_enabled()
	if is_instance_valid(environment) and environment.has_method("set_motion_enabled"):
		environment.set_motion_enabled(value)
	if is_instance_valid(motion_button):
		motion_button.text = _motion_label()

func _motion_label() -> String:
	return "动态效果：开" if _motion_enabled() else "动态效果：关"

## 主流程 Esc 接口：先关确认弹窗，再收演练子菜单；其余情况交回全局处理。
func handle_escape() -> bool:
	if is_instance_valid(confirm_dialog) and confirm_dialog.visible:
		_close_confirm()
		return true
	if training_open:
		_set_training_open(false)
		return true
	return false

func _fade_in_ui() -> void:
	# 只淡入 UI 层，背景与角色保持立即可见，避免整幅画面先被淡黑。
	ui_layer.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(ui_layer, "modulate:a", 1.0, 0.4)
