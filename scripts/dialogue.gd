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
			var b := button(self, text, Vector2(427-i*12,320+i*78), Vector2(845,62), func(): select(i), true)
			b.disabled = not allowed
			b.tooltip_text = "信用点不足，可选择拒绝支付或按 F1 测试支付分支。" if not allowed else ""
			choice_buttons.append(b)
	polygon(self,[Vector2(79,603),Vector2(1406,626),Vector2(1365,843),Vector2(35,817)],PINK)
	polygon(self,[Vector2(57,631),Vector2(1378,604),Vector2(1391,815),Vector2(72,836)],CREAM)
	polygon(self,[Vector2(66,639),Vector2(1369,613),Vector2(1381,807),Vector2(80,827)],INK)
	var speaker: String = node.get("speakerId", "")
	polygon(self,[Vector2(88,592),Vector2(383,577),Vector2(366,637),Vector2(74,650)],PINK)
	label(self, Game.display_name(speaker) if not speaker.is_empty() else "场景", Vector2(108,588), Vector2(255,45), 25, INK)
	text_label = label(self, Game.render_text(node.get("text", "")), Vector2(107,661), Vector2(1210,112), 25)
	text_label.visible_characters = 0
	label(self, "SPACE / ENTER  推进    ·    1 / 2  选择", Vector2(107,783), Vector2(770,29), 14, MUTED)
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
