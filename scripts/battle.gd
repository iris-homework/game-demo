extends DemoUI
## Presentation only. CombatModel owns rules; Game owns persistence and story returns.
signal card_aim_started(uid: String)
signal card_aim_cancelled
signal card_played(uid: String)
signal resource_denied
signal pile_inspected(title: String)
var tutorial_guide: Control
var model: CombatModel
var battle: Dictionary
var expected_revision: int
var selected_uid := ""
var held_card_uid := ""
var held_shortcut_keys: Dictionary = {}
var cards: Dictionary = {}
var enemy_hud: Control
var targets: Array[Button] = []
var enemy_plates: Array[Control] = []
var enemy_intents: Array[Control] = []
var enemy_summary_plates: Array[Control] = []
const ActorHUD = preload("res://scripts/combat/actor_hud.gd")
const EnemyHPSummary = preload("res://scripts/combat/enemy_hp_summary.gd")
const EnemyIntent = preload("res://scripts/combat/enemy_intent.gd")
const EnergyHUD = preload("res://scripts/combat/energy_hud.gd")
const AmmoHUD = preload("res://scripts/combat/ammo_hud.gd")
var player_plate: Control
var player_hover: Control
var shown_player_ammo := 0
var shown_player_block := 0
var shown_player_parry := 0
var shown_player_pollution := 0
var shown_player_weak := 0
var shown_player_buffs: Dictionary = {}
var presenting_enemy_turn := false
var presenting_player_attack := false
var presenting_player_hits := false
const ENEMY_INTENT_SIZE := EnemyIntent.DIMENSIONS
var aim: Node2D
var hovered_target := -1
var preview_selection := ""
var player_portrait: Node2D
var enemy_portraits: Array = []
var turn_label: Label
var turn_hud: Control
var turn_banner: Control
var resource_feedback: Control
var draw_count: Label
var discard_count: Label
var shown_draw_count := 0
var shown_discard_count := 0
var pending_recycles: Dictionary = {}
var shuffle_fx: Node2D
var end_button: Button
var cyberware_button: Button
var resources_label: Label
var ammo_panel: Control
var energy_panel: Panel
var energy_value: Label
var held_start := Vector2.ZERO
var held_card_moved := false
var held_confirmation := false
var exhaust_button: Button
var pile_overlay: Control
var choice_hidden_cards: Array[CombatCard] = []
var initialized := false
var pending_battle_result := ""
var stage: Control
var shown_enemies: Array = []
var shown_encounter_phase := 1
var dancer_darkness: ColorRect
var dancer_blackout: ColorRect
var dancer_reveal_flash: ColorRect
var shown_player_hp := -1
var preview_attack_style := ""
# Visual variation must not consume the global RNG used by deck shuffling.
var melee_animation_rng := RandomNumberGenerator.new()
const ACTOR_OFFSET := Vector2(0,24)
const ACTOR_SCALE := 0.85
# Additional placement belongs to the selected stage; fallback scenes retain the base.
var actor_offset := ACTOR_OFFSET
const HAND_SCALE := 1.056
const HAND_BASE_Y := 748.0
const HAND_SAFE_WIDTH := 1020.0 # Between the side controls, x=210..1230.
const HAND_EDGE_PADDING := 8.0
const CENTER_DROP_RECT := Rect2(210,90,1020,620)
const CARD_DRAG_THRESHOLD := 12.0
const PILE_SIZE := Vector2(46,58)
const DRAW_POS := Vector2(30,814)
const DISCARD_POS := Vector2(1364,814)

func _ready() -> void:
	melee_animation_rng.randomize()
	enter({"battleId":Game.state.battleId,"eventId":Game.state.activeEventId})

