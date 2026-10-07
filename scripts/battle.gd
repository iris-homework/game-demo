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
var turn_label: Label
var turn_banner: Control
var draw_count: Label
var discard_count: Label
var shown_draw_count := 0
var shown_discard_count := 0
var end_button: Button
var cyberware_button: Button
var cyberware_status: Label
var pile_overlay: Control
var initialized := false
const ACTOR_OFFSET := Vector2(0,24)
const HAND_SCALE := 0.75
const PILE_SIZE := Vector2(58,72)
const DRAW_POS := Vector2(30,800)
const DISCARD_POS := Vector2(1352,800)

func _ready() -> void:
	enter({"battleId":Game.state.battleId,"eventId":Game.state.activeEventId})

func enter(params: Dictionary) -> void:
	battle = Game.battles[params.battleId]
	if Game.state.combat.is_empty(): Game.initialize_combat()
	model = CombatModel.new()
	model.restore(Game.state.combat)
	expected_revision = Game.revision
	var integrated_ground := battle_background()
	var arena := Node2D.new()
	arena.set_script(preload("res://scripts/combat/arena_fx.gd"))
	arena.paint_ground = not integrated_ground
	add_child(arena)
	if integrated_ground:
		# Let the illustrated road continue behind the hand, with a soft readability fade.
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color("090b1200"),Color("090b12bd")])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill_from = Vector2.ZERO
		texture.fill_to = Vector2(0,1)
		var shade := TextureRect.new()
		shade.texture = texture
		shade.position = Vector2(0,650)
		shade.size = Vector2(1440,250)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
	else:
		polygon(self,[Vector2(0,704),Vector2(1440,681),Vector2(1440,900),Vector2(0,900)],Color("090b12e5"))
		polygon(self,[Vector2(0,697),Vector2(238,692),Vector2(235,698),Vector2(0,704)],PINK)
	chrome("战斗",false)
	label(self,battle.name,Vector2(41,112),Vector2(700,55),33)
	label(self,"COMBAT // " + Game.place_data(battle.placeId).name,Vector2(43,166),Vector2(670,29),14,CYAN)
	tag("演练模式 · 不影响冒险" if Game.training_mode else "临时规则 / 攻击 1 · 敌方 HP 3",Vector2(1030,117),CYAN,360)
	if Game.texture(Game.place_data(battle.placeId).backgroundAssetId) == null:
		label(self,"场景美术待补",Vector2(43,203),Vector2(330,26),13,MUTED)
	cut_panel(self,Vector2(550,24),Vector2(340,48),INK,Color("3d9eff"),12)
	turn_label = label(self,"回合 %02d  /  你的回合" % model.turn,Vector2(566,29),Vector2(308,37),19,Color("8fcaff"))
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var n_asset: String = Game.characters.noren.get("battlePortraitAssetId", "")
	player_portrait = battle_portrait(n_asset,Vector2(90,215)+ACTOR_OFFSET,Vector2(630,335))
	label(self,Game.display_name("noren"),Vector2(305,552)+ACTOR_OFFSET,Vector2(280,33),23)
	label(self,"NEURAL LINK / ONLINE",Vector2(268,590)+ACTOR_OFFSET,Vector2(340,27),12,CYAN)
	for i in model.enemies.size():
		var pos := enemy_position(i)
		var portrait_node := battle_portrait(model.enemies[i].battlePortraitAssetId,pos,Vector2(460,317))
		enemy_portraits.append(portrait_node)
		if portrait_node: arena.contact_points.append(pos+Vector2(230,307))
	refresh_enemy_hud()
	pile_button(DRAW_POS,"抽牌堆",func(): show_pile("抽牌堆",model.draw_pile))
	pile_button(DISCARD_POS,"弃牌堆",func(): show_pile("弃牌堆",model.discard_pile))
	draw_count = label(self,"",DRAW_POS+Vector2(0,3),Vector2(PILE_SIZE.x,33),23,CYAN)
	discard_count = label(self,"",DISCARD_POS+Vector2(0,3),Vector2(PILE_SIZE.x,33),23,PINK)
	draw_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discard_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_button = button(self,"结束回合  →",Vector2(1240,719),Vector2(170,40),end_turn_pressed,true)
	end_button.add_theme_font_size_override("font_size",16)
	end_button.tooltip_text = "敌方执行头顶意图；未使用手牌弃置，再抽取新手牌。临时规则不限制出牌次数。"
	cyberware_button = button(self,"激活义体",Vector2(30,719),Vector2(170,40),show_cyberware)
	cyberware_button.add_theme_font_size_override("font_size",15)
	for state_name in ["normal","hover","pressed","focus"]:
		var purple_style := button_style(state_name,false)
		purple_style.border_color = Color("c895ff")
		if state_name != "focus": purple_style.bg_color = Color("482866") if state_name == "hover" else Color("251638")
		cyberware_button.add_theme_stylebox_override(state_name,purple_style)
	cyberware_status = label(self,"",Vector2(30,765),Vector2(170,24),11,Color("c895ff"))
	cyberware_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	refresh_cyberware()
	if Game.config.developmentMode:
		button(self,"调试结果",Vector2(1230,163),Vector2(160,36),show_debug_results).add_theme_font_size_override("font_size",15)
	button(self,"投降",Vector2(1230,211),Vector2(160,36),func(): finish("surrender")).add_theme_font_size_override("font_size",15)
	aim = Node2D.new()
	aim.set_script(preload("res://scripts/combat/targeting_line.gd"))
	aim.z_index = 35
	aim.visible = false
	add_child(aim)
	refresh_counts()
	set_busy(true)
	start_hand.call_deferred()

