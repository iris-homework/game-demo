extends DemoUI
## Global definition browser. Preview cards cannot be played or claimed.
signal closed
var definitions: Array = []
var card_views: Array[CombatCard] = []
var scroll: ScrollContainer
var grid: GridContainer
var close_button: Button
var owned_only := true
var counter: Label
var current_deck_mode := false
var display_counts: Dictionary = {}
var current_catalog: Dictionary = {}
var deck_hint := ""
const FILTER_VALUES := {
	"rarity": ["all", "C", "B", "A", "S"],
	"cost": ["all", "0", "1", "2", "3+"],
	"type": ["all", "attack", "skill", "power"]
}
var filters := {"rarity":"all", "cost":"all", "type":"all"}
var filter_buttons: Dictionary = {}
var scope_buttons: Dictionary = {}
var clear_filter_button: Button
var empty_state: Control

func setup_current_deck(combat: Dictionary = {}) -> void:
	current_deck_mode = true
	display_counts.clear()
	if combat.is_empty():
		display_counts = Game.owned_card_counts()
		current_catalog = Game.prototype_rules.get("cards", {}).duplicate(true)
		current_catalog.merge(Game.reward_rules.get("cards", {}), true)
		current_catalog.merge(Game.card_catalog, true)
		deck_hint = "当前拥有 · 同名卡合并显示"
	else:
		# Use this battle's frozen definitions and all instances, including exhausted cards.
		current_catalog = combat.get("cardCatalog", {}).duplicate(true)
		for id in combat.get("instances", {}).values():
			display_counts[id] = int(display_counts.get(id,0)) + 1
		deck_hint = "本场完整卡组 · 包含所有牌区"

func _ready() -> void:
	if current_deck_mode:
		z_index = 115
		mouse_filter = Control.MOUSE_FILTER_STOP
	definitions = Game.library_cards()
	# The catalogue occupies the full game canvas, with only a compact toolbar.
	rect(self,Vector2.ZERO,Vector2(1440,900),INK)
	rect(self,Vector2.ZERO,Vector2(1440,84),Color("131c27"))
	rect(self,Vector2(0,83),Vector2(1440,1),Color("345258"))
	rect(self,Vector2(28,82),Vector2(76,2),CYAN)
	label(self,"当前卡组" if current_deck_mode else "牌库",Vector2(28,18),Vector2(180 if current_deck_mode else 104,49),32)
	counter = label(self,"",Vector2(220 if current_deck_mode else 150,30),Vector2(280,30),16,CYAN)
	if current_deck_mode:
		label(self,deck_hint,Vector2(560,30),Vector2(400,30),16,MUTED)
	else:
		var owned_button := button(self,"已拥有",Vector2(460,22),Vector2(120,42),func(): set_scope(true))
		owned_button.name = "scope_owned"
		owned_button.toggle_mode = true
		owned_button.add_theme_font_size_override("font_size",16)
		scope_buttons["owned"] = owned_button
		var all_button := button(self,"全部卡牌",Vector2(600,22),Vector2(150,42),func(): set_scope(false))
		all_button.name = "scope_all"
		all_button.toggle_mode = true
		all_button.add_theme_font_size_override("font_size",16)
		scope_buttons["all"] = all_button
	label(self,"滚轮浏览  ·  Esc 关闭",Vector2(1030,31),Vector2(299,29),16,MUTED)
	close_button = button(self,"×",Vector2(1354,18),Vector2(58,50),close_library)
	close_button.name = "close_library"
	close_button.add_theme_font_size_override("font_size",34)
	close_button.tooltip_text = "关闭牌库，返回原画面（Esc）" if current_deck_mode else "关闭牌库，返回主菜单（Esc）"
	build_filters()
	refresh_library()
	close_button.grab_focus()
	fade_in()

func close_library() -> void:
	if current_deck_mode: closed.emit()
	else: Game.menu()