func enter(params: Dictionary) -> void:
	battle = Game.battles[params.battleId]
	if Game.state.combat.is_empty(): Game.initialize_combat()
	model = CombatModel.new()
	model.restore(Game.state.combat)
	model.discard_recycled.connect(func(amount: int, next_uid: String): pending_recycles[next_uid] = amount)
	expected_revision = Game.revision
	shown_enemies = model.enemies.duplicate(true)
	shown_player_hp = model.player_hp
	shown_player_block = model.block
	shown_player_parry = model.parry
	shown_player_pollution = model.buffs.count(model, "pollution")
	shown_player_buffs = model.buff_state.duplicate(true)
	shown_player_weak = model.buffs.count(model,"weak")
	# Retain existing HUD offsets; only the world imagery is replaced.
	var scenery_place_id: String = Game.training_scenery_place_id if Game.training_mode and not Game.training_scenery_place_id.is_empty() else battle.placeId
	var place_asset: String = Game.place_data(scenery_place_id).backgroundAssetId
	var stage_asset: String = Game.assets.get(place_asset,{}).get("battleAssetId","")
	var old_offset: Array = Game.assets.get(stage_asset,{}).get("actorOffset",Game.assets.get(place_asset,{}).get("battleActorOffset",[0,0]))
	actor_offset = ACTOR_OFFSET+Vector2(old_offset[0],old_offset[1])
	var backdrop := rect(self,Vector2.ZERO,Vector2(1440,900),Color("07080c"))
	backdrop.z_index = -3
	stage = preload("res://scripts/combat/test_stage.gd").new()
	add_child(stage)
	var enemy_visuals: Array[EnemyVisualResolver.Visual] = []
	for enemy in model.enemies:
		enemy_visuals.append(Game.enemy_combat_visual(enemy))
	var stage_definition: Dictionary = Game.assets.get(stage_asset,{})
	var stage_texture: Texture2D = Game.texture(stage_asset) if stage_definition.get("battleEnabled",true) else null
	stage.setup(533+actor_offset.y,enemy_visuals,stage_texture,float(stage_definition.get("groundStart",0.5)))
	shown_encounter_phase = model.encounter_phase
	if model.profile.get("encounterId", "") == "dancer_duet" and shown_encounter_phase == 2:
		setup_dancer_duet()
	if stage.scenery != null:
		var shade := Gradient.new()
		shade.offsets = PackedFloat32Array([0.0,0.25,0.38,0.66,0.88,1.0])
		shade.colors = PackedColorArray([Color(0.025,0.03,0.05,0.40),Color(0.025,0.03,0.05,0.40),Color(0.025,0.03,0.05,0.04),Color(0.025,0.03,0.05,0.04),Color(0.025,0.03,0.05,0.82),Color(0.025,0.03,0.05,0.96)])
		var shade_texture := GradientTexture2D.new()
		shade_texture.gradient = shade
		shade_texture.fill_from = Vector2.ZERO
		shade_texture.fill_to = Vector2(0,1)
		var shade_view := TextureRect.new()
		shade_view.texture = shade_texture
		shade_view.size = Vector2(1440,900)
		shade_view.z_index = -2
		shade_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade_view)
	# Battle has no footer; changing the section title must retain that layout.
	status_bar("新手教程" if Game.tutorial_mode else Game.battle_type_label(Game.battle_type()),false,Callable(),false)
	if not Game.training_mode and not model.is_noren():
		tag("旧版测试规则",Vector2(760,117),CYAN,310)
	if Game.texture(place_asset) == null:
		label(self,"场景美术待补",Vector2(43,203),Vector2(330,26),13,MUTED)
	turn_hud = preload("res://scripts/combat/turn_hud.gd").new()
	turn_hud.position = Vector2(570,10)
	add_child(turn_hud)
	turn_hud.set_state(model.turn)
	turn_label = turn_hud.round_label
	resource_feedback = preload("res://scripts/combat/resource_feedback.gd").new()
	add_child(resource_feedback)
	player_portrait = stage.player
	player_plate = ActorHUD.new()
	player_plate.z_index = -1
	add_child(player_plate)
	player_hover = preload("res://scripts/combat/stance_hover.gd").new()
	add_child(player_hover)
	ammo_panel = AmmoHUD.new()
	ammo_panel.position = Vector2(30,667-AmmoHUD.DIMENSIONS.y-22)
	add_child(ammo_panel)
	resources_label = label(ammo_panel,"",Vector2(6,3),Vector2(AmmoHUD.DIMENSIONS.x-12,22),15,AmmoHUD.ORANGE)
	resources_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_panel.value_label = resources_label
	build_energy_hud()
	exhaust_button = button(self,"消耗 0",Vector2(1240,770),Vector2(170,30),func(): show_pile("消耗 / 能力",model.exhaust_pile))
	exhaust_button.add_theme_font_size_override("font_size",13)
	exhaust_button.visible = model.is_noren()
	refresh_resources()
	stage.player.set_combat_stance(model.stance if model.is_noren() else "melee")
	enemy_portraits.clear()
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
	cyberware_button = button(self,"激活科技",Vector2(30,667),Vector2(170,40),show_cyberware)
	cyberware_button.add_theme_font_size_override("font_size",15)
	for state_name in ["normal","hover","pressed","focus"]:
		var purple_style := button_style(state_name,false)
		purple_style.border_color = Color("c895ff")
		if state_name != "focus": purple_style.bg_color = Color("482866") if state_name == "hover" else Color("251638")
		cyberware_button.add_theme_stylebox_override(state_name,purple_style)
	refresh_cyberware()
	aim = Node2D.new()
	aim.set_script(preload("res://scripts/combat/targeting_line.gd"))
	aim.z_index = 35
	aim.visible = false
	add_child(aim)
	refresh_counts()
	set_busy(true)
	if Game.tutorial_mode:
		tutorial_guide = preload("res://scripts/combat/tutorial_guide.gd").new()
		add_child(tutorial_guide)
		tutorial_guide.configure(self)
	start_hand.call_deferred()

func battle_background() -> bool:
	actor_offset = ACTOR_OFFSET
	var place_asset: String = Game.place_data(battle.placeId).backgroundAssetId
	var stage_asset: String = Game.assets.get(place_asset,{}).get("battleAssetId","")
	if stage_asset.is_empty() or not Game.assets.get(stage_asset,{}).get("battleEnabled",true) or Game.texture(stage_asset) == null:
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

func displayed_enemy_intent(enemy: Dictionary) -> String:
	if presenting_enemy_turn:
		# The ordered status events already include this round's player decay.
		# Enemy strength/weakness also come from the supplied display snapshot.
		return model.enemy_intent_text(enemy, false, int(shown_player_buffs.get("vulnerable", 0)))
	return model.enemy_intent_text(enemy)

