extends DemoUI
## Battle technologies; separate from the read-only combat piles.
signal closed
signal activation_requested(id: String)
const PURPLE := Color("c895ff")
var model: CombatModel
var card_buttons: Array[Button] = []
var state_labels: Array[Label] = []
var status_label: Label
var close_button: Button

func setup(combat: CombatModel) -> void:
	model = combat

func _ready() -> void:
	z_index = 70
	mouse_filter = Control.MOUSE_FILTER_STOP
	rect(self,Vector2.ZERO,Vector2(1440,900),Color("06030fee"))
	cut_panel(self,Vector2(64,34),Vector2(1312,828),INK,PURPLE,28)
	rect(self,Vector2(102,70),Vector2(5,67),PURPLE)
	label(self,"激活科技",Vector2(122,68),Vector2(350,56),36)
	label(self,"%02d / TECHNOLOGY" % model.cyberware_cards().size(),Vector2(420,80),Vector2(420,38),20,PURPLE)
	label(self,"冷却计入使用当回合 · 每进入下一玩家回合，剩余冷却减少 1",Vector2(124,129),Vector2(1000,31),17,MUTED)
	close_button = button(self,"关闭  ×",Vector2(1190,78),Vector2(146,46),func(): closed.emit())
	if model.cyberware_cards().is_empty():
		label(self,"当前角色没有可激活科技",Vector2(310,360),Vector2(820,60),30,MUTED)
	for i in model.cyberware_cards().size():
		var definition: Dictionary = model.cyberware_cards()[i]
		# Normalize legacy snapshot text for display without changing saved rules.
		var display_name := str(definition.name).replace("义体", "科技")
		var description := str(definition.description).replace("义体", "科技")
		var row_width := model.cyberware_cards().size()*270 + maxi(0, model.cyberware_cards().size()-1)*30
		var pos := Vector2((1440-row_width)/2.0+i*300,320)
		var b := button(self,"",pos,Vector2(270,246),func(): activation_requested.emit(definition.id))
		for state_name in ["normal","hover","pressed","disabled","focus"]:
			var fill := Color("251638")
			if state_name == "hover": fill = Color("482866")
			elif state_name == "pressed": fill = Color("342047")
			elif state_name == "disabled": fill = Color("25272d")
			elif state_name == "focus": fill = Color.TRANSPARENT
			b.add_theme_stylebox_override(state_name,style(fill,PURPLE if state_name != "disabled" else Color("606570"),2))
		var cooldown := int(definition.get("cooldownTurns", 1))
		b.tooltip_text = display_name + "\n" + description + "\n冷却 %d 回合（含使用当回合）。" % cooldown
		label(b,"TECH / %02d" % (i+1),Vector2(20,13),Vector2(228,25),12,PURPLE)
		label(b,display_name,Vector2(20,46),Vector2(230,38),25)
		rect(b,Vector2(20,92),Vector2(230,1),Color("74528f"))
		var effect_label := label(b,description,Vector2(20,105),Vector2(230,54),19,CREAM)
		effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label(b,"冷却 %d 回合" % cooldown,Vector2(20,169),Vector2(230,25),15,PURPLE)
		state_labels.append(label(b,"",Vector2(20,200),Vector2(235,31),17,PURPLE))
		for child in b.get_children():
			if child is Label: child.set_meta("active_color",child.get_theme_color("font_color"))
			elif child is ColorRect: child.set_meta("active_color",child.color)
		card_buttons.append(b)
	status_label = label(self,"",Vector2(125,748),Vector2(1100,34),20,PURPLE)
	var shortcut := ""
	if card_buttons.size() == 1: shortcut = "  /  数字 1 激活"
	elif card_buttons.size() > 1: shortcut = "  /  数字 1—%d 激活" % card_buttons.size()
	label(self,"点击卡牌激活" + shortcut + "  /  Esc 或右键关闭",Vector2(124,811),Vector2(860,28),15,MUTED)
	button(self,"返回战斗  →",Vector2(1100,797),Vector2(234,46),func(): closed.emit())
	refresh()
	close_button.grab_focus()

func refresh() -> void:
	for i in card_buttons.size():
		var id: String = model.cyberware_cards()[i].id
		var remaining := model.cyberware_cooldown(id)
		var used := not model.cyberware_available(id)
		card_buttons[i].disabled = used
		for child in card_buttons[i].get_children():
			if child is Label: child.add_theme_color_override("font_color",Color("a7abb5") if used else child.get_meta("active_color"))
			elif child is ColorRect: child.color = Color("606570") if used else child.get_meta("active_color")
		state_labels[i].text = ("冷却中 · 下回合可用" if remaining == 1 else "冷却中 · 剩余 %d 回合" % remaining) if remaining > 0 else ("当前不可用" if used else "%d  /  点击激活" % (i+1))
	status_label.text = "本回合可用 %d 项科技" % model.available_cyberware_count()
	if model.next_attack_bonus > 0: status_label.text += "    /    待生效：下次攻击伤害 +%d" % model.next_attack_bonus

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		if not event.pressed or event.is_echo(): return
		if event.keycode in [KEY_ESCAPE,KEY_ENTER,KEY_KP_ENTER]:
			closed.emit()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			var index: int = event.keycode-KEY_1
			if index < card_buttons.size() and not card_buttons[index].disabled:
				activation_requested.emit(model.cyberware_cards()[index].id)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		closed.emit()
