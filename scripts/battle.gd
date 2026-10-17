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
var enemy_plates: Array[Control] = []
var enemy_intents: Array[Control] = []
const ActorHUD = preload("res://scripts/combat/actor_hud.gd")
var player_plate: Control
var shown_player_block := 0
var shown_player_parry := 0
var presenting_enemy_turn := false
const ENEMY_INTENT_SIZE := Vector2(126,28)
var aim: Node2D
var hovered_target := -1
var preview_selection := ""
var player_portrait: Node2D
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
var resources_label: Label
var energy_panel: Panel
var energy_value: Label
var held_start := Vector2.ZERO
var held_card_moved := false
var held_confirmation := false
var exhaust_button: Button
var pile_overlay: Control
var initialized := false
var stage: Control
var shown_enemies: Array = []
var shown_player_hp := -1
var preview_attack_style := ""
const ACTOR_OFFSET := Vector2(0,24)
const ACTOR_SCALE := 0.85
# Additional placement belongs to the selected stage; fallback scenes retain the base.
var actor_offset := ACTOR_OFFSET
const HAND_SCALE := 0.75
const CENTER_DROP_RECT := Rect2(210,90,1020,620)
const CARD_DRAG_THRESHOLD := 12.0
const PILE_SIZE := Vector2(46,58)
const DRAW_POS := Vector2(30,814)
const DISCARD_POS := Vector2(1364,814)

func _ready() -> void:
	enter({"battleId":Game.state.battleId,"eventId":Game.state.activeEventId})

