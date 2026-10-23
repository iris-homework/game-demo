extends DemoUI
## Each equipment change is committed immediately; closing only dismisses the panel.
signal closed
const TechnologyIcons = preload("res://scripts/technology_icons.gd")
const PURPLE := Color("c895ff")
var selected_ids: Array = []
var slot_buttons: Array[Button] = []
var technology_buttons: Dictionary = {}
var summary_label: Label
var message_label: Label
var expected_revision := 0

func _ready() -> void:
	z_index = 75
	mouse_filter = Control.MOUSE_FILTER_STOP
	selected_ids = Game.equipped_cyberware_ids()
	expected_revision = Game.revision
	rect(self,Vector2.ZERO,Vector2(1440,900),Color("06030fee"))
	cut_panel(self,Vector2(64,34),Vector2(1312,828),INK,PURPLE,28)
	rect(self,Vector2(102,70),Vector2(5,67),PURPLE)
	label(self,"科技配置",Vector2(122,68),Vector2(650,56),36)
	label(self,"从已有科技中选择携带，最多 4 项。更改自动保存，用于之后的新战斗。",Vector2(124,130),Vector2(1060,34),19,MUTED)
	var close_button := button(self,"关闭  ×",Vector2(1190,78),Vector2(146,46),func(): closed.emit())
	summary_label = label(self,"",Vector2(124,187),Vector2(900,30),20,PURPLE)
	for i in CombatModel.CYBERWARE_LIMIT:
		var slot := button(self,"",Vector2(135+i*300,234),Vector2(270,130),remove_slot.bind(i))
		TechnologyIcons.create(slot,"",Vector2(18,34),Vector2(60,60))
		label(slot,"",Vector2(92,28),Vector2(162,80),18).name = "equipped_title"
		slot_buttons.append(slot)
	label(self,"已有科技",Vector2(124,408),Vector2(900,38),25)
	label(self,"点击携带或卸下；上方顺序对应战斗中的数字键。",Vector2(124,451),Vector2(1080,30),17,MUTED)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(124,495)
	scroll.size = Vector2(1190,235)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",18)
	grid.add_theme_constant_override("v_separation",16)
	scroll.add_child(grid)
	for id in Game.owned_cyberware_ids():
		var definition := Game.cyberware_definition(id)
		var card := Button.new()
		card.custom_minimum_size = Vector2(376,212)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(toggle_technology.bind(id))
		grid.add_child(card)
		TechnologyIcons.create(card,id,Vector2(20,18),Vector2(96,96))
		label(card,str(definition.name),Vector2(134,25),Vector2(222,40),24)
		label(card,TechnologyIcons.activation_label(definition),Vector2(134,78),Vector2(222,26),16,PURPLE)
		label(card,str(definition.description),Vector2(20,119),Vector2(336,50),17)
		label(card,"",Vector2(20,174),Vector2(336,26),17,PURPLE).name = "selection_state"
		technology_buttons[id] = card
	if technology_buttons.is_empty():
		label(grid,"当前角色暂无已有科技",Vector2.ZERO,Vector2(1100,60),25,MUTED)
	message_label = label(self,"",Vector2(124,744),Vector2(1040,30),18,PURPLE)
	label(self,"更改自动保存，关闭或 Esc 返回地图",Vector2(124,805),Vector2(1080,30),16,MUTED)
	refresh()
	close_button.grab_focus()

func toggle_technology(id: String) -> void:
	if not technology_buttons.has(id): return
	var next_ids := selected_ids.duplicate()
	if id in next_ids:
		next_ids.erase(id)
	elif next_ids.size() < CombatModel.CYBERWARE_LIMIT:
		next_ids.append(id)
	else:
		message_label.text = "最多携带 4 项科技，请先卸下一项。"
		return
	commit_selection(next_ids)

func remove_slot(index: int) -> void:
	if index < 0 or index >= selected_ids.size(): return
	var next_ids := selected_ids.duplicate()
	next_ids.remove_at(index)
	commit_selection(next_ids)

func commit_selection(ids: Array) -> void:
	var saved := Game.set_technology_loadout(ids,expected_revision)
	selected_ids = Game.equipped_cyberware_ids()
	expected_revision = Game.revision
	message_label.text = "已自动保存，下场战斗生效。" if saved else "保存失败，未应用本次更改，请重试。"
	refresh()

func refresh() -> void:
	summary_label.text = "携带科技  %d / 4" % selected_ids.size()
	for i in slot_buttons.size():
		var slot := slot_buttons[i]
		slot.disabled = i >= selected_ids.size()
		slot.text = "%02d  /  空位" % (i+1) if slot.disabled else ""
		var id := "" if slot.disabled else str(selected_ids[i])
		TechnologyIcons.assign(slot.get_node("technology_icon"),id)
		slot.get_node("equipped_title").text = "" if slot.disabled else "%02d / %s\n点击卸下" % [i+1,Game.cyberware_definition(id).name]
		slot.add_theme_font_size_override("font_size",20)
	for id in technology_buttons:
		var card: Button = technology_buttons[id]
		var selected: bool = id in selected_ids
		card.add_theme_stylebox_override("normal",style(Color("30203f") if selected else Color("15131e"),PURPLE if selected else Color("494053"),2))
		card.add_theme_stylebox_override("hover",style(Color("482866"),PURPLE,2))
		card.add_theme_stylebox_override("pressed",style(Color("342047"),PURPLE,2))
		card.add_theme_stylebox_override("focus",style(Color.TRANSPARENT,PURPLE,2))
		card.get_node("selection_state").text = "已携带 · 点击卸下" if selected else "点击携带"
		card.tooltip_text = "卸下" if selected else "携带"

