extends DemoUI

func _ready() -> void:
	background("city", 0.20)
	rect(self, Vector2.ZERO, Vector2(740,900), Color("120d20d9"))
	rect(self, Vector2(80,99), Vector2(62,4), PINK)
	label(self, "MIDNIGHT COMMISSION", Vector2(80,128), Vector2(590,42), 19, CYAN)
	label(self, "午夜委托", Vector2(73,196), Vector2(655,120), 88)
	label(self, "霓虹之下，每条线索都有价码。", Vector2(82,348), Vector2(580,52), 24, CREAM)
	label(self, "接下委托，追踪线索。\n在沃斯集团与革命军之间，走进这座城市。", Vector2(83,425), Vector2(560,80), 20, MUTED)
	button(self, "继续旅程    →", Vector2(83,525), Vector2(440,61), Game.resume, true).disabled = Game.state.is_empty() and not Game.has_save()
	button(self, "开始新的委托", Vector2(83,603), Vector2(440,61), request_new)
	button(self,"战斗演练",Vector2(83,683),Vector2(208,51),func(): Game.start_training("B04"))
	button(self,"机甲演练",Vector2(311,683),Vector2(212,51),func(): Game.start_training("B12"),true)
	button(self,"义体档案",Vector2(83,752),Vector2(440,45),Game.open_cyberware)
	label(self,"第一周 / 卡牌战斗原型 R1",Vector2(83,811),Vector2(600,29),15,MUTED)
	tag("WEEK 01 / 午夜开场", Vector2(1090,68), CYAN, 270)
	panel(self, Vector2(933,666), Vector2(426,149), Color("16111eda"), Color("665169"))
	label(self, "城市档案  /  01", Vector2(961,686), Vector2(350,31), 16, PINK)
	label(self, "沃斯的灯，整夜不熄。", Vector2(961,728), Vector2(370,44), 25)
	label(self, "点击操作 · 空格 / 回车推进对白 · Esc 菜单", Vector2(80,854), Vector2(900,30), 15, MUTED)
	fade_in()

func request_new() -> void:
	if Game.has_save() or not Game.state.is_empty():
		var confirm := ConfirmationDialog.new()
		confirm.title = "开始新的委托"
		confirm.dialog_text = "这会覆盖当前游戏进度。是否开始新游戏？"
		confirm.ok_button_text = "开始新游戏"
		confirm.cancel_button_text = "返回"
		confirm.confirmed.connect(Game.new_game)
		add_child(confirm)
		confirm.popup_centered(Vector2i(550,180))
	else: Game.new_game()
