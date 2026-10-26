extends DemoUI
## Presentation only. Reward ownership and persistence remain in Game.
signal card_picked(id: String)
signal closed
const SLOT_SIZE := Vector2(328, 530)
const CARD_SCALE := 1.62
const CARD_HOME := Vector2(18.2, 65)
const SLOT_ORIGIN := Vector2(164, 235)
const SLOT_STEP := 392.0
const ENTRANCE_DURATION := 0.52
const REVEAL_MARGIN := Vector2(70, 26)
const REVEAL_SIZE := Vector2i(468, 582)
const REVEAL_SHADER := preload("res://shaders/reward_reveal.gdshader")
var option_buttons: Array[Button] = []
var option_slots: Array[Control] = []
var cards: Array[CombatCard] = []
var owned_labels: Array[Label] = []
var back_button: Button
var hovered_index := -1
var focused_index := -1
var active_index := -1
var options: Array = []
var catalog: Dictionary = {}
var owned_counts: Dictionary = {}
var event_reward := false
var frames: Array[Panel] = []
var action_labels: Array[Label] = []
var rarity_colors: Array[Color] = []
var card_tweens: Array[Tween] = []
var glows: Array[TextureRect] = []
var entrance_running := true
var entrance_tween: Tween
var entrance_surfaces: Array[SubViewport] = []
var entrance_images: Array[TextureRect] = []
var entrance_materials: Array[ShaderMaterial] = []

func setup(ids: Array, definitions: Dictionary, counts: Dictionary, from_event: bool) -> void:
	options = ids.duplicate()
	catalog = definitions
	owned_counts = counts.duplicate()
	event_reward = from_event

func _ready() -> void:
	name = "RewardPicker"
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	# A quiet city silhouette gives the cards context without competing with their art.
	rect(self, Vector2.ZERO, Vector2(1440,900), Color("090c17"))
	var city := image_asset(self, "city", Vector2.ZERO, Vector2(1440,900))
	if city != null: city.modulate = Color(0.42,0.46,0.65,0.18)
	var wash := Gradient.new()
	wash.colors = PackedColorArray([Color(0.035,0.045,0.085,0.4), Color(0.035,0.045,0.085,0.98)])
	var wash_texture := GradientTexture2D.new()
	wash_texture.gradient = wash
	wash_texture.fill_from = Vector2(0,0)
	wash_texture.fill_to = Vector2(0,1)
	texture_rect(self, wash_texture, Vector2.ZERO, Vector2(1440,900))
	# Offset architectural lines and a low stage horizon, all below the card content.
	for x in [80,1360]: rect(self, Vector2(x,60), Vector2(1,780), Color("263041"))
	polygon(self,[Vector2(0,745),Vector2(530,710),Vector2(1440,776),Vector2(1440,900),Vector2(0,900)],Color(0.015,0.022,0.043,0.65))
	rect(self,Vector2(164,68),Vector2(28,4),PINK)
	label(self,"来自午夜酒馆的回礼" if event_reward else "战 利 品  /  REWARD",Vector2(205,54),Vector2(600,32),16,CYAN)
	label(self,"挑选你的下一张底牌",Vector2(160,100),Vector2(930,70),44,CREAM).name = "PickerTitle"
	label(self,"带上这份回礼，继续你的委托。" if event_reward else "选择一张加入牌组，为下一场战斗做好准备。",Vector2(164,177),Vector2(850,34),20,MUTED)
	var count_label := label(self,"3 选 1",Vector2(1100,107),Vector2(175,55),36,CREAM)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for i in options.size(): build_option(i)
	rect(self,Vector2(164,801),Vector2(1112,1),Color("2a3548"))
	back_button = button(self,"返回奖励  /  Esc",Vector2(1048,822),Vector2(228,48),func(): closed.emit())
	back_button.name = "ReturnToRewards"
	back_button.focus_entered.connect(refresh_active)
	back_button.focus_exited.connect(refresh_active)
	var focus_buttons: Array[Button] = option_buttons.duplicate()
	focus_buttons.append(back_button)
	for i in focus_buttons.size():
		focus_buttons[i].focus_next = focus_buttons[i].get_path_to(focus_buttons[(i+1)%focus_buttons.size()])
		focus_buttons[i].focus_previous = focus_buttons[i].get_path_to(focus_buttons[(i+focus_buttons.size()-1)%focus_buttons.size()])
	# No preselection: mouse or keyboard focus makes one offer stand out.
	play_entrance()

