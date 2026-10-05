extends DemoUI

func _ready() -> void:
	background("city", 0.12)
	# A graphic split leaves the existing city illustration visible on the right.
	polygon(self,[Vector2(0,0),Vector2(856,0),Vector2(590,900),Vector2(0,900)],Color("090b12f5"))
	polygon(self,[Vector2(813,0),Vector2(838,0),Vector2(572,900),Vector2(547,900)],PINK)
	polygon(self,[Vector2(874,0),Vector2(878,0),Vector2(612,900),Vector2(608,900)],CYAN)
	label(self,"M / C",Vector2(64,39),Vector2(180,43),28,CREAM)
	label(self,"独立佣兵终端  /  连接已建立",Vector2(67,92),Vector2(540,26),13,CYAN)
	label(self,"01",Vector2(1125,134),Vector2(280,190),138,Color("ffffff28"))
	label(self,"MIDNIGHT",Vector2(62,158),Vector2(600,69),49,CREAM)
	label(self,"COMMISSION / 午夜开场",Vector2(68,231),Vector2(560,30),16,CYAN)
	var title := label(self,"午夜委托",Vector2(56,281),Vector2(660,133),96,CREAM)
	title.rotation_degrees = -4
	polygon(self,[Vector2(65,427),Vector2(535,397),Vector2(526,444),Vector2(58,474)],PINK)
	label(self,"霓虹之下，每条线索都有价码。",Vector2(79,424),Vector2(450,33),22,INK).rotation_degrees = -4
	button(self,"01   /   继续旅程     →",Vector2(84,524),Vector2(451,61),Game.resume,true).disabled = Game.state.is_empty() and not Game.has_save()
	button(self,"02   /   开始新的委托",Vector2(77,603),Vector2(444,61),request_new)
	button(self,"战斗演练",Vector2(71,683),Vector2(207,50),func(): Game.start_training("B04"))
	button(self,"机甲演练",Vector2(294,683),Vector2(211,50),func(): Game.start_training("B12"))
	button(self,"03   /   义体档案",Vector2(65,750),Vector2(425,48),Game.open_cyberware)
	label(self,"第一周  /  卡牌战斗原型",Vector2(66,820),Vector2(480,27),14,MUTED)
	tag("WEEK 01 / 午夜开场",Vector2(1083,53),CYAN,284)
	cut_panel(self,Vector2(930,638),Vector2(430,181),Color("090b12eb"),CREAM)
	label(self,"CITY ARCHIVE   /   001",Vector2(960,659),Vector2(360,29),13,CYAN)
	label(self,"沃斯的灯，\n整夜不熄。",Vector2(958,699),Vector2(366,97),32,CREAM)
	rect(self,Vector2(931,819),Vector2(154,5),PINK)
	label(self,"点击操作   /   空格推进对白   /   Esc 返回",Vector2(854,857),Vector2(525,26),13,MUTED)
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
