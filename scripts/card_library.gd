extends DemoUI
## Global definition browser. Preview cards cannot be played or claimed.
var definitions: Array = []
var card_views: Array[CombatCard] = []
var scroll: ScrollContainer
var grid: GridContainer
var close_button: Button

func _ready() -> void:
	definitions = Game.library_cards()
	# The catalogue occupies the full game canvas, with only a compact toolbar.
	rect(self,Vector2.ZERO,Vector2(1440,900),INK)
	rect(self,Vector2.ZERO,Vector2(1440,84),Color("131c27"))
	rect(self,Vector2(0,83),Vector2(1440,1),Color("345258"))
	rect(self,Vector2(28,82),Vector2(76,2),CYAN)
	label(self,"牌库",Vector2(28,18),Vector2(104,49),32)
	label(self,"全部卡牌  /  %d 种" % definitions.size(),Vector2(153,29),Vector2(450,30),18,CYAN)
	label(self,"滚轮浏览  ·  Esc 关闭",Vector2(1030,31),Vector2(299,29),16,MUTED)
	close_button = button(self,"×",Vector2(1354,18),Vector2(58,50),Game.menu)
	close_button.name = "close_library"
	close_button.add_theme_font_size_override("font_size",34)
	close_button.tooltip_text = "关闭牌库，返回主菜单（Esc）"
	build_grid()
	if definitions.is_empty():
		var empty := label(self,"暂无卡牌",Vector2(220,461),Vector2(1000,55),32,MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.grab_focus()
	fade_in()

func build_grid() -> void:
	scroll = ScrollContainer.new()
	scroll.position = Vector2(24,94)
	scroll.size = Vector2(1392,782)
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
		slot.custom_minimum_size = Vector2(184,244)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(slot)
		var card := CombatCard.new()
		card.setup(definition.id,definition,true)
		card.position = Vector2(2,4)
		card.pivot_offset = Vector2.ZERO
		slot.add_child(card)
		card_views.append(card)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed(): return
	match event.keycode:
		KEY_PAGEDOWN: scroll.scroll_vertical += int(scroll.size.y - 32)
		KEY_PAGEUP: scroll.scroll_vertical -= int(scroll.size.y - 32)
		KEY_HOME: scroll.scroll_vertical = 0
		KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_: return
	get_viewport().set_input_as_handled()
