extends DemoUI
signal closed
signal picked(value)
var heading := "选择"
var options: Array = []
var option_buttons: Array[Button] = []
var cancel_button: Button
var resolved := false

func _ready() -> void:
	z_index = 75
	mouse_filter = Control.MOUSE_FILTER_STOP
	rect(self,Vector2.ZERO,Vector2(1440,900),Color(0.01,0.02,0.04,0.94))
	panel(self,Vector2(240,120),Vector2(960,660),INK,CYAN)
	label(self,heading,Vector2(280,146),Vector2(720,50),29)
	cancel_button = button(self,"取消",Vector2(1000,146),Vector2(150,42),cancel)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(280,222)
	scroll.size = Vector2(880,514)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",12)
	scroll.add_child(column)
	for option in options:
		var btn := Button.new()
		btn.text = option.text
		btn.custom_minimum_size = Vector2(850,70)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size",18)
		btn.pressed.connect(choose.bind(option.value))
		column.add_child(btn)
		option_buttons.append(btn)
	# Explicit neighbours keep Tab and directional focus inside the modal, including
	# the empty-options case where Cancel is the only focusable control.
	var controls: Array[Button] = option_buttons.duplicate()
	controls.append(cancel_button)
	for i in controls.size():
		var previous := controls[i].get_path_to(controls[posmod(i-1,controls.size())])
		var following := controls[i].get_path_to(controls[(i+1)%controls.size()])
		controls[i].focus_previous = previous
		controls[i].focus_next = following
		controls[i].focus_neighbor_top = previous
		controls[i].focus_neighbor_left = previous
		controls[i].focus_neighbor_bottom = following
		controls[i].focus_neighbor_right = following
	controls[0].grab_focus()

func choose(value) -> void:
	if resolved: return
	resolved = true
	picked.emit(value)

func cancel() -> void:
	if resolved: return
	resolved = true
	closed.emit()

func is_gui_key(event: InputEventKey) -> bool:
	for action in ["ui_accept","ui_focus_next","ui_focus_prev","ui_up","ui_down","ui_left","ui_right"]:
		if event.is_action(action): return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if resolved:
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if event.pressed and not event.echo: cancel()
		elif is_gui_key(event):
			# Let the focused Button handle both press and release, so accepting a
			# choice follows the same single-activation path as a mouse click.
			var focus := get_viewport().gui_get_focus_owner()
			if focus == null or not is_ancestor_of(focus):
				if option_buttons.is_empty(): cancel_button.grab_focus()
				else: option_buttons[0].grab_focus()
		else:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		cancel()

func _unhandled_key_input(_event: InputEvent) -> void:
	# GUI navigation that has no destination must not become a battle shortcut.
	get_viewport().set_input_as_handled()
