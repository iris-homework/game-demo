extends DemoUI
## Presentation only. CombatModel owns rules; Game owns persistence and story returns.
var model: CombatModel
var battle: Dictionary
var expected_revision: int
var selected_uid := ""
var held_card_uid := ""
var cards: Dictionary = {}
var enemy_hud: Control
var targets: Array[Button] = []
var aim: Node2D
var hovered_target := -1
var player_portrait: TextureRect
var enemy_portraits: Array = []
var message_label: Label
var turn_label: Label
var draw_count: Label
var discard_count: Label
var end_button: Button
var cyberware_button: Button
var cyberware_status: Label
var pile_overlay: Control
var initialized := false
const DRAW_POS := Vector2(75,711)
const DISCARD_POS := Vector2(1250,711)

func _ready() -> void:
	enter({"battleId":Game.state.battleId,"eventId":Game.state.activeEventId})

func enter(params: Dictionary) -> void:
	battle = Game.battles[params.battleId]
	if Game.state.combat.is_empty(): Game.initialize_combat()
	model = CombatModel.new()
	model.restore(Game.state.combat)
	expected_revision = Game.revision
	background(Game.place_data(battle.placeId).backgroundAssetId,0.15)
	# A restrained lower tint separates readable cards from the scene.
	polygon(self,[Vector2(0,629),Vector2(1440,606),Vector2(1440,900),Vector2(0,900)],Color("090b12e5"))
	polygon(self,[Vector2(0,622),Vector2(330,617),Vector2(327,625),Vector2(0,630)],PINK)
	var arena := Node2D.new()
	arena.set_script(preload("res://scripts/combat/arena_fx.gd"))
	add_child(arena)
	chrome("战斗")
	label(self,battle.name,Vector2(41,112),Vector2(700,55),33)
	label(self,"COMBAT // " + Game.place_data(battle.placeId).name,Vector2(43,166),Vector2(670,29),14,CYAN)
	tag("演练模式 · 不影响冒险" if Game.training_mode else "临时规则 / 攻击 1 · 敌方 HP 3",Vector2(1030,117),CYAN,360)
	if Game.texture(Game.place_data(battle.placeId).backgroundAssetId) == null:
		label(self,"场景美术待补",Vector2(43,203),Vector2(330,26),13,MUTED)
	cut_panel(self,Vector2(565,204),Vector2(310,45),INK,CYAN,12)
	turn_label = label(self,"回合 %02d  /  你的回合" % model.turn,Vector2(592,210),Vector2(275,37),18,CYAN)
	var n_asset: String = Game.characters.noren.get("battlePortraitAssetId", "")
	player_portrait = battle_portrait(n_asset,Vector2(90,215),Vector2(630,335))
	label(self,Game.display_name("noren"),Vector2(305,552),Vector2(280,33),23)
	label(self,"NEURAL LINK / ONLINE",Vector2(268,590),Vector2(340,27),12,CYAN)
	for i in model.enemies.size():
		var pos := enemy_position(i)
		var portrait_node := battle_portrait(model.enemies[i].battlePortraitAssetId,pos,Vector2(460,317))
		enemy_portraits.append(portrait_node)
	refresh_enemy_hud()
	message_label = label(self,"选取手牌，再点击敌方目标",Vector2(570,482),Vector2(290,62),17,CREAM)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pile_button(DRAW_POS,"抽牌堆",func(): show_pile("抽牌堆",model.draw_pile))
	pile_button(DISCARD_POS,"弃牌堆",func(): show_pile("弃牌堆",model.discard_pile))
	draw_count = label(self,"",DRAW_POS+Vector2(17,21),Vector2(75,55),35,CYAN)
	discard_count = label(self,"",DISCARD_POS+Vector2(0,21),Vector2(107,55),35,PINK)
	draw_count.position.x = DRAW_POS.x
	draw_count.size.x = 107
	draw_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discard_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_button = button(self,"结束回合  →",Vector2(1180,620),Vector2(216,56),end_turn_pressed,true)
	end_button.tooltip_text = "敌方执行头顶意图；未使用手牌弃置，再抽取新手牌。临时规则不限制出牌次数。"
	cyberware_button = button(self,"激活义体",Vector2(51,620),Vector2(250,56),show_cyberware)
	for state_name in ["normal","hover","pressed","focus"]:
		var purple_style := button_style(state_name,false)
		purple_style.border_color = Color("c895ff")
		if state_name != "focus": purple_style.bg_color = Color("482866") if state_name == "hover" else Color("251638")
		cyberware_button.add_theme_stylebox_override(state_name,purple_style)
	cyberware_status = label(self,"",Vector2(51,678),Vector2(310,28),15,Color("c895ff"))
	refresh_cyberware()
	label(self,"道具栏",Vector2(51,272),Vector2(130,30),14,MUTED)
	for i in 3:
		var slot := button(self,"＋",Vector2(51+i*61,312),Vector2(52,44),func(): use_item(""))
		slot.disabled = true
		slot.tooltip_text = "道具待配置"
	label(self,"暂无道具",Vector2(51,366),Vector2(180,26),13,MUTED)
	if Game.config.developmentMode:
		button(self,"调试结果",Vector2(1235,197),Vector2(156,42),show_debug_results).add_theme_font_size_override("font_size",15)
	button(self,"投降",Vector2(1270,492),Vector2(122,41),func(): finish("surrender")).add_theme_font_size_override("font_size",15)
	aim = Node2D.new()
	aim.set_script(preload("res://scripts/combat/targeting_line.gd"))
	aim.z_index = 35
	aim.visible = false
	add_child(aim)
	refresh_counts()
	set_busy(true)
	start_hand.call_deferred()

