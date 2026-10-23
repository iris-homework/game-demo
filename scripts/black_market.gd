extends DemoUI
## The illustration is scenery only. Prices, stock and transactions come from Game.
const GOLD := Color("f3cc85")
const STOCK_ORIGIN := Vector2(448,188)
const SLOT_STEP := Vector2(190,320)
const CARD_SCALE := 1.05
const BUY_OFFSET := Vector2(5,252)
const BUY_SIZE := Vector2(180,44)
var stock: Control
var modal: Control
var suspended: Array = []
var expected_revision := 0
var last_trigger: Button
var stock_caption: Label

func _ready() -> void:
	Game.ensure_black_market()
	# Keep the shopkeeper at the source illustration brightness.
	rect(self,Vector2.ZERO,Vector2(1440,900),INK)
	add_child(preload("res://scripts/black_market_art.gd").new())
	status_bar("黑市")
	panel(self,Vector2(430,94),Vector2(982,734),Color("090b12a8"),Color("49394d"))
	cut_panel(self,Vector2(28,96),Vector2(220,66),Color("100e19e8"),PINK,18)
	label(self,"黑 市",Vector2(49,103),Vector2(176,47),34,CREAM)
	label(self,"卡牌交易",Vector2(448,106),Vector2(280,44),30).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stock_caption = label(self,"",Vector2(930,106),Vector2(458,44),18,GOLD)
	stock_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stock_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rect(self,Vector2(448,166),Vector2(944,1),Color("674254"))
	rect(self,Vector2(448,165),Vector2(72,3),PINK)
	button(self,"← 离开黑市",Vector2(28,830),Vector2(244,48),Game.go_map).name = "return_map"
	refresh_stock()
	fade_in()

func refresh_stock() -> void:
	if is_instance_valid(stock):
		remove_child(stock)
		stock.queue_free()
	stock = Control.new()
	stock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stock)
	expected_revision = Game.revision
	var market: Dictionary = Game.black_market_state()
	var restock_day := int(market.get("restockDay",1))
	stock_caption.text = "下次补货：第 %d 天" % (4 if restock_day < 4 else 7) if restock_day < 7 else "下次补货：无（本周最后一批）"
	for i in market.get("slots",[]).size():
		var slot: Dictionary = market.slots[i]
		var origin := STOCK_ORIGIN + Vector2((i % 5) * SLOT_STEP.x,floori(float(i) / 5.0) * SLOT_STEP.y)
		var card := CombatCard.new()
		card.setup(str(i),Game.card_catalog[slot.cardId],true)
		card.position = origin
		card.pivot_offset = Vector2.ZERO
		card.scale = Vector2.ONE * CARD_SCALE
		stock.add_child(card)
		if slot.sold:
			card.modulate = Color(0.34,0.31,0.39,0.7)
			card.allow_zoom_preview = false
			var stamp := cut_panel(stock,origin+Vector2(6,98),Vector2(176,50),Color("120e19f2"),PINK,9)
			label(stamp,"已 售 罄",Vector2(0,5),Vector2(176,35),22,PINK).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var buy := button(stock,"已售罄" if slot.sold else "购买  %d" % int(slot.price),origin+BUY_OFFSET,BUY_SIZE,open_purchase.bind(i))
		buy.name = "buy_slot_%d" % i
		buy.add_theme_font_size_override("font_size",18)
		buy.disabled = slot.sold or int(Game.state.credits) < int(slot.price)
		buy.tooltip_text = "本次补货前不会再次上架" if slot.sold else "信用点不足" if buy.disabled else "购买后加入当前卡组"
		if not slot.sold:
			buy.icon = CREDIT_ICON
			buy.expand_icon = true
			buy.add_theme_constant_override("icon_max_width",20)
	var used: bool = market.get("soldCardUsed",false)
	var sell := cut_panel(stock,Vector2(1212,508),Vector2(181,242),Color("15121be8"),Color("55434f") if used else PINK,12)
	label(sell,"本批已出售" if used else "卡 牌 回 收",Vector2(10,157),Vector2(161,35),20,MUTED if used else CREAM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(sell,"◇",Vector2(10,67),Vector2(161,76),60,MUTED if used else PINK).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sell_button := button(stock,"已使用" if used else "选择要出售的牌",Vector2(1213,760),BUY_SIZE,open_sell_picker)
	sell_button.name = "sell_card"
	sell_button.add_theme_font_size_override("font_size",17)
	sell_button.disabled = used or Game.full_deck_ids().is_empty()
	refresh_hp()

func begin_modal(title: String) -> void:
	last_trigger = get_viewport().gui_get_focus_owner() as Button
	suspended.clear()
	for card in find_children("*","Control",true,false):
		if card is CombatCard: card.hide_zoom_preview()
	for b in find_children("*","Button",true,false):
		suspended.append([b,b.disabled,b.focus_mode])
		b.release_focus()
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
	modal = Control.new()
	modal.name = "market_modal"
	modal.size = Vector2(1440,900)
	modal.z_index = 90
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)
	rect(modal,Vector2.ZERO,Vector2(1440,900),Color("050710ed"))
	cut_panel(modal,Vector2(154,105),Vector2(1132,689),Color("10131e"),PINK,24)
	label(modal,title,Vector2(193,128),Vector2(900,52),32)
	var close := button(modal,"×",Vector2(1192,127),Vector2(52,45),close_modal)
	close.name = "close_market_modal"

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

