extends DemoUI
## 城市总览地图：大幅等比底图 + 地点／任务标记 + 悬停预览与固定详情。
## 只读取 Game 的状态查询并调用既有流程接口，不在这里复制解锁规则。
##
## 供输入测试使用的可观察接口：
##   selected_id:String、preview:Control、detail:Control、markers:Dictionary、
##   map_rect:Rect2、get_marker_center(id)->Vector2、select_place(id)、
##   close_detail()、handle_escape()->bool；详情按钮命名为
##   enter_place／heal_place／event_<事件ID>，可用 find_child 查找。

const CANVAS := Vector2(1440.0, 900.0)
const HUD_HEIGHT := 76.0
const MARKER_HEIGHT := 72.0
const HOVER_DELAY := 0.2
const EDGE := 12.0
const MIN_GAP := 3.0
const MAX_NUDGE := 150.0
const MAP_FALLBACK_SIZE := Vector2(1671.0, 941.0)
const CARD_BOUNDS := Rect2(12.0, 82.0, 1416.0, 794.0)
const GOLD := Color("ffdb72")

## 治疗会触发 checkpoint 让整页重建；只在治疗前设置，新视图消费或失败时清空。
static var pending_selection_id := ""

var selected_id := ""
var preview: Control = null
var detail: Control = null
var markers := {}
var map_rect := Rect2()

var _hud_hp_fill: ColorRect
var _hud_hp_text: Label
var _hover_timer: Timer
var _hover_pending_id := ""
var _hovered_id := ""
var _week_dialog: AcceptDialog
var _leader_layer: Control
var _blank_hit: Control
var _pointer_seen := false
var _pointer_canvas := Vector2.ZERO
var _hover_started_us := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect(self, Vector2.ZERO, CANVAS, INK)
	set_process(true)
	_build_blank_hit()
	_build_map()
	_build_hud()
	_build_markers()
	_refresh_hud()
	if not Game.status_changed.is_connected(_refresh_hud):
		Game.status_changed.connect(_refresh_hud)
	_hover_timer = Timer.new()
	_hover_timer.one_shot = true
	_hover_timer.wait_time = HOVER_DELAY
	_hover_timer.timeout.connect(_on_hover_timeout)
	add_child(_hover_timer)
	_consume_pending_selection()

func _consume_pending_selection() -> void:
	if pending_selection_id.is_empty():
		return
	var id := pending_selection_id
	pending_selection_id = ""
	if Game.place_data(id).is_empty():
		return
	select_place(id)

# ---------------------------------------------------------------- 底图与 HUD

