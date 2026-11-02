extends DemoUI
## Read-only interlude: the combat model has already committed phase two.
signal finished
const Presentation := preload("res://scripts/dialogue_presentation.gd")
var lines: Array = []
var cursor := 0
var content: Control

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
	content = Presentation.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	content.background(Game.place_data(Game.events.E23.placeId).backgroundAssetId, 0.19)
	var speaker: String = line.get("speakerId", "")
	var side := "" if speaker.is_empty() else ("left" if speaker == Game.PLAYER_REFERENCE else "right")
	content.dialogue_portraits({"left":Game.PLAYER_REFERENCE, "right":line.get("portrait", "noss_phase2")}, speaker, side)
	var advance_area := Control.new()
	advance_area.name = "DialogueAdvanceArea"
	advance_area.position = Vector2(0,180)
	advance_area.size = Vector2(1440,720)
	advance_area.mouse_filter = Control.MOUSE_FILTER_STOP
	advance_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	advance_area.gui_input.connect(_on_advance_area_input)
	content.add_child(advance_area)
	content.dialogue_panel(speaker)
	content.dialogue_text(Game.render_text(line.get("text", "")))
	content.dialogue_hint(("点击进入第二阶段" if cursor == lines.size() - 1 else "点击继续") + "    ·    " + PlayerSettings.key_label("advance"))

func _on_advance_area_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		advance_line()

func advance_line() -> void:
	cursor += 1
	show_line()

func _input(event: InputEvent) -> void:
	if PlayerSettings.matches(event, "advance"):
		get_viewport().set_input_as_handled()
		advance_line()
