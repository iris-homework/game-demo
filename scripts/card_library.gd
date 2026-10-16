extends DemoUI
## Global definition browser. Preview cards cannot be played or claimed.
var definitions: Array = []
var card_views: Array[CombatCard] = []
var scroll: ScrollContainer
var grid: GridContainer
var close_button: Button
var owned_only := true
var counter: Label

func _ready() -> void:
	definitions = Game.library_cards()
	# The catalogue occupies the full game canvas, with only a compact toolbar.
	rect(self,Vector2.ZERO,Vector2(1440,900),INK)
	rect(self,Vector2.ZERO,Vector2(1440,84),Color("131c27"))
	rect(self,Vector2(0,83),Vector2(1440,1),Color("345258"))
	rect(self,Vector2(28,82),Vector2(76,2),CYAN)
	label(self,"牌库",Vector2(28,18),Vector2(104,49),32)
	counter = label(self,"",Vector2(150,30),Vector2(200,30),16,CYAN)
	button(self,"已拥有",Vector2(365,22),Vector2(130,42),func(): owned_only = true; refresh_library()).add_theme_font_size_override("font_size",16)
	button(self,"全部卡牌",Vector2(515,22),Vector2(150,42),func(): owned_only = false; refresh_library()).add_theme_font_size_override("font_size",16)
	for i in 4:
		var rarity: String = ["C","B","A","S"][i]
		label(self,rarity,Vector2(737+i*56,31),Vector2(40,27),18,CombatCard.RARITY_COLORS[rarity])
	label(self,"滚轮浏览  ·  Esc 关闭",Vector2(1030,31),Vector2(299,29),16,MUTED)
	close_button = button(self,"×",Vector2(1354,18),Vector2(58,50),Game.menu)
	close_button.name = "close_library"
	close_button.add_theme_font_size_override("font_size",34)
	close_button.tooltip_text = "关闭牌库，返回主菜单（Esc）"
	refresh_library()
	if definitions.is_empty():
		var empty := label(self,"暂无卡牌",Vector2(220,461),Vector2(1000,55),32,MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.grab_focus()
	fade_in()

func refresh_library() -> void:
	if is_instance_valid(scroll):
		remove_child(scroll)
		scroll.queue_free()
	card_views.clear()
	var counts := Game.owned_card_counts()
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
		var amount := int(Game.owned_card_counts().get(definition.id, 0))
		var owned_label := label(slot,"拥有 ×%d" % amount if amount > 0 else "尚未获得",Vector2(4,235),Vector2(176,20),11,CREAM if amount > 0 else MUTED)
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