func build_filters() -> void:
	rect(self,Vector2(0,84),Vector2(1440,66),Color("101720"))
	rect(self,Vector2(24,149),Vector2(1392,1),Color("2b3e4b"))
	label(self,"品级",Vector2(28,105),Vector2(46,26),16,MUTED)
	add_filter_group("rarity",Vector2(82,101),["全部","C","B","A","S"],[56,42,42,42,42])
	rect(self,Vector2(357,98),Vector2(1,38),Color("2b3e4b"))
	label(self,"基础费用",Vector2(382,105),Vector2(80,26),16,MUTED)
	add_filter_group("cost",Vector2(470,101),["全部","0","1","2","3+"],[56,42,42,42,48])
	rect(self,Vector2(750,98),Vector2(1,38),Color("2b3e4b"))
	label(self,"类型",Vector2(772,105),Vector2(46,26),16,MUTED)
	add_filter_group("type",Vector2(826,101),["全部","攻击","技能","能力"],[56,64,64,64])
	clear_filter_button = button(self,"清除筛选",Vector2(1200,101),Vector2(210,36),clear_filters)
	clear_filter_button.name = "clear_filters"
	clear_filter_button.add_theme_font_size_override("font_size",15)
	clear_filter_button.tooltip_text = "清除品级、基础费用和类型筛选，保留当前查看范围。"

func add_filter_group(kind: String, origin: Vector2, captions: Array, widths: Array) -> void:
	filter_buttons[kind] = {}
	var x := origin.x
	for i in FILTER_VALUES[kind].size():
		var value: String = FILTER_VALUES[kind][i]
		var option := button(self,captions[i],Vector2(x,origin.y),Vector2(widths[i],36),func(): set_filter(kind,value))
		option.name = "filter_%s_%s" % [kind,value]
		option.toggle_mode = true
		option.set("corner_marks",false)
		option.set_meta("selection_size",Vector2(widths[i],36))
		option.add_theme_font_size_override("font_size",15)
		filter_buttons[kind][value] = option
		x += float(widths[i])+6

func set_filter(kind: String, value: String) -> void:
	if not FILTER_VALUES.has(kind) or not value in FILTER_VALUES[kind]: return
	if filters[kind] == value:
		refresh_filter_buttons()
		return
	filters[kind] = value
	if is_instance_valid(counter): refresh_library()

func clear_filters() -> void:
	for kind in filters: filters[kind] = "all"
	if is_instance_valid(counter): refresh_library()

func set_scope(show_owned: bool) -> void:
	owned_only = show_owned
	if is_instance_valid(counter): refresh_library()

func has_active_filters() -> bool:
	return filters.rarity != "all" or filters.cost != "all" or filters.type != "all"

func matches_filters(definition: Dictionary) -> bool:
	if filters.rarity != "all" and str(definition.get("rarity","")).to_upper() != filters.rarity: return false
	if filters.type != "all" and str(definition.get("type","")) != filters.type: return false
	if filters.cost != "all":
		# Classify the displayed definition, including frozen battle and legacy cards.
		var base_cost := int(definition.get("cost",0)) if definition.get("cost") != null else 0
		if filters.cost == "3+":
			if base_cost < 3: return false
		elif base_cost != int(filters.cost): return false
	return true

func refresh_filter_buttons() -> void:
	for kind in filter_buttons:
		for value in filter_buttons[kind]:
			var tint: Color = CombatCard.RARITY_COLORS.get(value,CYAN) if kind == "rarity" else CYAN
			style_selection(filter_buttons[kind][value],filters[kind] == value,tint)
	for scope in scope_buttons:
		style_selection(scope_buttons[scope],owned_only if scope == "owned" else not owned_only,CYAN)
	if is_instance_valid(clear_filter_button): clear_filter_button.disabled = not has_active_filters()

func style_selection(option: Button, active: bool, tint: Color) -> void:
	option.set_pressed_no_signal(active)
	for state_name in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(4)
		box.set_border_width_all(2 if active else 1)
		box.border_color = tint if active or state_name in ["hover","focus"] else tint.darkened(0.65)
		box.bg_color = Color.TRANSPARENT if state_name == "focus" else (tint.darkened(0.65) if active else Color("151f2b"))
		if state_name == "hover" or state_name == "hover_pressed": box.bg_color = box.bg_color.lightened(0.08)
		box.content_margin_left = 6
		box.content_margin_right = 6
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		option.add_theme_stylebox_override(state_name,box)
	for color_name in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color"]:
		option.add_theme_color_override(color_name,CREAM if active else tint)
	if option.has_meta("selection_size"): option.size = option.get_meta("selection_size")
	option.queue_redraw()

