extends DemoUI
signal closed
var entry: LineEdit
var output: RichTextLabel
var history: Array[String] = []
var history_index := 0

func _ready() -> void:
	z_index = 120
	mouse_filter = Control.MOUSE_FILTER_STOP
	rect(self, Vector2.ZERO, Vector2(1440,900), Color(0,0,0,0.86))
	panel(self, Vector2(190,100), Vector2(1060,680), INK, CYAN)
	label(self,"卡牌控制台",Vector2(222,118),Vector2(600,52),30)
	button(self,"关闭 / F2",Vector2(1040,121),Vector2(175,42),func(): closed.emit())
	output = RichTextLabel.new()
	output.position = Vector2(226,190)
	output.size = Vector2(990,470)
	output.add_theme_font_size_override("normal_font_size",18)
	output.selection_enabled = true
	output.scroll_following = true
	add_child(output)
	output.text = Game.console_command("help") + "\n"
	entry = LineEdit.new()
	entry.position = Vector2(226,684)
	entry.size = Vector2(990,54)
	entry.placeholder_text = "addcard 短点连射 2"
	entry.add_theme_font_size_override("font_size",20)
	entry.text_submitted.connect(submit)
	add_child(entry)
	entry.grab_focus()

func submit(command: String) -> void:
	if command.strip_edges().is_empty(): return
	history.append(command)
	history_index = history.size()
	output.append_text("\n> " + command + "\n" + Game.console_command(command) + "\n")
	entry.clear()
	entry.grab_focus()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	if event.keycode in [KEY_ESCAPE, KEY_F2]:
		get_viewport().set_input_as_handled()
		closed.emit()
	elif event.keycode in [KEY_UP, KEY_DOWN] and entry.has_focus():
		get_viewport().set_input_as_handled()
		history_index = clampi(history_index + (-1 if event.keycode == KEY_UP else 1), 0, history.size())
		entry.text = history[history_index] if history_index < history.size() else ""
		entry.caret_column = entry.text.length()