func refresh_enemy_hud() -> void:
	if is_instance_valid(enemy_hud):
		remove_child(enemy_hud)
		enemy_hud.queue_free()
	targets.clear()
	enemy_plates.clear()
	enemy_intents.clear()
	enemy_summary_plates.clear()
	enemy_hud = Control.new()
	enemy_hud.position = Vector2(0,actor_offset.y)
	enemy_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(enemy_hud)
	var summary := Control.new()
	enemy_hud.add_child(summary)
	# Use the frozen battle type, including training and restored encounters.
	var boss: bool = model.profile.get("battleType","normal") == "boss"
	var summary_width: float = EnemyHPSummary.BOSS_DIMENSIONS.x if boss else EnemyHPSummary.DIMENSIONS.x
	summary.size = Vector2(summary_width+16,80*mini(3,shown_enemies.size())-12)
	# Center the visible health track; the HP readout sits to its right.
	summary.global_position = Vector2(720-EnemyHPSummary.BOSS_TRACK.get_center().x,96) if boss else Vector2(1072,96)
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A fixed-height viewport keeps larger encounters above the actor stage.
	var summary_scroll := ScrollContainer.new()
	summary_scroll.size = summary.size
	summary_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	summary_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE if shown_enemies.size() <= 3 else Control.MOUSE_FILTER_PASS
	summary.add_child(summary_scroll)
	var rows := Control.new()
	rows.custom_minimum_size = Vector2(summary_width,80*shown_enemies.size()-12)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_scroll.add_child(rows)
	for i in shown_enemies.size():
		var enemy: Dictionary = shown_enemies[i]
		var summary_plate := EnemyHPSummary.new()
		rows.add_child(summary_plate)
		summary_plate.position = Vector2(0,i*80)
		summary_plate.setup(enemy,i+1,base_font,boss)
		enemy_summary_plates.append(summary_plate)
		var intent_text := displayed_enemy_intent(enemy)
		var plate := ActorHUD.new()
		# Floor (-2) < foot bars (-1) < actor artwork (0).
		# Keep the original foot placement; nearer art may cover these strips.
		plate.z_index = -1
		enemy_hud.add_child(plate)
		enemy_plates.append(plate)
		plate.update_values(int(enemy.hp),int(enemy.maxHp),int(enemy.get("block",0)),enemy_statuses(enemy))
		var intent := EnemyIntent.new()
		enemy_hud.add_child(intent)
		enemy_intents.append(intent)
		intent.setup(enemy.get("intent",{}),intent_text,button_font)
		var tooltip_data := preload("res://scripts/combat/intent_tooltip.gd").describe(enemy,intent_text)
		intent.configure_tooltip(tooltip_data)
		var target := preload("res://scripts/combat/enemy_target.gd").new()
		# Self-targeted cards must suppress both armed and ordinary hover brackets.
		target.brackets_enabled = selected_uid.is_empty() or model.card_target(selected_uid) != "self"
		target.armed = not selected_uid.is_empty() and target.brackets_enabled
		target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		target.pressed.connect(func():
			var front := target_at_pointer()
			if front >= 0: play_selected(front)
		)
		enemy_hud.add_child(target)
		targets.append(target)
		target.disabled = enemy.hp <= 0
		target.tooltip_data = tooltip_data
		target.tooltip_text = tooltip_data.plain
	# Status icons receive hover before the transparent target buttons.
	for plate in enemy_plates: enemy_hud.move_child(plate,-1)
	for intent in enemy_intents: enemy_hud.move_child(intent,-1)
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
	# Reserve the full rotated card footprint, rather than just its centre span.
	var edge_angle := absf(hand_rotation(0,count))
	var half_width := HAND_SCALE*(90.0*cos(edge_angle)+115.0*sin(edge_angle))
	var span := HAND_SAFE_WIDTH-2.0*(half_width+HAND_EDGE_PADDING)
	var spacing := minf(129.8,span/maxi(count-1,1))
	if is_zero_approx(edge_angle): return Vector2(630,HAND_BASE_Y)
	# Position and tilt share one circle. An independently flattened height curve
	# makes the inward upper corners of the outer cards poke above their neighbours.
	var radius := spacing*(count-1)/2.0/sin(edge_angle)
	var angle := hand_rotation(index,count)
	return Vector2(720+radius*sin(angle)-90,HAND_BASE_Y+radius*(1.0-cos(angle)))

func hand_rotation(index: int, count: int) -> float:
	return deg_to_rad((index-(count-1)/2.0)/maxf((count-1)/2.0,1.0)*minf(12.0,(count-1)*2.0))

func hand_at_pointer() -> String:
	return hand_at_point(get_global_mouse_position())

func hand_at_point(pointer: Vector2) -> String:
	var nearest := ""
	# A centered aimed card is above the fan, so its visible face wins hits too.
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
		uid = selected_uid if following_card_selected() else (held_card_uid if not held_card_uid.is_empty() else hand_at_pointer())
	for card_uid in cards: cards[card_uid].hover(card_uid == uid)

func create_card(uid: String, index: int, count: int, animate: bool) -> CombatCard:
	var view := CombatCard.new()
	view.managed_input = true
	view.home_scale = HAND_SCALE
	view.home_rotation = hand_rotation(index,count)
	view.home_z = 10+index
	view.lifted_z = maxi(30,10+count)
	view.selection_home = hand_position(0,1)+Vector2(0,36) # Keep the aimed card above the viewport bottom.
	view.center_on_selection = uses_centered_aim(uid)
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
		await commit()
	await deal_hand(first_draw)
	refresh_counts()
	initialized = true
	set_busy(false)

func deal_hand(animate: bool) -> void:
	if model.hand.is_empty(): return
	var last_flight: Node2D
	var duration := maxf(timing("drawDuration",0.26),0.38)
	var batch_index := 0
	for i in model.hand.size():
		if cards.has(model.hand[i]): continue
		if animate and pending_recycles.has(model.hand[i]):
			# Finish the old deck's flights before recycling, including mid-deal.
			if is_instance_valid(last_flight): await last_flight.landed
			last_flight = null
			var amount: int = pending_recycles[model.hand[i]]
			pending_recycles.erase(model.hand[i])
			await animate_shuffle(amount)
			batch_index = 0
		var view := create_card(model.hand[i],i,model.hand.size(),animate)
		if animate:
			var fx := preload("res://scripts/combat/draw_fx.gd").new()
			add_child(fx)
			fx.departed.connect(on_card_drawn)
			fx.start(view,DRAW_POS+PILE_SIZE/2.0,duration,batch_index*0.055)
			batch_index += 1
			last_flight = fx
	if animate and is_instance_valid(last_flight): await last_flight.landed

func animate_shuffle(amount: int) -> void:
	shuffle_fx = preload("res://scripts/combat/shuffle_fx.gd").new()
	add_child(shuffle_fx)
	shuffle_fx.transferred.connect(func(count: int):
		shown_discard_count -= count
		shown_draw_count += count
		render_counts()
	)
	shuffle_fx.start(DISCARD_POS+PILE_SIZE/2.0,DRAW_POS+PILE_SIZE/2.0,amount)
	await shuffle_fx.landed
	shuffle_fx = null

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

func uses_centered_aim(uid: String) -> bool:
	return model.card(uid).get("type", "attack") == "attack" or model.card_target(uid) == "enemy"

func following_card_selected() -> bool:
	return cards.has(selected_uid) and not cards[selected_uid].center_on_selection

func release_area_contains(uid: String, point: Vector2) -> bool:
	if cards.has(uid) and not cards[uid].center_on_selection:
		return get_global_rect().has_point(point)
	return CENTER_DROP_RECT.has_point(point)

func cancel_selection() -> void:
	clear_card_drag()
	if selected_uid.is_empty(): return
	selected_uid = ""
	card_aim_cancelled.emit()
	for uid in cards: cards[uid].set_selected(false)
	if is_instance_valid(aim): aim.visible = false
	refresh_enemy_hud()

func select_card(uid: String, toggle: bool = true) -> void:
	if Game.transition_locked or Game.battle_busy or not initialized or is_instance_valid(pile_overlay): return
	if not cards.has(uid): return
	clear_card_drag()
	var reason := model.play_error(uid)
	if not reason.is_empty():
		report_play_error(uid,reason)
		return
	clear_resource_feedback()
	selected_uid = "" if toggle and selected_uid == uid else uid
	if selected_uid.is_empty(): card_aim_cancelled.emit()
	else: card_aim_started.emit(selected_uid)
	for card_uid in cards:
		# A stance-dependent skill can change target while remaining in this hand.
		cards[card_uid].center_on_selection = uses_centered_aim(card_uid)
		cards[card_uid].set_selected(card_uid == selected_uid)
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