func enter(params: Dictionary) -> void:
	battle = Game.battles[params.battleId]
	if Game.state.combat.is_empty(): Game.initialize_combat()
	model = CombatModel.new()
	model.restore(Game.state.combat)
	expected_revision = Game.revision
	shown_enemies = model.enemies.duplicate(true)
	shown_player_hp = model.player_hp
	shown_player_block = model.block
	shown_player_parry = model.parry
	# Retain existing HUD offsets; only the world imagery is replaced.
	var place_asset: String = Game.place_data(battle.placeId).backgroundAssetId
	var stage_asset: String = Game.assets.get(place_asset,{}).get("battleAssetId","")
	var old_offset: Array = Game.assets.get(stage_asset,{}).get("actorOffset",[0,0])
	actor_offset = ACTOR_OFFSET+Vector2(old_offset[0],old_offset[1])
	rect(self,Vector2.ZERO,Vector2(1440,900),Color("07080c"))
	stage = preload("res://scripts/combat/test_stage.gd").new()
	add_child(stage)
	var enemy_visuals: Array[EnemyVisualResolver.Visual] = []
	for enemy in model.enemies:
		enemy_visuals.append(Game.enemy_combat_visual(enemy))
	stage.setup(533+actor_offset.y,enemy_visuals)
	chrome("战斗",false)
	label(self,battle.name,Vector2(41,112),Vector2(700,55),33)
	label(self,"COMBAT // " + Game.place_data(battle.placeId).name,Vector2(43,166),Vector2(670,29),14,CYAN)
	tag("演练模式 · 不影响冒险" if Game.training_mode else ("诺伦 / 形态与弹药" if model.is_noren() else "旧版测试规则"),Vector2(1030,117),CYAN,360)
	if Game.texture(Game.place_data(battle.placeId).backgroundAssetId) == null:
		label(self,"场景美术待补",Vector2(43,203),Vector2(330,26),13,MUTED)
	cut_panel(self,Vector2(596,14),Vector2(248,48),INK,Color("3d9eff"),12)
	turn_label = label(self,"回合 %02d  /  你的回合" % model.turn,Vector2(604,20),Vector2(232,36),18,Color("8fcaff"))
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_portrait = stage.player
	player_plate = ActorHUD.new()
	add_child(player_plate)
	resources_label = label(self,"",Vector2(220,620)+actor_offset,Vector2(220,25),14,CYAN)
	resources_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_energy_hud()
	exhaust_button = button(self,"消耗 0",Vector2(1240,770),Vector2(170,30),func(): show_pile("消耗 / 能力",model.exhaust_pile))
	exhaust_button.add_theme_font_size_override("font_size",13)
	exhaust_button.visible = model.is_noren()
	refresh_resources()
	stage.player.set_combat_stance(model.stance if model.is_noren() else "melee")
	for i in model.enemies.size():
		var actor: Node2D = stage.enemies[i]
		actor.alive = model.enemies[i].hp > 0
		actor.visible = actor.alive
		enemy_portraits.append(actor)
	refresh_enemy_hud()
	RenderingServer.frame_pre_draw.connect(update_target_rects)
	pile_button(DRAW_POS,"抽牌堆",func(): show_pile("抽牌堆",model.draw_pile))
	pile_button(DISCARD_POS,"弃牌堆",func(): show_pile("弃牌堆",model.discard_pile))
	draw_count = label(self,"",DRAW_POS+Vector2(0,3),Vector2(PILE_SIZE.x,27),19,CYAN)
	discard_count = label(self,"",DISCARD_POS+Vector2(0,3),Vector2(PILE_SIZE.x,27),19,PINK)
	draw_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discard_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_button = button(self,"结束回合  →",Vector2(1240,719),Vector2(170,40),end_turn_pressed,true)
	end_button.add_theme_font_size_override("font_size",16)
	end_button.tooltip_text = "敌方执行头顶意图；未使用手牌弃置，再抽取新手牌。每回合恢复 3 能量、抽 5 张牌。"
	cyberware_button = button(self,"激活科技",Vector2(30,637),Vector2(170,40),show_cyberware)
	cyberware_button.add_theme_font_size_override("font_size",15)
	for state_name in ["normal","hover","pressed","focus"]:
		var purple_style := button_style(state_name,false)
		purple_style.border_color = Color("c895ff")
		if state_name != "focus": purple_style.bg_color = Color("482866") if state_name == "hover" else Color("251638")
		cyberware_button.add_theme_stylebox_override(state_name,purple_style)
	cyberware_status = label(self,"",Vector2(30,683),Vector2(170,24),11,Color("c895ff"))
	cyberware_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	refresh_cyberware()
	if Game.config.developmentMode:
		button(self,"调试结果",Vector2(1230,163),Vector2(160,36),show_debug_results).add_theme_font_size_override("font_size",15)
	aim = Node2D.new()
	aim.set_script(preload("res://scripts/combat/targeting_line.gd"))
	aim.z_index = 35
	aim.visible = false
	add_child(aim)
	refresh_counts()
	set_busy(true)
	start_hand.call_deferred()

func battle_background() -> bool:
	actor_offset = ACTOR_OFFSET
	var place_asset: String = Game.place_data(battle.placeId).backgroundAssetId
	var stage_asset: String = Game.assets.get(place_asset,{}).get("battleAssetId","")
	if stage_asset.is_empty() or Game.texture(stage_asset) == null:
		background(place_asset,0.15)
		return false
	var stage_offset: Array = Game.assets[stage_asset].get("actorOffset", [0,0])
	actor_offset += Vector2(stage_offset[0],stage_offset[1])
	rect(self,Vector2.ZERO,Vector2(1440,900),INK)
	image_asset(self,stage_asset,Vector2.ZERO,Vector2(1440,900),true)
	rect(self,Vector2.ZERO,Vector2(1440,900),Color(0.025,0.015,0.045,0.16))
	return true

func battle_portrait(asset_id: String, pos: Vector2, dimensions: Vector2, foot_anchor: Vector2) -> TextureRect:
	var node := image_asset(self,asset_id,pos,dimensions,false)
	if node:
		# Scale around the soles so stage placement stays grounded.
		node.pivot_offset = foot_anchor
		node.scale = Vector2.ONE * ACTOR_SCALE
	if node and Game.assets.get(asset_id,{}).get("whiteKey",false):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/white_key.gdshader")
		if asset_id == "noren_battle":
			material.set_shader_parameter("ground_mask_enabled",true)
			material.set_shader_parameter("ground_mask",preload("res://assets/characters/noren_shadow_mask.png"))
		node.material = material
	return node