func battle_portrait(asset_id: String, pos: Vector2, dimensions: Vector2) -> TextureRect:
	var node := image_asset(self,asset_id,pos,dimensions,false)
	if node and Game.assets.get(asset_id,{}).get("whiteKey",false):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/white_key.gdshader")
		node.material = material
	return node

func enemy_position(index: int) -> Vector2:
	return Vector2(791 + index*180 - (model.enemies.size()-1)*100,229)

func refresh_enemy_hud() -> void:
	if is_instance_valid(enemy_hud):
		remove_child(enemy_hud)
		enemy_hud.queue_free()
	targets.clear()
	enemy_hud = Control.new()
	enemy_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(enemy_hud)
	for i in model.enemies.size():
		var enemy: Dictionary = model.enemies[i]
		var center := enemy_position(i) + Vector2(230,0)
		var intent_text := "攻击 %d" % int(enemy.intent.get("amount",0))
		if int(enemy.intent.get("hits",1)) > 1: intent_text += " ×%d" % int(enemy.intent.hits)
		cut_panel(enemy_hud,Vector2(center.x-98,181),Vector2(196,65),INK,PINK,13)
		label(enemy_hud,"↗",Vector2(center.x-83,184),Vector2(55,50),38,PINK)
		label(enemy_hud,intent_text,Vector2(center.x-28,185),Vector2(135,35),24)
		label(enemy_hud,"下回合意图",Vector2(center.x-28,218),Vector2(140,22),12,MUTED)
		label(enemy_hud,enemy.displayName,Vector2(center.x-126,553),Vector2(300,34),22)
		panel(enemy_hud,Vector2(center.x-125,585),Vector2(250,13),Color("331d33"),Color("594858"))
		rect(enemy_hud,Vector2(center.x-123,587),Vector2(246*float(enemy.hp)/enemy.maxHp,9),PINK)
		label(enemy_hud,"%d / %d" % [enemy.hp,enemy.maxHp],Vector2(center.x+92,551),Vector2(104,32),19,PINK)
		var target := Button.new()
		target.position = Vector2(center.x-151,259)
		target.size = Vector2(302,287)
		target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		target.pressed.connect(func(): play_selected(i))
		enemy_hud.add_child(target)
		targets.append(target)
		var clear := StyleBoxFlat.new()
		clear.bg_color = Color(0,0,0,0)
		clear.border_color = CYAN if not selected_uid.is_empty() else Color(0,0,0,0)
		clear.set_border_width_all(1)
		target.add_theme_stylebox_override("normal",clear)
		var hover := clear.duplicate()
		hover.bg_color = Color(0.95,0.2,0.5,0.06) if not selected_uid.is_empty() else Color(0.08,0.8,0.9,0.035)
		hover.border_color = PINK if not selected_uid.is_empty() else CYAN
		target.add_theme_stylebox_override("hover",hover)
		target.add_theme_stylebox_override("pressed",hover)
		target.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
		target.add_theme_stylebox_override("disabled",StyleBoxEmpty.new())
		target.disabled = enemy.hp <= 0
		target.tooltip_text = "攻击目标：" + enemy.displayName + "\n下次行动：" + intent_text
		if not selected_uid.is_empty():
			label(enemy_hud,"⌖  点击攻击",Vector2(center.x-87,455),Vector2(245,50),23,CYAN)