func texture_rect(parent: Node, texture: Texture2D, pos: Vector2, dimensions: Vector2) -> TextureRect:
	var item := TextureRect.new()
	item.texture = texture
	item.position = pos
	item.size = dimensions
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item

func build_option(index: int) -> void:
	var id: String = options[index]
	var definition: Dictionary = catalog[id]
	var rarity: String = str(definition.get("rarity", ""))
	var color: Color = CombatCard.RARITY_COLORS.get(rarity, CYAN)
	rarity_colors.append(color)
	var slot := Control.new()
	slot.name = "RewardSlot%d" % (index+1)
	slot.position = SLOT_ORIGIN + Vector2(index*SLOT_STEP,0)
	slot.size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot)
	option_slots.append(slot)
	var glow_gradient := Gradient.new()
	glow_gradient.colors = PackedColorArray([Color(color,0.2),Color(color,0)])
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow_gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5,0.5)
	glow_texture.fill_to = Vector2(0.5,0)
	var glow := texture_rect(slot,glow_texture,Vector2(-70,-26),Vector2(468,562))
	glow.modulate.a = 0.65
	glows.append(glow)
	var frame := Panel.new()
	frame.size = SLOT_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel",frame_style(color,false))
	slot.add_child(frame)
	frames.append(frame)
	# Solid grade tag, a restrained top rule and an outlined key make each offer distinct.
	rect(slot,Vector2(18,0),Vector2(292,2),Color(color,0.7))
	rect(slot,Vector2(20,20),Vector2(61,27),color)
	var rank := label(slot,rarity+" 级" if not rarity.is_empty() else "卡牌",Vector2(20,20),Vector2(61,27),15,INK)
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var serial := label(slot,"0%d" % (index+1),Vector2(239,14),Vector2(68,35),24,Color(color,0.7))
	serial.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var card := CombatCard.new()
	card.managed_input = true
	card.allow_zoom_preview = false
	card.setup(id,definition,true)
	card.pivot_offset = Vector2(90,115)
	card.scale = Vector2.ONE * CARD_SCALE
	# Account for the centered scale pivot: the visible card starts at CARD_HOME.
	card.position = CARD_HOME + card.pivot_offset * (CARD_SCALE-1)
	slot.add_child(card)
	cards.append(card)
	var kind: String = {"attack":"攻击", "skill":"技能", "power":"能力"}.get(definition.get("type", ""), "卡牌")
	label(slot,kind+"  /  "+str(definition.get("archetype", "通用")),Vector2(22,451),Vector2(182,29),16,MUTED)
	var count := int(owned_counts.get(id,0))
	var owned := label(slot,"未拥有" if count == 0 else "已拥有 %d 张" % count,Vector2(198,451),Vector2(108,29),15,color if count == 0 else MUTED)
	owned.name = "OwnedCount%d" % (index+1)
	owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	owned_labels.append(owned)
	rect(slot,Vector2(22,488),Vector2(284,1),Color(color,0.26))
	var action := label(slot,"收下这张",Vector2(22,495),Vector2(210,30),18,color)
	action_labels.append(action)
	var keycap := label(slot,"[%d]  →" % (index+1),Vector2(243,496),Vector2(65,29),17,color)
	keycap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var b := Button.new()
	b.name = "RewardOption%d" % (index+1)
	b.position = slot.position
	b.size = SLOT_SIZE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = str(definition.get("name", ""))
	for mode in ["normal","pressed","hover","focus","disabled"]: b.add_theme_stylebox_override(mode,StyleBoxEmpty.new())
	b.pressed.connect(func(): request_pick(index))
	b.mouse_entered.connect(func(): hovered_index = index; refresh_active())
	b.mouse_exited.connect(func():
		if hovered_index == index: hovered_index = -1
		refresh_active())
	b.focus_entered.connect(func():
		focused_index = index
		refresh_active())
	b.focus_exited.connect(func():
		if focused_index == index: focused_index = -1
		refresh_active())
	add_child(b)
	option_buttons.append(b)
	card_tweens.append(null)