func choose_player_attack_style(definition: Dictionary, result: Dictionary) -> String:
	# Use the stance captured at card resolution, including attack-then-shift cards.
	if result.get("stance", "melee") == "ranged": return "shoot"
	if Game.training_mode and not preview_attack_style.is_empty(): return preview_attack_style
	var authored_style: String = definition.get("animation", "")
	if not authored_style.is_empty(): return authored_style
	if result.get("hits", []).is_empty(): return "slash"
	return "slash" if melee_animation_rng.randi_range(0, 1) == 0 else "pierce"

func play_selected(target: int, discard_uid: String = "", extra_ammo: int = -1) -> void:
	if selected_uid.is_empty() or Game.transition_locked or Game.battle_busy or is_instance_valid(pile_overlay): return
	var uid := selected_uid
	var error := model.play_error(uid)
	if not error.is_empty():
		report_play_error(uid,error)
		return
	for effect in model.card(uid).get("effects", []):
		if effect.type == "exhaust_hand" and discard_uid.is_empty():
			var options: Array = []
			for candidate in model.exhaust_candidates(uid):
				options.append({"value":candidate,"text":"%s · 费用 %d\n%s" % [model.card(candidate).name,model.card_cost(candidate),model.card_preview(candidate).text]})
			show_card_choice("选择消耗另一张手牌",options,func(value): play_selected(target,value,extra_ammo),true)
			return
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
	var block_before := model.block
	var result := model.play_card(uid,target,discard_uid,maxi(0,extra_ammo))
	if result.is_empty(): return
	card_played.emit(uid)
	if cards.has(uid):
		cards[uid].show_preview(played_preview)
		cards[uid].show_cost(played_cost)
	presenting_player_attack = result.get("stance", "") == "melee" and not result.hits.is_empty()
	presenting_player_hits = not result.hits.is_empty()
	set_busy(true)
	selected_uid = ""
	aim.visible = false
	await commit()
	var retired: Array = [uid]
	retired.append_array(result.get("discarded", []))
	retired.append_array(result.get("exhaustedCards", []))
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
		if (retired_view.uid == uid and result.get("exhausted",false)) or retired_view.uid in result.get("exhaustedCards",[]): animate_exhaust(retired_view)
		else: animate_discard(retired_view)
	var block_gained := maxi(0, model.block - block_before)
	if block_gained > 0:
		shown_player_block = model.block
		refresh_player_plate()
		stage.present_card_gain("block", block_gained)
	# Choose once per committed card; all hits and targets share its attack motion.
	var style := choose_player_attack_style(model.card(uid), result)
	stage.player.set_combat_stance(result.get("stance", "melee"))
	for index in shown_enemies.size():
		var target_hits: Array = result.hits.filter(func(hit): return int(hit.get("target",target)) == index)
		if target_hits.is_empty(): continue
		await stage.attack(stage.player,stage.enemies[index],style,target_hits,func(hit: Dictionary, _index: int):
			shown_enemies[index].hp = hit.hpAfter
			shown_enemies[index].block = hit.get("blockAfter",0)
			shown_enemies[index].bleed = hit.get("bleedAfter",0)
			if hit.has("electricChargeAfter"):
				apply_shown_status({"target":index,"buffId":"electric_charge","stacksAfter":hit.electricChargeAfter})
			if hit.has("ammoAfter"):
				shown_player_ammo = int(hit.ammoAfter)
				refresh_ammo()
			present_enemy_death_effect(hit)
			refresh_enemy_hud()
			var text := "−%d" % hit.damage
			if int(hit.get("bleedDamage",0)) > 0: text += " (裂伤 %d)" % hit.bleedDamage
			impact(stage.contact(stage.enemies[index]),text,PINK)
		)
	for event in result.get("phaseTurnEvents", []):
		await present_status_event(event)
	await present_encounter_phase()
	shown_enemies = model.enemies.duplicate(true)
	refresh_enemy_hud()
	# Discard flight already runs in parallel; only attack playback precedes the shift.
	await stage.player.transition_combat_stance(model.stance if model.is_noren() else "melee")
	for retired_view in retired_views:
		while is_instance_valid(retired_view) and retired_view.visible: await get_tree().process_frame
	if result.get("phaseChanged", false):
		await announce_turn("第%d回合" % model.turn)
	stage.present_card_gain("draw", result.get("drawn", []).size())
	await deal_hand(true)
	arrange_hand()
	refresh_counts()
	presenting_player_attack = false
	presenting_player_hits = false
	refresh_resources()
	set_busy(false)
	if not model.outcome.is_empty(): finish(model.outcome)

func show_card_choice(title: String, options: Array, callback: Callable, show_cards := false) -> void:
	clear_card_drag()
	pile_overlay = preload("res://scripts/combat/choice_picker.gd").new()
	pile_overlay.heading = title
	pile_overlay.card_mode = show_cards
	pile_overlay.model = model
	pile_overlay.options = options
	if show_cards:
		for option in options:
			var candidate: CombatCard = cards.get(str(option.value))
			if not is_instance_valid(candidate): continue
			pile_overlay.hand_layout[str(option.value)] = {
				"position":candidate.home+candidate.pivot_offset-(candidate.pivot_offset*candidate.home_scale).rotated(candidate.home_rotation),
				"scale":candidate.home_scale,"rotation":candidate.home_rotation}
			if candidate.visible:
				choice_hidden_cards.append(candidate)
				candidate.hide()
		# The pending source card must not remain lifted behind the chosen card.
		if cards.has(selected_uid) and cards[selected_uid].visible:
			choice_hidden_cards.append(cards[selected_uid])
			cards[selected_uid].hide()
	pile_overlay.closed.connect(close_pile)
	pile_overlay.picked.connect(func(value):
		close_pile()
		callback.call(value))
	add_child(pile_overlay)

