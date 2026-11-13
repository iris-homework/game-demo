extends DemoUI
## Per-week completion; only week one offers a next-week entry.
var return_button: Button
var next_week_button: Button

func _ready() -> void:
	var second: bool = int(Game.state.get("currentWeek", 1)) == 2
	background(Game.place_data(Game.state.get("currentPlaceId", "hive")).get("backgroundAssetId", "hive"), 0.48 if second else 0.82)
	rect(self, Vector2.ZERO, Vector2(1440,900), Color("07131b99"))
	label(self, "MIDNIGHT / WEEK 02 COMPLETE" if second else "MIDNIGHT / WEEK 01 COMPLETE", Vector2(64,43), Vector2(800,26), 14, CYAN)
	rect(self, Vector2(64,75), Vector2(1312,1), Color("2f6178"))
	if second:
		_build_final_report()
		fade_in()
		return
	rect(self, Vector2(270,231), Vector2(900,1), Color("2f6178"))
	polygon(self, [Vector2(270,231),Vector2(306,231),Vector2(270,267)], CYAN)
	center_text("第一周结束", 300, 110, 64, CREAM, "week_end_title")
	center_text("第二周 · 新的委托已开放", 427, 52, 28, CYAN, "week_end_message")
	var rev := Game.revision
	next_week_button = button(self, "进入第二周    →", Vector2(360,548), Vector2(350,60), func(): Game.start_second_week(rev), true)
	next_week_button.name = "start_second_week"
	return_button = button(self, "返回主菜单", Vector2(730,548), Vector2(350,60), Game.menu)
	return_button.name = "return_to_menu"
	return_button.focus_mode = Control.FOCUS_ALL
	next_week_button.grab_focus()
	rect(self, Vector2(270,680), Vector2(900,1), Color("2f6178"))
	polygon(self, [Vector2(1170,680),Vector2(1134,680),Vector2(1170,644)], CYAN)
	fade_in()

func _build_final_report() -> void:
	var title := label(self, "胜利，城市已解放", Vector2(104,108), Vector2(960,92), 60)
	title.name = "week_end_title"
	var message := label(self, "封锁已解除", Vector2(108,203), Vector2(480,42), 24, CYAN)
	message.name = "week_end_message"

	var summary := cut_panel(self, Vector2(104,280), Vector2(466,450), Color("101b23"), Color("386057"))
	label(summary, "剩余生命", Vector2(32,25), Vector2(390,32), 19, MUTED)
	var hp := label(summary, "%d / %d" % [Game.state.currentHp, Game.state.maxHp], Vector2(30,61), Vector2(398,68), 43)
	hp.name = "final_health_value"
	rect(summary, Vector2(32,141), Vector2(402,1), Color("37504f"))
	label(summary, "携带科技", Vector2(32,162), Vector2(390,32), 19, MUTED)
	var technologies := PackedStringArray()
	for id in Game.equipped_cyberware_ids():
		technologies.append(Game.cyberware_definition(id).get("name", id))
	var loadout := label(summary, "、".join(technologies) if not technologies.is_empty() else "未携带", Vector2(32,204), Vector2(402,95), 24)
	loadout.name = "final_technology_value"
	rect(summary, Vector2(32,310), Vector2(402,1), Color("37504f"))
	label(summary, "击败的 Boss", Vector2(32,331), Vector2(390,32), 19, MUTED)
	var bosses := _defeated_bosses()
	var victories := label(summary, "、".join(bosses) if not bosses.is_empty() else "无记录", Vector2(32,372), Vector2(402,65), 24)
	victories.name = "final_boss_value"

	_build_deck_panel()
	return_button = button(self, "返回主菜单", Vector2(1006,774), Vector2(330,62), Game.menu)
	return_button.name = "return_to_menu"
	return_button.grab_focus()

func _defeated_bosses() -> PackedStringArray:
	var wins := {}
	for entry in Game.state.get("battleHistory", []):
		if entry is Dictionary and entry.get("result") == "win":
			wins[entry.get("battleId", "")] = true
	var names := PackedStringArray()
	for battle in Game.battles.values():
		if battle.get("battleType") != "boss" or battle.get("trainingOnly", false): continue
		if not wins.has(battle.id) and battle.eventId not in Game.state.completedEventIds: continue
		var enemy: Dictionary = Game.enemy_catalog.get(battle.get("phaseOneEndEnemyId", ""), {})
		names.append(enemy.get("displayName", battle.name))
	return names

func _build_deck_panel() -> void:
	var counts := Game.owned_card_counts()
	var definitions := []
	var total := 0
	for id in counts:
		var card: Dictionary = Game.reward_rules.cards.get(id, Game.prototype_rules.cards.get(id, {}))
		definitions.append(card)
		total += int(counts[id])
	definitions.sort_custom(Game.card_display_before)

	var deck := cut_panel(self, Vector2(600,280), Vector2(736,450), Color("111922"), Color("4b6269"))
	label(deck, "最终卡组", Vector2(30,22), Vector2(360,52), 32)
	var count_label := label(deck, "%d 张" % total, Vector2(520,31), Vector2(182,36), 22, CYAN)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rect(deck, Vector2(30,86), Vector2(676,1), Color("35444f"))

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30,103)
	scroll.size = Vector2(676,264)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	deck.add_child(scroll)
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_ALL
	var list := VBoxContainer.new()
	list.name = "final_deck_list"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 2)
	list.add_child(grid)
	for card in definitions:
		var row := label(grid, "%s ×%d" % [card.name, counts[card.id]], Vector2.ZERO, Vector2.ZERO, 21)
		row.custom_minimum_size = Vector2(0,36)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var reward: Dictionary = Game.state.get("battleReward", {})
	var card_id: String = reward.get("selectedCardId", "")
	var receipt_text := "无最终选卡记录"
	if reward.get("eventId", "") == Game.week_boss_event():
		if reward.get("status") == "claimed" and not card_id.is_empty():
			receipt_text = "最终选卡　" + str(Game.reward_rules.cards.get(card_id, {}).get("name", card_id))
		elif reward.get("status") == "skipped":
			receipt_text = "最终选卡已跳过"
	rect(deck, Vector2(30,383), Vector2(676,1), Color("35444f"))
	label(deck, receipt_text, Vector2(30,397), Vector2(676,37), 19, CYAN).name = "final_reward_card"

func center_text(text: String, y: float, height: float, font_size: int, color: Color, node_name: String) -> void:
	var text_label := label(self, text, Vector2(270,y), Vector2(900,height), font_size, color)
	text_label.name = node_name
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func handle_escape() -> bool:
	Game.menu()
	return true
