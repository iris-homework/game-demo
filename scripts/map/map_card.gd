class_name MidnightMapCard
extends Control
## 地图浮动信息卡：只读悬停预览与可操作固定详情共用同一内容来源。
## 预览整卡 mouse_ignore，不抢地图事件；详情拦截点击与滚轮，不穿透到底图。
## 详情只把名称／状态固定在上方，完整简介与全部事件都在 detail_scroll 里，
## 长文不会被截断，也不会把事件按钮推出卡片；进入／治疗固定在 footer。

const CREAM := Color("f3ebde")
const MUTED := Color("aaa4b8")
const CYAN := Color("58e1eb")
const PINK := Color("f04b88")
const GOLD := Color("f2c14e")
const LOCKED := Color("8f9fb8")
const PANEL_FILL := Color("0b1422f5")
const PANEL_EDGE := Color("36546a")

const PAD := 16.0
const WIDTH_DETAIL := 388.0
const WIDTH_PREVIEW := 340.0
const BUTTON_HEIGHT := 46.0
const EVENT_SEPARATION := 14.0
const FOOTER_GAP := 8.0
const LIST_TAIL := 16.0
const PREVIEW_DESC_LINES := 5
const PREVIEW_EVENT_LINES := 2

var mode := "detail"
var card_width := WIDTH_DETAIL
var _content := {}
var _action := Callable()
var _font: Font
var _provider: Object
var _bounds := Rect2(Vector2(12.0, 82.0), Vector2(1416.0, 794.0))
var _detail_scroll: ScrollContainer = null
var _action_hits: Array = []
var _press_point := Vector2.ZERO
var _pressed_action := {}
var _dispatched_event := ""

func setup_detail(content: Dictionary, action: Callable, font: Font, provider: Object, bounds: Rect2) -> void:
	mode = "detail"
	_content = content
	_action = action
	_font = font
	_provider = provider
	_bounds = bounds
	card_width = WIDTH_DETAIL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func setup_preview(content: Dictionary, font: Font, bounds: Rect2) -> void:
	mode = "preview"
	_content = content
	_font = font
	_bounds = bounds
	card_width = WIDTH_PREVIEW
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func card_size() -> Vector2:
	return size

func _build() -> void:
	var inner_w := card_width - PAD * 2.0
	var accent: Color = _content.get("accent", CYAN)
	var max_h: float = maxf(240.0, _bounds.size.y - 24.0)
	var name_text := str(_content.get("name", ""))
	var state_text := str(_content.get("state_label", ""))
	var desc_text := str(_content.get("description", ""))
	var lock_text := str(_content.get("lock_hint", ""))
	var open := bool(_content.get("open", false))
	var events: Array = _content.get("events", [])
	var name_w := inner_w - (58.0 if mode == "detail" else 0.0)
	var name_h := _text_height(name_text, 24, name_w)
	var state_h := _text_height(state_text, 14, inner_w)
	if mode == "preview":
		_build_preview(accent, name_text, state_text, desc_text, lock_text, open, events, inner_w, max_h, name_h, state_h)
	else:
		_build_detail(accent, name_text, state_text, desc_text, lock_text, open, events, inner_w, max_h, name_h, state_h)

