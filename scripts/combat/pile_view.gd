extends DemoUI
## Read-only card browser. The sorted copy never changes the combat piles.
signal closed
var model: CombatModel
var pile_title := ""
var displayed_uids: Array = []
var scroll: ScrollContainer
var grid: GridContainer
var close_button: Button

func setup(combat: CombatModel, title: String, contents: Array) -> void:
	model = combat
	pile_title = title
	displayed_uids = ordered_cards(combat, contents)

static func ordered_cards(combat: CombatModel, contents: Array) -> Array:
	var ranks: Dictionary = {}
	var index := 0
	for id in combat.card_catalog:
		ranks[id] = int(combat.card_catalog[id].get("sortOrder", index))
		index += 1
	var result := contents.duplicate()
	result.sort_custom(func(a, b):
		var a_id: String = combat.instances.get(a, "")
		var b_id: String = combat.instances.get(b, "")
		var a_rank: int = ranks.get(a_id, 2147483647)
		var b_rank: int = ranks.get(b_id, 2147483647)
		if a_rank != b_rank: return a_rank < b_rank
		if a_id != b_id: return a_id < b_id
		return str(a).naturalnocasecmp_to(str(b)) < 0)
	return result

func _ready() -> void:
	z_index = 70
	mouse_filter = Control.MOUSE_FILTER_STOP
	rect(self, Vector2.ZERO, Vector2(1440,900), Color("030810ee"))
	cut_panel(self, Vector2(64,34), Vector2(1312,828), INK, CREAM,28)
	var accent := CYAN if pile_title == "抽牌堆" else PINK
	rect(self, Vector2(102,70), Vector2(5,67), accent)
	label(self, pile_title, Vector2(122,68), Vector2(230,56), 36)
	label(self, "%02d 张卡牌" % displayed_uids.size(), Vector2(335,78), Vector2(240,43), 24, accent)
	label(self, "默认排序 · 不代表抽取顺序", Vector2(124,125), Vector2(690,31), 17, MUTED)
	close_button = button(self, "关闭  ×", Vector2(1190,78), Vector2(146,46), func(): closed.emit())
	rect(self, Vector2(102,165), Vector2(1234,1), Color("294156"))
	scroll = ScrollContainer.new()
	scroll.position = Vector2(102,174)
	scroll.size = Vector2(1236,592)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scroll)
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 10
	bar.add_theme_stylebox_override("scroll", scrollbar_style(Color("101f30")))
	bar.add_theme_stylebox_override("grabber", scrollbar_style(Color("3b697d")))
	bar.add_theme_stylebox_override("grabber_highlight", scrollbar_style(CYAN))
	bar.add_theme_stylebox_override("grabber_pressed", scrollbar_style(PINK))
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_"+side, 8)
	scroll.add_child(margin)
	grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(grid)
	for uid in displayed_uids:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(224,284)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(slot)
		var card := CombatCard.new()
		card.setup(uid, model.card(uid), true)
		card.position = Vector2(4,4)
		card.pivot_offset = Vector2.ZERO
		card.scale = Vector2(1.2,1.2)
		slot.add_child(card)
	if displayed_uids.is_empty():
		var empty_title := label(self, "牌堆为空", Vector2(370,365), Vector2(700,60), 32, CREAM)
		empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var empty_hint := label(self, "这里暂时没有卡牌", Vector2(370,432), Vector2(700,38), 20, MUTED)
		empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rect(self, Vector2(102,781), Vector2(1234,1), Color("294156"))
	label(self, "滚轮 / 触控板上下浏览 · Esc / 右键关闭", Vector2(112,807), Vector2(720,31), 16, MUTED)
	button(self, "返回战斗  →", Vector2(1100,797), Vector2(234,46), func(): closed.emit(), true)
	close_button.grab_focus()

func scrollbar_style(color: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(5)
	return result

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		if event.pressed and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
			closed.emit()
			return
		# Keep all battle shortcuts behind the modal; scrolling is handled here.
		if event.pressed:
			if event.keycode == KEY_PAGEDOWN: scroll.scroll_vertical += 450
			elif event.keycode == KEY_PAGEUP: scroll.scroll_vertical -= 450
			elif event.keycode == KEY_DOWN: scroll.scroll_vertical += 72
			elif event.keycode == KEY_UP: scroll.scroll_vertical -= 72
			elif event.keycode == KEY_HOME: scroll.scroll_vertical = 0
			elif event.keycode == KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		closed.emit()
