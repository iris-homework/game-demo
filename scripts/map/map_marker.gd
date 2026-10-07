class_name MidnightMapMarker
extends Control
## 单个地点标记：状态外框 + 符号 + 任务角标 + 当前位置头像 + 名称。
## 只展示状态，不提交游戏流程；点击只发出 chosen 信号，交给地图控制器处理。

signal chosen(place_id: String)
signal hover_changed(place_id: String, hovered: bool)

const AVATAR_SIZE := 56.0
const AVATAR_GAP := 6.0
const AVATAR_HIT := AVATAR_SIZE + AVATAR_GAP
const TOP_PAD := 10.0
const NAME_WIDTH := 190.0
const NAME_HEIGHT := 22.0
const NAME_FONT_SIZE := 17
const NAME_GAP := 3.0

var place_id := ""
var marker_height := 72.0
var name_text := ""
var frame_size := Vector2.ZERO
var tip_local := Vector2.ZERO
var left_pad := 0.0
var right_pad := 0.0
var accent := Color.WHITE
var frame_tint := Color.WHITE
var symbol_tint := Color.WHITE
var persistent_name := false
var name_offset := Vector2.ZERO
var has_avatar := false

var _frame_tex: TextureRect
var _underlay: TextureRect
var _hover_ring: TextureRect
var _select_ring: TextureRect
var _symbol: TextureRect
var _name_label: Label
var _avatar_root: Control
var _avatar_pic: TextureRect
var _badges: Array = []
var _hovered := false
var _selected := false

func prepare(spec: Dictionary) -> void:
	place_id = str(spec.get("id", ""))
	name_text = str(spec.get("name", place_id))
	marker_height = float(spec.get("height", 72.0))
	accent = spec.get("accent", Color.WHITE)
	frame_tint = spec.get("frame_tint", Color.WHITE)
	symbol_tint = spec.get("symbol_tint", Color.WHITE)
	persistent_name = bool(spec.get("persistent_name", false))
	name_offset = spec.get("name_offset", Vector2.ZERO)
	has_avatar = bool(spec.get("avatar", false))
	var side := "right" if str(spec.get("avatar_side", "left")) == "right" else "left"
	frame_size = Vector2(marker_height * MidnightMapAssets.FRAME_CANVAS.x / MidnightMapAssets.FRAME_CANVAS.y, marker_height)
	tip_local = Vector2(frame_size.x * MidnightMapAssets.FRAME_TIP.x, frame_size.y * MidnightMapAssets.FRAME_TIP.y)
	left_pad = AVATAR_HIT if has_avatar and side == "left" else 0.0
	right_pad = AVATAR_HIT if has_avatar and side == "right" else 0.0
	size = Vector2(left_pad + frame_size.x + right_pad, TOP_PAD + frame_size.y)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 简介由地图自定义悬停卡展示，关闭系统 tooltip，避免延时叠出第二份简介。
	tooltip_text = ""
	_build(side, spec)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

func _build(side: String, spec: Dictionary) -> void:
	var origin := Vector2(left_pad, TOP_PAD)
	var frames := MidnightMapAssets.frames()
	_select_ring = _frame_view(frames.get("selected"), origin, 1.20, Color(0.95, 0.92, 0.86, 0.72))
	_select_ring.visible = false
	_hover_ring = _frame_view(frames.get("hover"), origin, 1.10, Color(0.70, 1.0, 1.0, 0.82))
	_hover_ring.visible = false
	_underlay = _frame_view(frames.get("normal"), origin, 1.12, Color(accent, 0.30))
	_frame_tex = _frame_view(frames.get("normal"), origin, 1.0, frame_tint)
	_symbol = TextureRect.new()
	_symbol.texture = MidnightMapAssets.symbol(place_id)
	_symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_symbol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_symbol.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_symbol.modulate = symbol_tint
	var symbol_material := ShaderMaterial.new()
	symbol_material.shader = preload("res://scripts/map/symbol_readability.gdshader")
	_symbol.material = symbol_material
	var unit_scale := marker_height / MidnightMapAssets.FRAME_CANVAS.y
	_symbol.position = origin + MidnightMapAssets.SYMBOL_SAFE_RECT.position * unit_scale
	_symbol.size = MidnightMapAssets.SYMBOL_SAFE_RECT.size * unit_scale
	add_child(_symbol)
	if has_avatar:
		_build_avatar(side, spec)
	_build_badges(spec)
	_build_name()
	_update_visuals()

func _frame_view(texture: Texture2D, origin: Vector2, view_scale: float, tint: Color) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.size = frame_size * view_scale
	node.position = origin - frame_size * (view_scale - 1.0) * MidnightMapAssets.FRAME_TIP
	node.modulate = tint
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/map/frame_state.gdshader")
	var edge_color := accent
	if view_scale == 1.20:
		edge_color = Color("fff4dc")
	elif view_scale == 1.10:
		edge_color = Color("9af8ff")
	material.set_shader_parameter("edge_color", Color(edge_color, tint.a))
	node.material = material
	node.modulate = Color.WHITE
	add_child(node)
	return node