func _build_detail(accent: Color, name_text: String, state_text: String, desc_text: String, lock_text: String, open: bool, events: Array, inner_w: float, max_h: float, name_h: float, state_h: float) -> void:
	var has_heal := open and bool(_content.get("has_service", false))
	var has_enter := open
	var footer_h := 14.0
	if has_heal:
		footer_h += BUTTON_HEIGHT + 8.0
	if has_enter:
		footer_h += BUTTON_HEIGHT + 8.0
	var header_h := 14.0 + name_h + 2.0 + state_h + 10.0
	var content_w := inner_w - 16.0
	var body_content_h := _detail_body_height(desc_text, lock_text, open, events, content_w)
	var total := header_h + body_content_h + footer_h + FOOTER_GAP
	var height := clampf(total, 260.0, max_h)
	_apply_size(height)
	_build_bg()
	_build_header(accent, name_text, state_text, desc_text, lock_text, open, inner_w)
	# 底部操作区先占用固定高度，滚动区止于分隔带上方，内容不会压到 footer。
	var footer_top := maxf(height - footer_h, 0.0)
	var body_h := maxf(footer_top - FOOTER_GAP - header_h, 60.0)
	if header_h + body_h > footer_top:
		body_h = maxf(footer_top - header_h, 60.0)
	var scroll := ScrollContainer.new()
	scroll.name = "detail_scroll"
	scroll.position = Vector2(PAD, header_h)
	scroll.size = Vector2(card_width - PAD * 2.0, body_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.clip_contents = true
	# PASS：滚轮仍由滚动容器自己处理；未被按钮消费的点击会继续上抛给卡片做兜底。
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)
	_detail_scroll = scroll
	var list := VBoxContainer.new()
	list.name = "event_list"
	list.custom_minimum_size = Vector2(content_w, 0.0)
	list.add_theme_constant_override("separation", int(EVENT_SEPARATION))
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(list)
	if not desc_text.is_empty():
		var desc := _label_into(list, desc_text, 16, MUTED)
		desc.custom_minimum_size = Vector2(0.0, _text_height(desc_text, 16, content_w))
	if not open and not lock_text.is_empty():
		var lock_text_full := "尚未开放 · " + lock_text
		var lock := _label_into(list, lock_text_full, 15, LOCKED)
		lock.custom_minimum_size = Vector2(0.0, _text_height(lock_text_full, 15, content_w))
	if events.is_empty():
		var none := _label_into(list, "此地暂无新的事件。", 16, MUTED)
		none.custom_minimum_size = Vector2(0.0, 24.0)
		if bool(_content.get("has_service", false)):
			var hint := _label_into(list, "可以使用现有服务；进入地点查看区域。", 14, MUTED)
			hint.custom_minimum_size = Vector2(0.0, 22.0)
	else:
		var head := _label_into(list, "可用事件", 15, accent)
		head.custom_minimum_size = Vector2(0.0, 20.0)
		for event in events:
			_add_event_block(list, event, content_w)
	# 尾部留白：滚到最底时最后一个动作也不会贴住裁剪边缘与 footer。
	var tail := Control.new()
	tail.name = "list_tail_spacer"
	tail.custom_minimum_size = Vector2(0.0, LIST_TAIL)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(tail)
	# 分隔带：不透明底色盖住滚动内容可能溢出的部分，内容区与底部操作区明确分层。
	var strip := Panel.new()
	strip.name = "footer_strip"
	strip.position = Vector2(0.0, footer_top)
	strip.size = Vector2(card_width, maxf(height - footer_top, 0.0))
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip_style := StyleBoxFlat.new()
	strip_style.bg_color = PANEL_FILL
	strip_style.border_color = PANEL_EDGE
	strip_style.border_width_top = 1
	strip.add_theme_stylebox_override("panel", strip_style)
	add_child(strip)
	var footer_y := height - footer_h + 6.0
	if has_heal:
		_add_button("治疗 · 回复 30% 最大 HP", "heal_place", Rect2(PAD, footer_y, inner_w, BUTTON_HEIGHT), false, func(): _emit("heal", ""))
		footer_y += BUTTON_HEIGHT + 8.0
	if has_enter:
		_add_button("进入地点    →", "enter_place", Rect2(PAD, footer_y, inner_w, BUTTON_HEIGHT), false, func(): _emit("enter", ""))
	_add_button("关闭", "close_place", Rect2(card_width - PAD - 56.0, 12.0, 56.0, 24.0), false, func(): _emit("close", "")).add_theme_font_size_override("font_size", 12)

func _build_preview(accent: Color, name_text: String, state_text: String, desc_text: String, lock_text: String, open: bool, events: Array, inner_w: float, max_h: float, name_h: float, state_h: float) -> void:
	var desc_h := _text_height(desc_text, 16, inner_w, PREVIEW_DESC_LINES)
	var lock_h := 0.0
	if not open and not lock_text.is_empty():
		lock_h = _text_height("尚未开放 · " + lock_text, 15, inner_w, 3)
	var header_h := 14.0 + name_h + 2.0 + state_h + 8.0 + desc_h + 10.0
	if lock_h > 0.0:
		header_h += lock_h + 10.0
	var limit := minf(max_h, 400.0)
	limit = maxf(limit, header_h + 34.0)
	var budget := maxf(limit - header_h - 34.0, 0.0)
	var used := 0.0
	var rows: Array = []
	for event in events:
		var title_text := str(event.get("title", ""))
		var desc := str(event.get("description", ""))
		var title_h := _text_height(title_text, 16, inner_w)
		var row_desc_h := _text_height(desc, 14, inner_w, PREVIEW_EVENT_LINES)
		# tag 18px 与标题、说明之间的间距都要计入预算，避免多行溢出卡片。
		var row_h := 18.0 + title_h + 2.0 + row_desc_h + 8.0
		if used + row_h > budget:
			break
		rows.append({"event": event, "title_h": title_h, "desc_h": row_desc_h})
		used += row_h
	var height := minf(header_h + used + 34.0, limit)
	_apply_size(height)
	_build_bg()
	_build_header(accent, name_text, state_text, desc_text, lock_text, open, inner_w)
	var y := header_h
	if rows.is_empty():
		_label("此地暂无新的事件。", Vector2(PAD, y), Vector2(inner_w, 22.0), 15, MUTED)
	else:
		for row in rows:
			var event: Dictionary = row.event
			var optional := bool(event.get("optional", false))
			var tag_text := "可选事件" if optional else "主线任务"
			_label(tag_text, Vector2(PAD, y), Vector2(inner_w, 18.0), 12, CYAN if optional else PINK)
			y += 18.0
			_label(str(event.get("title", "")), Vector2(PAD, y), Vector2(inner_w, float(row.title_h)), 16, CREAM)
			y += float(row.title_h) + 2.0
			var desc := str(event.get("description", ""))
			if not desc.is_empty():
				var desc_label := _label(desc, Vector2(PAD, y), Vector2(inner_w, float(row.desc_h)), 14, MUTED)
				desc_label.max_lines_visible = PREVIEW_EVENT_LINES
				desc_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
				y += float(row.desc_h) + 8.0
			else:
				y += 8.0
	_label("点击标记固定详情", Vector2(PAD, height - 26.0), Vector2(inner_w, 20.0), 12, Color(MUTED, 0.85))

