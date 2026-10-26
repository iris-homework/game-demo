extends DemoUI
## Battle rewards are committed by Game; this view only presents and selects them.
const GOLD := Color("ffda83")
var expected_revision: int
var picker: Control
var card_reward_button: Button
var credits_reward_button: Button
var exit_button: Button
var option_buttons: Array[Button] = []
var suspended_buttons: Array[Button] = []
var reward_identity: Dictionary
var credits_row: Control
var credits_status_label: Label
var card_row: Control
var card_subtitle: Label
var card_status_label: Label
var footer_label: Label
var boss_finale := false

func current_reward_identity() -> Dictionary:
	var identity: Dictionary = Game.state.get("battleReward", {}).duplicate(true)
	# These are the only mutable receipt fields during collection.
	for key in ["status", "creditsStatus", "selectedCardId"]: identity.erase(key)
	return identity

func _ready() -> void:
	expected_revision = Game.revision
	reward_identity = current_reward_identity()
	var reward: Dictionary = Game.state.battleReward
	var pending: bool = reward.status == "pending"
	var event_reward: bool = reward.get("source", "battle") == "event"
	background("city", 0.76)
	chrome("委托奖励" if event_reward else "战斗奖励")
	var heading := label(self,"约定的回礼" if event_reward else "战斗胜利",Vector2(210,145),Vector2(920,80),58)
	heading.add_theme_color_override("font_color",CREAM)
	tag("COMMISSION / " + reward.eventId if event_reward else "VICTORY / " + reward.battleId,Vector2(214,115),CYAN,290)
	label(self,Game.event_data().title + "  /  " + Game.battle_type_label(reward.get("battleType", "normal")) + "  /  战利品",Vector2(216,239),Vector2(980,40),20,MUTED)
	rect(self,Vector2(214,296),Vector2(1012,1),Color("3a5155"))
	label(self,"本次战利品",Vector2(214,314),Vector2(500,35),22)
	label(self,"REWARDS",Vector2(1040,320),Vector2(195,28),14,CYAN)

	var credits := cut_panel(self,Vector2(214,371),Vector2(1012,128),Color("172025"),Color("655a3f"),18)
	credits_row = credits
	credit_icon(credits,Vector2(24,23),Vector2(78,78))
	label(credits,"信用点",Vector2(130,19),Vector2(350,32),19,MUTED)
	label(credits,"+%d" % Game.reward_credit_amount(),Vector2(126,53),Vector2(380,60),42,GOLD)
	credits_reward_button = button(credits,"点击领取  →",Vector2(758,35),Vector2(221,55),claim_credits,true)
	credits_reward_button.name = "claim_reward_credits"
	credits.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			credits.accept_event()
			claim_credits())
	credits_status_label = label(credits,"",Vector2(819,49),Vector2(175,37),21,GOLD)

	var passive: Dictionary = Game.battle_passive_summary()
	if int(passive.get("credits",0)) > 0 or int(passive.get("healing",0)) > 0:
		var effects: Array[String] = []
		if int(passive.credits) > 0: effects.append("金钱芯片 +%d 信用点" % int(passive.credits))
		if int(passive.healing) > 0: effects.append("治疗芯片 +%d 生命" % int(passive.healing))
		label(credits,"额外被动收益："+"  ·  ".join(effects),Vector2(480,88),Vector2(502,30),15,CYAN).name = "passive_reward_summary"
	card_row = cut_panel(self,Vector2(214,519),Vector2(1012,161),Color("14242a") if pending else PANEL,CYAN if pending else Color("485661"),18)
	for i in range(3):
		cut_panel(card_row,Vector2(30+i*11,42-i*8),Vector2(48,70),Color("10232a"),CYAN if pending else MUTED,8)
	label(card_row,"奖励卡牌",Vector2(130,25),Vector2(410,43),29)
	card_subtitle = label(card_row,"",Vector2(132,80),Vector2(590,36),18,CYAN if pending else MUTED)
	card_reward_button = button(card_row,"点击选卡  →",Vector2(758,53),Vector2(221,55),open_picker,true)
	# The full reward entry opens the picker; decorative children ignore input.
	card_row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			card_row.accept_event()
			open_picker())
	card_status_label = label(card_row,"",Vector2(818,61),Vector2(180,37),21,CYAN)
	label(self,"从三张不同的非初始牌中选择一张 · B 蓝 / A 红 / S 金",Vector2(216,695),Vector2(980,32),15,MUTED)
	boss_finale = Game.state.activeEventId == "E16" and "E16" in Game.state.completedEventIds
	var complete: bool = Game.state.flags.get("week1Complete",false) and Game.event_data().get("nodes", {}).get("finish", {}).get("effects", []).any(func(action): return action.get("op") == "finishWeek")
	var time_text := "领奖不消耗时间。可以继续探索城市。" if event_reward else "时间推进1天。事件已更新到城市地图。"
	if boss_finale: time_text = "领取奖励后，结束第一周。"
	label(self,"第一周 · 落幕。可返回地图探索剩余事件。" if complete else time_text,Vector2(216,754),Vector2(820,35),20,CYAN)
	footer_label = label(self,"",Vector2(216,803),Vector2(775,31),16,MUTED)
	exit_button = button(self,"",Vector2(1110,782),Vector2(276,61),leave_rewards,true)
	if boss_finale:
		exit_button.add_theme_font_size_override("font_size",17)
	refresh_reward()
	fade_in()

