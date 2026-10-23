extends DemoUI
## Read-only catalog; viewing never grants or equips adventure technologies.
const TechnologyIcons = preload("res://scripts/technology_icons.gd")

func _ready() -> void:
	background("tower",0.67)
	label(self,"TECHNOLOGY / ARCHIVE",Vector2(84,74),Vector2(980,38),18,CYAN)
	label(self,"科技档案",Vector2(80,123),Vector2(900,80),52)
	rect(self,Vector2(85,215),Vector2(144,5),PINK)
	label(self,"在地图配置携带 · 主动科技手动激活，被动科技自动生效",Vector2(86,239),Vector2(1180,40),22,MUTED)
	var ids := TechnologyIcons.ids()
	for i in ids.size():
		var id: String = ids[i]
		var definition := Game.cyberware_definition(id)
		if definition.is_empty(): continue
		var passive := CombatModel.is_passive_cyberware(definition)
		var card := panel(self,Vector2(100+(i%3)*420,302+floori(float(i)/3.0)*248),Vector2(400,230),Color("090b12eb"),CYAN if passive else Color("746187"))
		card.name = "archive_" + id
		label(card,"TECH / %02d" % (i+1),Vector2(24,10),Vector2(352,24),12,CYAN)
		TechnologyIcons.create(card,id,Vector2(22,36),Vector2(120,120))
		label(card,str(definition.name),Vector2(160,45),Vector2(216,40),25)
		label(card,TechnologyIcons.activation_label(definition),Vector2(160,104),Vector2(216,28),16,CYAN)
		label(card,str(definition.description),Vector2(24,169),Vector2(352,49),17,MUTED)
	button(self,"← 返回主菜单",Vector2(84,810),Vector2(360,59),Game.menu,true).name = "return_menu"
