extends DemoUI
func _ready() -> void:
	background("tower",0.67)
	label(self,"CYBERWARE / META PROFILE",Vector2(84,108),Vector2(980,46),18,CYAN)
	label(self,"义体档案",Vector2(80,188),Vector2(900,90),63)
	label(self,"独立于本次委托的局外系统",Vector2(86,309),Vector2(1080,52),25,MUTED)
	cut_panel(self,Vector2(84,407),Vector2(1270,260),Color("090b12eb"),CYAN,28)
	rect(self,Vector2(85,278),Vector2(144,5),PINK)
	label(self,"尚无可配置义体",Vector2(120,448),Vector2(1120,62),34)
	label(self,"义体种类、获取、装备槽与效果待设计。\n当前入口不发放物品，也不改变冒险或战斗属性。",Vector2(123,533),Vector2(1110,94),22,MUTED)
	button(self,"← 返回主菜单",Vector2(84,738),Vector2(360,59),Game.menu,true)
