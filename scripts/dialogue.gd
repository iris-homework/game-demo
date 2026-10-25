extends DemoUI
signal advance_requested
signal choice_confirmed
const STORY_RED := Color("ff393e")
const STORY_WHITE := Color("f4f2ef")
var text_label: Label
var node: Dictionary
var expected_revision: int
var elapsed := 0.0
var choice_buttons: Array[Button] = []
var advance_area: Control
var skip_button: Button
var history_button: Button
var history_overlay: Control
var history_text: RichTextLabel
var history_background_buttons: Dictionary = {}

func _ready() -> void:
	expected_revision = Game.revision
	node = Game.node_data()
	var e := Game.event_data()
	if Game.in_place_dialogue():
		if e.placeId == "market":
			add_child(preload("res://scripts/black_market_art.gd").new())
		else:
			image_asset(self, "woss_mall_shop", Vector2.ZERO, Vector2(1440,900))
		rect(self, Vector2.ZERO, Vector2(1440,900), Color(0,0,0,0.10))
	else:
		background(Game.place_data(e.placeId).backgroundAssetId, 0.19)
	var side: String = node.get("speakerSide", "")
	# Visible characters can differ from the speaker (creatures and off-screen NPCs).
	# Resolve from the current node so continuing an old dialogue save also shows them.
	var shown: Dictionary = Game.state.portraits.duplicate()
	var overrides = node.get("portraits", {})
	if overrides is Dictionary:
		for portrait_side in ["left", "right"]:
			var id = overrides.get(portrait_side)
			if id is String and (id.is_empty() or Game.characters.has(Game.resolve_character_id(id))):
				shown[portrait_side] = id
	var speaker := Game.resolve_character_id(node.get("speakerId", ""))
	if not Game.in_place_dialogue():
		portrait(shown.left, "left", side == "left" and Game.resolve_character_id(shown.left) == speaker, 173, 642)
		portrait(shown.right, "right", side == "right" and Game.resolve_character_id(shown.right) == speaker, 173, 642)
	map_chrome(e.title, Callable(), true) # Keep the skip-story slot between deck and menu.
	history_button = button(self, "对话记录", Vector2(856,16), Vector2(108,44), open_history)
	history_button.add_theme_font_size_override("font_size", 17)
	history_button.tooltip_text = "回看本次冒险的对白与选择"
	skip_button = button(self, "跳过剧情", Vector2(1096,16), Vector2(140,44), skip)
	skip_button.add_theme_font_size_override("font_size", 17)
	skip_button.disabled = not node.get("choices", []).is_empty() or not node.has("next")
	skip_button.tooltip_text = "请先作出选择" if not node.get("choices", []).is_empty() else "跳至下一个选择点、战斗或剧情结束"
	tag(("初次到访" if Game.in_place_dialogue() else e.id) + " / " + Game.place_data(e.placeId).name, Vector2(54,104), CYAN, 280)
	_build_advance_area()
	if not node.get("choices", []).is_empty():
		var choice_size := Vector2(845,62)
		var choice_step := 78.0
		var group_height: float = choice_size.y + (node.choices.size() - 1) * choice_step
		var group_origin := (Vector2(1440,900) - Vector2(choice_size.x, group_height)) * 0.5
		for i in node.choices.size():
			var c: Dictionary = node.choices[i]
			var allowed := Game.meets(c.get("condition", {}))
			var text: String = "%s   %s" % [i+1,c.label]
			if not allowed and c.get("condition", {}).has("creditsAtLeast"):
				text += "  （还差 %s CR）" % (int(c.condition.creditsAtLeast)-int(Game.state.credits))
			var b := _story_button(text, group_origin + Vector2(0, i * choice_step), choice_size, func(): select(i))
			b.disabled = not allowed
			b.tooltip_text = "信用点不足，可选择拒绝支付或按 F1 测试支付分支。" if not allowed else ""
			choice_buttons.append(b)
	_build_dialogue_panel()
	text_label = label(self, Game.render_text(node.get("text", "")), Vector2(330,706), Vector2(1004,118), 25, STORY_WHITE)
	text_label.add_theme_constant_override("line_spacing", 8)
	text_label.visible_characters = 0
	var hint := "点击继续    ·    SPACE / ENTER" if node.has("next") and choice_buttons.is_empty() else "点击选项    ·    数字键选择"
	label(self, hint, Vector2(330,842), Vector2(650,26), 13, MUTED)

func _build_advance_area() -> void:
	# Middle and lower scene, behind choices; keep the HUD and event tag outside.
	advance_area = Control.new()
	advance_area.name = "DialogueAdvanceArea"
	advance_area.position = Vector2(0,180)
	advance_area.size = Vector2(1440,720)
	advance_area.mouse_filter = Control.MOUSE_FILTER_STOP
	advance_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if node.has("next") and node.get("choices", []).is_empty() else Control.CURSOR_ARROW
	advance_area.gui_input.connect(_on_advance_area_input)
	add_child(advance_area)

