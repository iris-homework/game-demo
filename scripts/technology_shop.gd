extends DemoUI
## Bright mall storefront. All ownership and payment remain in Game.
const TechnologyIcons = preload("res://scripts/technology_icons.gd")
const TEXT := Color("352d3b")
const SOFT := Color("756877")
const ROSE := Color("a7446a")
const EDGE := Color("d9cbd1")
const PAPER := Color("fffdf8f2")
const ORIGIN := Vector2(484,202)
const STEP := Vector2(304,302)
const TILE_SIZE := Vector2(288,282)
var stock: Control
var modal: Control
var suspended: Array = []
var last_trigger: Button
var expected_revision := 0

func _ready() -> void:
	rect(self,Vector2.ZERO,Vector2(1440,900),Color("eee7e0"))
	image_asset(self,"woss_mall_shop",Vector2.ZERO,Vector2(1440,900))
	status_bar("沃斯商场")
	panel(self,Vector2(28,98),Vector2(286,64),PAPER,EDGE)
	label(self,"沃 斯 商 场",Vector2(49,108),Vector2(248,46),31,TEXT)
	panel(self,Vector2(464,96),Vector2(948,716),Color("f5f0e9d9"),EDGE)
	label(self,"科技精选",Vector2(484,111),Vector2(460,45),30,TEXT)
	label(self,"战斗科技  /  六个展示位",Vector2(920,123),Vector2(472,28),17,SOFT).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rect(self,Vector2(484,174),Vector2(896,1),EDGE)
	rect(self,Vector2(484,173),Vector2(72,3),ROSE)
	shop_button(self,"← 离开商场",Vector2(28,830),Vector2(244,48),Game.go_map).name = "return_map"
	label(self,"购买后，在地图「科技配置」中携带",Vector2(744,837),Vector2(648,34),18,TEXT).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	refresh_stock()
	fade_in()

