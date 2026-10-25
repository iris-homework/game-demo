extends DemoUI
## First-week completion screen. Game owns progress and persistence.
var return_button: Button

func _ready() -> void:
	background(Game.place_data(Game.state.get("currentPlaceId", "hive")).get("backgroundAssetId", "hive"), 0.82)
	rect(self, Vector2.ZERO, Vector2(1440,900), Color("07131b99"))
	label(self, "MIDNIGHT / WEEK 01 COMPLETE", Vector2(64,43), Vector2(800,26), 14, CYAN)
	rect(self, Vector2(64,75), Vector2(1312,1), Color("2f6178"))
	rect(self, Vector2(270,231), Vector2(900,1), Color("2f6178"))
	polygon(self, [Vector2(270,231),Vector2(306,231),Vector2(270,267)], CYAN)
	center_text("第一周结束", 300, 110, 64, CREAM, "week_end_title")
	center_text("后续内容开发中", 439, 52, 28, CYAN, "week_end_message")
	return_button = button(self, "返回主菜单    →", Vector2(550,578), Vector2(340,60), Game.menu, true)
	return_button.name = "return_to_menu"
	return_button.focus_mode = Control.FOCUS_ALL
	return_button.grab_focus()
	rect(self, Vector2(270,701), Vector2(900,1), Color("2f6178"))
	polygon(self, [Vector2(1170,701),Vector2(1134,701),Vector2(1170,665)], CYAN)
	fade_in()

func center_text(text: String, y: float, height: float, font_size: int, color: Color, node_name: String) -> void:
	var text_label := label(self, text, Vector2(270,y), Vector2(900,height), font_size, color)
	text_label.name = node_name
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func handle_escape() -> bool:
	Game.menu()
	return true
