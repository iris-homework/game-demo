extends DemoUI
## Battle rewards are committed by Game; this view only presents and selects them.
const GOLD := Color("ffda83")
var expected_revision: int
var picker: Control
var card_reward_button: Button
var exit_button: Button
var option_buttons: Array[Button] = []
var suspended_buttons: Array[Button] = []

func _ready() -> void:
	expected_revision = Game.revision
	var reward: Dictionary = Game.state.battleReward
	var pending: bool = reward.status == "pending"
	background("city", 0.76)
	chrome("战斗奖励")
	var heading := label(self,"战斗胜利",Vector2(210,145),Vector2(920,80),58)
	heading.add_theme_color_override("font_color",CREAM)
	tag("VICTORY / " + reward.battleId,Vector2(214,115),CYAN,220)
	label(self,Game.event_data().title + "  /  战利品已结算",Vector2(216,239),Vector2(980,40),20,MUTED)
	rect(self,Vector2(214,296),Vector2(1012,1),Color("3a5155"))
	label(self,"本次战利品",Vector2(214,314),Vector2(500,35),22)
	label(self,"REWARDS / 02",Vector2(1040,320),Vector2(195,28),14,CYAN)

	var credits := cut_panel(self,Vector2(214,371),Vector2(1012,128),Color("172025"),Color("655a3f"),18)
	cut_panel(credits,Vector2(24,23),Vector2(78,78),Color("302c22"),GOLD,14)
	label(credits,"CR",Vector2(36,41),Vector2(63,39),28,GOLD)
	label(credits,"信用点",Vector2(130,19),Vector2(350,32),19,MUTED)
	label(credits,"+1,000",Vector2(126,53),Vector2(380,60),42,GOLD)
	label(credits,"✓  已到账",Vector2(819,49),Vector2(175,37),21,GOLD)

	var card_row := cut_panel(self,Vector2(214,519),Vector2(1012,161),Color("14242a") if pending else PANEL,CYAN if pending else Color("485661"),18)
	for i in range(3):
		cut_panel(card_row,Vector2(30+i*11,42-i*8),Vector2(48,70),Color("10232a"),CYAN if pending else MUTED,8)
	label(card_row,"奖励卡牌",Vector2(130,25),Vector2(410,43),29)
	var subtitle := "从三张卡牌中选择一张，加入牌组"
	if reward.status == "claimed": subtitle = "已获得「%s」 · 已加入牌组" % Game.reward_rules.cards[reward.selectedCardId].name
	elif reward.status == "skipped": subtitle = "已放弃本次选卡"
	label(card_row,subtitle,Vector2(132,80),Vector2(590,36),18,CYAN if pending else MUTED)
	if pending:
		card_reward_button = button(card_row,"点击选卡  →",Vector2(758,53),Vector2(221,55),open_picker,true)
		# The full reward entry opens the picker; decorative children ignore input.
		card_row.mouse_filter = Control.MOUSE_FILTER_STOP
		card_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card_row.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				card_row.accept_event()
				open_picker())
	else:
		label(card_row,"✓  已领取" if reward.status == "claimed" else "已跳过",Vector2(818,61),Vector2(180,37),21,CYAN if reward.status == "claimed" else MUTED)
	label(self,"三张卡牌暂用测试卡占位 · 均为攻击 1 / 无费用",Vector2(216,695),Vector2(980,32),15,MUTED)
	var complete: bool = Game.state.flags.get("week1Complete",false) and Game.state.activeEventId == "E12"
	label(self,"第一周 · 落幕。可返回地图探索剩余支线。" if complete else "新的线索已更新到城市地图。",Vector2(216,754),Vector2(820,35),20,CYAN)
	label(self,"离开将放弃本次未选择的卡牌。" if pending else "奖励已保存，可继续探索城市。",Vector2(216,803),Vector2(775,31),16,MUTED)
	exit_button = button(self,"返回地图  →",Vector2(1110,782),Vector2(276,61),leave_rewards,true)
	fade_in()