func open_purchase(index: int) -> void:
	if is_instance_valid(modal) or Game.transition_locked or Game.battle_busy: return
	var market: Dictionary = Game.black_market_state()
	if index < 0 or index >= market.slots.size() or market.slots[index].sold: return
	var slot: Dictionary = market.slots[index]
	if int(Game.state.credits) < int(slot.price): return
	open_confirmation(slot.cardId, false, index)

func open_confirmation(card_id: String, selling: bool, index: int = -1) -> void:
	close_modal()
	expected_revision = Game.revision
	begin_modal("出售卡牌" if selling else "购买卡牌")
	var definition: Dictionary = Game.card_catalog.get(card_id,Game.reward_rules.cards.get(card_id,Game.prototype_rules.cards.get(card_id,{})))
	var card := CombatCard.new()
	card.managed_input = true
	card.allow_zoom_preview = false
	card.setup(card_id,definition,true)
	card.position = Vector2(267,244)
	card.pivot_offset = Vector2.ZERO
	card.scale = Vector2.ONE * 1.6
	modal.add_child(card)
	var price: int = Game.market_sell_price(card_id) if selling else int(Game.black_market_state().slots[index].price)
	label(modal,definition.get("name",card_id),Vector2(659,244),Vector2(535,68),35)
	label(modal,"回收价" if selling else "售价",Vector2(663,335),Vector2(490,34),19,MUTED)
	credit_icon(modal,Vector2(665,384),Vector2(36,36))
	label(modal,("+ " if selling else "")+str(price),Vector2(716,373),Vector2(419,61),40,GOLD)
	label(modal,"持有 %d  →  交易后 %d" % [int(Game.state.credits),int(Game.state.credits)+(price if selling else -price)],Vector2(663,455),Vector2(523,35),20,CYAN)
	label(modal,"此牌将从卡组移除一张。\n本次补货前不能再次出售。" if selling else "此牌将加入你的卡组。\n本格售罄，直到下次补货。",Vector2(663,514),Vector2(523,88),19,MUTED)
	var cancel := button(modal,"返回",Vector2(660,669),Vector2(166,53),close_modal)
	cancel.name = "cancel_trade"
	var confirm := button(modal,"确认出售" if selling else "确认购买",Vector2(852,669),Vector2(338,53),func(): complete_trade(card_id,selling,index),true)
	confirm.name = "confirm_trade"
	cancel.grab_focus()

func complete_trade(card_id: String, selling: bool, index: int) -> void:
	if selling: Game.sell_market_card(card_id,expected_revision)
	else: Game.buy_market_card(index,expected_revision)
	close_modal()
	refresh_stock()

func open_sell_picker() -> void:
	if is_instance_valid(modal) or Game.transition_locked or Game.battle_busy or Game.black_market_state().get("soldCardUsed",false): return
	begin_modal("选择一张卡牌出售")
	label(modal,"包括初始牌 · 同名牌只移除一张 · 选择后确认成交",Vector2(196,193),Vector2(1000,32),17,MUTED)
	var scroll := ScrollContainer.new()
	scroll.name = "sell_scroll"
	scroll.position = Vector2(192,246)
	scroll.size = Vector2(1058,462)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation",17)
	grid.add_theme_constant_override("v_separation",22)
	scroll.add_child(grid)
	var counts: Dictionary = Game.owned_card_counts()
	var ids: Array = counts.keys()
	ids.sort()
	for id in ids:
		var definition: Dictionary = Game.card_catalog.get(id,Game.reward_rules.cards.get(id,Game.prototype_rules.cards.get(id,{})))
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(155,267)
		grid.add_child(cell)
		var card := CombatCard.new()
		card.setup(id,definition,true)
		card.pivot_offset = Vector2.ZERO
		card.scale = Vector2.ONE * 0.85
		cell.add_child(card)
		label(cell,"持有 ×%d" % int(counts[id]),Vector2(0,198),Vector2(155,24),13,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var pick := button(cell,"出售 +%d" % Game.market_sell_price(id),Vector2(3,228),Vector2(149,36),open_confirmation.bind(id,true))
		pick.name = "sell_pick_"+id
		pick.add_theme_font_size_override("font_size",15)
		pick.disabled = Game.market_sell_price(id) <= 0
	var back := button(modal,"返回黑市  /  Esc",Vector2(976,730),Vector2(267,42),close_modal)
	back.grab_focus()

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
		var next := posmod(current + (-1 if event.shift_pressed else 1),buttons.size())
		buttons[next].grab_focus()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F1 or preload("res://scripts/card_console.gd").is_toggle_event(event):
		get_viewport().set_input_as_handled()