func enemy_position(index: int) -> Vector2:
	return Vector2(791 + index*180 - (model.enemies.size()-1)*100,229)+actor_offset

func refresh_enemy_hud() -> void:
	if is_instance_valid(enemy_hud):
		remove_child(enemy_hud)
		enemy_hud.queue_free()
	targets.clear()
	enemy_plates.clear()
	enemy_intents.clear()
	enemy_hud = Control.new()
	enemy_hud.position = Vector2(0,actor_offset.y)
	enemy_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(enemy_hud)
	for i in model.enemies.size():
		var enemy: Dictionary = shown_enemies[i]
		var intent_text := model.enemy_intent_text(enemy)
		var plate := ActorHUD.new()
		enemy_hud.add_child(plate)
		enemy_plates.append(plate)
		plate.update_values(int(enemy.hp),int(enemy.maxHp),int(enemy.get("block",0)),enemy_statuses(enemy))
		var intent := Control.new()
		intent.size = ENEMY_INTENT_SIZE
		intent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		enemy_hud.add_child(intent)
		enemy_intents.append(intent)
		panel(intent,Vector2.ZERO,ENEMY_INTENT_SIZE,Color(0.025,0.035,0.055,0.94),Color("734457"))
		var intent_label := label(intent,"%02d  ↗ %s" % [i+1,intent_text],Vector2(5,2),Vector2(116,24),14,Color("ff9bbd"))
		intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		intent_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		var target := Button.new()
		target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		target.pressed.connect(func():
			var front := target_at_pointer()
			if front >= 0: play_selected(front)
		)
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
	# Status icons receive hover before the transparent target buttons.
	for plate in enemy_plates: enemy_hud.move_child(plate,-1)
	update_target_rects()

func pile_button(pos: Vector2, title: String, action: Callable) -> void:
	panel(self,pos+Vector2(6,-6),PILE_SIZE,Color("0d1728"),Color("335671"))
	panel(self,pos+Vector2(3,-3),PILE_SIZE,Color("0d1728"),Color("335671"))
	var pile := button(self,"",pos,PILE_SIZE,action)
	pile.set("corner_marks",false)
	# Piles retain their upright card-stack silhouette in every input state.
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var upright := pile.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
		upright.skew = Vector2.ZERO
		upright.set_corner_radius_all(5)
		pile.add_theme_stylebox_override(state_name, upright)
	var title_label := label(self,title,pos+Vector2(0,32),Vector2(PILE_SIZE.x,20),11)
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
	# The centered attack is visually above the fan, so its visible face wins hits too.
	if cards.has(selected_uid):
		var selected: CombatCard = cards[selected_uid]
		if selected.center_on_selection and Rect2(Vector2.ZERO,selected.size).has_point(selected.get_global_transform().affine_inverse()*pointer): return selected_uid
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
		# A following card sits under the pointer and must not swallow target clicks.
		if not card.dragging and (card.hovered or card.selected) and Rect2(Vector2.ZERO,card.size).has_point(card.get_global_transform().affine_inverse()*pointer): return uid
	return ""

func update_hand_hover() -> void:
	var uid := ""
	if initialized and not Game.battle_busy and not Game.transition_locked and not is_instance_valid(pile_overlay):
		uid = selected_uid if non_attack_selected() else (held_card_uid if not held_card_uid.is_empty() else hand_at_pointer())
	for card_uid in cards: cards[card_uid].hover(card_uid == uid)

