extends DemoUI
## 城市总览地图：大幅等比底图 + 地点／任务标记 + 悬停提亮与点击详情。
## 只读取 Game 的状态查询并调用既有流程接口，不在这里复制解锁规则。
##
## 供输入测试使用的可观察接口：
##   selected_id:String、detail:Control、markers:Dictionary、
##   map_rect:Rect2、get_marker_center(id)->Vector2、select_place(id)、
##   close_detail()、handle_escape()->bool；详情按钮命名为
##   enter_place／heal_place／event_<事件ID>，可用 find_child 查找。

const CANVAS := Vector2(1440.0, 900.0)
const HUD_HEIGHT := 76.0
const MARKER_HEIGHT := 72.0
const EDGE := 12.0
const MIN_GAP := 3.0
const MAX_NUDGE := 150.0
const MAP_FALLBACK_SIZE := Vector2(1671.0, 941.0)
const CARD_BOUNDS := Rect2(12.0, 82.0, 1416.0, 794.0)
const MIN_ZOOM := 1.0
const MAX_ZOOM := 1.5
const ZOOM_STEP := 0.1
const DRAG_THRESHOLD := 6.0
const MAP_VIEW := Rect2(0.0, HUD_HEIGHT, 1440.0, 824.0)
const ZOOM_BAR := Rect2(1120.0, 846.0, 304.0, 44.0)
const GOLD := Color("ffdb72")
const EVENT_COLORS := {"normal": Color("ffdb72"), "elite": Color("ff465c"), "boss": Color("ff58e6")}

## 治疗会触发 checkpoint 让整页重建；只在治疗前设置，新视图消费或失败时清空。
static var pending_selection_id := ""

var selected_id := ""
var detail: Control = null
var markers := {}
var map_rect := Rect2()
var _art_rect := Rect2()

var zoom_level := MIN_ZOOM
var _pan := Vector2.ZERO
var _map_layer: Control
var _map_art: Control
var _base_tips := {}
var _zoom_out: Button
var _zoom_in: Button
var _zoom_reset: Button
var _drag_pending := false
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_pan := Vector2.ZERO
var _drag_marker := ""

var _hovered_id := ""
var _week_dialog: AcceptDialog
var _leader_layer: Control
var _blank_hit: Control
var _window_active := true
var _pointer_seen := false
var _pointer_canvas := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect(self, Vector2.ZERO, CANVAS, INK)
	set_process(true)
	_build_blank_hit()
	_build_map()
	_build_markers()
	_build_hud()
	_build_zoom_controls()
	_apply_map_transform()
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
	var clip := Control.new()
	clip.name = "map_viewport"
	clip.position = MAP_VIEW.position
	clip.size = MAP_VIEW.size
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	_map_layer = Control.new()
	_map_layer.position = -MAP_VIEW.position
	_map_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_map_layer)
	_map_art = Control.new()
	_map_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_layer.add_child(_map_art)
	var asset_id := str(Game.map_config.get("cityMapAssetId", "city_map"))
	var texture: Texture2D = Game.texture(asset_id)
	var content := Rect2(0.0, 0.0, 1.0, 1.0)
	if texture != null:
		var asset: Dictionary = Game.assets.get(asset_id, {})
		var region: Array = asset.get("mapContentRect", [0.0, 0.0, 1.0, 1.0])
		content = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
	if texture == null:
		texture = MidnightMapAssets.map_texture()
	var source := MAP_FALLBACK_SIZE
	if texture != null and texture.get_width() > 0 and texture.get_height() > 0:
		source = Vector2(texture.get_size())
	# 地点锚点仍以原城市区域为基准，扩绘仅增加四周可浏览的画面。
	var core_size := source * content.size
	var fit_scale := minf(CANVAS.x / core_size.x, CANVAS.y / core_size.y)
	var dimensions := core_size * fit_scale
	map_rect = Rect2((CANVAS - dimensions) * 0.5, dimensions)
	_art_rect = Rect2(map_rect.position - source * content.position * fit_scale, source * fit_scale)
	if texture != null:
		var view := TextureRect.new()
		view.name = "map_texture"
		view.texture = texture
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_SCALE
		view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var clarity := ShaderMaterial.new()
		clarity.shader = preload("res://scripts/map/map_clarity.gdshader")
		view.material = clarity
		view.position = _art_rect.position
		view.size = _art_rect.size
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_art.add_child(view)
	else:
		panel(_map_art, map_rect.position, map_rect.size, Color("0e1928"), Color("264256"))
		label(_map_art, "城市地图插画待补", map_rect.position + Vector2(30.0, 30.0), Vector2(640.0, 44.0), 26, MUTED)
	rect(_map_art, _art_rect.position, _art_rect.size, Color(0.02, 0.03, 0.05, 0.12))
	var edge := Color(0.24, 0.62, 0.72, 0.55)
	rect(_map_art, _art_rect.position, Vector2(_art_rect.size.x, 1.0), edge)
	rect(_map_art, _art_rect.position + Vector2(0.0, _art_rect.size.y - 1.0), Vector2(_art_rect.size.x, 1.0), edge)
	rect(_map_art, _art_rect.position, Vector2(1.0, _art_rect.size.y), edge)
	rect(_map_art, _art_rect.position + Vector2(_art_rect.size.x - 1.0, 0.0), Vector2(1.0, _art_rect.size.y), edge)
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

