extends DemoUI
## Draft selection; only an explicit save changes the adventure loadout.
signal closed
const PURPLE := Color("c895ff")
var draft_ids: Array = []
var slot_buttons: Array[Button] = []
var technology_buttons: Dictionary = {}
var save_button: Button
var summary_label: Label
var message_label: Label
var expected_revision := 0

func _ready() -> void:
	z_index = 75
	mouse_filter = Control.MOUSE_FILTER_STOP
	draft_ids = Game.equipped_cyberware_ids()
	expected_revision = Game.revision
	rect(self,Vector2.ZERO,Vector2(1440,900),Color("06030fee"))
	cut_panel(self,Vector2(64,34),Vector2(1312,828),INK,PURPLE,28)
	rect(self,Vector2(102,70),Vector2(5,67),PURPLE)
	label(self,"科技配置",Vector2(122,68),Vector2(650,56),36)
	label(self,"从已有科技中选择携带，最多 4 项。保存后用于之后的新战斗。",Vector2(124,130),Vector2(1060,34),19,MUTED)
	var close_button := button(self,"关闭  ×",Vector2(1190,78),Vector2(146,46),func(): closed.emit())
	summary_label = label(self,"",Vector2(124,187),Vector2(900,30),20,PURPLE)
	for i in CombatModel.CYBERWARE_LIMIT:
		var slot := button(self,"",Vector2(135+i*300,234),Vector2(270,130),remove_slot.bind(i))
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
		label(card,str(definition.name),Vector2(20,18),Vector2(336,36),25)
		label(card,str(definition.description),Vector2(20,66),Vector2(336,64),19)
		label(card,"冷却 %d 回合" % int(definition.get("cooldownTurns",1)),Vector2(20,132),Vector2(336,26),16,PURPLE)
		label(card,"",Vector2(20,174),Vector2(336,26),17,PURPLE).name = "selection_state"
		technology_buttons[id] = card
	if technology_buttons.is_empty():
		label(grid,"当前角色暂无已有科技",Vector2.ZERO,Vector2(1100,60),25,MUTED)
	message_label = label(self,"",Vector2(124,744),Vector2(1040,30),18,PURPLE)
	button(self,"取消",Vector2(836,797),Vector2(234,46),func(): closed.emit())
	save_button = button(self,"保存配置",Vector2(1100,797),Vector2(234,46),save_selection,true)
	label(self,"关闭或 Esc 放弃本次未保存的修改",Vector2(124,805),Vector2(680,30),16,MUTED)
	refresh()
	close_button.grab_focus()

func toggle_technology(id: String) -> void:
	if not technology_buttons.has(id): return
	message_label.text = ""
	if id in draft_ids:
		draft_ids.erase(id)
	elif draft_ids.size() < CombatModel.CYBERWARE_LIMIT:
		draft_ids.append(id)
	else:
		message_label.text = "最多携带 4 项科技，请先卸下一项。"
	refresh()

func remove_slot(index: int) -> void:
	if index < 0 or index >= draft_ids.size(): return
	draft_ids.remove_at(index)
	message_label.text = ""
	refresh()

func refresh() -> void:
	summary_label.text = "携带科技  %d / 4" % draft_ids.size()
	for i in slot_buttons.size():
		var slot := slot_buttons[i]
		slot.disabled = i >= draft_ids.size()
		slot.text = "%02d  /  空位" % (i+1) if slot.disabled else "%02d  /  %s\n点击卸下" % [i+1,Game.cyberware_definition(draft_ids[i]).name]
		slot.add_theme_font_size_override("font_size",20)
	for id in technology_buttons:
		var card: Button = technology_buttons[id]
		var selected: bool = id in draft_ids
		card.add_theme_stylebox_override("normal",style(Color("30203f") if selected else Color("15131e"),PURPLE if selected else Color("494053"),2))
		card.add_theme_stylebox_override("hover",style(Color("482866"),PURPLE,2))
		card.add_theme_stylebox_override("pressed",style(Color("342047"),PURPLE,2))
		card.add_theme_stylebox_override("focus",style(Color.TRANSPARENT,PURPLE,2))
		card.get_node("selection_state").text = "已携带 · 点击卸下" if selected else "点击携带"
		card.tooltip_text = "卸下" if selected else "携带"

func save_selection() -> void:
	if not Game.set_technology_loadout(draft_ids,expected_revision):
		message_label.text = "保存失败，请检查存档状态或重新打开配置界面后再试。"
		return
	closed.emit()
	Game.notice.emit("科技配置已保存，下场战斗生效。")
