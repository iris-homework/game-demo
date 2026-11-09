extends DemoUI
## Read-only paged catalog; viewing never grants or equips technologies.
const TechnologyIcons = preload("res://scripts/technology_icons.gd")
const PAGE_SIZE := 6
var page_index := 0
var catalog: Control

func _ready() -> void:
	background("tower",0.67)
	label(self,"TECHNOLOGY / ARCHIVE",Vector2(84,74),Vector2(980,38),18,CYAN)
	label(self,"科技档案",Vector2(80,123),Vector2(900,80),52)
	rect(self,Vector2(85,215),Vector2(144,5),PINK)
	label(self,"在地图配置携带 · 主动科技手动激活，被动科技自动生效",Vector2(86,239),Vector2(1180,40),22,MUTED)
	button(self,"← 返回主菜单",Vector2(84,810),Vector2(360,59),Game.menu,true).name = "return_menu"
	refresh_catalog()

func change_page(delta: int) -> void:
	var pages := maxi(1,ceili(float(TechnologyIcons.ids().size())/PAGE_SIZE))
	var next := clampi(page_index+delta,0,pages-1)
	if next == page_index: return
	page_index = next
	refresh_catalog()
	catalog.get_node("previous_page" if delta > 0 else "next_page").grab_focus()

func refresh_catalog() -> void:
	if is_instance_valid(catalog):
		remove_child(catalog)
		catalog.queue_free()
	catalog = Control.new()
	catalog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(catalog)
	var ids := TechnologyIcons.ids()
	var pages := maxi(1,ceili(float(ids.size())/PAGE_SIZE))
	page_index = clampi(page_index,0,pages-1)
	for i in range(page_index*PAGE_SIZE,mini((page_index+1)*PAGE_SIZE,ids.size())):
		var id: String = ids[i]
		var definition := Game.cyberware_definition(id)
		if definition.is_empty(): continue
		var passive := CombatModel.is_passive_cyberware(definition)
		var local_index := i%PAGE_SIZE
		var card := panel(catalog,Vector2(100+(local_index%3)*420,302+floori(float(local_index)/3.0)*248),Vector2(400,230),Color("090b12eb"),CYAN if passive else Color("746187"))
		card.name = "archive_" + id
		label(card,"TECH / %02d" % (i+1),Vector2(24,8),Vector2(352,20),12,CYAN)
		TechnologyIcons.create(card,id,Vector2(22,29),Vector2(120,120))
		label(card,str(definition.name),Vector2(160,45),Vector2(216,40),25)
		label(card,TechnologyIcons.activation_label(definition),Vector2(160,104),Vector2(216,28),16,CYAN)
		label(card,str(definition.description),Vector2(24,153),Vector2(352,69),16,MUTED)
	var previous := button(catalog,"上一页",Vector2(762,817),Vector2(146,46),change_page.bind(-1))
	previous.name = "previous_page"
	previous.disabled = page_index == 0
	label(catalog,"第 %d / %d 页 · 共 %d 项" % [page_index+1,pages,ids.size()],Vector2(922,821),Vector2(258,34),18,CYAN).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var next := button(catalog,"下一页",Vector2(1194,817),Vector2(146,46),change_page.bind(1))
	next.name = "next_page"
	next.disabled = page_index >= pages-1
