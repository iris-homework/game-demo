extends DemoUI
## Per-week completion; only week one offers a next-week entry.
var return_button: Button
var next_week_button: Button

func _ready() -> void:
	var second: bool = int(Game.state.get("currentWeek", 1)) == 2
	background(Game.place_data(Game.state.get("currentPlaceId", "hive")).get("backgroundAssetId", "hive"), 0.82)
	rect(self, Vector2.ZERO, Vector2(1440,900), Color("07131b99"))
	label(self, "MIDNIGHT / WEEK 02 COMPLETE" if second else "MIDNIGHT / WEEK 01 COMPLETE", Vector2(64,43), Vector2(800,26), 14, CYAN)
	rect(self, Vector2(64,75), Vector2(1312,1), Color("2f6178"))
	rect(self, Vector2(270,231), Vector2(900,1), Color("2f6178"))
	polygon(self, [Vector2(270,231),Vector2(306,231),Vector2(270,267)], CYAN)
	center_text("胜利，城市已解放" if second else "第一周结束", 300, 110, 64, CREAM, "week_end_title")
	center_text("封锁已解除" if second else "第二周 · 新的委托已开放", 427, 52, 28, CYAN, "week_end_message")
	var rev := Game.revision
	if not second:
		next_week_button = button(self, "进入第二周    →", Vector2(360,548), Vector2(350,60), func(): Game.start_second_week(rev), true)
		next_week_button.name = "start_second_week"
	return_button = button(self, "返回主菜单", Vector2(545 if second else 730,548), Vector2(350,60), Game.menu)
	return_button.name = "return_to_menu"
	return_button.focus_mode = Control.FOCUS_ALL
	if second: return_button.grab_focus()
	else: next_week_button.grab_focus()
	rect(self, Vector2(270,680), Vector2(900,1), Color("2f6178"))
	polygon(self, [Vector2(1170,680),Vector2(1134,680),Vector2(1170,644)], CYAN)
	fade_in()

func center_text(text: String, y: float, height: float, font_size: int, color: Color, node_name: String) -> void:
	var text_label := label(self, text, Vector2(270,y), Vector2(900,height), font_size, color)
	text_label.name = node_name
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func handle_escape() -> bool:
	Game.menu()
	return true