func _build_map() -> void:
	var texture: Texture2D = Game.texture("city_map")
	if texture == null:
		texture = MidnightMapAssets.map_texture()
	var source := MAP_FALLBACK_SIZE
	if texture != null and texture.get_width() > 0 and texture.get_height() > 0:
		source = Vector2(texture.get_size())
	var fit_scale := minf(CANVAS.x / source.x, CANVAS.y / source.y)
	var dimensions := source * fit_scale
	map_rect = Rect2((CANVAS - dimensions) * 0.5, dimensions)
	if texture != null:
		var view := TextureRect.new()
		view.name = "map_texture"
		view.texture = texture
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_SCALE
		view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		view.position = map_rect.position
		view.size = map_rect.size
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(view)
	else:
		panel(self, map_rect.position, map_rect.size, Color("0e1928"), Color("264256"))
		label(self, "城市地图插画待补", map_rect.position + Vector2(30.0, 30.0), Vector2(640.0, 44.0), 26, MUTED)
	rect(self, map_rect.position, map_rect.size, Color(0.02, 0.03, 0.05, 0.12))
	var edge := Color(0.24, 0.62, 0.72, 0.55)
	rect(self, map_rect.position, Vector2(map_rect.size.x, 1.0), edge)
	rect(self, map_rect.position + Vector2(0.0, map_rect.size.y - 1.0), Vector2(map_rect.size.x, 1.0), edge)
	rect(self, map_rect.position, Vector2(1.0, map_rect.size.y), edge)
	rect(self, map_rect.position + Vector2(map_rect.size.x - 1.0, 0.0), Vector2(1.0, map_rect.size.y), edge)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(0.02, 0.03, 0.05, 0.92), Color(0.02, 0.03, 0.05, 0.0)])
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0.0, 0.0)
	gradient_texture.fill_to = Vector2(0.0, 1.0)
	var shade := TextureRect.new()
	shade.texture = gradient_texture
	shade.position = Vector2.ZERO
	shade.size = Vector2(CANVAS.x, HUD_HEIGHT + 42.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

func _build_hud() -> void:
	rect(self, Vector2.ZERO, Vector2(CANVAS.x, HUD_HEIGHT), Color("070e19ee"))
	rect(self, Vector2(0.0, HUD_HEIGHT - 1.0), Vector2(CANVAS.x, 1.0), Color("2f6178"))
	label(self, Game.display_name("noren") + " / 城市总览", Vector2(24.0, 8.0), Vector2(320.0, 26.0), 19, CREAM)
	panel(self, Vector2(24.0, 46.0), Vector2(170.0, 12.0), Color("382333"), Color("805071"))
	_hud_hp_fill = rect(self, Vector2(26.0, 48.0), Vector2(166.0, 8.0), PINK)
	_hud_hp_text = label(self, "", Vector2(202.0, 34.0), Vector2(126.0, 28.0), 16, CREAM)
	label(self, "%d CR" % int(Game.state.get("credits", 0)), Vector2(340.0, 12.0), Vector2(116.0, 30.0), 20, CREAM)
	label(self, "信用点", Vector2(340.0, 44.0), Vector2(116.0, 20.0), 12, MUTED)
	var faction: String = {"": "自由佣兵", "company": "公司特遣部", "resistance": "革命军"}.get(Game.state.get("faction", ""), "自由佣兵")
	label(self, faction, Vector2(470.0, 12.0), Vector2(116.0, 30.0), 19, CYAN)
	label(self, "当前阵营", Vector2(470.0, 44.0), Vector2(116.0, 20.0), 12, MUTED)
	# Keep the date centered on the canvas, independent of the fields to its left.
	var day := clampi(int(Game.state.get("currentDay", 1)), 1, 7)
	var date_width := 238.0
	var date_x := (CANVAS.x - date_width) * 0.5
	var date_label := label(self, "第 %d 天" % day, Vector2(date_x, 8.0), Vector2(date_width, 26.0), 19, CYAN)
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rect(self, Vector2(date_x, 39.0), Vector2(date_width, 22.0), Color("456576"))
	rect(self, Vector2(date_x + 1.0, 40.0), Vector2(date_width - 2.0, 20.0), Color("0b1520"))
	for index in range(7):
		var x := date_x + 6.0 + float(index) * 33.0
		rect(self, Vector2(x, 45.0), Vector2(28.0, 10.0), CYAN if index < day else Color("253544"))
	button(self, "周次", Vector2(1096.0, 16.0), Vector2(140.0, 44.0), show_weeks).add_theme_font_size_override("font_size", 17)
	button(self, "菜单", Vector2(1248.0, 16.0), Vector2(140.0, 44.0), Game.menu)

func _refresh_hud() -> void:
	if not is_instance_valid(_hud_hp_fill) or not is_instance_valid(_hud_hp_text):
		return
	var maximum := maxi(int(Game.state.get("maxHp", 100)), 1)
	var hp := int(Game.state.get("currentHp", maximum))
	_hud_hp_fill.size.x = 166.0 * float(hp) / float(maximum)
	_hud_hp_text.text = "%d / %d" % [hp, maximum]

# ------------------------------------------------------------------- 标记

func _build_markers() -> void:
	var avatar_texture: Texture2D = Game.texture("noren")
	if avatar_texture == null:
		avatar_texture = MidnightMapAssets.portrait_texture()
	var specs: Array = []
	for place in Game.places:
		specs.append(_make_spec(place, avatar_texture))
	var by_id := {}
	for spec in specs:
		by_id[spec.id] = spec
	var order: Array = []
	for spec in specs:
		if spec.current or spec.target:
			order.append(spec.id)
	for spec in specs:
		if not (spec.current or spec.target):
			order.append(spec.id)
	var built := {}
	for spec in specs:
		var marker := MidnightMapMarker.new()
		marker.prepare({
			"id": spec.id, "height": MARKER_HEIGHT, "accent": spec.accent,
			"frame_tint": spec.frame_tint, "symbol_tint": spec.symbol_tint,
			"persistent_name": spec.persistent_name, "name": spec.name,
			"name_offset": spec.label_offset, "avatar": spec.avatar,
			"avatar_side": spec.avatar_side, "avatar_texture": spec.avatar_texture,
			"badges": spec.badges, "font": base_font, "tooltip": spec.tooltip,
		})
		marker.chosen.connect(_on_marker_chosen)
		marker.hover_changed.connect(_on_marker_hover)
		built[spec.id] = marker
	var placements := _resolve_placements(order, by_id, built)
	_leader_layer = Control.new()
	_leader_layer.name = "leader_layer"
	_leader_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_leader_layer)
	for id in order:
		_draw_leader(placements[id], by_id[id].accent)
	var add_order := order.duplicate()
	add_order.reverse()
	for id in add_order:
		var marker = built[id]
		add_child(marker)
		marker.set_tip(placements[id].tip)
		marker.fit_name(CARD_BOUNDS)
		markers[id] = marker