func _detail_body_height(desc_text: String, lock_text: String, open: bool, events: Array, width: float) -> float:
	# 按 VBox 的真实子项与间距计高，包含末尾留白，普通单任务卡不需要滚动按钮。
	var heights: Array[float] = []
	if not desc_text.is_empty():
		heights.append(_text_height(desc_text, 16, width))
	if not open and not lock_text.is_empty():
		heights.append(_text_height("尚未开放 · " + lock_text, 15, width))
	if events.is_empty():
		heights.append(24.0)
		if bool(_content.get("has_service", false)):
			heights.append(22.0)
	else:
		heights.append(20.0)
		for event in events:
			var row_h := 18.0 + _text_height(str(event.get("title", "")), 17, width) + BUTTON_HEIGHT + 8.0
			var description := str(event.get("description", ""))
			if not description.is_empty():
				row_h += _text_height(description, 15, width) + 4.0
			heights.append(row_h)
	heights.append(LIST_TAIL)
	var total := EVENT_SEPARATION * float(heights.size() - 1)
	for height in heights:
		total += height
	return total

func _add_event_block(list: VBoxContainer, event: Dictionary, width: float) -> void:
	var optional := bool(event.get("optional", false))
	var event_id := str(event.get("id", ""))
	var block := VBoxContainer.new()
	block.name = "event_block_" + event_id
	block.add_theme_constant_override("separation", 4)
	block.mouse_filter = Control.MOUSE_FILTER_PASS
	list.add_child(block)
	var tag := _label_into(block, "可选事件" if optional else "主线任务", 13, CYAN if optional else PINK)
	tag.custom_minimum_size = Vector2(0.0, 18.0)
	var title_text := str(event.get("title", event_id))
	var title := _label_into(block, title_text, 17, CREAM)
	title.custom_minimum_size = Vector2(0.0, _text_height(title_text, 17, width))
	var desc_text := str(event.get("description", ""))
	if not desc_text.is_empty():
		var desc := _label_into(block, desc_text, 15, MUTED)
		desc.custom_minimum_size = Vector2(0.0, _text_height(desc_text, 15, width))
	# 可见文案保持简短；内部事件 ID 只留在节点名里供输入测试查找。
	var button := _button_into(block, "开始事件" if optional else "开始任务", "event_" + event_id, BUTTON_HEIGHT, not optional, func(): _emit("event", event_id))
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	# 滚轮事件继续传给 detail_scroll（force_pass_scroll_events 默认开启），点击仍由按钮自己处理。
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.mouse_force_pass_scroll_events = true
	_action_hits.append({"node": button, "kind": "event", "id": event_id})

func _build_header(accent: Color, name_text: String, state_text: String, desc_text: String, lock_text: String, open: bool, inner_w: float) -> void:
	# 名称可用宽度在这里自行推导；固定详情为右侧关闭按钮留出空间。
	var name_w := inner_w - (58.0 if mode == "detail" else 0.0)
	var name_h := _text_height(name_text, 24, name_w)
	var bar := ColorRect.new()
	bar.color = accent
	bar.position = Vector2(PAD - 6.0, 14.0)
	bar.size = Vector2(3.0, name_h)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var y := 14.0
	_label(name_text, Vector2(PAD, y), Vector2(name_w, name_h), 24, CREAM)
	y += name_h + 2.0
	var state_h := _text_height(state_text, 14, inner_w)
	_label(state_text, Vector2(PAD, y), Vector2(inner_w, state_h), 14, accent)
	y += state_h + 8.0
	if mode == "preview":
		var desc_h := _text_height(desc_text, 16, inner_w, PREVIEW_DESC_LINES)
		var desc := _label(desc_text, Vector2(PAD, y), Vector2(inner_w, desc_h), 16, MUTED)
		desc.name = "place_description"
		desc.max_lines_visible = PREVIEW_DESC_LINES
		desc.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		y += desc_h + 10.0
		if not open and not lock_text.is_empty():
			var lock_text_full := "尚未开放 · " + lock_text
			_label(lock_text_full, Vector2(PAD, y), Vector2(inner_w, _text_height(lock_text_full, 15, inner_w, 3)), 15, LOCKED)