# 只变换地图插画与锚点；标记保持可读尺寸，HUD 和详情留在固定画布上。
func _build_zoom_controls() -> void:
	var bar := Control.new()
	bar.name = "map_zoom_controls"
	bar.position = ZOOM_BAR.position
	bar.size = ZOOM_BAR.size
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.z_index = 10
	add_child(bar)
	_zoom_out = button(bar, "−", Vector2.ZERO, Vector2(48, 44), func(): set_map_zoom(zoom_level - ZOOM_STEP))
	_zoom_reset = button(bar, "100%", Vector2(56, 0), Vector2(112, 44), func(): set_map_zoom(MIN_ZOOM))
	_zoom_in = button(bar, "＋", Vector2(176, 0), Vector2(48, 44), func(): set_map_zoom(zoom_level + ZOOM_STEP))
	label(bar, "缩放", Vector2(238, 8), Vector2(62, 28), 16, MUTED)
	_zoom_reset.tooltip_text = "点击恢复全图；滚轮缩放，放大后按住左键拖动"
	_zoom_out.tooltip_text = "缩小地图"
	_zoom_in.tooltip_text = "放大地图"
	for control in [_zoom_out, _zoom_reset, _zoom_in]:
		control.focus_mode = Control.FOCUS_NONE

func set_map_zoom(value: float, anchor: Vector2 = MAP_VIEW.get_center()) -> void:
	if Game.transition_locked or Game.battle_busy or is_instance_valid(_week_dialog):
		return
	var next := clampf(value, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(next, zoom_level):
		return
	var origin := map_rect.position
	var local_point := (anchor - origin - _pan) / zoom_level
	_pan = anchor - origin - local_point * next
	zoom_level = next
	_cancel_drag()
	_apply_map_transform()

func _apply_map_transform() -> void:
	# 使用扩绘底图的真实边缘限制拖动，始终覆盖地图视口。
	var origin_offset := map_rect.position * (1.0 - zoom_level)
	var art_bounds := Rect2(_art_rect.position * zoom_level + origin_offset, _art_rect.size * zoom_level)
	_pan = Vector2.ZERO if zoom_level <= MIN_ZOOM else _pan.clamp(MAP_VIEW.end - art_bounds.end, MAP_VIEW.position - art_bounds.position)
	var offset := origin_offset + _pan
	_map_art.position = offset
	_map_art.scale = Vector2.ONE * zoom_level
	_leader_layer.position = offset
	_leader_layer.scale = Vector2.ONE * zoom_level
	for id in markers:
		markers[id].set_tip(_base_tips[id] * zoom_level + offset)
	_zoom_out.disabled = zoom_level <= MIN_ZOOM
	_zoom_in.disabled = zoom_level >= MAX_ZOOM
	_zoom_reset.text = "%d%%" % roundi(zoom_level * 100.0)
	_blank_hit.mouse_default_cursor_shape = Control.CURSOR_DRAG if zoom_level > MIN_ZOOM else Control.CURSOR_ARROW
	if is_instance_valid(detail):
		_place_card(detail, selected_id)
	_update_hover_from_pointer()

func _cancel_drag() -> void:
	_drag_pending = false
	_dragging = false
	_drag_marker = ""

func _map_navigation_allowed(point: Vector2) -> bool:
	return (_window_active and not Game.transition_locked and not Game.battle_busy
		and not is_instance_valid(_week_dialog) and _pointer_over_map_layer()
		and MAP_VIEW.has_point(point) and not ZOOM_BAR.has_point(point)
		and not (is_instance_valid(detail) and detail.get_global_rect().has_point(point)))

func _navigate_map(event: InputEvent) -> void:
	var point := _pointer_point()
	if not _window_active or Game.transition_locked or Game.battle_busy or is_instance_valid(_week_dialog) or not _pointer_over_map_layer():
		_cancel_drag()
		return
	if _drag_pending and event is InputEventMouseMotion:
		var delta := point - _drag_start
		if not _dragging and delta.length() >= DRAG_THRESHOLD:
			_dragging = true
			close_detail()
			_set_hovered_marker("")
		if _dragging:
			_pan = _drag_pan + delta
			_apply_map_transform()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if _drag_pending and mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
			var clicked := not _dragging and _map_navigation_allowed(point)
			var id := _drag_marker
			_cancel_drag()
			get_viewport().set_input_as_handled()
			if clicked:
				if not id.is_empty() and _marker_at(point) == id:
					select_place(id)
				elif id.is_empty():
					close_detail()
			return
		if not mouse.pressed or not _map_navigation_allowed(point):
			return
		if mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := 1.0 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			set_map_zoom(zoom_level + direction * ZOOM_STEP * maxf(mouse.factor, 0.1), point)
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_LEFT and zoom_level > MIN_ZOOM:
			_drag_pending = true
			_drag_start = point
			_drag_pan = _pan
			_drag_marker = _marker_at(point)
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture and _map_navigation_allowed(point):
		set_map_zoom(zoom_level * event.factor, point)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture and _map_navigation_allowed(point) and zoom_level > MIN_ZOOM:
		_pan -= event.delta * 24.0
		_apply_map_transform()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_active = false
		_pointer_seen = false
		_cancel_drag()
		_set_hovered_marker("")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_active = true
		# 弹窗或切换应用期间根视口未必收到鼠标移动，不能继续使用旧坐标。
		_pointer_seen = false

func _build_hud() -> void:
	map_chrome("城市总览")
	var deck_button := get_node("current_deck_button") as Button
	var menu_button := get_node("menu_button") as Button
	deck_button.position.x = menu_button.position.x - deck_button.size.x - 8.0
	var technology_button := button(self,"科技配置",Vector2(deck_button.position.x-140,deck_button.position.y),Vector2(132,44),Game.open_technology_loadout)
	technology_button.name = "technology_loadout_button"

# ------------------------------------------------------------------- 标记

func _build_markers() -> void:
	var avatar_texture: Texture2D = Game.texture(Game.player_asset_id())
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
			"avatar_crop": spec.avatar_crop,
			"badges": spec.badges, "font": base_font, "tooltip": spec.tooltip,
			"boss_effect": spec.boss_effect,
		})
		marker.chosen.connect(_on_marker_chosen)
		marker.hover_changed.connect(_on_marker_hover)
		built[spec.id] = marker
	var placements := _resolve_placements(order, by_id, built)
	_leader_layer = Control.new()
	_leader_layer.name = "leader_layer"
	_leader_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_layer.add_child(_leader_layer)
	for id in order:
		_draw_leader(placements[id], by_id[id].accent)
	var add_order := order.duplicate()
	add_order.reverse()
	for id in add_order:
		var marker = built[id]
		_map_layer.add_child(marker)
		_base_tips[id] = placements[id].tip
		marker.set_tip(placements[id].tip)
		marker.fit_name(CARD_BOUNDS)
		markers[id] = marker