func pile_button(pos: Vector2, title: String, action: Callable) -> void:
	panel(self,pos+Vector2(10,-10),Vector2(107,127),Color("0d1728"),Color("335671"))
	panel(self,pos+Vector2(5,-5),Vector2(107,127),Color("0d1728"),Color("335671"))
	var pile := button(self,"",pos,Vector2(107,127),action)
	# Piles retain their upright card-stack silhouette in every input state.
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var upright := pile.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
		upright.skew = Vector2.ZERO
		upright.set_corner_radius_all(7)
		pile.add_theme_stylebox_override(state_name, upright)
	var title_label := label(self,title,pos+Vector2(0,83),Vector2(107,29),17)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func hand_position(index: int, count: int) -> Vector2:
	var spacing := minf(199,800.0/maxi(count,1))
	return Vector2(720-(count-1)*spacing/2.0-90+index*spacing,627)

func create_card(uid: String, index: int, count: int, animate: bool) -> CombatCard:
	var view := CombatCard.new()
	view.setup(uid,model.card(uid))
	view.home = hand_position(index,count)
	add_child(view)
	view.chosen.connect(begin_card_aim)
	view.position = view.home
	view.visible = not animate
	view.z_index = 10
	cards[uid] = view
	return view

func start_hand() -> void:
	while Game.transition_locked:
		await get_tree().process_frame
	if not model.outcome.is_empty():
		set_busy(false)
		finish(model.outcome)
		return
	var first_draw: bool = model.hand.is_empty() and model.turn == 1
	if first_draw:
		model.draw_cards()
		commit()
	await deal_hand(first_draw)
	refresh_counts()
	initialized = true
	set_busy(false)

func deal_hand(animate: bool) -> void:
	if model.hand.is_empty(): return
	var last_flight: Node2D
	var duration := maxf(timing("drawDuration",0.26),0.38)
	for i in model.hand.size():
		var view := create_card(model.hand[i],i,model.hand.size(),animate)
		if animate:
			var fx := preload("res://scripts/combat/draw_fx.gd").new()
			add_child(fx)
			fx.start(view,DRAW_POS+Vector2(53.5,63.5),duration,i*0.055)
			last_flight = fx
	if animate: await last_flight.landed

func _process(_delta: float) -> void:
	if not is_instance_valid(aim): return
	aim.visible = not selected_uid.is_empty() and not Game.battle_busy and not Game.transition_locked and not is_instance_valid(pile_overlay)
	if not aim.visible or not cards.has(selected_uid): return
	var view: CombatCard = cards[selected_uid]
	aim.set("origin", view.get_global_transform() * Vector2(90, 8))
	aim.set("tip", get_global_mouse_position())
	hovered_target = target_at_pointer()
	aim.set("locked", hovered_target >= 0)
	if hovered_target >= 0:
		aim.set("target_center", enemy_position(hovered_target) + Vector2(230,150))
		message_label.text = "锁定 · " + str(model.enemies[hovered_target].displayName) + ("\n松开释放攻击" if not held_card_uid.is_empty() else "\n点击释放攻击")
	else:
		message_label.text = "指向敌方目标\n右键 / Esc 取消"

func cancel_selection() -> void:
	held_card_uid = ""
	if selected_uid.is_empty(): return
	selected_uid = ""
	for uid in cards: cards[uid].set_selected(false)
	if is_instance_valid(aim): aim.visible = false
	message_label.text = "选取手牌，再点击敌方目标"
	refresh_enemy_hud()

func select_card(uid: String) -> void:
	if Game.transition_locked or Game.battle_busy or not initialized or is_instance_valid(pile_overlay): return
	if not cards.has(uid): return
	held_card_uid = ""
	selected_uid = "" if selected_uid == uid else uid
	for card_uid in cards: cards[card_uid].set_selected(card_uid == selected_uid)
	message_label.text = "选取手牌，再点击敌方目标" if selected_uid.is_empty() else "选择攻击目标  /  右键取消"
	refresh_enemy_hud()
	_process(0.0)