func create_card(uid: String, index: int, count: int, animate: bool) -> CombatCard:
	var view := CombatCard.new()
	view.managed_input = true
	view.home_scale = HAND_SCALE
	view.home_rotation = hand_rotation(index,count)
	view.home_z = 10+index
	view.lifted_z = maxi(30,10+count)
	view.selection_home = hand_position(0,1)+Vector2(0,36) # Enlarged attack ends about 10 pixels above the viewport bottom.
	view.center_on_selection = model.card(uid).get("type","attack") == "attack"
	view.setup(uid,model.card(uid))
	view.home = hand_position(index,count)
	add_child(view)
	view.show_preview(model.card_preview(uid))
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
	var first_draw: bool = not model.opening_draw_done
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
		if cards.has(model.hand[i]): continue
		var view := create_card(model.hand[i],i,model.hand.size(),animate)
		if animate:
			var fx := preload("res://scripts/combat/draw_fx.gd").new()
			add_child(fx)
			fx.departed.connect(on_card_drawn)
			fx.start(view,DRAW_POS+PILE_SIZE/2.0,duration,i*0.055)
			last_flight = fx
	if animate and is_instance_valid(last_flight): await last_flight.landed

func _process(_delta: float) -> void:
	update_hand_hover()
	update_center_drag()
	update_target_rects()
	if not is_instance_valid(aim): return
	aim.visible = not selected_uid.is_empty() and model.card_target(selected_uid) == "enemy" and not Game.battle_busy and not Game.transition_locked and not is_instance_valid(pile_overlay)
	var next_target := target_at_pointer() if aim.visible else -1
	if next_target != hovered_target or preview_selection != selected_uid:
		hovered_target = next_target
		preview_selection = selected_uid
		refresh_card_previews()
	if not aim.visible or not cards.has(selected_uid): return
	var view: CombatCard = cards[selected_uid]
	aim.set("origin", view.get_global_transform() * Vector2(90, 8))
	aim.set("tip", get_global_mouse_position())
	aim.set("locked", hovered_target >= 0)
	if hovered_target >= 0:
		aim.set("target_center", stage.contact(stage.enemies[hovered_target]))

func clear_card_hold() -> void:
	held_card_uid = ""
	held_card_moved = false
	held_confirmation = false

func clear_card_drag() -> void:
	clear_card_hold()
	for view in cards.values(): view.stop_drag()

func update_center_drag() -> void:
	if selected_uid.is_empty() or not cards.has(selected_uid): return
	if Game.battle_busy or Game.transition_locked or is_instance_valid(pile_overlay):
		clear_card_drag()
		return
	var pointer := get_global_mouse_position()
	if not held_card_uid.is_empty() and pointer.distance_to(held_start) >= CARD_DRAG_THRESHOLD:
		held_card_moved = true
	var view: CombatCard = cards[selected_uid]
	if not view.center_on_selection: view.drag_to(pointer)

func non_attack_selected() -> bool:
	return cards.has(selected_uid) and not cards[selected_uid].center_on_selection

func release_area_contains(uid: String, point: Vector2) -> bool:
	if cards.has(uid) and not cards[uid].center_on_selection:
		return get_global_rect().has_point(point)
	return CENTER_DROP_RECT.has_point(point)

func cancel_selection() -> void:
	clear_card_drag()
	if selected_uid.is_empty(): return
	selected_uid = ""
	for uid in cards: cards[uid].set_selected(false)
	if is_instance_valid(aim): aim.visible = false
	refresh_enemy_hud()

func select_card(uid: String, toggle: bool = true) -> void:
	if Game.transition_locked or Game.battle_busy or not initialized or is_instance_valid(pile_overlay): return
	if not cards.has(uid): return
	clear_card_drag()
	var reason := model.play_error(uid)
	if not reason.is_empty():
		Game.notice.emit(reason)
		return
	selected_uid = "" if toggle and selected_uid == uid else uid
	for card_uid in cards: cards[card_uid].set_selected(card_uid == selected_uid)
	refresh_enemy_hud()
	_process(0.0)

func begin_card_aim(uid: String) -> void:
	# A cancelled skill choice can leave selection active; grabbing it again re-arms the drag.
	select_card(uid, model.card_target(uid) == "enemy")
	held_start = get_global_mouse_position()
	if selected_uid == uid and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		held_card_uid = uid
	_process(0.0)

func target_at_pointer() -> int:
	return target_at_point(get_global_mouse_position())

