extends DemoUI
## Read-only interlude: the combat model has already committed phase two.
signal finished
var lines: Array = []
var cursor := 0
var content: Control
var next_button: Button

func _ready() -> void:
	name = "NossPhaseDialogue"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 115
	mouse_filter = Control.MOUSE_FILTER_STOP
	show_line()

func show_line() -> void:
	if is_instance_valid(content):
		remove_child(content)
		content.queue_free()
	if cursor >= lines.size():
		finished.emit()
		return
	var line: Dictionary = lines[cursor]
	Game.record_encounter_line(cursor, line)
	content = Control.new()
	content.size = Vector2(1440, 900)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	rect(content, Vector2.ZERO, Vector2(1440, 900), Color("080913ed"))
	var portrait_root := DemoUI.new()
	content.add_child(portrait_root)
	portrait_root.portrait(Game.PLAYER_REFERENCE, "left", line.get("speakerId") == Game.PLAYER_REFERENCE, 82, 650)
	portrait_root.portrait(line.get("portrait", "noss_phase2"), "right", line.get("speakerId") != Game.PLAYER_REFERENCE, 82, 650)
	label(content, "太阳之下  /  第二阶段", Vector2(60, 48), Vector2(1100, 50), 26, Color("ffe6a0"))
	panel(content, Vector2(60, 648), Vector2(1320, 214), Color("0b101af5"), Color("bb984e"))
	var speaker: String = line.get("speakerId", "")
	label(content, Game.display_name(speaker) if not speaker.is_empty() else "场景", Vector2(92, 669), Vector2(1180, 42), 25, Color("ffe6a0"))
	label(content, Game.render_text(line.get("text", "")), Vector2(94, 718), Vector2(1178, 85), 25, CREAM)
	next_button = button(content, "进入第二阶段  →" if cursor == lines.size() - 1 else "继续  →", Vector2(1116, 805), Vector2(230, 42), advance_line, true)
	next_button.grab_focus()

func advance_line() -> void:
	cursor += 1
	show_line()

func _input(event: InputEvent) -> void:
	if PlayerSettings.matches(event, "advance"):
		get_viewport().set_input_as_handled()
		advance_line()
