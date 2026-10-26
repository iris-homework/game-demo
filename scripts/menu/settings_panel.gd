extends DemoUI
signal closed

var master_slider: HSlider
var sfx_slider: HSlider
var sfx_toggle: CheckButton
var binding_buttons: Dictionary = {}
var listening_action := ""
var status_label: Label
var close_button: Button
var reset_button: Button
var master_value: Label
var sfx_value: Label
var focus_controls: Array[Control] = []

func _ready() -> void:
	name = "settings_panel"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(1440, 900)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := rect(self, Vector2.ZERO, size, Color(0, 0, 0, 0.78))
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	panel(self, Vector2(235, 55), Vector2(970, 790), PANEL, CYAN)
	label(self, "设置", Vector2(277, 78), Vector2(400, 48), 32)
	label(self, "调整后立即生效并自动保存", Vector2(278, 135), Vector2(870, 28), 17, MUTED)
	label(self, "声音", Vector2(278, 185), Vector2(300, 32), 23, CYAN)
	label(self, "总音量", Vector2(278, 239), Vector2(180, 30), 19)
	master_value = label(self, "", Vector2(555, 239), Vector2(80, 30), 18, MUTED)
	master_slider = _slider(Vector2(280, 285))
	label(self, "音效音量", Vector2(278, 343), Vector2(180, 30), 19)
	sfx_value = label(self, "", Vector2(555, 343), Vector2(80, 30), 18, MUTED)
	sfx_slider = _slider(Vector2(280, 389))
	sfx_toggle = CheckButton.new()
	sfx_toggle.text = "开启音效"
	sfx_toggle.position = Vector2(278, 445)
	sfx_toggle.size = Vector2(350, 48)
	add_child(sfx_toggle)
	focus_controls.append(sfx_toggle)
	label(self, "涵盖界面、对白与战斗声音", Vector2(278, 506), Vector2(350, 30), 16, MUTED)
	var help := label(self, "固定操作\nEsc / 右键：取消或返回\nTab / 方向键：界面导航\nEnter / Space：确认焦点按钮\n对白数字键：选择选项\n出牌仍需鼠标选定目标", Vector2(278, 565), Vector2(355, 160), 16, MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label(self, "快捷键", Vector2(700, 185), Vector2(400, 32), 23, CYAN)
	label(self, "点击键位后按下新键 · Esc 取消改键", Vector2(700, 224), Vector2(440, 28), 16, MUTED)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.position = Vector2(690, 266)
	scroll.size = Vector2(465, 448)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margins := MarginContainer.new()
	margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 10)
	scroll.add_child(margins)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	margins.add_child(column)
	for action in PlayerSettings.DEFAULT_BINDINGS:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 42
		column.add_child(row)
		var title := Label.new()
		title.text = PlayerSettings.action_label(action)
		title.add_theme_font_size_override("font_size", 17)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var key_button := button(row, "", Vector2.ZERO, Vector2(168, 42), begin_rebind.bind(action))
		key_button.custom_minimum_size = Vector2(168, 42)
		key_button.add_theme_font_size_override("font_size", 16)
		binding_buttons[action] = key_button
		focus_controls.append(key_button)
	reset_button = button(self, "恢复默认", Vector2(278, 757), Vector2(178, 46), _reset)
	close_button = button(self, "返回主菜单", Vector2(934, 757), Vector2(220, 46), func(): closed.emit(), true)
	focus_controls.append(reset_button)
	focus_controls.append(close_button)
	status_label = label(self, "", Vector2(478, 752), Vector2(435, 58), 16, MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	master_slider.value_changed.connect(func(value: float): PlayerSettings.set_master_volume(value / 100.0); _update_values())
	sfx_slider.value_changed.connect(func(value: float): PlayerSettings.set_sfx_volume(value / 100.0); _update_values())
	sfx_toggle.toggled.connect(func(value: bool): PlayerSettings.set_sfx_enabled(value))
	PlayerSettings.status_changed.connect(_status_changed)
	_refresh()
	_status_changed(not PlayerSettings.pending_save)
	# Keep keyboard focus within this modal, including both ends of the scroll list.
	for index in focus_controls.size():
		var current := focus_controls[index]
		current.focus_next = current.get_path_to(focus_controls[(index + 1) % focus_controls.size()])
		current.focus_previous = current.get_path_to(focus_controls[posmod(index - 1, focus_controls.size())])
		current.focus_neighbor_top = current.focus_previous
		current.focus_neighbor_bottom = current.focus_next
	close_button.grab_focus()

func _slider(pos: Vector2) -> HSlider:
	var slider := HSlider.new()
	slider.position = pos
	slider.size = Vector2(350, 38)
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	add_child(slider)
	focus_controls.append(slider)
	return slider

func _update_values() -> void:
	master_value.text = "%d%%" % roundi(PlayerSettings.master_volume * 100)
	sfx_value.text = "%d%%" % roundi(PlayerSettings.sfx_volume * 100)

func _refresh() -> void:
	master_slider.set_value_no_signal(PlayerSettings.master_volume * 100)
	sfx_slider.set_value_no_signal(PlayerSettings.sfx_volume * 100)
	sfx_toggle.set_pressed_no_signal(PlayerSettings.sfx_enabled)
	_update_values()
	for action in binding_buttons:
		binding_buttons[action].text = "请按新键…" if action == listening_action else PlayerSettings.key_label(action)

func _status_changed(success: bool) -> void:
	if not is_instance_valid(status_label): return
	status_label.text = "已自动保存" if success else "设置已生效，保存失败；正在自动重试。"
	status_label.modulate = CREAM if success else PINK

func _reset() -> void:
	listening_action = ""
	PlayerSettings.reset_defaults()
	_refresh()

func begin_rebind(action: String) -> void:
	listening_action = action
	_refresh()
	status_label.text = "请按新键，Esc 取消；不支持组合键。"

func handle_key(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if not listening_action.is_empty():
		if event.keycode == KEY_ESCAPE:
			listening_action = ""
			_refresh()
			_status_changed(not PlayerSettings.pending_save)
			return
		if event.ctrl_pressed or event.alt_pressed or event.shift_pressed or event.meta_pressed:
			status_label.text = "请选择单个按键，不支持组合键。"
			return
		var error := PlayerSettings.bind_key(listening_action, event.keycode)
		if not error.is_empty():
			status_label.text = error
			return
		listening_action = ""
		_refresh()
		_status_changed(not PlayerSettings.pending_save)
	elif event.keycode == KEY_ESCAPE:
		closed.emit()
