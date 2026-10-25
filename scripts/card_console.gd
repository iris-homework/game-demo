extends DemoUI
signal closed
var entry: LineEdit
var output: RichTextLabel
var history: Array[String] = []
var history_index := 0
var card_buttons: Dictionary = {}
var owned_labels: Dictionary = {}
var card_scroll: ScrollContainer

static func is_toggle_event(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_A and event.ctrl_pressed and event.shift_pressed and not event.alt_pressed and not event.meta_pressed

func _ready() -> void:
	z_index = 120
	mouse_filter = Control.MOUSE_FILTER_STOP
	rect(self, Vector2.ZERO, Vector2(1440,900), Color(0,0,0,0.86))
	panel(self, Vector2(90,60), Vector2(1260,780), INK, CYAN)
	label(self,"卡牌控制台",Vector2(122,78),Vector2(600,52),30)
	button(self,"关闭 / Ctrl+Shift+A",Vector2(1034,81),Vector2(280,42),func(): closed.emit())
	var hint := "点击卡牌添加 1 张 · 自动保存至自己的牌库 · 战斗中直接加入抽牌堆"
	if Game.state.is_empty(): hint = "全部卡牌 · 请先开始或继续委托，再点击加牌"
	elif Game.training_mode: hint = "点击卡牌加入本场抽牌堆 · 演练加牌仅本场有效"
	label(self,hint,Vector2(126,143),Vector2(1188,30),17,MUTED)
	build_card_list()
	output = RichTextLabel.new()
	output.position = Vector2(126,662)
	output.size = Vector2(1188,64)
	output.add_theme_font_size_override("normal_font_size",16)
	output.selection_enabled = true
	output.scroll_following = true
	add_child(output)
	output.text = "已显示全部 %d 种卡牌。每点击一次加入一张，可重复添加。\n下方仍可输入指令，输入 help 查看帮助。" % card_buttons.size()
	entry = LineEdit.new()
	entry.position = Vector2(126,752)
	entry.size = Vector2(1188,54)
	entry.placeholder_text = "可选指令：addcard 深度伤口 2 / kill / owned / help"
	entry.add_theme_font_size_override("font_size",20)
	entry.text_submitted.connect(submit)
	add_child(entry)
	entry.grab_focus()

func build_card_list() -> void:
	card_scroll = ScrollContainer.new()
	card_scroll.position = Vector2(126,190)
	card_scroll.size = Vector2(1188,452)
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(card_scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",5)
	card_scroll.add_child(grid)
	for definition in Game.library_cards():
		var id: String = definition.id
		var rarity := str(definition.get("rarity", "")).to_upper()
		var color: Color = CombatCard.RARITY_COLORS.get(rarity, CYAN)
		var item := Button.new()
		item.set_script(preload("res://scripts/combat/card_tooltip_button.gd"))
		item.definition = definition
		item.name = "add_" + id
		item.custom_minimum_size = Vector2(282,40)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		item.tooltip_text = "%s [%s] — 点击添加一张\n%s" % [definition.name,rarity,definition.get("description", "")]
		for state_name in ["normal","hover","pressed","focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color("263443") if state_name in ["hover","pressed"] else PANEL
			box.border_color = color if state_name != "normal" else color.darkened(0.55)
			box.set_border_width_all(1)
			item.add_theme_stylebox_override(state_name,box)
		item.pressed.connect(add_card.bind(id))
		grid.add_child(item)
		label(item,rarity,Vector2(12,5),Vector2(26,30),20,color)
		label(item,definition.name,Vector2(44,7),Vector2(154,28),17)
		var owned := label(item,"",Vector2(202,10),Vector2(72,24),13,MUTED)
		owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		card_buttons[id] = item
		owned_labels[id] = owned
	refresh_owned_counts()

func refresh_owned_counts() -> void:
	var counts: Dictionary = {} if Game.state.is_empty() else Game.owned_card_counts()
	for id in owned_labels:
		owned_labels[id].text = "已有 %d" % int(counts.get(id,0))

func add_card(id: String) -> void:
	output.append_text("\n" + Game.console_command("addcard %s 1" % id) + "\n")
	refresh_owned_counts()

func submit(command: String) -> void:
	if command.strip_edges().is_empty(): return
	history.append(command)
	history_index = history.size()
	var result := Game.console_command(command)
	output.append_text("\n> " + command + "\n" + result + "\n")
	refresh_owned_counts()
	entry.clear()
	entry.grab_focus()
	if command.strip_edges().to_lower() == "kill" and result.begins_with("已清除"):
		closed.emit()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE or is_toggle_event(event):
		get_viewport().set_input_as_handled()
		closed.emit()
	elif event.keycode in [KEY_UP, KEY_DOWN] and entry.has_focus():
		get_viewport().set_input_as_handled()
		history_index = clampi(history_index + (-1 if event.keycode == KEY_UP else 1), 0, history.size())
		entry.text = history[history_index] if history_index < history.size() else ""
		entry.caret_column = entry.text.length()