func target_at_point(point: Vector2) -> int:
	var result := -1
	var front_y := -INF
	for i in targets.size():
		if not targets[i].disabled and targets[i].get_global_rect().has_point(point):
			var foot_y: float = stage.enemies[i].position.y
			if foot_y >= front_y:
				front_y = foot_y
				result = i
	return result

func play_selected(target: int, discard_uid: String = "", extra_ammo: int = -1) -> void:
	if selected_uid.is_empty() or Game.transition_locked or Game.battle_busy or is_instance_valid(pile_overlay): return
	var uid := selected_uid
	var error := model.play_error(uid)
	if not error.is_empty():
		Game.notice.emit(error)
		return
	for effect in model.card(uid).get("effects", []):
		if effect.type == "discard_attack" and discard_uid.is_empty():
			var options: Array = []
			for candidate in model.discard_candidates(uid):
				options.append({"value":candidate,"text":"%s · 费用 %d\n%s" % [model.card(candidate).name,model.card_cost(candidate),model.card_preview(candidate).text]})
			show_card_choice("选择弃置一张攻击牌",options,func(value): play_selected(target,value,extra_ammo))
			return
	if extra_ammo < 0 and model.extra_ammo_limit(uid) > 0:
		var options: Array = []
		for count in model.extra_ammo_limit(uid) + 1:
			options.append({"value":count,"text":"额外消耗 %d 颗弹药\n%s" % [count,model.card_preview(uid,target,count).text.replace("\n"," ")]})
		show_card_choice("选择额外耗弹数量（通常耗弹 1 颗）",options,func(value): play_selected(target,discard_uid,value))
		return
	var played_preview := model.card_preview(uid,target,maxi(0,extra_ammo))
	var played_cost := model.card_cost(uid)
	var result := model.play_card(uid,target,discard_uid,maxi(0,extra_ammo))
	if result.is_empty(): return
	if cards.has(uid):
		cards[uid].show_preview(played_preview)
		cards[uid].show_cost(played_cost)
	set_busy(true)
	selected_uid = ""
	aim.visible = false
	commit()
	var retired: Array = [uid]
	retired.append_array(result.get("discarded", []))
	var retired_views: Array = []
	for removed_uid in retired:
		if not cards.has(removed_uid): continue
		var retired_view: CombatCard = cards[removed_uid]
		cards.erase(removed_uid)
		retired_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		retired_view.card_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		retired_view.set_selected(false)
		if retired_view.hover_tween: retired_view.hover_tween.kill()
		retired_view.z_index = 40
		retired_views.append(retired_view)
	arrange_hand()
	for retired_view in retired_views:
		if retired_view.uid == uid and result.get("exhausted",false): animate_exhaust(retired_view)
		else: animate_discard(retired_view)
	var style: String = model.card(uid).get("animation","slash")
	if result.get("stance", "melee") == "ranged": style = "shoot"
	elif Game.training_mode and not preview_attack_style.is_empty(): style = preview_attack_style
	stage.player.set_combat_stance(result.get("stance", "melee"))
	for index in model.enemies.size():
		var target_hits: Array = result.hits.filter(func(hit): return int(hit.get("target",target)) == index)
		if target_hits.is_empty(): continue
		await stage.attack(stage.player,stage.enemies[index],style,target_hits,func(hit: Dictionary, _index: int):
			shown_enemies[index].hp = hit.hpAfter
			shown_enemies[index].block = hit.get("blockAfter",0)
			shown_enemies[index].bleed = hit.get("bleedAfter",0)
			refresh_enemy_hud()
			var text := "−%d" % hit.damage
			if int(hit.get("bleedDamage",0)) > 0: text += " (裂伤 %d)" % hit.bleedDamage
			impact(stage.contact(stage.enemies[index]),text,PINK)
		)
	shown_enemies = model.enemies.duplicate(true)
	refresh_enemy_hud()
	# Discard flight already runs in parallel; only attack playback precedes the shift.
	await stage.player.transition_combat_stance(model.stance if model.is_noren() else "melee")
	for retired_view in retired_views:
		while is_instance_valid(retired_view) and retired_view.visible: await get_tree().process_frame
	await deal_hand(true)
	arrange_hand()
	refresh_counts()
	refresh_resources()
	set_busy(false)
	if not model.outcome.is_empty(): finish(model.outcome)

