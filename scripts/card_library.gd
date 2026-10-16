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

func setup_current_deck(combat: Dictionary = {}) -> void:
	current_deck_mode = true
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
	counter = label(self,"",Vector2(220 if current_deck_mode else 150,30),Vector2(200,30),16,CYAN)
	if current_deck_mode:
		label(self,deck_hint,Vector2(420,30),Vector2(310,30),16,MUTED)
	else:
		button(self,"已拥有",Vector2(365,22),Vector2(130,42),func(): owned_only = true; refresh_library()).add_theme_font_size_override("font_size",16)
		button(self,"全部卡牌",Vector2(515,22),Vector2(150,42),func(): owned_only = false; refresh_library()).add_theme_font_size_override("font_size",16)
	for i in 4:
		var rarity: String = ["C","B","A","S"][i]
		label(self,rarity,Vector2(737+i*56,31),Vector2(40,27),18,CombatCard.RARITY_COLORS[rarity])
	label(self,"滚轮浏览  ·  Esc 关闭",Vector2(1030,31),Vector2(299,29),16,MUTED)
	close_button = button(self,"×",Vector2(1354,18),Vector2(58,50),close_library)
	close_button.name = "close_library"
	close_button.add_theme_font_size_override("font_size",34)
	close_button.tooltip_text = "关闭牌库，返回原画面（Esc）" if current_deck_mode else "关闭牌库，返回主菜单（Esc）"
	refresh_library()
	if definitions.is_empty():
		var empty := label(self,"暂无卡牌",Vector2(220,461),Vector2(1000,55),32,MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.grab_focus()
	fade_in()

func close_library() -> void:
	if current_deck_mode: closed.emit()
	else: Game.menu()

func refresh_library() -> void:
	if is_instance_valid(scroll):
		remove_child(scroll)
		scroll.queue_free()
	card_views.clear()
	if current_deck_mode:
		definitions.clear()
		for id in display_counts:
			var definition: Dictionary = current_catalog.get(id, {}).duplicate(true)
			if definition.is_empty(): continue
			definition.id = id
			definitions.append(definition)
		definitions.sort_custom(func(a: Dictionary,b: Dictionary):
			var a_order := int(a.get("sortOrder",2147483647))
			var b_order := int(b.get("sortOrder",2147483647))
			return a_order < b_order if a_order != b_order else str(a.id).naturalnocasecmp_to(str(b.id)) < 0)
		var total := 0
		for count in display_counts.values(): total += int(count)
		counter.text = "%d 种 / %d 张" % [definitions.size(),total]
		build_grid()
		return
	display_counts = Game.owned_card_counts()
	var counts := display_counts
	definitions = Game.library_cards()
	if owned_only:
		definitions = definitions.filter(func(definition): return counts.has(definition.id))
		for id in counts:
			if not Game.card_catalog.has(id):
				var old: Dictionary = Game.reward_rules.cards.get(id, Game.prototype_rules.cards.get(id, {}))
				if not old.is_empty(): definitions.append(old)
	var total := 0
	for count in counts.values(): total += int(count)
	counter.text = "%d 种 / %d 张" % [definitions.size(),total] if owned_only else "%d 种卡牌" % definitions.size()
	build_grid()

func build_grid() -> void:
	scroll = ScrollContainer.new()
	scroll.position = Vector2(24,94)
	scroll.size = Vector2(1392,798)
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

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed(): return
	match event.keycode:
		KEY_PAGEDOWN: scroll.scroll_vertical += int(scroll.size.y - 32)
		KEY_PAGEUP: scroll.scroll_vertical -= int(scroll.size.y - 32)
		KEY_HOME: scroll.scroll_vertical = 0
		KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_: return
	get_viewport().set_input_as_handled()