## Return false when this is a different receipt, so normal routing can rebuild.
func refresh_reward() -> bool:
	if Game.is_week_complete() or not Game.has_battle_reward() or current_reward_identity() != reward_identity: return false
	var reward: Dictionary = Game.state.battleReward
	var pending: bool = reward.status == "pending"
	var credits_pending := Game.reward_credits_status() == "pending"
	var focus_claimed := (credits_reward_button.has_focus() and not credits_pending) or (card_reward_button.has_focus() and not pending) or (is_instance_valid(picker) and not pending)
	if not pending and is_instance_valid(picker): close_picker()
	expected_revision = Game.revision
	credits_reward_button.visible = credits_pending
	credits_reward_button.disabled = not credits_pending or is_instance_valid(picker)
	credits_status_label.visible = not credits_pending
	credits_status_label.text = "✓  已到账" if Game.reward_credits_status() == "claimed" else "已放弃"
	credits_row.mouse_filter = Control.MOUSE_FILTER_STOP if credits_pending else Control.MOUSE_FILTER_IGNORE
	credits_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if credits_pending else Control.CURSOR_ARROW
	card_reward_button.visible = pending
	card_reward_button.disabled = not pending or is_instance_valid(picker)
	card_status_label.visible = not pending
	card_status_label.text = "✓  已领取" if reward.status == "claimed" else "已跳过"
	card_status_label.add_theme_color_override("font_color", CYAN if reward.status == "claimed" else MUTED)
	card_subtitle.text = "从三张卡牌中选择一张，加入牌组" if pending else ("已获得「%s」 · 已加入牌组" % Game.reward_rules.cards[reward.selectedCardId].name if reward.status == "claimed" else "已放弃本次选卡")
	card_subtitle.add_theme_color_override("font_color", CYAN if pending else MUTED)
	card_row.mouse_filter = Control.MOUSE_FILTER_STOP if pending else Control.MOUSE_FILTER_IGNORE
	card_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if pending else Control.CURSOR_ARROW
	# cut_panel owns its border and fill polygons, followed by the three icons.
	(card_row.get_child(0) as Polygon2D).color = CYAN if pending else Color("485661")
	(card_row.get_child(1) as Polygon2D).color = Color("14242a") if pending else PANEL
	for i in range(2, 5):
		(card_row.get_child(i).get_child(0) as Polygon2D).color = CYAN if pending else MUTED
	var unclaimed: Array[String] = []
	if credits_pending: unclaimed.append("信用点")
	if pending: unclaimed.append("卡牌")
	footer_label.text = "离开将放弃本次未领取的%s。" % "和".join(unclaimed) if not unclaimed.is_empty() else ("奖励已保存，可以结束第一周。" if boss_finale else "奖励已保存，可继续探索城市。")
	var abandoned := "奖励" if credits_pending and pending else "信用点" if credits_pending else "卡牌" if pending else ""
	if boss_finale:
		exit_button.text = "放弃%s并结束第一周 →" % abandoned if not abandoned.is_empty() else "结束第一周  →"
	else:
		exit_button.text = "放弃%s并返回  →" % abandoned if not abandoned.is_empty() else "返回地图  →"
	if focus_claimed and not is_instance_valid(picker):
		if pending: card_reward_button.grab_focus()
		elif credits_pending: credits_reward_button.grab_focus()
		else: exit_button.grab_focus()
	refresh_credits(true)
	refresh_hp()
	return true

func leave_rewards() -> void:
	if is_instance_valid(picker): return
	Game.claim_rewards(expected_revision)

func claim_credits() -> void:
	if is_instance_valid(picker): return
	if not Game.claim_reward_credits(expected_revision) and Game.reward_credits_status() == "pending":
		Game.notice.emit("信用点尚未领取，请重试；若保存失败，请检查存储空间。")

func open_picker() -> void:
	if is_instance_valid(picker) or Game.transition_locked or Game.battle_busy or expected_revision != Game.revision: return
	if not Game.has_battle_reward() or Game.state.battleReward.status != "pending": return
	# Block mouse and keyboard focus on all underlying buttons, including the menu.
	suspended_buttons.clear()
	for node in find_children("*","Button",true,false):
		if not node.disabled:
			if node.has_focus(): node.release_focus()
			node.disabled = true
			suspended_buttons.append(node)
	picker = preload("res://scripts/reward_picker.gd").new()
	picker.setup(Game.state.battleReward.options, Game.reward_rules.cards, Game.owned_card_counts(), Game.state.battleReward.get("source", "battle") == "event")
	picker.card_picked.connect(func(id: String): Game.choose_reward_card(id,expected_revision))
	picker.closed.connect(close_picker)
	add_child(picker)
	option_buttons = picker.option_buttons

func _input(event: InputEvent) -> void:
	if not is_instance_valid(picker): return
	var focused := get_viewport().gui_get_focus_owner()
	if event is InputEventMouseMotion:
		# Mouse hover takes over without leaving a keyboard highlight behind.
		# Keep focus during a click: releasing it cancels BaseButton's pending
		# press, so normal pointer drift would swallow the following release.
		if event.button_mask == 0 and is_instance_valid(focused) and picker.is_ancestor_of(focused):
			focused.release_focus()
	elif not is_instance_valid(focused):
		# Enter the modal's focus loop explicitly when it starts without focus.
		if event.is_action_pressed("ui_focus_next"):
			option_buttons[0].grab_focus()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_focus_prev"):
			option_buttons[0].get_node(option_buttons[0].focus_previous).grab_focus()
			get_viewport().set_input_as_handled()

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