func _make_spec(place: Dictionary, avatar_texture: Texture2D) -> Dictionary:
	var id := str(place.get("id", ""))
	var state := _place_state(id)
	var main_events: Array = state.main_events if state.main_events is Array else []
	var optional_events: Array = state.optional_events if state.optional_events is Array else []
	var available: Array = state.available if state.available is Array else []
	var open := bool(state.open)
	var current := bool(state.current)
	var target := bool(state.target)
	var completed := bool(state.completed)
	var anchor := map_rect.position + Vector2(float(place.mapAnchor[0]), float(place.mapAnchor[1])) * map_rect.size
	var display: Dictionary = place.get("mapDisplay", {}) if place.get("mapDisplay", {}) is Dictionary else {}
	var offset := _vec2(display.get("offset", [0.0, 0.0]))
	var label_offset := _vec2(display.get("labelOffset", [0.0, 0.0]))
	var side := str(display.get("avatarSide", "left"))
	if side != "left" and side != "right":
		side = "left"
	var frame_width := MARKER_HEIGHT * MidnightMapAssets.FRAME_CANVAS.x / MidnightMapAssets.FRAME_CANVAS.y
	var tip_x := anchor.x + offset.x
	if side == "left" and tip_x - frame_width * 0.5 - MidnightMapMarker.AVATAR_HIT < CARD_BOUNDS.position.x:
		side = "right"
	elif side == "right" and tip_x + frame_width * 0.5 + MidnightMapMarker.AVATAR_HIT > CARD_BOUNDS.end.x:
		side = "left"
	var accent := Color("d8e4ef")
	var frame_tint := Color.WHITE
	var symbol_tint := Color.WHITE
	if not open:
		accent = Color("a7b6ca")
		symbol_tint = Color("a7b6ca")
	elif target:
		accent = GOLD
		symbol_tint = Color("fff0bf")
	elif current:
		accent = Color("7af4ff")
		symbol_tint = Color("d8fcff")
	elif not main_events.is_empty():
		accent = Color("83dce5")
	elif not optional_events.is_empty():
		accent = Color("a8e3eb")
	if open and completed and available.is_empty():
		symbol_tint = Color("d8e4ef")
	var badges: Array = []
	if not open:
		badges.append({"kind": "lock", "count": 0, "color": accent})
	else:
		if not main_events.is_empty():
			badges.append({"kind": "main", "count": main_events.size(), "color": accent})
		if not optional_events.is_empty():
			badges.append({"kind": "optional", "count": optional_events.size(), "color": accent})
		if badges.is_empty() and completed:
			badges.append({"kind": "check", "count": 0, "color": Color("9fd3dc")})
	var tooltip := str(place.get("description", ""))
	if not open:
		tooltip = str(place.get("lockHint", "尚未开放"))
	return {
		"id": id, "name": str(place.get("name", id)), "anchor": anchor, "offset": offset,
		"label_offset": label_offset, "avatar_side": side, "avatar": current,
		"current": current, "target": target, "persistent_name": current or target,
		"accent": accent, "frame_tint": frame_tint, "symbol_tint": symbol_tint,
		"badges": badges, "avatar_texture": avatar_texture, "tooltip": tooltip,
	}