func _build_avatar(side: String, spec: Dictionary) -> void:
	_avatar_root = Control.new()
	_avatar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar_root.size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	var x := 0.0 if side == "left" else left_pad + frame_size.x + AVATAR_GAP
	var plate_h := frame_size.y * 53.0 / 72.0
	_avatar_root.position = Vector2(x, TOP_PAD + (plate_h - AVATAR_SIZE) * 0.5)
	add_child(_avatar_root)
	var ring := Panel.new()
	ring.position = Vector2.ZERO
	ring.size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(0.05, 0.09, 0.14, 0.94)
	ring_style.border_color = Color("7af4ff")
	ring_style.set_border_width_all(3)
	ring_style.set_corner_radius_all(int(AVATAR_SIZE * 0.5))
	ring_style.shadow_color = Color(0.35, 0.88, 0.92, 0.35)
	ring_style.shadow_size = 6
	ring.add_theme_stylebox_override("panel", ring_style)
	_avatar_root.add_child(ring)
	_avatar_pic = TextureRect.new()
	var inset := 3.0
	_avatar_pic.position = Vector2(inset, inset)
	_avatar_pic.size = Vector2(AVATAR_SIZE - inset * 2.0, AVATAR_SIZE - inset * 2.0)
	_avatar_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar_pic.stretch_mode = TextureRect.STRETCH_SCALE
	_avatar_pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_avatar_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar_pic.texture = MidnightMapAssets.avatar_texture(spec.get("avatar_texture", null))
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/map/round_avatar.gdshader")
	_avatar_pic.material = material
	_avatar_root.add_child(_avatar_pic)

func _build_badges(spec: Dictionary) -> void:
	var entries: Array = spec.get("badges", [])
	var right := left_pad + frame_size.x
	for entry in entries:
		var badge := MidnightMapBadge.new()
		badge.setup(str(entry.get("kind", "none")), int(entry.get("count", 0)), entry.get("color", accent), spec.get("font", null))
		add_child(badge)
		var badge_size: Vector2 = badge.badge_size()
		if badge_size.x <= 0.0:
			continue
		right -= badge_size.x
		badge.position = Vector2(right, TOP_PAD - badge_size.y * 0.25)
		right -= 3.0
		_badges.append(badge)

func _build_name() -> void:
	_name_label = Label.new()
	_name_label.text = name_text
	_name_label.size = Vector2(NAME_WIDTH, NAME_HEIGHT)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_name_label.add_theme_color_override("font_color", accent)
	_name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.95))
	_name_label.add_theme_constant_override("outline_size", 5)
	_name_label.position = Vector2(left_pad + frame_size.x * 0.5 - NAME_WIDTH * 0.5 + name_offset.x, TOP_PAD - NAME_HEIGHT - NAME_GAP + name_offset.y)
	add_child(_name_label)

func _on_mouse_entered() -> void:
	hover_changed.emit(place_id, true)

func _on_mouse_exited() -> void:
	hover_changed.emit(place_id, false)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			# 按下与松开都算标记自己处理，避免松开落回地图空白关闭刚打开的详情。
			if button.pressed:
				chosen.emit(place_id)
			accept_event()

func set_hovered(value: bool) -> void:
	if _hovered == value:
		return
	_hovered = value
	_update_visuals()

func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	_update_visuals()

func is_hovered() -> bool:
	return _hovered

func _update_visuals() -> void:
	if is_instance_valid(_hover_ring):
		_hover_ring.visible = _hovered
	if is_instance_valid(_select_ring):
		_select_ring.visible = _selected
	if is_instance_valid(_name_label):
		_name_label.visible = persistent_name or _hovered or _selected
	if _selected:
		z_index = 6
	elif _hovered:
		z_index = 5
	elif persistent_name:
		z_index = 3
	else:
		z_index = 2

func set_tip(tip: Vector2) -> void:
	position = tip - tip_local - Vector2(left_pad, TOP_PAD)

func hit_rect_for(tip: Vector2) -> Rect2:
	return Rect2(tip - tip_local - Vector2(left_pad, TOP_PAD), size)

func get_hit_rect() -> Rect2:
	return Rect2(global_position, size)

func get_frame_rect() -> Rect2:
	return Rect2(global_position + Vector2(left_pad, TOP_PAD), frame_size)

func get_click_point() -> Vector2:
	return global_position + Vector2(left_pad + frame_size.x * 0.5, TOP_PAD + frame_size.y * 0.45)

func fit_name(bounds: Rect2) -> void:
	if not is_instance_valid(_name_label):
		return
	var rect := Rect2(_name_label.global_position, _name_label.size)
	var dx := 0.0
	var dy := 0.0
	if rect.position.x < bounds.position.x:
		dx = bounds.position.x - rect.position.x
	elif rect.end.x > bounds.end.x:
		dx = bounds.end.x - rect.end.x
	if rect.position.y < bounds.position.y:
		dy = bounds.position.y - rect.position.y
	elif rect.end.y > bounds.end.y:
		dy = bounds.end.y - rect.end.y
	_name_label.global_position += Vector2(dx, dy)