func show_card_choice(title: String, options: Array, callback: Callable) -> void:
	clear_card_drag()
	pile_overlay = preload("res://scripts/combat/choice_picker.gd").new()
	pile_overlay.heading = title
	pile_overlay.options = options
	pile_overlay.closed.connect(close_pile)
	pile_overlay.picked.connect(func(value):
		close_pile()
		callback.call(value))
	add_child(pile_overlay)

func animate_exhaust(view: CombatCard) -> void:
	view.set_enabled(false)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(view,"position",Vector2(1180,690),0.35)
	tween.tween_property(view,"scale",Vector2.ONE*0.25,0.35)
	tween.tween_property(view,"modulate:a",0.0,0.4)
	await tween.finished
	view.hide()
	view.queue_free()

func arrange_hand() -> void:
	for i in model.hand.size():
		if not cards.has(model.hand[i]): continue
		var view: CombatCard = cards[model.hand[i]]
		view.home_rotation = hand_rotation(i,model.hand.size())
		view.home_z = 10+i
		view.lifted_z = maxi(30,10+model.hand.size())
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
	await stage.wide()
	await announce_turn("敌方回合",true)
	if discard_wait != null and discard_wait.time_left > 0.0:
		await discard_wait.timeout
	presenting_enemy_turn = true
	var result := model.end_turn()
	if result.is_empty():
		presenting_enemy_turn = false
		set_busy(false)
		return
	commit()
	for attack in result.attacks:
		var attacker_index := -1
		for i in model.enemies.size():
			if model.enemies[i].id == attack.id: attacker_index = i
		if attacker_index < 0: continue
		shown_enemies[attacker_index].block = 0
		refresh_enemy_hud()
		var style: String = shown_enemies[attacker_index].intent.get("animation","pierce")
		await stage.attack(stage.enemies[attacker_index],stage.player,style,attack.hits,func(hit: Dictionary, _index: int):
			shown_player_hp = int(hit.hpAfter)
			shown_player_block = maxi(0,shown_player_block-int(hit.get("blocked",0)))
			refresh_player_plate()
			refresh_hp()
			impact(stage.contact(stage.player),"−%d HP" % hit.damage if hit.damage > 0 else "格挡",PINK)
		)
		if not attack.get("counters",[]).is_empty() and stage.player.alive:
			await stage.attack(stage.player,stage.enemies[attacker_index],"slash",attack.counters,func(hit: Dictionary, _index: int):
				shown_enemies[attacker_index].hp = hit.hpAfter
				shown_enemies[attacker_index].block = hit.get("blockAfter",0)
				shown_enemies[attacker_index].bleed = hit.bleedAfter
				refresh_enemy_hud()
				impact(stage.contact(stage.enemies[attacker_index]),"弹反 −%d" % hit.damage,CYAN)
			)
		shown_player_parry = maxi(0,shown_player_parry-1)
		refresh_player_plate()
	if not model.outcome.is_empty():
		presenting_enemy_turn = false
		set_busy(false)
		finish(model.outcome)
		return
	await stage.return_home()
	presenting_enemy_turn = false
	refresh_resources()
	stage.player.set_combat_stance(model.stance if model.is_noren() else "melee")
	shown_enemies = model.enemies.duplicate(true)
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
	if value: clear_card_drag()
	if is_instance_valid(end_button): end_button.disabled = value
	if is_instance_valid(exhaust_button): exhaust_button.disabled = value
	if is_instance_valid(cyberware_button): cyberware_button.disabled = value
	for view in cards.values():
		view.set_enabled(not value)
	refresh_card_previews()
	refresh_resources()