func _resolve_placements(order: Array, by_id: Dictionary, built: Dictionary) -> Dictionary:
	var accepted: Array = []
	var result := {}
	for id in order:
		var spec: Dictionary = by_id[id]
		var marker = built[id]
		var base_tip: Vector2 = spec.anchor + spec.offset
		var moved := Vector2.ZERO
		var attempts := 0
		while attempts < 24:
			var rect: Rect2 = marker.hit_rect_for(base_tip + moved).grow(MIN_GAP * 0.5)
			var conflict = _first_conflict(rect, accepted)
			if conflict == null:
				break
			var other: Rect2 = conflict
			var overlap_x := minf(rect.end.x, other.end.x) - maxf(rect.position.x, other.position.x)
			var overlap_y := minf(rect.end.y, other.end.y) - maxf(rect.position.y, other.position.y)
			if overlap_x <= overlap_y:
				var direction_x := signf(rect.get_center().x - other.get_center().x)
				if is_zero_approx(direction_x):
					direction_x = 1.0
				moved.x += (overlap_x + MIN_GAP) * direction_x
			else:
				var direction_y := signf(rect.get_center().y - other.get_center().y)
				if is_zero_approx(direction_y):
					direction_y = 1.0
				moved.y += (overlap_y + MIN_GAP) * direction_y
			attempts += 1
			if moved.length() > MAX_NUDGE:
				moved = moved.normalized() * MAX_NUDGE
				break
		var final_tip := base_tip + moved
		accepted.append(marker.hit_rect_for(final_tip).grow(MIN_GAP * 0.5))
		result[id] = {"tip": final_tip, "anchor": spec.anchor}
	return result

func _first_conflict(rect: Rect2, accepted: Array):
	for other in accepted:
		if rect.intersects(other):
			return other
	return null

func _draw_leader(placement: Dictionary, accent: Color) -> void:
	var from: Vector2 = placement.anchor
	var to: Vector2 = placement.tip
	if from.distance_to(to) < 2.0:
		return
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = 1.2
	line.default_color = Color(accent, 0.5)
	line.antialiased = true
	_leader_layer.add_child(line)

# ------------------------------------------------------------------- 状态

func _place_state(id: String) -> Dictionary:
	# 直接共用 Game 的只读查询；视图不复制解锁、完成或目标规则。
	var raw = Game.map_place_state(id)
	if not (raw is Dictionary):
		return {
			"place": Game.place_data(id), "open": false, "available": [],
			"main_events": [], "optional_events": [], "current": false,
			"target": false, "completed": false, "services": [],
		}
	var state: Dictionary = raw
	for key in ["available", "main_events", "optional_events", "services"]:
		if not (state.get(key, null) is Array):
			state[key] = []
	if not state.has("place"):
		state["place"] = Game.place_data(id)
	return state