func battle_background() -> bool:
	var place_asset: String = Game.place_data(battle.placeId).backgroundAssetId
	var stage_asset: String = Game.assets.get(place_asset,{}).get("battleAssetId","")
	if stage_asset.is_empty() or Game.texture(stage_asset) == null:
		background(place_asset,0.15)
		return false
	rect(self,Vector2.ZERO,Vector2(1440,900),INK)
	image_asset(self,stage_asset,Vector2.ZERO,Vector2(1440,900),true)
	rect(self,Vector2.ZERO,Vector2(1440,900),Color(0.025,0.015,0.045,0.16))
	return true

func battle_portrait(asset_id: String, pos: Vector2, dimensions: Vector2) -> TextureRect:
	var node := image_asset(self,asset_id,pos,dimensions,false)
	if node and Game.assets.get(asset_id,{}).get("whiteKey",false):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/white_key.gdshader")
		if asset_id == "noren_battle":
			material.set_shader_parameter("ground_mask_enabled",true)
			material.set_shader_parameter("ground_mask",preload("res://assets/characters/noren_shadow_mask.png"))
		node.material = material
	return node

func enemy_position(index: int) -> Vector2:
	return Vector2(791 + index*180 - (model.enemies.size()-1)*100,229)+ACTOR_OFFSET

func refresh_enemy_hud() -> void:
	if is_instance_valid(enemy_hud):
		remove_child(enemy_hud)
		enemy_hud.queue_free()
	targets.clear()
	enemy_hud = Control.new()
	enemy_hud.position = ACTOR_OFFSET
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
	panel(self,pos+Vector2(8,-8),PILE_SIZE,Color("0d1728"),Color("335671"))
	panel(self,pos+Vector2(4,-4),PILE_SIZE,Color("0d1728"),Color("335671"))
	var pile := button(self,"",pos,PILE_SIZE,action)
	# Piles retain their upright card-stack silhouette in every input state.
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var upright := pile.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
		upright.skew = Vector2.ZERO
		upright.set_corner_radius_all(7)
		pile.add_theme_stylebox_override(state_name, upright)
	var title_label := label(self,title,pos+Vector2(0,42),Vector2(PILE_SIZE.x,23),12)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func hand_position(index: int, count: int) -> Vector2:
	var offset := index-(count-1)/2.0
	var spacing := minf(92.0,820.0/maxi(count-1,1))
	var normalized := offset/maxf((count-1)/2.0,1.0)
	return Vector2(720+offset*spacing-90,760+normalized*normalized*minf(24.0,(count-1)*3.0))

func hand_rotation(index: int, count: int) -> float:
	return deg_to_rad((index-(count-1)/2.0)/maxf((count-1)/2.0,1.0)*minf(14.0,(count-1)*2.4))

func hand_at_pointer() -> String:
	var pointer := get_global_mouse_position()
	var nearest := ""
	# Stable resting footprints prevent enlarged cards from stealing their neighbours.
	for uid in model.hand:
		if not cards.has(uid): continue
		var card: CombatCard = cards[uid]
		var local := (pointer-card.home-card.pivot_offset).rotated(-card.home_rotation)/card.home_scale+card.pivot_offset
		if Rect2(Vector2.ZERO,card.size).has_point(local):
			# Later cards are drawn above earlier cards in overlapping resting areas.
			nearest = uid
	if not nearest.is_empty(): return nearest
	# Keep the lifted preview selectable above the resting fan.
	for uid in model.hand:
		if not cards.has(uid): continue
		var card: CombatCard = cards[uid]
		if (card.hovered or card.selected) and Rect2(Vector2.ZERO,card.size).has_point(card.get_global_transform().affine_inverse()*pointer): return uid
	return ""

func update_hand_hover() -> void:
	var uid := ""
	if initialized and not Game.battle_busy and not Game.transition_locked and not is_instance_valid(pile_overlay):
		uid = held_card_uid if not held_card_uid.is_empty() else hand_at_pointer()
	for card_uid in cards: cards[card_uid].hover(card_uid == uid)