func refresh_library() -> void:
	if is_instance_valid(scroll):
		remove_child(scroll)
		scroll.queue_free()
	if is_instance_valid(empty_state):
		remove_child(empty_state)
		empty_state.queue_free()
		empty_state = null
	card_views.clear()
	if current_deck_mode:
		definitions.clear()
		for id in display_counts:
			var definition: Dictionary = current_catalog.get(id, {}).duplicate(true)
			if definition.is_empty(): continue
			definition.id = id
			definitions.append(definition)
		definitions.sort_custom(Game.card_display_before)
	else:
		display_counts = Game.owned_card_counts()
		definitions = Game.library_cards()
		if owned_only:
			definitions = definitions.filter(func(definition): return display_counts.has(definition.id))
			for id in display_counts:
				if not Game.card_catalog.has(id):
					var old: Dictionary = Game.reward_rules.cards.get(id, Game.prototype_rules.cards.get(id, {})).duplicate(true)
					if not old.is_empty():
						old.id = id
						definitions.append(old)
			definitions.sort_custom(Game.card_display_before)
	var total_types := definitions.size()
	var total := 0
	for count in display_counts.values(): total += int(count)
	definitions = definitions.filter(matches_filters)
	if has_active_filters():
		var matched_total := 0
		for definition in definitions: matched_total += int(display_counts.get(definition.id,0))
		counter.text = "%d / %d 种 · %s %d 张" % [definitions.size(),total_types,"卡组" if current_deck_mode else "拥有",matched_total]
	else:
		counter.text = "%d 种 / %d 张" % [definitions.size(),total] if current_deck_mode or owned_only else "%d 种卡牌" % definitions.size()
	refresh_filter_buttons()
	build_grid()

func build_grid() -> void:
	scroll = ScrollContainer.new()
	scroll.position = Vector2(24,158)
	scroll.size = Vector2(1392,734)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scroll)
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 10
	for mode in ["scroll","grabber","grabber_highlight","grabber_pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("14272f") if mode == "scroll" else (CYAN if mode == "grabber_highlight" else Color("53898c"))
		box.set_corner_radius_all(5)
		bar.add_theme_stylebox_override(mode,box)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,8)
	scroll.add_child(margin)
	grid = GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(grid)
	for definition in definitions:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(184,250)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(slot)
		var card := CombatCard.new()
		card.setup(definition.id,definition,true)
		card.position = Vector2(2,4)
		card.pivot_offset = Vector2.ZERO
		slot.add_child(card)
		card_views.append(card)
		var amount := int(display_counts.get(definition.id, 0))
		var amount_text := ("卡组内 ×%d" if current_deck_mode else "拥有 ×%d") % amount if amount > 0 else "尚未获得"
		var owned_label := label(slot,amount_text,Vector2(4,235),Vector2(176,20),11,CREAM if amount > 0 else MUTED)
		owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if definitions.is_empty():
		empty_state = Control.new()
		empty_state.name = "empty_state"
		empty_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(empty_state)
		var empty_title := label(empty_state,"没有符合条件的卡牌" if has_active_filters() else "暂无卡牌",Vector2(220,415),Vector2(1000,55),30,MUTED)
		empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var empty_hint := label(empty_state,"试试其他分类，或点击「清除筛选」恢复。" if has_active_filters() else "已拥有的卡牌会显示在这里。",Vector2(220,480),Vector2(1000,34),18,MUTED)
		empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed(): return
	match event.keycode:
		KEY_PAGEDOWN: scroll.scroll_vertical += int(scroll.size.y - 32)
		KEY_PAGEUP: scroll.scroll_vertical -= int(scroll.size.y - 32)
		KEY_HOME: scroll.scroll_vertical = 0
		KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_: return
	get_viewport().set_input_as_handled()