func _on_advance_area_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		advance_area.accept_event()
		advance()

func _build_dialogue_panel() -> void:
	# Solid reading panel and a shared horizontal cap for the rising left graphics.
	rect(self, Vector2(0,650), Vector2(1440,250), Color.BLACK)
	# Two rising red rails frame the lower-right corner; the center stays open.
	_dialogue_polygon([Vector2(1025,900),Vector2(1440,786),Vector2(1440,839),Vector2(1214,900)], STORY_RED)
	_dialogue_polygon([Vector2(1047,900),Vector2(1440,792),Vector2(1440,832),Vector2(1190,900)], Color.BLACK)
	_dialogue_polygon([Vector2(1320,801),Vector2(1440,767),Vector2(1440,783),Vector2(1320,817)], STORY_RED)
	# Left slopes are clipped at y=650; keep the long underline and short bottom stripe.
	_dialogue_polygon([Vector2(0,708),Vector2(242.20,650),Vector2(275.60,650),Vector2(0,716)], STORY_RED)
	_dialogue_polygon([Vector2(0,716),Vector2(275.60,650),Vector2(380,650),Vector2(380,676),Vector2(0,767)], Color.BLACK)
	_dialogue_polygon([Vector2(0,767),Vector2(486.85,650),Vector2(511.81,650),Vector2(0,773)], STORY_RED)
	_dialogue_polygon([Vector2(0,779),Vector2(260,717),Vector2(260,804),Vector2(0,866)], STORY_RED)
	_dialogue_polygon([Vector2(0,877),Vector2(170,836),Vector2(170,844),Vector2(0,885)], STORY_RED)
	var speaker: String = node.get("speakerId", "")
	var speaker_name := Game.display_name(speaker) if not speaker.is_empty() else "场景"
	var name_font := FontVariation.new()
	name_font.base_font = base_font
	name_font.variation_embolden = 0.65
	name_font.spacing_glyph = 2
	var speaker_label := label(self, speaker_name, Vector2(20,708), Vector2(222,49), 27, STORY_WHITE)
	speaker_label.name = "SpeakerName"
	speaker_label.add_theme_font_override("font", name_font)
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speaker_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	speaker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	speaker_label.rotation = -0.20
	# Center both lines on the red plaque's local axis, using the original fonts.
	var brand_center := Vector2(130,791.5)
	var brand_angle := Vector2(260,-62).angle() # Match the plaque edge exactly.
	var title := label(self, "午夜委托", brand_center + Vector2(-110,-30).rotated(brand_angle), Vector2(220,30), 21, Color.BLACK)
	title.add_theme_font_override("font", name_font)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.rotation = brand_angle
	var subtitle := label(self, "MIDNIGHT COMMISSION", brand_center + Vector2(-110,3).rotated(brand_angle), Vector2(220,22), 13, Color.BLACK)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	subtitle.rotation = brand_angle

func _story_button(text: String, pos: Vector2, dimensions: Vector2, action: Callable) -> Button:
	# Native button states keep keyboard focus visible without the shared cyan corner marks.
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = dimensions
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", base_font)
	b.add_theme_font_size_override("font_size", 23)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var frame := StyleBoxFlat.new()
		frame.bg_color = Color("050505")
		frame.border_color = STORY_RED
		frame.set_border_width_all(3)
		frame.border_width_left = 6
		frame.skew = Vector2(0.065,0)
		frame.anti_aliasing = true
		frame.anti_aliasing_size = 1.5
		frame.content_margin_left = 22
		frame.content_margin_right = 22
		frame.content_margin_top = 4
		frame.content_margin_bottom = 4
		match state_name:
			"hover":
				frame.bg_color = Color("361015")
				frame.border_color = Color("ff6b6e")
			"pressed":
				frame.bg_color = Color("761c25")
				frame.border_color = STORY_WHITE
			"disabled":
				frame.bg_color = Color("101012")
				frame.border_color = Color("654047")
			"focus":
				frame.bg_color = Color.TRANSPARENT
				frame.border_color = STORY_WHITE
				frame.set_border_width_all(2)
		b.add_theme_stylebox_override(state_name, frame)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(color_name, STORY_WHITE)
	b.add_theme_color_override("font_disabled_color", Color("8c8385"))
	b.pressed.connect(action)
	add_child(b)
	return b

func _dialogue_polygon(points: Array, color: Color) -> Polygon2D:
	var shape := polygon(self, points, color)
	shape.antialiased = true
	return shape

