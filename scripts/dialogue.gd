extends DemoUI
var text_label: Label
var node: Dictionary
var expected_revision: int
var elapsed := 0.0
var choice_buttons: Array[Button] = []
var advance_button: Button

func _ready() -> void:
	expected_revision = Game.revision
	node = Game.node_data()
	var e := Game.event_data()
	background(Game.place_data(e.placeId).backgroundAssetId, 0.19)
	var side: String = node.get("speakerSide", "")
	portrait(Game.state.portraits.left, "left", side == "left", 123, 642)
	portrait(Game.state.portraits.right, "right", side == "right", 123, 642)
	chrome(e.title)
	tag(e.id + " / " + Game.place_data(e.placeId).name, Vector2(54,104), CYAN, 280)
	if not node.get("choices", []).is_empty():
		for i in node.choices.size():
			var c: Dictionary = node.choices[i]
			var allowed := Game.meets(c.get("condition", {}))
			var text: String = "%s   %s" % [i+1,c.label]
			if not allowed and c.get("condition", {}).has("creditsAtLeast"):
				text += "  （还差 %s CR）" % (int(c.condition.creditsAtLeast)-int(Game.state.credits))
			var b := button(self, text, Vector2(390,347+i*80), Vector2(860,64), func(): select(i), true)
			b.disabled = not allowed
			b.tooltip_text = "信用点不足，可选择拒绝支付或按 F1 测试支付分支。" if not allowed else ""
			choice_buttons.append(b)
	panel(self, Vector2(57,623), Vector2(1327,204), Color("15111ff5"), Color("a4517b"))
	rect(self, Vector2(57,623), Vector2(6,204), PINK)
	var speaker: String = node.get("speakerId", "")
	panel(self, Vector2(88,587), Vector2(290,57), PINK, PINK)
	label(self, Game.display_name(speaker) if not speaker.is_empty() else "场景", Vector2(108,592), Vector2(255,45), 25, INK)
	text_label = label(self, Game.render_text(node.get("text", "")), Vector2(96,668), Vector2(1222,98), 25)
	text_label.visible_characters = 0
	label(self, "SPACE / ENTER  推进    ·    1 / 2  选择", Vector2(96,784), Vector2(770,29), 14, MUTED)
	if node.has("next"):
		advance_button = button(self, "继续  ▸", Vector2(1190,769), Vector2(151,42), advance)
	else:
		label(self, "请选择上方选项", Vector2(1160,783), Vector2(185,32), 16, CYAN)

func _process(delta: float) -> void:
	elapsed += delta
	if is_instance_valid(text_label) and text_label.visible_characters >= 0:
		text_label.visible_characters = int(elapsed * 40)
		if text_label.visible_characters >= text_label.text.length(): text_label.visible_characters = -1

func advance() -> void:
	if text_label.visible_characters >= 0:
		text_label.visible_characters = -1
		return
	Game.advance(expected_revision)

func select(index: int) -> void:
	Game.choose(index, expected_revision)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	if event.keycode in [KEY_SPACE, KEY_ENTER]:
		get_viewport().set_input_as_handled()
		advance()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		get_viewport().set_input_as_handled()
		select(event.keycode - KEY_1)
