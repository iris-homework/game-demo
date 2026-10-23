extends DemoUI
## Terminal adventure view. No map, rewards or battle controls are exposed here.
var return_button: Button

func _ready() -> void:
	var place := Game.place_data(Game.state.get("currentPlaceId", ""))
	background(place.get("backgroundAssetId", ""), 0.85)
	rect(self, Vector2.ZERO, Vector2(1440, 900), Color("160a10a6"))
	# Broken telemetry line and cut corners share the game's angular neon language.
	rect(self, Vector2(64, 75), Vector2(1312, 1), Color("73303e"))
	label(self, "MIDNIGHT / CONNECTION LOST", Vector2(64, 43), Vector2(650, 26), 14, MUTED)
	var signal_label := label(self, "●  佣兵信号中断", Vector2(1076, 43), Vector2(300, 26), 14, PINK)
	signal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	polygon(self, [Vector2(270, 200), Vector2(307, 200), Vector2(270, 237)], PINK)
	polygon(self, [Vector2(1170, 713), Vector2(1133, 713), Vector2(1170, 676)], PINK)
	rect(self, Vector2(302, 200), Vector2(868, 1), Color("73303e"))
	rect(self, Vector2(270, 713), Vector2(868, 1), Color("73303e"))
	center_text("GAME OVER", 247, 34, 18, PINK, "game_over_label")
	center_text("战 败", 300, 143, 104, CREAM, "defeat_title")
	# A flatlined signal under the title makes the lost-signal motif explicit.
	rect(self, Vector2(553, 464), Vector2(136, 2), Color("73303e"))
	rect(self, Vector2(705, 463), Vector2(30, 4), PINK)
	rect(self, Vector2(751, 464), Vector2(136, 2), Color("73303e"))
	center_text("本次冒险已结束", 501, 43, 28, CREAM, "defeat_message")
	center_text("返回主菜单，开始新的委托。", 554, 34, 19, MUTED, "defeat_hint")
	return_button = button(self, "返回主菜单    →", Vector2(550, 625), Vector2(340, 60), Game.menu)
	return_button.name = "return_to_menu"
	return_button.focus_mode = Control.FOCUS_ALL
	for state_name in ["normal", "hover", "pressed", "focus"]:
		var box := button_style(state_name, false)
		box.border_color = PINK if state_name != "focus" else CREAM
		if state_name == "hover": box.bg_color = Color("612536")
		elif state_name == "normal": box.bg_color = Color("30141f")
		return_button.add_theme_stylebox_override(state_name, box)
	return_button.grab_focus()
	var context := "第 %d 天  /  %s" % [int(Game.state.get("currentDay", 1)), str(place.get("name", "未知地点"))]
	center_text(context, 788, 30, 15, MUTED, "defeat_context")
	fade_in()

func center_text(text: String, y: float, height: float, font_size: int, color: Color, node_name: String) -> Label:
	var text_label := label(self, text, Vector2(270, y), Vector2(900, height), font_size, color)
	text_label.name = node_name
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return text_label

func handle_escape() -> bool:
	Game.request_menu()
	return true