func play_entrance() -> void:
	entrance_running = true
	for i in option_slots.size():
		option_buttons[i].disabled = true
		option_buttons[i].mouse_filter = Control.MOUSE_FILTER_IGNORE
		option_buttons[i].focus_mode = Control.FOCUS_NONE
		# Composite text, card art and frame together, including fallback text cards.
		# These temporary surfaces never receive input or read back GPU pixels.
		var surface := SubViewport.new()
		surface.size = REVEAL_SIZE
		surface.transparent_bg = true
		surface.disable_3d = true
		surface.gui_disable_input = true
		surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(surface)
		option_slots[i].reparent(surface, false)
		option_slots[i].position = REVEAL_MARGIN
		entrance_surfaces.append(surface)
		var ink := ShaderMaterial.new()
		ink.shader = REVEAL_SHADER
		ink.set_shader_parameter("progress", 0.0)
		ink.set_shader_parameter("seed", float(i)*7.13)
		var image := texture_rect(self, surface.get_texture(), SLOT_ORIGIN+Vector2(i*SLOT_STEP,0)-REVEAL_MARGIN, Vector2(REVEAL_SIZE))
		image.material = ink
		entrance_images.append(image)
		entrance_materials.append(ink)
	entrance_tween = create_tween()
	entrance_tween.tween_method(update_entrance, 0.0, 1.0, ENTRANCE_DURATION)
	entrance_tween.tween_callback(finish_entrance)

func update_entrance(progress: float) -> void:
	for ink in entrance_materials: ink.set_shader_parameter("progress", progress)

func finish_entrance() -> void:
	entrance_running = false
	hovered_index = -1
	for i in option_slots.size():
		option_slots[i].reparent(self, false)
		option_slots[i].position = SLOT_ORIGIN+Vector2(i*SLOT_STEP,0)
		entrance_images[i].hide()
		entrance_images[i].queue_free()
		entrance_surfaces[i].queue_free()
		option_buttons[i].disabled = false
		option_buttons[i].mouse_filter = Control.MOUSE_FILTER_STOP
		option_buttons[i].focus_mode = Control.FOCUS_ALL
		if option_buttons[i].get_global_rect().has_point(get_global_mouse_position()): hovered_index = i
	entrance_images.clear()
	entrance_surfaces.clear()
	entrance_materials.clear()
	refresh_active()

func request_pick(index: int) -> void:
	# All pointer, keyboard and callback selection paths share the entrance lock.
	if entrance_running or not is_inside_tree() or index < 0 or index >= options.size(): return
	card_picked.emit(str(options[index]))

func _exit_tree() -> void:
	if entrance_tween and entrance_tween.is_valid(): entrance_tween.kill()

func frame_style(color: Color, active: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("1b2234") if active else Color("111725")
	box.border_color = Color(color,0.95 if active else 0.27)
	box.set_border_width_all(2 if active else 1)
	box.set_corner_radius_all(6)
	box.corner_radius_top_right = 22
	box.corner_radius_bottom_left = 22
	box.shadow_color = Color(color,0.18) if active else Color(0,0,0,0.38)
	box.shadow_size = 22 if active else 12
	return box

func refresh_active() -> void:
	if entrance_running: return
	# Keep physical hover while keyboard focus takes precedence. Mouse motion in
	# reward.gd releases focus, including movement within the same button.
	var next_index := focused_index if focused_index >= 0 else hovered_index
	if is_instance_valid(back_button) and back_button.has_focus(): next_index = -1
	if active_index == next_index: return
	active_index = next_index
	for i in option_slots.size():
		var active := i == active_index
		frames[i].add_theme_stylebox_override("panel",frame_style(rarity_colors[i],active))
		action_labels[i].text = "加入牌组  →" if active else "收下这张"
		glows[i].modulate.a = 1.0 if active else 0.65
		if card_tweens[i] and card_tweens[i].is_valid(): card_tweens[i].kill()
		var motion := create_tween().set_parallel(true)
		motion.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		motion.tween_property(cards[i],"position",CARD_HOME+Vector2(90,115)*(CARD_SCALE-1)+Vector2(0,-9 if active else 0),0.16)
		motion.tween_property(cards[i],"scale",Vector2.ONE*(CARD_SCALE+0.04 if active else CARD_SCALE),0.16)
		motion.tween_property(cards[i],"modulate:a",1.0 if active or active_index < 0 else 0.78,0.16)
		card_tweens[i] = motion