func animate_exhaust(view: CombatCard) -> void:
	var fx := preload("res://scripts/combat/exhaust_fx.gd").new()
	add_child(fx)
	fx.start(view)

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
	# A terminal snapshot can enter this view without drawing/initializing a hand.
	# Retry only the transactional story exit, never the combat turn or card play.
	if not pending_battle_result.is_empty():
		finish(pending_battle_result)
		return
	if not initialized or not model.outcome.is_empty() or Game.transition_locked or Game.battle_busy or is_instance_valid(pile_overlay): return
	set_busy(true)
	selected_uid = ""
	aim.visible = false
	turn_hud.set_state(model.turn,"enemy")
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
	await commit()
	for attack in result.get("turnEvents", result.attacks):
		if attack.get("type", "attack") != "attack":
			await present_status_event(attack)
			continue
		var attacker_index := int(attack.get("index", -1))
		if attacker_index < 0:
			for i in shown_enemies.size():
				if shown_enemies[i].id == attack.id: attacker_index = i
		if attacker_index < 0: continue
		present_attack_start(attack, attacker_index)
		var default_style: String = stage.enemies[attacker_index].attack_style_override
		if default_style.is_empty(): default_style = "pierce"
		var style: String = shown_enemies[attacker_index].intent.get("animation",default_style)
		await stage.attack(stage.enemies[attacker_index],stage.player,style,attack.hits,func(hit: Dictionary, _index: int):
			if _index == 0: present_attack_impact(attack, attacker_index)
			shown_player_hp = int(hit.hpAfter)
			shown_player_block = maxi(0,shown_player_block-int(hit.get("blocked",0)))
			shown_player_pollution = int(hit.get("pollutionAfter", shown_player_pollution))
			if int(hit.damage) > 0:
				var pollution_gain := int(shown_enemies[attacker_index].get("attackPollution",0))
				if pollution_gain > 0:
					stage.spawn_pollution_spit(stage.enemies[attacker_index],stage.player,true)
				present_pollution_gain(pollution_gain)
			refresh_player_plate()
			refresh_hp()
			impact(stage.contact(stage.player),"−%d HP" % hit.damage if hit.damage > 0 else "格挡",PINK)
		)
		await stage.wait_pollution_spits()
		if not attack.get("counters",[]).is_empty() and stage.player.alive:
			await stage.attack(stage.player,stage.enemies[attacker_index],"slash",attack.counters,func(hit: Dictionary, _index: int):
				shown_enemies[attacker_index].hp = hit.hpAfter
				shown_enemies[attacker_index].block = hit.get("blockAfter",0)
				shown_enemies[attacker_index].bleed = hit.bleedAfter
				shown_player_ammo = int(hit.get("ammoAfter", model.ammo))
				refresh_ammo()
				present_enemy_death_effect(hit)
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
	await present_encounter_phase()
	presenting_enemy_turn = false
	refresh_resources()
	stage.player.set_combat_stance(model.stance if model.is_noren() else "melee")
	shown_enemies = model.enemies.duplicate(true)
	refresh_enemy_hud()
	turn_hud.set_state(model.turn)
	await announce_turn("第%d回合" % model.turn)
	await deal_hand(true)
	refresh_counts()
	set_busy(false)


func present_attack_start(_attack: Dictionary, _index: int) -> void:
	# Expiry comes from the model's ordered block_clear event. A shield granted
	# earlier in this enemy phase (the dancers' link) must survive the attack.
	refresh_enemy_hud()

func present_attack_impact(attack: Dictionary, index: int) -> void:
	var enemy: Dictionary = shown_enemies[index]
	if int(attack.get("electricChargeUsed",0)) <= 0: return
	if model.buffs.enemy_count(enemy,model.buffs.definition("electric_charge")) <= 0: return
	# Keep the badge through preparation; spend it on the first actual hit only.
	# Fold its captured bonus into the shown intent to keep later-hit previews stable.
	enemy.intent = enemy.intent.duplicate(true)
	enemy.intent.amount = int(enemy.intent.get("amount",0)) + int(attack.electricChargeUsed)
	apply_shown_status({"target":index,"buffId":"electric_charge","stacksAfter":int(attack.electricChargeAfter)})

func setup_dancer_duet() -> void:
	var visuals: Array[EnemyVisualResolver.Visual] = []
	for enemy in model.enemies:
		visuals.append(Game.enemy_combat_visual(enemy))
	stage.set_dancer_duet(visuals)
	if not is_instance_valid(dancer_darkness):
		dancer_darkness = rect(self, Vector2.ZERO, Vector2(1440,900), Color(0.005,0.008,0.02,0.88))
		dancer_darkness.name = "DancerStageDarkness"
		dancer_darkness.z_index = -2
		dancer_darkness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in stage.enemies.size():
		stage.enemies[i].alive = model.enemies[i].hp > 0
		stage.enemies[i].visible = stage.enemies[i].alive
	stage.face_duet_survivor()
	enemy_portraits.assign(stage.enemies)

func present_encounter_phase() -> void:
	if model.profile.get("encounterId", "") != "dancer_duet" or model.encounter_phase == shown_encounter_phase: return
	# No HP or deck mutations here. Input stays locked across the entire reveal.
	dancer_blackout = rect(self, Vector2.ZERO, Vector2(1440,900), Color.BLACK)
	dancer_blackout.name = "DancerBlackout"
	dancer_blackout.z_index = 100
	dancer_blackout.mouse_filter = Control.MOUSE_FILTER_STOP
	await get_tree().create_timer(1.0).timeout
	setup_dancer_duet()
	shown_encounter_phase = model.encounter_phase
	shown_enemies = model.enemies.duplicate(true)
	refresh_enemy_hud()
	# Reveal the committed new-round resources together with the new formation.
	shown_player_hp = model.player_hp
	shown_player_block = model.block
	shown_player_ammo = model.ammo
	shown_player_parry = model.parry
	shown_player_pollution = model.buffs.count(model, "pollution")
	shown_player_buffs = model.buff_state.duplicate(true)
	shown_player_weak = model.buffs.count(model,"weak")
	refresh_player_plate()
	refresh_hp()
	refresh_ammo()
	prepare_phase_deal_counts()
	turn_hud.set_state(model.turn,"reveal")
	# Hard light cue: reveal the complete formation in one frame, with no fade.
	stage.dancer_lights.modulate.a = 1.0
	var light_pulse: Tween = stage.dancer_lights.flash_on()
	# A single warm exposure accent starts at full intensity with the light cue.
	dancer_reveal_flash = rect(self, Vector2.ZERO, Vector2(1440,900), Color(1.0,0.96,0.84,0.32))
	dancer_reveal_flash.name = "DancerRevealFlash"
	dancer_reveal_flash.z_index = 80
	dancer_reveal_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var exposure := create_tween()
	exposure.tween_interval(0.045)
	exposure.tween_property(dancer_reveal_flash,"color:a",0.0,0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	exposure.tween_callback(dancer_reveal_flash.queue_free)
	dancer_blackout.hide()
	dancer_blackout.queue_free()
	dancer_blackout = null
	# Hold the tableau and input lock while the opening brightness settles.
	await light_pulse.finished
	dancer_reveal_flash = null
	turn_hud.set_state(model.turn)

func present_enemy_death_effect(hit: Dictionary) -> void:
	if not hit.has("playerPollutionAfter"): return
	shown_player_pollution = int(hit.playerPollutionAfter)
	refresh_player_plate()
	if int(hit.get("deathPollution",0)) > 0:
		present_pollution_gain(int(hit.deathPollution))

func present_pollution_gain(amount: int) -> void:
	if amount <= 0: return
	impact(stage.contact(stage.player) - Vector2(0,90),"污染+%d" % amount,Color("a7d85b"),0.625)

func present_status_event(event: Dictionary) -> void:
	var target_index := int(event.get("target", -1))
	var actor = stage.player if target_index < 0 else stage.enemies[target_index]
	if event.type == "intent_change":
		var enemy: Dictionary = shown_enemies[target_index]
		enemy.intent = event.intent.duplicate(true)
		enemy.intentIndex = event.intentIndex
		enemy.intentPhase = event.intentPhase
		refresh_enemy_hud()
		return
	if event.type == "status_decay":
		apply_shown_status(event)
		return
	if event.type == "block_clear":
		shown_enemies[target_index].block = 0
		refresh_enemy_hud()
		return
	if event.type == "heal":
		apply_shown_heal(event)
		impact(stage.contact(actor)-Vector2(0,70),"恢复+%d" % int(event.get("amount",0)),Color("81d6a5"),0.75)
		await get_tree().create_timer(0.30).timeout
		return
	if event.type == "status_apply":
		var source := int(event.source)
		if event.buffId == "pollution":
			await stage.present_pollution_spit(stage.enemies[source],actor,func():
				apply_shown_status(event)
				present_pollution_gain(int(event.get("amount", shown_enemies[source].intent.get("amount",0))))
			)
		else:
			apply_shown_status(event)
			var definition := model.buffs.definition(event.buffId)
			impact(stage.contact(actor)-Vector2(0,70),"%s+%d" % [definition.name,int(event.get("amount",0))],Color(definition.color),0.75)
			await get_tree().create_timer(0.30).timeout
		return
	if event.type != "status_tick": return
	if target_index < 0:
		shown_player_hp = int(event.hpAfter)
		shown_player_block = int(event.blockAfter)
		shown_player_pollution = int(event.stacksAfter)
		refresh_player_plate()
		refresh_hp()
	else:
		var enemy: Dictionary = shown_enemies[target_index]
		enemy.hp = event.hpAfter
		enemy.block = event.blockAfter
		if not enemy.has("buffs"): enemy.buffs = {}
		enemy.buffs[event.buffId] = event.stacksAfter
		present_enemy_death_effect(event)
		refresh_enemy_hud()
	actor.set_pose("damaged" if int(event.damage) > 0 else "block")
	impact(stage.contact(actor),"−%d" % int(event.damage) if int(event.damage) > 0 else "格挡",Color("a7d85b"))
	await get_tree().create_timer(0.25).timeout
	if event.killed:
		await stage.retire_actor(actor)
	else:
		actor.set_pose("idle")

func apply_shown_heal(event: Dictionary) -> void:
	var index := int(event.get("target",-1))
	if index < 0 or index >= shown_enemies.size(): return
	shown_enemies[index].hp = int(event.hpAfter)
	refresh_enemy_hud()

func apply_shown_status(event: Dictionary) -> void:
	var index := int(event.get("target", -1))
	if index < 0:
		if event.buffId == "pollution": shown_player_pollution = int(event.stacksAfter)
		if event.buffId == "weak": shown_player_weak = int(event.stacksAfter)
		if int(event.stacksAfter) == 0: shown_player_buffs.erase(event.buffId)
		else: shown_player_buffs[event.buffId] = int(event.stacksAfter)
		refresh_player_plate()
		if event.buffId == "vulnerable": refresh_enemy_hud()
	else:
		var enemy: Dictionary = shown_enemies[index]
		var definition := model.buffs.definition(event.buffId)
		var field: String = definition.get("field", "")
		if not field.is_empty(): enemy[field] = int(event.stacksAfter)
		else:
			if not enemy.has("buffs"): enemy.buffs = {}
			if int(event.stacksAfter) == 0: enemy.buffs.erase(event.buffId)
			else: enemy.buffs[event.buffId] = int(event.stacksAfter)
		refresh_enemy_hud()

func announce_turn(text: String, enemy: bool = false) -> void:
	turn_hud.set_state(model.turn,"enemy" if enemy else "player")
	var banner := preload("res://scripts/combat/turn_banner.gd").new()
	turn_banner = banner
	add_child(banner)
	await banner.play(text,button_font,enemy)
	remove_child(banner)
	banner.queue_free()
	turn_banner = null

func impact(pos: Vector2, text: String, color: Color, text_scale: float = 1.0) -> void:
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
	floating.start(text,button_font,color,pos,lane,text_scale)
	# Preserve enemy-action pacing while the visual tail finishes independently.
	await get_tree().create_timer(timing("impactDuration",0.36)+0.1).timeout

func prepare_phase_deal_counts() -> void:
	# The model has already drawn the fresh hand, but its flights/shuffles have
	# not played. Rebuild their starting counts, including generated cards.
	var upcoming_draws := 0
	var upcoming_recycles := 0
	for uid in model.hand:
		if cards.has(uid): continue
		upcoming_draws += 1
		upcoming_recycles += int(pending_recycles.get(uid,0))
	shown_draw_count = model.draw_pile.size()+upcoming_draws-upcoming_recycles
	shown_discard_count = model.discard_pile.size()+upcoming_recycles
	render_counts()

func refresh_counts() -> void:
	# Initialize/reset after a complete deal, never during an in-flight discard.
	shown_draw_count = model.draw_pile.size()
	shown_discard_count = model.discard_pile.size()
	render_counts()

func render_counts() -> void:
	draw_count.text = str(shown_draw_count)
	discard_count.text = str(shown_discard_count)

func on_card_drawn() -> void:
	# Recycling has already been presented before this batch can depart.
	shown_draw_count -= 1
	render_counts()

func on_card_discarded() -> void:
	# Each flight reports arrival once; overlapping attacks and turn cleanup
	# share this path without changing any model pile or saved state.
	shown_discard_count += 1
	render_counts()

func set_busy(value: bool) -> void:
	Game.battle_busy = value
	if value:
		clear_card_drag()
		clear_resource_feedback()
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

func resume_console_combat() -> void:
	if not initialized or model.snapshot() == Game.state.get("combat", {}): return
	var previous_phase := model.encounter_phase
	model.restore(Game.state.combat)
	expected_revision = Game.revision
	if previous_phase != model.encounter_phase:
		set_busy(true)
		# The model has already discarded the old hand and dealt the new round.
		# Retire old views even when recycling happened to return the same UID.
		for view in cards.values(): view.queue_free()
		cards.clear()
		await present_encounter_phase()
		if model.outcome.is_empty():
			await announce_turn("第%d回合" % model.turn)
			await deal_hand(true)
			arrange_hand()
		set_busy(false)
	shown_enemies = model.enemies.duplicate(true)
	for i in stage.enemies.size():
		stage.enemies[i].alive = model.enemies[i].hp > 0
		stage.enemies[i].visible = stage.enemies[i].alive
	stage.face_duet_survivor()
	refresh_enemy_hud()
	refresh_resources()
	refresh_card_previews()
	refresh_counts()
	if not model.outcome.is_empty(): finish(model.outcome)

func commit() -> void:
	if not Game.commit_combat(model):
		await Game.checkpoint_saved
	expected_revision = Game.revision
	refresh_cyberware()
	refresh_card_previews()
	refresh_resources()

func refresh_cyberware() -> void:
	if not is_instance_valid(cyberware_button): return
	cyberware_button.text = "激活科技"
	cyberware_button.tooltip_text = "下次攻击伤害 +%d" % model.next_attack_bonus if model.next_attack_bonus > 0 else "点击查看战斗科技"

func show_cyberware() -> void:
	if not initialized or Game.battle_busy or Game.transition_locked or is_instance_valid(pile_overlay): return
	clear_resource_feedback()
	cancel_selection()
	pile_overlay = preload("res://scripts/combat/cyberware_view.gd").new()
	pile_overlay.setup(model)
	pile_overlay.closed.connect(close_pile)
	pile_overlay.activation_requested.connect(activate_cyberware)
	add_child(pile_overlay)

func activate_cyberware(id: String) -> void:
	if not initialized or Game.battle_busy or Game.transition_locked or not is_instance_valid(pile_overlay): return
	if not pile_overlay.has_signal("activation_requested"): return
	var old_hand := model.hand.duplicate()
	var redraw := false
	var legacy_bonus := false
	for definition in model.cyberware_cards():
		if definition.id != id: continue
		redraw = definition.get("effect", "") == "redraw_hand"
		legacy_bonus = definition.get("effect", "next_attack_bonus") == "next_attack_bonus"
	if not model.activate_cyberware(id): return
	await commit()
	if legacy_bonus:
		pile_overlay.refresh()
		return
	# Commit the complete model result once; then present discarded/drawn cards.
	# Redraw can return the same UIDs after recycling, so retire every old view.
	close_pile()
	set_busy(true)
	var retired_views: Array = []
	if redraw:
		for uid in old_hand:
			if not cards.has(uid): continue
			var view: CombatCard = cards[uid]
			cards.erase(uid)
			retired_views.append(view)
			animate_discard(view)
	await stage.player.transition_combat_stance(model.stance if model.is_noren() else "melee")
	for view in retired_views:
		while is_instance_valid(view) and view.visible: await get_tree().process_frame
	await deal_hand(true)
	arrange_hand()
	refresh_counts()
	set_busy(false)

func finish(result: String) -> void:
	if Game.transition_locked or Game.battle_busy or is_instance_valid(pile_overlay): return
	if Game.battle_exit(result,Game.revision):
		pending_battle_result = ""
		return
	pending_battle_result = result
	end_button.text = "重试战后结算"
	end_button.tooltip_text = "保存未完成。处理存储问题后点击重试，战斗结果会保留。"
	end_button.disabled = false
	turn_hud.set_state(model.turn,"save")
	Game.notice.emit("战后结算未能保存，请点击“重试战后结算”。")

func use_item(item_id: String) -> void:
	if Game.battle_busy or Game.transition_locked: return
	var response := model.use_item(item_id,0,Game.state.inventory,Game.item_catalog)
	Game.notice.emit(response.reason)

func show_pile(title: String, contents: Array) -> void:
	if Game.battle_busy or Game.transition_locked or is_instance_valid(pile_overlay): return
	clear_resource_feedback()
	cancel_selection()
	pile_overlay = preload("res://scripts/combat/pile_view.gd").new()
	pile_overlay.setup(model, title, contents)
	pile_overlay.closed.connect(close_pile)
	add_child(pile_overlay)
	pile_inspected.emit(title)

func close_pile() -> void:
	if not is_instance_valid(pile_overlay): return
	var previous := pile_overlay
	pile_overlay = null
	remove_child(previous)
	previous.queue_free()
	for candidate in choice_hidden_cards:
		if is_instance_valid(candidate): candidate.show()
	choice_hidden_cards.clear()
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

func handle_battle_shortcut(event: InputEventKey) -> bool:
	# Own the whole key gesture before focused Buttons see ui_accept. The action
	# may open a modal or start an animation before the matching release arrives.
	if held_shortcut_keys.has(event.keycode):
		held_shortcut_keys.erase(event.keycode)
		if not event.pressed or event.echo:
			if event.pressed: held_shortcut_keys[event.keycode] = true
			get_viewport().set_input_as_handled()
			return true
		# A fresh press can follow a release consumed while this view was paused.
	if not event.pressed or event.echo: return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed: return false
	if not initialized or Game.battle_busy or Game.transition_locked or is_instance_valid(pile_overlay): return false
	if not model.outcome.is_empty(): return false
	for action in ["end_turn", "technology", "draw_pile", "discard_pile"]:
		if not PlayerSettings.matches(event, action): continue
		held_shortcut_keys[event.keycode] = true
		get_viewport().set_input_as_handled()
		match action:
			"end_turn": end_turn_pressed()
			"technology": show_cyberware()
			"draw_pile": show_pile("抽牌堆", model.draw_pile)
			"discard_pile": show_pile("弃牌堆", model.discard_pile)
		return true
	# Resolve bindings against the current hand order, including default keypad aliases.
	# An empty hand slot still owns its binding instead of confirming a GUI button.
	for index in 10:
		if PlayerSettings.matches(event, "hand_%d" % (index + 1)):
			held_shortcut_keys[event.keycode] = true
			get_viewport().set_input_as_handled()
			if index < model.hand.size(): select_card(model.hand[index], false)
			return true
	return false

func _input(event: InputEvent) -> void:
	# Guide controls must reach GUI before a selected self/all card claims the click.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(tutorial_guide) and tutorial_guide.blocks_pointer(event.position):
		if event.pressed: cancel_selection()
		else: clear_card_drag()
		return
	if event is InputEventKey and handle_battle_shortcut(event): return
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
			# A following self/all card owns clicks over buttons and other cards.
			if following_card_selected():
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
			if following_card_selected(): get_viewport().set_input_as_handled()
			if model.card_target(released_uid) in ["self","all"]:
				get_viewport().set_input_as_handled()
				if should_release:
					if release_area_contains(released_uid,get_global_mouse_position()): play_selected(-1)
					elif not following_card_selected(): cancel_selection()
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
	update_player_hover()
	for i in targets.size():
		var area: Rect2 = stage.target_rect(i)
		targets[i].position = area.position-enemy_hud.global_position
		targets[i].size = area.size
	update_enemy_plates()

func update_player_hover() -> void:
	if not is_instance_valid(player_hover): return
	player_hover.configure(model.stance,int(model.profile.get("ammoCap",10)))
	var area: Rect2 = (stage.player.get_global_transform() * stage.player.target_bounds).intersection(stage.get_global_rect())
	player_hover.position = area.position-global_position
	player_hover.size = area.size
	player_hover.visible = model.is_noren() and model.outcome.is_empty() and stage.player.visible and stage.player.modulate.a > 0.01 and area.has_area() and not Game.battle_busy and not Game.transition_locked and selected_uid.is_empty() and not is_instance_valid(pile_overlay)
	player_hover.mouse_filter = Control.MOUSE_FILTER_PASS if player_hover.visible else Control.MOUSE_FILTER_IGNORE

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

func enemy_statuses(enemy: Dictionary) -> Array:
	return model.buffs.enemy_badges(enemy)

func refresh_player_plate() -> void:
	if not is_instance_valid(player_plate): return
	player_plate.update_values(shown_player_hp,model.max_hp,shown_player_block,model.buffs.player_badges(model,shown_player_parry,shown_player_pollution,shown_player_buffs,shown_player_weak))

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

func report_play_error(uid: String, reason: String) -> void:
	# Classify the model's rejection; never perform or change resource validation here.
	var resource := "energy" if reason.begins_with("能量不足") else ("ammo" if reason.begins_with("弹药不足") else "")
	if resource.is_empty():
		Game.notice.emit(reason)
		return
	clear_resource_feedback()
	resource_feedback.present(resource,model.card_cost(uid),model.energy)
	var resource_panel: Control = energy_panel if resource == "energy" else ammo_panel
	var warning = resource_panel.get_node_or_null("ResourceWarningFX")
	if warning == null:
		warning = preload("res://scripts/combat/resource_warning_fx.gd").new()
		warning.name = "ResourceWarningFX"
		resource_panel.add_child(warning)
	warning.flash(Color("70b7ff") if resource == "energy" else AmmoHUD.ORANGE,resource_panel.size)
	resource_denied.emit()

func clear_resource_feedback() -> void:
	if is_instance_valid(resource_feedback): resource_feedback.dismiss()
	for resource_panel in [energy_panel,ammo_panel]:
		if not is_instance_valid(resource_panel): continue
		var warning = resource_panel.get_node_or_null("ResourceWarningFX")
		if warning != null:
			warning.hide()
			warning.set_process(false)

func build_energy_hud() -> void:
	energy_panel = EnergyHUD.new()
	energy_panel.position = Vector2(30,719)
	add_child(energy_panel)
	energy_panel.title_label = label(energy_panel,"能量",Vector2(31,9),Vector2(61,17),10,CYAN)
	energy_value = label(energy_panel,"",Vector2(90,0),Vector2(70,34),23,CREAM)
	energy_value.add_theme_font_override("font",button_font)
	energy_value.autowrap_mode = TextServer.AUTOWRAP_OFF
	energy_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	energy_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	energy_panel.value_label = energy_value

func refresh_resources() -> void:
	if not presenting_enemy_turn:
		shown_player_block = model.block
		if not presenting_player_attack: shown_player_ammo = model.ammo
		shown_player_parry = model.parry
		# Player hits reveal death pollution at their own impact callbacks.
		if not presenting_player_hits: shown_player_pollution = model.buffs.count(model, "pollution")
		shown_player_buffs = model.buff_state.duplicate(true)
		shown_player_weak = model.buffs.count(model,"weak")
	refresh_player_plate()
	if not is_instance_valid(resources_label): return
	if is_instance_valid(energy_panel):
		energy_panel.visible = model.is_noren()
		var per_turn := maxi(1,int(model.profile.get("energyPerTurn",3)))
		energy_panel.set_energy(model.energy,per_turn)
	if not model.is_noren():
		ammo_panel.visible = false
		return
	refresh_ammo()
	if is_instance_valid(exhaust_button): exhaust_button.text = "消耗 / 能力 %d" % model.exhaust_pile.size()

func refresh_ammo() -> void:
	if not is_instance_valid(ammo_panel): return
	ammo_panel.visible = model.is_noren()
	if ammo_panel.visible:
		ammo_panel.set_ammo(shown_player_ammo,int(model.profile.get("ammoCap",10)),model.stance)