func leave_rewards() -> void:
	if is_instance_valid(picker): return
	Game.claim_rewards(expected_revision)

func open_picker() -> void:
	if is_instance_valid(picker) or Game.transition_locked or Game.battle_busy or expected_revision != Game.revision: return
	if not Game.has_battle_reward() or Game.state.battleReward.status != "pending": return
	# Block mouse and keyboard focus on all underlying buttons, including the menu.
	suspended_buttons.clear()
	for node in find_children("*","Button",true,false):
		if not node.disabled:
			node.disabled = true
			suspended_buttons.append(node)
	picker = Control.new()
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.mouse_filter = Control.MOUSE_FILTER_STOP
	picker.z_index = 60
	add_child(picker)
	rect(picker,Vector2.ZERO,Vector2(1440,900),Color(0.015,0.025,0.04,0.94))
	cut_panel(picker,Vector2(129,117),Vector2(1182,670),Color("101920"),CYAN,25)
	label(picker,"选择一张奖励卡牌",Vector2(191,157),Vector2(1030,65),40)
	label(picker,"三选一  /  点击卡牌领取，所选卡牌将在后续战斗中加入牌组。",Vector2(194,233),Vector2(1030,39),19,MUTED)
	option_buttons.clear()
	for i in range(3):
		var id: String = Game.state.battleReward.options[i]
		var pos := Vector2(225+i*360,316)
		var card := CombatCard.new()
		card.managed_input = true
		card.setup(id,Game.reward_rules.cards[id],true)
		card.pivot_offset = Vector2.ZERO
		card.position = pos
		card.scale = Vector2.ONE * 1.5
		picker.add_child(card)
		var b := Button.new()
		b.name = "RewardOption%d" % (i+1)
		b.position = pos-Vector2(10,10)
		b.size = Vector2(290,403)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for mode in ["normal","pressed","hover","focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(0.25,0.9,0.8,0.06) if mode in ["hover","focus"] else Color.TRANSPARENT
			box.border_color = CYAN if mode != "pressed" else PINK
			box.set_border_width_all(2 if mode in ["hover","focus","pressed"] else 0)
			b.add_theme_stylebox_override(mode,box)
		b.pressed.connect(func(): Game.choose_reward_card(id,expected_revision))
		picker.add_child(b)
		option_buttons.append(b)
		var caption := label(picker,"选择这张  [%d]" % (i+1),pos+Vector2(0,357),Vector2(270,35),19,CYAN)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var back := button(picker,"返回奖励  /  Esc",Vector2(1052,717),Vector2(212,44),close_picker)
	label(picker,"临时测试卡 · 攻击 1 · 无费用",Vector2(192,726),Vector2(680,32),16,MUTED)
	var focus_buttons: Array[Button] = option_buttons.duplicate()
	focus_buttons.append(back)
	for i in focus_buttons.size():
		focus_buttons[i].focus_next = focus_buttons[i].get_path_to(focus_buttons[(i+1)%focus_buttons.size()])
		focus_buttons[i].focus_previous = focus_buttons[i].get_path_to(focus_buttons[(i+focus_buttons.size()-1)%focus_buttons.size()])
	option_buttons[0].grab_focus()

func close_picker() -> void:
	if not is_instance_valid(picker): return
	remove_child(picker)
	picker.queue_free()
	picker = null
	option_buttons.clear()
	for b in suspended_buttons:
		if is_instance_valid(b): b.disabled = false
	suspended_buttons.clear()
	if is_instance_valid(card_reward_button): card_reward_button.grab_focus()

func handle_escape() -> bool:
	if not is_instance_valid(picker): return false
	close_picker()
	return true

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_instance_valid(picker) or not event.is_pressed() or event.is_echo() or not event is InputEventKey: return
	if event.keycode >= KEY_1 and event.keycode <= KEY_3:
		get_viewport().set_input_as_handled()
		Game.choose_reward_card(Game.state.battleReward.options[event.keycode-KEY_1],expected_revision)