func _process(delta: float) -> void:
	if is_instance_valid(history_overlay): return
	elapsed += delta
	if is_instance_valid(text_label) and text_label.visible_characters >= 0:
		text_label.visible_characters = int(elapsed * 40)
		if text_label.visible_characters >= text_label.text.length(): text_label.visible_characters = -1

func advance() -> void:
	if is_instance_valid(history_overlay): return
	advance_requested.emit()
	if text_label.visible_characters >= 0:
		text_label.visible_characters = -1
		return
	if not node.get("choices", []).is_empty() or not node.has("next"):
		return
	Game.advance(expected_revision)

func select(index: int) -> void:
	if is_instance_valid(history_overlay): return
	if Game.choose(index, expected_revision): choice_confirmed.emit()

func skip() -> void:
	if is_instance_valid(history_overlay): return
	Game.skip_dialogue(expected_revision)

func open_history() -> void:
	if is_instance_valid(history_overlay): return
	for b in find_children("*", "Button", true, false):
		history_background_buttons[b] = b.disabled
		b.release_focus()
		b.disabled = true
	history_overlay = Control.new()
	history_overlay.name = "DialogueHistory"
	history_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	history_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(history_overlay)
	rect(history_overlay, Vector2.ZERO, Vector2(1440,900), Color(0,0,0,0.78))
	panel(history_overlay, Vector2(180,118), Vector2(1080,674), Color("0d0d10"), STORY_RED)
	rect(history_overlay, Vector2(180,118), Vector2(1080,5), STORY_RED)
	label(history_overlay, "对话记录", Vector2(216,144), Vector2(600,48), 30, STORY_WHITE)
	label(history_overlay, "本次冒险 · 已经过的对白与选择", Vector2(218,199), Vector2(740,30), 16, MUTED)
	var close := button(history_overlay, "关闭 ×", Vector2(1090,148), Vector2(130,44), close_history)
	close.focus_next = close.get_path()
	close.focus_previous = close.get_path()
	rect(history_overlay, Vector2(216,245), Vector2(1008,1), Color("533037"))
	history_text = RichTextLabel.new()
	history_text.position = Vector2(218,266)
	history_text.size = Vector2(1000,458)
	history_text.add_theme_font_override("normal_font", base_font)
	history_text.add_theme_font_size_override("normal_font_size", 22)
	history_text.add_theme_color_override("default_color", STORY_WHITE)
	history_text.add_theme_constant_override("line_separation", 8)
	history_text.bbcode_enabled = false
	history_text.selection_enabled = true
	history_text.focus_mode = Control.FOCUS_NONE
	history_overlay.add_child(history_text)
	var last_event := ""
	for entry in Game.state.get("dialogueHistory", []):
		if entry.eventId != last_event:
			history_text.push_color(MUTED)
			history_text.add_text("— %s —\n\n" % entry.title)
			history_text.pop()
			last_event = entry.eventId
		history_text.push_color(STORY_RED if entry.kind == "choice" else Color("ff8588"))
		history_text.add_text(entry.speaker + "\n")
		history_text.pop()
		history_text.add_text(entry.text + "\n\n")
	if history_text.get_total_character_count() == 0:
		history_text.add_text("暂无对话记录。之后经过的对白会保存在这里。")
	label(history_overlay, "滚轮 / 触控板回看    ·    ↑ ↓ / PageUp / PageDown    ·    Esc 返回", Vector2(218,746), Vector2(1000,26), 15, MUTED)
	close.grab_focus()
	_history_scroll_to_latest.call_deferred()

func _history_scroll_to_latest() -> void:
	if is_instance_valid(history_overlay):
		history_text.scroll_to_line(maxi(0, history_text.get_line_count() - 1))

func close_history() -> void:
	if not is_instance_valid(history_overlay): return
	remove_child(history_overlay)
	history_overlay.queue_free()
	history_overlay = null
	history_text = null
	for b in history_background_buttons:
		if is_instance_valid(b): b.disabled = history_background_buttons[b]
	history_background_buttons.clear()
	history_button.grab_focus()

func handle_escape() -> bool:
	if not is_instance_valid(history_overlay): return false
	close_history()
	return true

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	if is_instance_valid(history_overlay):
		var scroll := history_text.get_v_scroll_bar()
		match event.keycode:
			KEY_UP: scroll.value -= 48
			KEY_DOWN: scroll.value += 48
			KEY_PAGEUP: scroll.value -= scroll.page
			KEY_PAGEDOWN: scroll.value += scroll.page
			KEY_HOME: scroll.value = 0
			KEY_END: scroll.value = scroll.max_value
		get_viewport().set_input_as_handled()
		return
	if event.keycode in [KEY_SPACE, KEY_ENTER]:
		get_viewport().set_input_as_handled()
		advance()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		get_viewport().set_input_as_handled()
		select(event.keycode - KEY_1)