func begin_card_aim(uid: String) -> void:
	select_card(uid)
	if selected_uid == uid and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		held_card_uid = uid
	_process(0.0)

func target_at_pointer() -> int:
	for i in targets.size():
		if not targets[i].disabled and targets[i].get_global_rect().has_point(get_global_mouse_position()):
			return i
	return -1

func play_selected(target: int) -> void:
	if selected_uid.is_empty() or Game.transition_locked or Game.battle_busy or is_instance_valid(pile_overlay): return
	var uid := selected_uid
	var result := model.play_card(uid,target)
	if result.is_empty(): return
	set_busy(true)
	selected_uid = ""
	aim.visible = false
	commit()
	var card_view: CombatCard = cards[uid]
	cards.erase(uid)
	card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_view.card_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_view.set_selected(false)
	if card_view.hover_tween: card_view.hover_tween.kill()
	card_view.z_index = 40
	# Remove this card from the live hand immediately; the visual can finish later.
	arrange_hand()
	var hit_pos := enemy_position(target)+Vector2(230,150)
	var launch := create_tween().set_parallel(true)
	launch.tween_property(card_view,"position",hit_pos-Vector2(90,115),0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	launch.tween_property(card_view,"scale",Vector2(0.48,0.48),0.16)
	launch.tween_property(card_view,"rotation_degrees",12.0,0.16)
	await launch.finished
	refresh_enemy_hud()
	impact(hit_pos,"−%d" % result.damage,PINK)
	var burst := Node2D.new()
	burst.set_script(preload("res://scripts/combat/hit_fx.gd"))
	burst.position = hit_pos
	burst.z_index = 45
	add_child(burst)
	animate_discard(card_view)
	refresh_counts()
	message_label.text = "攻击命中 · 造成 %d 点伤害" % result.damage
	if not model.outcome.is_empty():
		await get_tree().create_timer(0.52).timeout
		set_busy(false)
		finish(model.outcome)
	else:
		# Impact numbers and discard travel never hold up the next selection.
		set_busy(false)

func arrange_hand() -> void:
	for i in model.hand.size():
		var view: CombatCard = cards[model.hand[i]]
		view.move_home(hand_position(i,model.hand.size()))

func animate_discard(view: CombatCard, delay: float = 0.0, turn_cleanup: bool = false) -> void:
	if view.hover_tween: view.hover_tween.kill()
	view.set_enabled(false)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.card_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fx := preload("res://scripts/combat/discard_fx.gd").new()
	add_child(fx)
	fx.start(view,DISCARD_POS+Vector2(53.5,63.5),0.32 if turn_cleanup else 0.40,delay,0.55 if turn_cleanup else 1.0)

func end_turn_pressed() -> void:
	if Game.transition_locked or Game.battle_busy or is_instance_valid(pile_overlay): return
	set_busy(true)
	selected_uid = ""
	aim.visible = false
	var result := model.end_turn()
	if result.is_empty():
		set_busy(false)
		return
	commit()
	turn_label.text = "敌方回合 / 执行意图"
	var discarded_views := cards.values()
	cards.clear()
	for i in discarded_views.size():
		animate_discard(discarded_views[i],i*0.045,true)
	if not discarded_views.is_empty():
		await get_tree().create_timer(0.33+(discarded_views.size()-1)*0.045).timeout
	for attack in result.attacks:
		await impact(Vector2(418,421),"−%d HP" % attack.damage,PINK)
	if not model.outcome.is_empty():
		set_busy(false)
		finish(model.outcome)
		return
	refresh_enemy_hud()
	turn_label.text = "回合 %02d  /  你的回合" % model.turn
	await deal_hand(true)
	refresh_counts()
	message_label.text = "你的回合 · 手牌已补充"
	set_busy(false)

func impact(pos: Vector2, text: String, color: Color) -> void:
	var occupied: Array[int] = []
	for popup in get_tree().get_nodes_in_group("combat_damage_numbers"):
		if popup.get_parent() == self and popup.anchor.distance_to(pos) < 10.0:
			occupied.append(int(round(popup.drift/72.0)))
	var lane := 0
	for candidate in [0,-1,1,-2,2]:
		if not occupied.has(candidate):
			lane = candidate
			break
	var floating := preload("res://scripts/combat/damage_number_fx.gd").new()
	add_child(floating)
	floating.start(text,button_font,color,pos,lane)
	# Preserve enemy-action pacing while the visual tail finishes independently.
	await get_tree().create_timer(timing("impactDuration",0.36)+0.1).timeout

func refresh_counts() -> void:
	draw_count.text = str(model.draw_pile.size())
	discard_count.text = str(model.discard_pile.size())

func set_busy(value: bool) -> void:
	Game.battle_busy = value
	if value: held_card_uid = ""
	if is_instance_valid(end_button): end_button.disabled = value
	if is_instance_valid(cyberware_button): cyberware_button.disabled = value
	for view in cards.values(): view.set_enabled(not value)

func commit() -> void:
	Game.commit_combat(model)
	expected_revision = Game.revision
	refresh_cyberware()

func refresh_cyberware() -> void:
	if not is_instance_valid(cyberware_status): return
	cyberware_button.text = "激活义体 · %d/%d" % [model.available_cyberware_count(),model.cyberware_cards().size()]
	cyberware_status.text = "下次攻击伤害 +%d" % model.next_attack_bonus if model.next_attack_bonus > 0 else "临时义体 / 点击查看"

func show_cyberware() -> void:
	if not initialized or Game.battle_busy or Game.transition_locked or is_instance_valid(pile_overlay): return
	cancel_selection()
	pile_overlay = preload("res://scripts/combat/cyberware_view.gd").new()
	pile_overlay.setup(model)
	pile_overlay.closed.connect(close_pile)
	pile_overlay.activation_requested.connect(activate_cyberware)
	add_child(pile_overlay)

func activate_cyberware(id: String) -> void:
	if not initialized or Game.battle_busy or Game.transition_locked or not is_instance_valid(pile_overlay): return
	if not pile_overlay.has_signal("activation_requested"): return
	if not model.activate_cyberware(id): return
	commit()
	pile_overlay.refresh()

func finish(result: String) -> void:
	if Game.transition_locked or Game.battle_busy or is_instance_valid(pile_overlay): return
	Game.battle_exit(result,Game.revision)

func use_item(item_id: String) -> void:
	if Game.battle_busy or Game.transition_locked: return
	var response := model.use_item(item_id,0,Game.state.inventory,Game.item_catalog)
	Game.notice.emit(response.reason)

func show_pile(title: String, contents: Array) -> void:
	if Game.battle_busy or Game.transition_locked or is_instance_valid(pile_overlay): return
	cancel_selection()
	pile_overlay = preload("res://scripts/combat/pile_view.gd").new()
	pile_overlay.setup(model, title, contents)
	pile_overlay.closed.connect(close_pile)
	add_child(pile_overlay)

func close_pile() -> void:
	if not is_instance_valid(pile_overlay): return
	var previous := pile_overlay
	pile_overlay = null
	remove_child(previous)
	previous.queue_free()
	end_button.grab_focus()

func show_debug_results() -> void:
	if Game.battle_busy or Game.transition_locked or is_instance_valid(pile_overlay): return
	cancel_selection()
	var popup := ConfirmationDialog.new()
	popup.title = "开发结果模拟"
	popup.dialog_text = "仅用于验证剧情返回；正常胜负由卡牌和生命判定。"
	popup.ok_button_text = "模拟胜利"
	popup.cancel_button_text = "关闭"
	popup.add_button("模拟失败",false,"lose")
	popup.confirmed.connect(func(): finish("win"))
	popup.custom_action.connect(func(action): popup.hide(); finish(action))
	add_child(popup)
	popup.popup_centered(Vector2i(610,185))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var released_uid := held_card_uid
		held_card_uid = ""
		if not released_uid.is_empty() and selected_uid == released_uid and not Game.battle_busy and not Game.transition_locked and not is_instance_valid(pile_overlay):
			var target := target_at_pointer()
			if target >= 0:
				get_viewport().set_input_as_handled()
				play_selected(target)
		return
	if selected_uid.is_empty() or Game.battle_busy or Game.transition_locked: return
	var right_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	var escape: bool = event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE
	if right_click or escape:
		cancel_selection()
		get_viewport().set_input_as_handled()

func timing(key: String, fallback: float) -> float:
	return maxf(0.01,float(model.profile.get("visuals",{}).get(key,fallback)))