func _vec2(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

# ------------------------------------------------------------------- 选择

func _on_marker_chosen(id: String) -> void:
	select_place(id)

func select_place(id: String) -> void:
	if Game.transition_locked or Game.battle_busy:
		return
	if Game.place_data(id).is_empty():
		return
	selected_id = id
	_hover_pending_id = ""
	if is_instance_valid(_hover_timer):
		_hover_timer.stop()
	_hide_preview()
	_apply_selection_visuals()
	_build_detail(id)

func close_detail() -> void:
	if is_instance_valid(detail):
		remove_child(detail)
		detail.queue_free()
	detail = null
	selected_id = ""
	_apply_selection_visuals()

func _apply_selection_visuals() -> void:
	for id in markers:
		var marker = markers[id]
		if is_instance_valid(marker):
			marker.set_selected(id == selected_id)

func get_marker_center(id: String) -> Vector2:
	var marker = markers.get(id)
	if is_instance_valid(marker):
		return marker.get_click_point()
	return Vector2.ZERO

func get_detail_button(button_name: String) -> Button:
	if not is_instance_valid(detail):
		return null
	return detail.find_child(button_name, true, false) as Button

func _build_detail(id: String) -> void:
	if is_instance_valid(detail):
		remove_child(detail)
		detail.queue_free()
		detail = null
	var card := MidnightMapCard.new()
	card.name = "detail_card"
	card.z_index = 20
	detail = card
	add_child(card)
	card.setup_detail(_card_content(id), Callable(self, "_on_card_action"), base_font, self, CARD_BOUNDS)
	_place_card(card, id)

func _card_content(id: String) -> Dictionary:
	var place := Game.place_data(id)
	var state := _place_state(id)
	var open := bool(state.open)
	var available: Array = state.available if state.available is Array else []
	var main_events: Array = state.main_events if state.main_events is Array else []
	var optional_events: Array = state.optional_events if state.optional_events is Array else []
	var labels: Array = []
	if bool(state.current):
		labels.append("当前所在地")
	if bool(state.target):
		labels.append("下一步目标")
	if not open:
		labels.append("尚未开放")
	elif available.is_empty():
		labels.append("已完成" if bool(state.completed) else "暂无新事件")
	else:
		labels.append("可接委托")
	var accent := Color("c9d3e0")
	if not open:
		accent = Color("8f9fb8")
	elif bool(state.target):
		accent = GOLD
	elif bool(state.current):
		accent = CYAN
	elif not main_events.is_empty():
		accent = Color("4fc6d4")
	elif not optional_events.is_empty():
		accent = Color("3f9fb0")
	var rows: Array = []
	for event in available:
		rows.append({
			"id": str(event.get("id", "")), "title": str(event.get("title", "")),
			"description": str(event.get("description", "")),
			"optional": bool(event.get("optional", false)),
		})
	var services: Array = state.services if state.services is Array else []
	return {
		"id": id, "name": str(place.get("name", id)), "accent": accent,
		"state_label": " · ".join(labels), "description": str(place.get("description", "")),
		"lock_hint": str(place.get("lockHint", "")), "open": open,
		"events": rows, "has_service": not services.is_empty(),
	}

func _place_card(card: Control, id: String) -> void:
	var frame := Rect2(map_rect.get_center(), Vector2(MARKER_HEIGHT, MARKER_HEIGHT))
	var marker = markers.get(id)
	if is_instance_valid(marker):
		frame = marker.get_frame_rect()
	var card_size: Vector2 = card.size
	var x := frame.end.x + 14.0
	if x + card_size.x > CARD_BOUNDS.end.x:
		x = frame.position.x - card_size.x - 14.0
	x = clampf(x, CARD_BOUNDS.position.x, CARD_BOUNDS.end.x - card_size.x)
	var y := frame.get_center().y - card_size.y * 0.42
	y = clampf(y, CARD_BOUNDS.position.y, CARD_BOUNDS.end.y - card_size.y)
	card.position = Vector2(x, y)

func _on_card_action(kind: String, id: String) -> bool:
	if Game.transition_locked or Game.battle_busy:
		return false
	match kind:
		"enter":
			if not selected_id.is_empty():
				Game.visit(selected_id)
				return Game.page == "place"
		"heal":
			var place := selected_id
			if place.is_empty():
				return false
			pending_selection_id = place
			var healed := Game.heal_at(place)
			if not healed:
				pending_selection_id = ""
			return healed
		"event":
			if not id.is_empty():
				return Game.start_event(id)
		"close":
			close_detail()
			return true
	return false

# ------------------------------------------------------------------- 悬停

func _on_marker_hover(id: String, hovered: bool) -> void:
	# 每帧指针轮询给出权威结果；进入／离开信号只做即时提示，并先用实际指针位置复核，
	# 避免合成输入与系统事件交错时反复清除悬停、反复重置延迟。
	if hovered:
		if _pointer_seen and not _pointer_over_marker(id):
			return
		_set_hovered_marker(id)
		return
	if _hovered_id != id:
		return
	if _pointer_seen and _pointer_over_marker(id):
		return
	_set_hovered_marker("")

func _set_hovered_marker(id: String) -> void:
	if _hovered_id == id:
		return
	var previous := _hovered_id
	_hovered_id = id
	if not previous.is_empty():
		var old = markers.get(previous)
		if is_instance_valid(old):
			old.set_hovered(false)
	if id.is_empty():
		_hover_pending_id = ""
		if is_instance_valid(_hover_timer):
			_hover_timer.stop()
		_hide_preview()
		return
	if is_instance_valid(preview) and str(preview.get_meta("place_id", "")) != id:
		_hide_preview()
	var marker = markers.get(id)
	if is_instance_valid(marker):
		marker.set_hovered(true)
	_hover_pending_id = id
	_hover_started_us = Time.get_ticks_usec()
	if is_instance_valid(_hover_timer):
		_hover_timer.start(HOVER_DELAY)

func _on_hover_timeout() -> void:
	var id := _hover_pending_id
	var elapsed := float(Time.get_ticks_usec() - _hover_started_us) / 1000000.0
	if elapsed < HOVER_DELAY:
		# Timer 的首帧 delta 可能包含启动前的时间；以单调时钟保证实际悬停满 0.2 秒。
		_hover_timer.start(HOVER_DELAY - elapsed)
		return
	_hover_pending_id = ""
	if id.is_empty():
		return
	if is_instance_valid(detail):
		return
	if Game.transition_locked or Game.battle_busy:
		return
	_show_preview(id)

func _show_preview(id: String) -> void:
	_hide_preview()
	var card := MidnightMapCard.new()
	card.name = "preview_card"
	card.z_index = 18
	preview = card
	add_child(card)
	card.setup_preview(_card_content(id), base_font, CARD_BOUNDS)
	card.set_meta("place_id", id)
	card.set_meta("hover_delay_seconds", float(Time.get_ticks_usec() - _hover_started_us) / 1000000.0)
	_place_card(card, id)

func _hide_preview() -> void:
	if is_instance_valid(preview):
		remove_child(preview)
		preview.queue_free()
	preview = null

# ------------------------------------------------------------------- 输入

func _build_blank_hit() -> void:
	# 透明底层命中控件：地图空白点击在 GUI 阶段就被本页接管，
	# 不再依赖 _unhandled_input（上层主根 Control 会先消费空白 GUI 点击）。
	var hit := Control.new()
	hit.name = "map_blank_hit"
	hit.position = Vector2.ZERO
	hit.size = CANVAS
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.gui_input.connect(_on_blank_hit_input)
	add_child(hit)
	_blank_hit = hit

func _on_blank_hit_input(event: InputEvent) -> void:
	if Game.transition_locked or Game.battle_busy:
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	# 只有真正落在空白处才会到这里：marker、详情卡与 HUD 按钮都在上层先命中。
	if is_instance_valid(_blank_hit):
		_blank_hit.accept_event()
	if is_instance_valid(detail):
		close_detail()
	elif is_instance_valid(preview):
		_hide_preview()

func handle_escape() -> bool:
	if is_instance_valid(_week_dialog):
		_close_weeks()
		return true
	if is_instance_valid(detail):
		close_detail()
		return true
	if is_instance_valid(preview):
		_hide_preview()
		return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_track_pointer((event as InputEventMouse).position)
	if event is InputEventMouseMotion:
		_update_hover_from_pointer()

func _process(_delta: float) -> void:
	# 每帧轮询指针位置：mouse_entered／exited 漏发或抖动时悬停仍稳定；
	# 悬停延迟只在真正切换目标时重开，指针停在原地不会重置。
	_update_hover_from_pointer()

func _track_pointer(viewport_position: Vector2) -> void:
	_pointer_seen = true
	# Godot 在调用 _input 前已经把窗口事件转换为视口坐标；不要再逆变换缩放。
	_pointer_canvas = get_viewport().get_canvas_transform().affine_inverse() * viewport_position

func _pointer_point() -> Vector2:
	# 输入事件位置与各控件矩形同属画布坐标；还没有事件时才退回系统指针。
	if _pointer_seen:
		return _pointer_canvas
	return get_global_mouse_position()

func _marker_at(point: Vector2) -> String:
	for id in markers:
		var marker = markers[id]
		if is_instance_valid(marker) and marker.get_hit_rect().has_point(point):
			return id
	return ""

func _pointer_over_marker(id: String) -> bool:
	var marker = markers.get(id)
	if not is_instance_valid(marker):
		return false
	return marker.get_hit_rect().has_point(_pointer_point())

func _pointer_over_map_layer() -> bool:
	# 开发面板等上层控件盖住地图时不再更新悬停，避免从弹层下方穿透。
	var parent := get_parent()
	if parent == null:
		return true
	var children := parent.get_children()
	var index := children.find(self)
	var point := _pointer_point()
	for i in range(children.size()):
		var node = children[i]
		if node == self:
			continue
		var control := node as Control
		if control == null or not control.visible:
			continue
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if (i > index or control.z_index > z_index) and control.get_global_rect().has_point(point):
			return false
	return true

func _update_hover_from_pointer() -> void:
	if Game.transition_locked or Game.battle_busy:
		return
	if is_instance_valid(_week_dialog):
		return
	if not _pointer_over_map_layer():
		return
	var point := _pointer_point()
	if is_instance_valid(detail) and detail.get_global_rect().has_point(point):
		return
	if is_instance_valid(preview) and preview.get_global_rect().has_point(point):
		return
	_set_hovered_marker(_marker_at(point))

func _unhandled_input(event: InputEvent) -> void:
	if Game.transition_locked or Game.battle_busy:
		return
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var point := get_global_mouse_position()
	for id in markers:
		var marker = markers[id]
		if is_instance_valid(marker) and marker.get_hit_rect().has_point(point):
			return
	if is_instance_valid(detail):
		close_detail()
		get_viewport().set_input_as_handled()
	elif is_instance_valid(preview):
		_hide_preview()
		get_viewport().set_input_as_handled()

func show_weeks() -> void:
	if Game.transition_locked or Game.battle_busy:
		return
	if is_instance_valid(_week_dialog):
		return
	var dialog := AcceptDialog.new()
	dialog.name = "week_dialog"
	dialog.title = "周次档案"
	dialog.dialog_text = "第一周：%s / 第 %d 天\n\n第二周：内容待设计\n第三周：内容待设计\n\n时间不会因移动、对话或治疗自动推进。" % ["已完成" if Game.state.flags.get("week1Complete", false) else "进行中", int(Game.state.get("currentDay", 1))]
	dialog.ok_button_text = "返回城市"
	dialog.exclusive = true
	add_child(dialog)
	_week_dialog = dialog
	dialog.confirmed.connect(_close_weeks)
	dialog.canceled.connect(_close_weeks)
	dialog.popup_centered(Vector2i(590, 300))

func _close_weeks() -> void:
	if is_instance_valid(_week_dialog):
		_week_dialog.queue_free()
	_week_dialog = null