func _make_spec(place: Dictionary, avatar_texture: Texture2D) -> Dictionary:
	var id := str(place.get("id", ""))
	var state := _place_state(id)
	var available: Array = state.available if state.available is Array else []
	var open := bool(state.open)
	var current := bool(state.current)
	var target := bool(state.target)
	var completed := bool(state.completed)
	var anchor := map_rect.position + Vector2(float(place.mapAnchor[0]), float(place.mapAnchor[1])) * map_rect.size
	var display: Dictionary = place.get("mapDisplay", {}) if place.get("mapDisplay", {}) is Dictionary else {}
	var resident := bool(display.get("resident", false))
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
	elif current:
		accent = Color("7af4ff")
		symbol_tint = Color("d8fcff")
	if open and completed and available.is_empty():
		symbol_tint = Color("d8e4ef")
	var badges: Array = []
	var boss_effect := false
	if not open:
		badges.append({"kind": "lock", "count": 0, "color": accent})
	else:
		var counts := {"normal": 0, "elite": 0, "boss": 0}
		for event in available:
			counts[Game.map_event_type(str(event.get("id", "")))] += 1
		for kind in ["normal", "elite", "boss"]:
			if counts[kind] == 0: continue
			accent = EVENT_COLORS[kind]
			symbol_tint = accent.lightened(0.35)
			badges.append({"kind": kind, "count": counts[kind], "color": accent})
		boss_effect = counts.boss > 0
	if resident:
		accent = Color("79e69b")
		boss_effect = false
		badges.push_front({"kind": "resident", "count": 0, "color": accent})
	var tooltip := str(place.get("description", ""))
	if not open:
		tooltip = str(place.get("lockHint", "尚未开放"))
	return {
		"id": id, "name": str(place.get("name", id)), "anchor": anchor, "offset": offset,
		"label_offset": label_offset, "avatar_side": side, "avatar": current,
		"current": current, "target": target, "persistent_name": current or target,
		"accent": accent, "frame_tint": frame_tint, "symbol_tint": symbol_tint,
		"badges": badges, "boss_effect": boss_effect, "avatar_texture": avatar_texture,
		"avatar_crop": Game.player_character().get("mapAvatarCrop", [0.0, 0.0, 1.0, 1.0]), "tooltip": tooltip,
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
			"current": false,
			"target": false, "completed": false, "services": [],
		}
	var state: Dictionary = raw
	for key in ["available", "services"]:
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
	elif not available.is_empty():
		accent = Color("4fc6d4")
	var rows: Array = []
	for event in available:
		rows.append({
			"id": str(event.get("id", "")), "title": str(event.get("title", "")),
			"description": str(event.get("description", "")),
			"refresh_time": Game.event_refresh_time_label(event),
		})
	var service := Game.healing_service(id)
	return {
		"id": id, "name": str(place.get("name", id)), "accent": accent,
		"state_label": " · ".join(labels), "description": str(place.get("description", "")),
		"lock_hint": str(place.get("lockHint", "")), "open": open,
		"events": rows, "has_service": not service.is_empty(), "healing_service": service,
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
	if _hover_input_blocked():
		_set_hovered_marker("")
		return
	# 每帧指针轮询给出权威结果；进入／离开信号只做即时提示，并先用实际指针位置复核，
	# 避免合成输入与系统事件交错时反复清除悬停、打断动画。
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
	var marker = markers.get(id)
	if is_instance_valid(marker):
		marker.set_hovered(true)

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

func handle_escape() -> bool:
	if is_instance_valid(_week_dialog):
		_close_weeks()
		return true
	if is_instance_valid(detail):
		close_detail()
		return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_track_pointer((event as InputEventMouse).position)
	if event is InputEventGesture:
		_track_pointer(event.position)
	_navigate_map(event)
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
	if not MAP_VIEW.has_point(point) or ZOOM_BAR.has_point(point):
		return ""
	for id in markers:
		var marker = markers[id]
		if is_instance_valid(marker) and marker.get_hit_rect().has_point(point):
			return id
	return ""

func _pointer_over_marker(id: String) -> bool:
	if not MAP_VIEW.has_point(_pointer_point()) or ZOOM_BAR.has_point(_pointer_point()):
		return false
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

func _hover_input_blocked() -> bool:
	return (not _window_active or _dragging or Game.transition_locked or Game.battle_busy
		or is_instance_valid(_week_dialog) or not _pointer_over_map_layer())

func _update_hover_from_pointer() -> void:
	# 暂停悬停更新前同时清除视觉，避免弹层关闭或失焦后保留旧地点的高亮。
	if _hover_input_blocked():
		_set_hovered_marker("")
		return
	var point := _pointer_point()
	if is_instance_valid(detail) and detail.get_global_rect().has_point(point):
		_set_hovered_marker("")
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

func show_weeks() -> void:
	if Game.transition_locked or Game.battle_busy:
		return
	if is_instance_valid(_week_dialog):
		return
	var dialog := AcceptDialog.new()
	dialog.name = "week_dialog"
	dialog.title = "周次档案"
	dialog.dialog_text = "第一周：%s / 第 %d 天\n\n第二周：内容待设计\n第三周：内容待设计\n\n每完成一个事件推进1天；移动、对话与治疗不计时。\n地图同时最多刷新3个事件。" % ["已完成" if Game.state.flags.get("week1Complete", false) else "进行中", int(Game.state.get("currentDay", 1))]
	dialog.ok_button_text = "返回城市"
	dialog.exclusive = true
	add_child(dialog)
	_week_dialog = dialog
	dialog.confirmed.connect(_close_weeks)
	dialog.canceled.connect(_close_weeks)
	dialog.popup_centered(Vector2i(590, 300))

func _close_weeks() -> void:
	_pointer_seen = false
	if is_instance_valid(_week_dialog):
		_week_dialog.queue_free()
	_week_dialog = null
