extends DemoUI
signal closed
signal picked(value)
var heading := "选择"
var options: Array = []

func _ready() -> void:
	z_index = 75
	mouse_filter = Control.MOUSE_FILTER_STOP
	rect(self,Vector2.ZERO,Vector2(1440,900),Color(0.01,0.02,0.04,0.94))
	panel(self,Vector2(240,120),Vector2(960,660),INK,CYAN)
	label(self,heading,Vector2(280,146),Vector2(720,50),29)
	button(self,"取消",Vector2(1000,146),Vector2(150,42),func(): closed.emit())
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(280,222)
	scroll.size = Vector2(880,514)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
		btn.pressed.connect(func(): picked.emit(option.value))
		column.add_child(btn)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			closed.emit()
		elif event.keycode != KEY_TAB: get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		closed.emit()