func create_card(uid: String, index: int, count: int, animate: bool) -> CombatCard:
	var view := CombatCard.new()
	view.managed_input = true
	view.home_scale = HAND_SCALE
	view.home_rotation = hand_rotation(index,count)
	view.home_z = 10+index
	view.setup(uid,model.card(uid))
	view.home = hand_position(index,count)
	add_child(view)
	view.chosen.connect(begin_card_aim)
	view.position = view.home
	view.visible = not animate
	view.z_index = view.home_z
	view.scale = Vector2.ONE*view.home_scale
	view.rotation = view.home_rotation
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
		await announce_turn("第%d回合" % model.turn)
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
			fx.departed.connect(on_card_drawn)
			fx.start(view,DRAW_POS+PILE_SIZE/2.0,duration,i*0.055)
			last_flight = fx
	if animate: await last_flight.landed

func _process(_delta: float) -> void:
	update_hand_hover()
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

func cancel_selection() -> void:
	held_card_uid = ""
	if selected_uid.is_empty(): return
	selected_uid = ""
	for uid in cards: cards[uid].set_selected(false)
	if is_instance_valid(aim): aim.visible = false
	refresh_enemy_hud()

func select_card(uid: String) -> void:
	if Game.transition_locked or Game.battle_busy or not initialized or is_instance_valid(pile_overlay): return
	if not cards.has(uid): return
	held_card_uid = ""
	selected_uid = "" if selected_uid == uid else uid
	for card_uid in cards: cards[card_uid].set_selected(card_uid == selected_uid)
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
		view.home_rotation = hand_rotation(i,model.hand.size())
		view.home_z = 10+i
		view.move_home(hand_position(i,model.hand.size()))

func animate_discard(view: CombatCard, delay: float = 0.0, turn_cleanup: bool = false) -> void:
	if view.hover_tween: view.hover_tween.kill()
	view.set_enabled(false)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.card_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fx := preload("res://scripts/combat/discard_fx.gd").new()
	add_child(fx)
	fx.landed.connect(on_card_discarded)
	fx.start(view,DISCARD_POS+PILE_SIZE/2.0,0.32 if turn_cleanup else 0.40,delay,0.55 if turn_cleanup else 1.0)

func end_turn_pressed() -> void:
	if not initialized or not model.outcome.is_empty() or Game.transition_locked or Game.battle_busy or is_instance_valid(pile_overlay): return
	set_busy(true)
	selected_uid = ""
	aim.visible = false
	turn_label.text = "敌方回合 / 执行意图"
	# Retire hand visuals while the banner plays; the model resolves only once below.
	var discarded_views := cards.values()
	cards.clear()
	for i in discarded_views.size():
		animate_discard(discarded_views[i],i*0.045,true)
	var discard_wait: SceneTreeTimer
	if not discarded_views.is_empty():
		discard_wait = get_tree().create_timer(0.33+(discarded_views.size()-1)*0.045)
	await announce_turn("敌方回合",true)
	if discard_wait != null and discard_wait.time_left > 0.0:
		await discard_wait.timeout
	var result := model.end_turn()
	if result.is_empty():
		set_busy(false)
		return
	commit()
	for attack in result.attacks:
		await impact(Vector2(418,421)+ACTOR_OFFSET,"−%d HP" % attack.damage,PINK)
	if not model.outcome.is_empty():
		set_busy(false)
		finish(model.outcome)
		return
	refresh_enemy_hud()
	turn_label.text = "回合 %02d  /  你的回合" % model.turn
	await announce_turn("第%d回合" % model.turn)
	await deal_hand(true)
	refresh_counts()
	set_busy(false)

func announce_turn(text: String, enemy: bool = false) -> void:
	var banner := preload("res://scripts/combat/turn_banner.gd").new()
	turn_banner = banner
	add_child(banner)
	await banner.play(text,button_font,enemy)
	remove_child(banner)
	banner.queue_free()
	turn_banner = null

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
	# Initialize/reset after a complete deal, never during an in-flight discard.
	shown_draw_count = model.draw_pile.size()
	shown_discard_count = model.discard_pile.size()
	render_counts()

func render_counts() -> void:
	draw_count.text = str(shown_draw_count)
	discard_count.text = str(shown_discard_count)

func on_card_drawn() -> void:
	# Model drawing is already committed. Mirror its recycling only when the
	# next visible card leaves an empty deck, including mid-deal recycling.
	if shown_draw_count == 0 and model.profile.get("recycleDiscardWhenEmpty",true):
		shown_draw_count = shown_discard_count
		shown_discard_count = 0
	shown_draw_count -= 1
	render_counts()

func on_card_discarded() -> void:
	# Each flight reports arrival once; overlapping attacks and turn cleanup
	# share this path without changing any model pile or saved state.
	shown_discard_count += 1
	render_counts()

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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if initialized and not Game.battle_busy and not Game.transition_locked and not is_instance_valid(pile_overlay):
			var uid := hand_at_pointer()
			if not uid.is_empty():
				get_viewport().set_input_as_handled()
				begin_card_aim(uid)
				return
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