func refresh_card_previews() -> void:
	for uid in cards:
		# A resolving card keeps the numbers of this play during its exit animation.
		if not uid in model.hand: continue
		cards[uid].show_cost(model.card_cost(uid))
		cards[uid].show_preview(model.card_preview(uid, hovered_target if uid == selected_uid else -1))

func commit() -> void:
	Game.commit_combat(model)
	expected_revision = Game.revision
	refresh_cyberware()
	refresh_card_previews()
	refresh_resources()

func refresh_cyberware() -> void:
	if not is_instance_valid(cyberware_status): return
	cyberware_button.text = "激活科技 · %d/%d" % [model.available_cyberware_count(),model.cyberware_cards().size()]
	cyberware_status.text = "下次攻击伤害 +%d" % model.next_attack_bonus if model.next_attack_bonus > 0 else "临时科技 / 点击查看"

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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F5,KEY_F6,KEY_F7]:
		if Game.training_mode and Game.config.developmentMode:
			if event.keycode == KEY_F5:
				if not Game.battle_busy and not Game.transition_locked and not is_instance_valid(pile_overlay):
					preview_attack_style = "pierce" if preview_attack_style != "pierce" else "slash"
					Game.notice.emit("演练攻击动作："+("突刺" if preview_attack_style == "pierce" else "挥砍"))
			else:
				preview_defense(event.keycode == KEY_F7)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if initialized and not Game.battle_busy and not Game.transition_locked and not is_instance_valid(pile_overlay):
			# A selected non-attack owns the next click, including clicks over buttons or cards.
			if non_attack_selected():
				held_card_uid = selected_uid
				held_start = get_global_mouse_position()
				held_card_moved = false
				held_confirmation = true
				get_viewport().set_input_as_handled()
				return
			var uid := hand_at_pointer()
			if not uid.is_empty():
				get_viewport().set_input_as_handled()
				begin_card_aim(uid)
				if selected_uid == uid: held_card_uid = uid
				return
			if not selected_uid.is_empty():
				var target_type := model.card_target(selected_uid)
				var valid_target := target_at_pointer() >= 0 if target_type == "enemy" else CENTER_DROP_RECT.has_point(get_global_mouse_position())
				if valid_target:
					held_card_uid = selected_uid
					held_start = get_global_mouse_position()
					held_card_moved = false
					held_confirmation = true
					get_viewport().set_input_as_handled()
					return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var released_uid := held_card_uid
		# Resolve the final pointer position even if press, motion and release share a frame.
		update_center_drag()
		var should_release := held_card_moved or held_confirmation
		clear_card_hold()
		if not released_uid.is_empty() and selected_uid == released_uid and not Game.battle_busy and not Game.transition_locked and not is_instance_valid(pile_overlay):
			if non_attack_selected(): get_viewport().set_input_as_handled()
			if model.card_target(released_uid) in ["self","all"]:
				get_viewport().set_input_as_handled()
				if should_release:
					if release_area_contains(released_uid,get_global_mouse_position()): play_selected(-1)
					elif not non_attack_selected(): cancel_selection()
			else:
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

func update_target_rects() -> void:
	if not is_instance_valid(stage) or not is_instance_valid(enemy_hud): return
	for i in targets.size():
		var area: Rect2 = stage.target_rect(i)
		targets[i].position = area.position-enemy_hud.global_position
		targets[i].size = area.size
	update_enemy_plates()

func anchor_plate(plate: Control, actor: Node2D) -> void:
	var foot := actor.to_global(Vector2.ZERO)
	plate.global_position = Vector2(clampf(foot.x-ActorHUD.WIDTH/2,24,1416-ActorHUD.WIDTH),foot.y+12)
	plate.visible = actor.visible and actor.modulate.a > 0.01 and stage.get_global_rect().has_point(foot)
	plate.modulate.a = actor.modulate.a