func _apply_size(height: float) -> void:
	size = Vector2(card_width, height)

func _build_bg() -> void:
	var bg := Panel.new()
	bg.name = "card_bg"
	bg.position = Vector2.ZERO
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_FILL
	style.border_color = PANEL_EDGE
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0.02, 0.04, 0.07, 0.6)
	style.shadow_size = 10
	bg.add_theme_stylebox_override("panel", style)
	add_child(bg)

func _label(text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = text
	node.position = pos
	node.size = dimensions
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.clip_text = true
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_constant_override("line_spacing", 0)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	# 加入主题树后 Label 的最小尺寸会重算；再次限定宽度，避免简介恢复成自然行宽。
	node.size = dimensions
	return node

func _label_into(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_constant_override("line_spacing", 0)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _add_button(text: String, node_name: String, area: Rect2, accent: bool, action: Callable) -> Button:
	var button := _make_button(text, node_name, accent, action)
	button.position = area.position
	button.size = area.size
	add_child(button)
	return button

func _button_into(parent: Node, text: String, node_name: String, height: float, accent: bool, action: Callable) -> Button:
	var button := _make_button(text, node_name, accent, action)
	button.custom_minimum_size = Vector2(0.0, height)
	parent.add_child(button)
	return button

func _make_button(text: String, node_name: String, accent: bool, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", CREAM)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	if _provider != null and _provider.has_method("button_style"):
		for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state_name, _provider.button_style(state_name, accent))
	button.pressed.connect(action)
	return button

func _emit(kind: String, id: String) -> void:
	# 按钮与滚动区命中兜底共用提交入口；旧卡销毁前不重复提交同一事件。
	if kind == "event":
		if not _dispatched_event.is_empty():
			return
		_dispatched_event = id
	if _action.is_valid():
		var accepted = _action.call(kind, id)
		if kind == "event" and accepted != true:
			_dispatched_event = ""

func _text_height(text: String, font_size: int, width: float, max_lines: int = -1) -> float:
	if text.is_empty():
		return float(font_size) * 1.2
	if _font == null:
		var estimate := maxf(1.0, ceilf(text.length() * font_size * 0.6 / maxf(width, 1.0)))
		if max_lines > 0:
			estimate = minf(estimate, float(max_lines))
		return float(font_size) * 1.35 * estimate
	# 与 Label.WORD_SMART 使用相同断行旗标；默认 Font 只按词断行，会低估无空格中文段落高度。
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var measured := _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, max_lines, flags)
	return maxf(measured.y, float(font_size) * 1.25)

func _gui_input(event: InputEvent) -> void:
	# 事件动作按钮位于滚动容器内；若命中测试只落到容器上、没有交给按钮，
	# 卡片用同一份矩形兜底分发。按钮自己命中时会 accept_event，卡片收不到释放事件，不会重复触发。
	if mode != "detail":
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_press_point = button.position
		_pressed_action = _action_at(get_global_transform() * button.position)
		accept_event()
		return
	var pressed_action: Dictionary = _pressed_action
	_pressed_action = {}
	if button.position.distance_to(_press_point) > 8.0:
		accept_event()
		return
	var action := _action_at(get_global_transform() * button.position)
	accept_event()
	if not action.is_empty() and action == pressed_action:
		_emit(str(action.get("kind", "")), str(action.get("id", "")))

func _scroll_rect() -> Rect2:
	if is_instance_valid(_detail_scroll):
		return _detail_scroll.get_global_rect()
	return Rect2()

func _action_at(global_point: Vector2) -> Dictionary:
	# 只兜底滚动区里可见的动作；footer 与卡片其他位置仍由各自控件处理。
	var area := _scroll_rect()
	if area.size.x <= 0.0 or not area.has_point(global_point):
		return {}
	for entry in _action_hits:
		var node: Control = entry.get("node")
		if not is_instance_valid(node):
			continue
		if node.get_global_rect().has_point(global_point):
			return entry
	return {}