func shop_button(parent: Node, caption: String, pos: Vector2, dimensions: Vector2, action: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = caption
	b.position = pos
	b.size = dimensions
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size",19)
	b.add_theme_color_override("font_color",Color.WHITE if primary else TEXT)
	b.add_theme_color_override("font_hover_color",Color.WHITE if primary else ROSE)
	b.add_theme_color_override("font_pressed_color",Color.WHITE if primary else TEXT)
	b.add_theme_color_override("font_disabled_color",SOFT)
	for state_name in ["normal","hover","pressed","disabled","focus"]:
		var fill := ROSE if primary else Color("fffcf7")
		var border := ROSE if primary else EDGE
		if state_name == "hover": fill = Color("ba507b") if primary else Color("f5e7ee")
		if state_name == "pressed": fill = Color("863653") if primary else Color("eadbe2")
		if state_name == "disabled":
			fill = Color("e9e2e3")
			border = EDGE
		if state_name == "focus":
			fill = Color.TRANSPARENT
			border = Color("483446")
		var frame := style(fill,border,2 if state_name == "focus" else 1)
		frame.border_width_left = 2 if state_name == "focus" else 1
		b.add_theme_stylebox_override(state_name,frame)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func icon(parent: Node, id: String, pos: Vector2, dimensions: Vector2) -> TextureRect:
	return TechnologyIcons.create(parent,id,pos,dimensions)

func refresh_stock() -> void:
	if is_instance_valid(stock):
		remove_child(stock)
		stock.queue_free()
	stock = Control.new()
	stock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stock)
	expected_revision = Game.revision
	var offers: Array = Game.technology_shop_offers()
	for i in 6:
		var origin := ORIGIN + Vector2((i%3)*STEP.x,floori(float(i)/3.0)*STEP.y)
		var tile := panel(stock,origin,TILE_SIZE,PAPER,EDGE)
		tile.name = "technology_tile_%d" % i
		label(tile,"TECH / %02d" % (i+1),Vector2(17,11),Vector2(166,24),12,SOFT)
		if i >= offers.size():
			label(tile,"—",Vector2(20,85),Vector2(248,50),32,EDGE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label(tile,"暂未上架",Vector2(20,151),Vector2(248,35),20,SOFT).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			continue
		var offer: Dictionary = offers[i]
		var definition: Dictionary = Game.cyberware_definition(offer.id)
		var owned: bool = offer.id in Game.owned_cyberware_ids()
		label(tile,"已拥有" if owned else "被动科技" if CombatModel.is_passive_cyberware(definition) else "主动科技",Vector2(190,11),Vector2(80,24),12,ROSE).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		icon(tile,offer.id,Vector2(88,38),Vector2(112,92))
		label(tile,str(definition.name),Vector2(16,132),Vector2(256,30),22,TEXT).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label(tile,str(definition.description),Vector2(20,166),Vector2(248,48),14,SOFT).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label(tile,TechnologyIcons.activation_label(definition),Vector2(20,216),Vector2(248,20),12,ROSE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var buy := shop_button(stock,("已拥有  %d 信用点" if owned else "购买  %d 信用点") % int(offer.price),origin+Vector2(14,238),Vector2(260,34),open_purchase.bind(i),not owned)
		buy.name = "buy_slot_%d" % i
		buy.add_theme_font_size_override("font_size",16)
		buy.disabled = owned or int(Game.state.credits) < int(offer.price)
		buy.tooltip_text = "已加入已有科技，可在地图配置携带" if owned else "信用点不足" if buy.disabled else "查看详情并确认购买"
	refresh_hp()

func open_purchase(index: int) -> void:
	if is_instance_valid(modal) or Game.transition_locked or Game.battle_busy: return
	var offers: Array = Game.technology_shop_offers()
	if index < 0 or index >= offers.size(): return
	var offer: Dictionary = offers[index]
	if offer.id in Game.owned_cyberware_ids() or int(Game.state.credits) < int(offer.price): return
	var definition: Dictionary = Game.cyberware_definition(offer.id)
	expected_revision = Game.revision
	last_trigger = get_viewport().gui_get_focus_owner() as Button
	suspended.clear()
	for b in find_children("*","Button",true,false):
		suspended.append([b,b.disabled,b.focus_mode])
		b.release_focus()
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
	modal = Control.new()
	modal.name = "shop_modal"
	modal.size = Vector2(1440,900)
	modal.z_index = 90
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)
	rect(modal,Vector2.ZERO,Vector2(1440,900),Color("29212d9e"))
	panel(modal,Vector2(330,205),Vector2(780,490),Color("fffaf5"),ROSE)
	label(modal,"确认购买",Vector2(370,230),Vector2(600,44),28,TEXT)
	icon(modal,offer.id,Vector2(379,330),Vector2(174,174))
	label(modal,str(definition.name),Vector2(594,311),Vector2(466,44),28,TEXT)
	label(modal,str(definition.description),Vector2(594,370),Vector2(466,65),20,SOFT)
	label(modal,TechnologyIcons.activation_label(definition),Vector2(594,442),Vector2(466,30),17,ROSE)
	label(modal,"%d 信用点" % int(offer.price),Vector2(594,486),Vector2(466,42),28,ROSE)
	label(modal,"余额 %d → %d  ·  购买后请到地图配置携带" % [int(Game.state.credits),int(Game.state.credits)-int(offer.price)],Vector2(370,553),Vector2(700,31),17,SOFT)
	var cancel := shop_button(modal,"取消",Vector2(370,615),Vector2(195,48),close_modal)
	cancel.name = "cancel_trade"
	for color_name in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		cancel.add_theme_color_override(color_name,ROSE)
	for state_name in ["normal","hover","pressed"]:
		var cancel_frame := style(Color("f5e7ee"),Color("483446"))
		cancel_frame.border_width_left = 1
		cancel.add_theme_stylebox_override(state_name,cancel_frame)
	var confirm := shop_button(modal,"确认购买",Vector2(589,615),Vector2(481,48),complete_trade.bind(index),true)
	confirm.name = "confirm_trade"
	cancel.grab_focus()

func complete_trade(index: int) -> void:
	Game.buy_shop_technology(index,expected_revision)
	close_modal()
	refresh_stock()
	var trigger := stock.get_node_or_null("buy_slot_%d" % index) as Button
	if is_instance_valid(trigger) and not trigger.disabled: trigger.grab_focus()
	else: get_node("return_map").grab_focus()

func close_modal() -> void:
	if not is_instance_valid(modal): return
	get_viewport().gui_release_focus()
	remove_child(modal)
	modal.queue_free()
	modal = null
	for item in suspended:
		if is_instance_valid(item[0]):
			item[0].disabled = item[1]
			item[0].focus_mode = item[2]
	suspended.clear()
	if is_instance_valid(last_trigger): last_trigger.grab_focus()

func handle_escape() -> bool:
	if is_instance_valid(modal): close_modal()
	else: Game.go_map()
	return true

func _input(event: InputEvent) -> void:
	if not is_instance_valid(modal) or not event is InputEventKey or not event.pressed: return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_modal()
	elif event.keycode == KEY_TAB:
		var buttons: Array = modal.find_children("*","Button",true,false).filter(func(b): return not b.disabled and b.focus_mode != Control.FOCUS_NONE)
		if buttons.is_empty(): return
		var current := buttons.find(get_viewport().gui_get_focus_owner())
		buttons[posmod(current+(-1 if event.shift_pressed else 1),buttons.size())].grab_focus()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F1 or preload("res://scripts/card_console.gd").is_toggle_event(event):
		get_viewport().set_input_as_handled()