func update_enemy_plates() -> void:
	anchor_plate(player_plate,stage.player)
	for i in enemy_plates.size():
		var actor: Node2D = stage.enemies[i]
		anchor_plate(enemy_plates[i],actor)
		var intent := enemy_intents[i]
		intent.visible = actor.visible and actor.alive and actor.modulate.a > 0.01
		intent.modulate.a = actor.modulate.a
		var head := actor.to_global(Vector2(0,-130))
		intent.global_position = Vector2(clampf(head.x-ENEMY_INTENT_SIZE.x*0.5,16,1424-ENEMY_INTENT_SIZE.x),clampf(head.y-ENEMY_INTENT_SIZE.y-8,206,674))
	# At melee distance, separate intersecting strips while retaining their foot anchors.
	var plates: Array = [player_plate]+enemy_plates
	for pass_index in 3:
		for a in plates.size():
			for b in range(a+1,plates.size()):
				var first: Control = plates[a]
				var second: Control = plates[b]
				if not first.visible or not second.visible: continue
				if not first.get_global_rect().grow(6).intersects(second.get_global_rect()): continue
				var left: Control = first if first.position.x < second.position.x else second
				var right: Control = second if left == first else first
				var overlap := left.global_position.x+ActorHUD.WIDTH+20-right.global_position.x
				left.global_position.x = maxf(24,left.global_position.x-overlap/2)
				right.global_position.x = minf(1416-ActorHUD.WIDTH,right.global_position.x+overlap/2)
	resources_label.global_position = player_plate.global_position+Vector2(-12,player_plate.size.y+2)
	resources_label.visible = player_plate.visible
	resources_label.modulate.a = player_plate.modulate.a

func enemy_statuses(enemy: Dictionary) -> Array:
	return model.buffs.enemy_badges(enemy)

func refresh_player_plate() -> void:
	if not is_instance_valid(player_plate): return
	player_plate.update_values(shown_player_hp,model.max_hp,shown_player_block,model.buffs.player_badges(model,shown_player_parry))

func refresh_hp() -> void:
	if shown_player_hp < 0:
		super.refresh_hp()
		return
	if not is_instance_valid(hp_fill): return
	hp_fill.size.x = hp_bar_width*shown_player_hp/maxi(model.max_hp,1)
	hp_label.text = "%d / %d" % [shown_player_hp,model.max_hp]

func preview_defense(partial: bool) -> void:
	if not initialized or Game.battle_busy or Game.transition_locked or is_instance_valid(pile_overlay): return
	if not Game.training_mode or not Game.config.developmentMode: return
	var index := -1
	for i in stage.enemies.size():
		if stage.enemies[i].alive:
			index = i
			break
	if index < 0: return
	cancel_selection()
	set_busy(true)
	Game.notice.emit("动作预览：部分格挡后受击（不结算）" if partial else "动作预览：完全格挡（不结算）")
	await stage.attack(stage.enemies[index],stage.player,"slash",[{"damage":1 if partial else 0,"blocked":1}],func(_hit, _i): pass)
	await stage.return_home()
	set_busy(false)

func build_energy_hud() -> void:
	energy_panel = panel(self,Vector2(30,719),Vector2(170,56),Color("0b1b23"),Color("28565f"))
	label(energy_panel,"能量",Vector2(12,12),Vector2(60,32),17,CYAN)
	energy_value = label(energy_panel,"",Vector2(72,8),Vector2(86,40),25,CREAM)
	energy_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func refresh_resources() -> void:
	if not presenting_enemy_turn:
		shown_player_block = model.block
		shown_player_parry = model.parry
	refresh_player_plate()
	if not is_instance_valid(resources_label): return
	if is_instance_valid(energy_panel):
		energy_panel.visible = model.is_noren()
		var per_turn := maxi(1,int(model.profile.get("energyPerTurn",3)))
		energy_value.text = "%d / %d" % [model.energy,per_turn]
	if not model.is_noren():
		resources_label.text = "旧版战斗快照"
		return
	resources_label.text = "%s  ·  弹药 %d / 6" % ["近战" if model.stance == "melee" else "远程",model.ammo]
	if is_instance_valid(exhaust_button): exhaust_button.text = "消耗 / 能力 %d" % model.exhaust_pile.size()
