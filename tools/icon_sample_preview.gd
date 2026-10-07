extends Control
## 午夜委托 · 地点标记图标预览（统一 SVG 外框 ＋ 透明符号 PNG）
##
## 输出固定 1280x800 的 PNG 供人工核对。本工具不启动游戏剧情或战斗流程，
## 关闭并隔离冒险存档写入（不碰用户正式存档），不移动鼠标、不注入输入。
##
##   godot --path . res://tools/icon_sample_preview.tscn -- --icon-preview-output <目录> --icon-preview-mode board|sizes|map
##
## 模式说明：
##   board  17 个地点的完整对照卡片（固定 6 列 × 3 行）
##   sizes  最初五个样板的 40 / 48 / 56 px 尺寸对照
##   map    17 个 48 px 标记叠加到地图底图的示意锚点
##
## 地点清单读取 res://assets/icons/map/locations.json，不再维护硬编码地点常量。
##
## 可选参数：
##   --icon-preview-symbols <目录>  指定符号 PNG 所在目录（默认依次查找 res://assets/icons/map/symbols、assets/icons/map、assets/icons）
##   --icon-preview-selected <id>   map 模式中标记为 selected 的地点（默认 tower）
##   --icon-preview-no-trim         不裁掉 PNG 透明边缘（默认裁掉后等比放入安全区）

const CANVAS := Vector2(1280, 800)

const CATALOG_PATH := "res://assets/icons/map/locations.json"
const FRAME_PATHS := {
	"normal": "res://assets/icons/map/marker_frame.svg",
	"hover": "res://assets/icons/map/marker_frame_hover.svg",
	"selected": "res://assets/icons/map/marker_frame_selected.svg",
}
const FRAME_VIEW := Vector2(64, 72)
const SVG_SCALE := 4.0
const FRAME_TIP := Vector2(32.0 / 64.0, 67.0 / 72.0)
const SYMBOL_SAFE_RECT := Rect2(12, 12, 40, 34)
const MARKER_STATES := ["normal", "hover", "selected"]
## 生成图边缘常带极低 alpha 杂点，用阈值判定主体范围，再向外留 2 源像素。
const ALPHA_CUTOFF := 16
const ALPHA_MARGIN := 2

## sizes 模式只保留最初的五个样板做尺寸对照；名称与锚点统一取自 locations.json。
const SAMPLE_IDS := ["bar", "tower", "hive", "hospital", "clinic"]

const MAP_IMAGE := "res://assets/map/map.jpg"
const MAP_RECT := Rect2(40, 70, 1200, 676)
const MAP_MARKER_HEIGHT := 48.0
const MAP_NAME_FONT_SIZE := 15
const MAP_NAME_SIZE := Vector2(160, 20)
## 名称相对标记位置的基准纵移（沿用旧版：标记顶部之上约 24 px）。
const MAP_NAME_BASE_OFFSET_Y := -24.0
## 名称像素微调，相对示意锚点（正 x 向右、正 y 向下）。只给锚点过近、
## 名称会互相压住的地点设置；非零时补一条短引线指向真实锚点。
const MAP_NAME_OFFSETS := {
	"bar": Vector2(-36, -22),
	"alley": Vector2(38, 16),
}

const BOARD_MARGIN := 40.0
const BOARD_COLUMNS := 6
const BOARD_CELL := Vector2(200, 210)
const BOARD_TOP := 84.0
const BOARD_BIG_MARKER := 96.0
const BOARD_SMALL_MARKER := 48.0
const BOARD_NAME_FONT_SIZE := 16

const SYMBOL_SEARCH_DIRS := [
	"res://assets/icons/map/symbols",
	"res://assets/icons/map",
	"res://assets/icons",
]

const INK := Color("070e19")
const PANEL_EDGE := Color("2b3a56")
const CYAN := Color("58e1eb")
const PINK := Color("f04b88")
const CREAM := Color("f3ebde")
const MUTED := Color("98a3ba")

var output_dir := ""
var mode := "map"
var symbols_dir := ""
var selected_id := "tower"
var trim_symbols := true

var font: Font
var frames := {}
var symbols := {}
var location_icons := {}
var map_draw_rect := MAP_RECT
var _drawn_frame := false

## locations.json 内容：顺序即 board 卡片顺序。
var location_ids: Array[String] = []
var location_names := {}
var location_anchors := {}


func _ready() -> void:
	_configure_window()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parse_args()
	# 与 tools/qa_capture.gd 相同：预览工具绝不写用户正式存档。
	Game.save_enabled = false
	Game.save_path = OS.get_temp_dir().path_join("midnight_icon_preview_checkpoint.json")
	Game.meta_path = OS.get_temp_dir().path_join("midnight_icon_preview_meta.json")
	_load_font()
	_load_catalog()
	_load_frames()
	_load_symbols()
	match mode:
		"board":
			_build_board()
		"sizes":
			_build_sizes()
		_:
			_build_map()
	# 等渲染出帧再截图，确保 SVG 与 PNG 纹理已经上传。
	# headless 下不会发出 frame_post_draw，带回退计时，避免挂起。
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_for_draw()
	_save_and_quit()


func _configure_window() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_size = Vector2i(CANVAS)
	if win.size != Vector2i(CANVAS):
		win.size = Vector2i(CANVAS)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var key := args[i]
		var value := args[i + 1] if i + 1 < args.size() else ""
		match key:
			"--icon-preview-output":
				output_dir = value
				i += 2
			"--icon-preview-mode":
				mode = value if value in ["board", "sizes", "map"] else "map"
				i += 2
			"--icon-preview-symbols":
				symbols_dir = value
				i += 2
			"--icon-preview-selected":
				selected_id = value
				i += 2
			"--icon-preview-no-trim":
				trim_symbols = false
				i += 1
			_:
				i += 1
	if output_dir.is_empty():
		output_dir = OS.get_temp_dir().path_join("midnight_icon_preview")


func _load_font() -> void:
	var path := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
	if ResourceLoader.exists(path):
		font = load(path)
	if font == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"])
		font = fallback


## 从美术目录读取地点清单，避免再维护一份硬编码的五地点常量。
func _load_catalog() -> void:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("ICON PREVIEW: 找不到地点目录 %s" % CATALOG_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ICON PREVIEW: 地点目录解析失败 %s" % CATALOG_PATH)
		return
	var data: Dictionary = parsed
	var list_value: Variant = data.get("locations", [])
	if typeof(list_value) != TYPE_ARRAY:
		push_error("ICON PREVIEW: 地点目录缺少 locations 数组 %s" % CATALOG_PATH)
		return
	var items: Array = list_value
	for raw_item in items:
		if typeof(raw_item) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = raw_item
		var id := str(item.get("id", ""))
		if id.is_empty():
			continue
		location_ids.append(id)
		location_names[id] = str(item.get("name", id))
		location_icons[id] = str(item.get("icon", id + ".png")).get_file()
		var anchor_out := Vector2(0.5, 0.5)
		var raw_anchor: Variant = item.get("previewAnchor", [])
		if typeof(raw_anchor) == TYPE_ARRAY:
			var anchor_values: Array = raw_anchor
			if anchor_values.size() >= 2:
				anchor_out = Vector2(float(anchor_values[0]), float(anchor_values[1]))
		location_anchors[id] = anchor_out
	print("ICON PREVIEW: 载入地点目录 %d 项 -> %s" % [location_ids.size(), CATALOG_PATH])


func _load_frames() -> void:
	for state in FRAME_PATHS:
		var path: String = FRAME_PATHS[state]
		var texture := _load_svg_texture(path)
		if texture == null:
			push_warning("ICON PREVIEW: 无法加载外框 %s" % path)
			continue
		frames[state] = texture


## 直接解析 SVG 文本，既不依赖资源 import，也让大尺寸预览保持矢量清晰度。
func _load_svg_texture(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var svg := FileAccess.get_file_as_string(path)
		if not svg.is_empty():
			var image := Image.new()
			if image.load_svg_from_string(svg, SVG_SCALE) == OK and not image.is_empty():
				image.generate_mipmaps()
				return ImageTexture.create_from_image(image)
	if ResourceLoader.exists(path):
		var imported := load(path)
		if imported is Texture2D:
			return imported
		if imported is Image:
			return ImageTexture.create_from_image(imported)
	return null


## 等待真实渲染帧；headless / 无渲染环境下用计时兜底。
func _wait_for_draw() -> void:
	_drawn_frame = false
	RenderingServer.frame_post_draw.connect(_on_frame_drawn, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not _drawn_frame and waited < 1.5:
		await get_tree().process_frame
		waited += 1.0 / 60.0


func _on_frame_drawn() -> void:
	_drawn_frame = true


func _load_symbols() -> void:
	for id in location_ids:
		var entry := _load_symbol(id)
		symbols[id] = entry
		if entry.texture == null:
			print("ICON PREVIEW: 缺图 %s.png，未找到于 %s（使用缺图提示）" % [id, _search_hint()])
		else:
			var region: Rect2i = entry.region
			var source: Vector2i = entry.source
			print("ICON PREVIEW: %s -> %s 画布 %dx%d，取样 %d,%d %dx%d" % [
				id, entry.path, source.x, source.y,
				region.position.x, region.position.y, region.size.x, region.size.y])


func _search_hint() -> String:
	var parts: Array[String] = []
	if not symbols_dir.is_empty():
		parts.append(symbols_dir)
	for dir in SYMBOL_SEARCH_DIRS:
		parts.append(dir)
	var out := ""
	for part in parts:
		if not out.is_empty():
			out += ", "
		out += part
	return out


func _find_symbol_path(id: String) -> String:
	var candidates: Array[String] = []
	var filename: String = location_icons.get(id, id + ".png")
	if not symbols_dir.is_empty():
		candidates.append(symbols_dir.path_join(filename))
	for dir in SYMBOL_SEARCH_DIRS:
		candidates.append(dir.path_join(filename))
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _load_symbol(id: String) -> Dictionary:
	var path := _find_symbol_path(id)
	if path.is_empty():
		return {"texture": null, "path": "", "source": Vector2i.ZERO, "region": Rect2i()}
	var image := Image.new()
	var err := image.load(path)
	if err != OK or image.is_empty():
		push_warning("ICON PREVIEW: 无法读取 %s（错误码 %d）" % [path, err])
		return {"texture": null, "path": path, "source": Vector2i.ZERO, "region": Rect2i()}
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var source := image.get_size()
	var region := Rect2i(Vector2i.ZERO, source)
	# 生成图尺寸不固定（1024 / 1254 等）。默认按 alpha 主体裁掉留白，
	# 让不同符号在安全区里保持一致的相对大小；不改动原 PNG 内容。
	if trim_symbols:
		var body := _alpha_body_region(image)
		if body.size.x > 0 and body.size.y > 0:
			region = _expand_and_clamp(body, ALPHA_MARGIN, source)
	# 仅为展示生成 mipmaps，减少千像素符号缩到二十余像素时的锯齿。
	image.generate_mipmaps()
	var base := ImageTexture.create_from_image(image)
	var texture: Texture2D = base
	if region != Rect2i(Vector2i.ZERO, source):
		var atlas := AtlasTexture.new()
		atlas.atlas = base
		atlas.region = region
		texture = atlas
	return {"texture": texture, "path": path, "source": source, "region": region}


## 扫描 RGBA8 数据，返回 alpha 大于阈值的像素范围；无主体时返回空矩形。
func _alpha_body_region(image: Image) -> Rect2i:
	var size := image.get_size()
	var data := image.get_data()
	if size.x <= 0 or size.y <= 0 or data.size() < size.x * size.y * 4:
		return Rect2i()
	var stride := size.x * 4
	var min_x := size.x
	var min_y := size.y
	var max_x := -1
	var max_y := -1
	for y in size.y:
		var row_min := -1
		var row_max := -1
		var index := y * stride + 3
		for x in size.x:
			if data[index] > ALPHA_CUTOFF:
				if row_min < 0:
					row_min = x
				row_max = x
			index += 4
		if row_min >= 0:
			if row_min < min_x:
				min_x = row_min
			if row_max > max_x:
				max_x = row_max
			if y < min_y:
				min_y = y
			max_y = y
	if max_x < 0 or max_y < 0:
		return Rect2i()
	return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))


func _expand_and_clamp(rect: Rect2i, margin: int, size: Vector2i) -> Rect2i:
	var left := maxi(rect.position.x - margin, 0)
	var top := maxi(rect.position.y - margin, 0)
	var right := mini(rect.position.x + rect.size.x + margin, size.x)
	var bottom := mini(rect.position.y + rect.size.y + margin, size.y)
	return Rect2i(Vector2i(left, top), Vector2i(maxi(right - left, 1), maxi(bottom - top, 1)))


func _rect(parent: Node, area: Rect2, color: Color) -> ColorRect:
	var node := ColorRect.new()
	node.position = area.position
	node.size = area.size
	node.color = color
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _panel(parent: Node, area: Rect2, fill: Color, edge: Color, width: int = 1, radius: int = 2) -> Panel:
	var node := Panel.new()
	node.position = area.position
	node.size = area.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	node.add_theme_stylebox_override("panel", style)
	parent.add_child(node)
	return node


func _label(parent: Node, txt: String, area: Rect2, font_size: int, color: Color, h := HORIZONTAL_ALIGNMENT_LEFT, v := VERTICAL_ALIGNMENT_TOP) -> Label:
	var node := Label.new()
	node.text = txt
	node.position = area.position
	node.size = area.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.horizontal_alignment = h
	node.vertical_alignment = v
	if font != null:
		node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node


func _dot(parent: Node, center: Vector2, radius: float, color: Color) -> void:
	var node := Panel.new()
	node.position = center - Vector2(radius, radius)
	node.size = Vector2(radius * 2.0, radius * 2.0)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(ceil(radius)))
	node.add_theme_stylebox_override("panel", style)
	parent.add_child(node)


## 名称避让用的短引线：从真实锚点指向偏移后的名称。
func _line(parent: Node, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var node := Line2D.new()
	node.points = PackedVector2Array([from, to])
	node.width = width
	node.default_color = color
	node.antialiased = true
	parent.add_child(node)


func _load_image_texture(path: String) -> Texture2D:
	var image := Image.new()
	var err := image.load(path)
	if err != OK or image.is_empty():
		push_warning("ICON PREVIEW: 无法读取图像 %s（错误码 %d）" % [path, err])
		return null
	return ImageTexture.create_from_image(image)


func _location_name(id: String) -> String:
	return str(location_names.get(id, id))


func _sample_ids() -> Array[String]:
	var out: Array[String] = []
	for sample_id in SAMPLE_IDS:
		var id := str(sample_id)
		if location_names.has(id):
			out.append(id)
	return out


func _build_marker(parent: Node, id: String, state: String, height: float) -> Control:
	var marker := Control.new()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width := height * FRAME_VIEW.x / FRAME_VIEW.y
	marker.size = Vector2(width, height)
	var frame := TextureRect.new()
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.texture = frames.get(state, null)
	frame.position = Vector2.ZERO
	frame.size = Vector2(width, height)
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(frame)
	_build_symbol_slot(marker, id, height)
	parent.add_child(marker)
	return marker


func _build_symbol_slot(marker: Control, id: String, height: float) -> void:
	var k := height / FRAME_VIEW.y
	var slot := Rect2(SYMBOL_SAFE_RECT.position * k, SYMBOL_SAFE_RECT.size * k)
	var entry: Dictionary = symbols.get(id, {})
	var texture: Texture2D = entry.get("texture", null)
	if texture != null:
		var view := TextureRect.new()
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.texture = texture
		view.position = slot.position
		view.size = slot.size
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_child(view)
		return
	# 缺图时给明确提示，不画假符号。
	_panel(marker, slot, Color(0.06, 0.09, 0.14, 0.9), Color(MUTED, 0.75), 1, 2)
	var font_size := int(clampf(round(slot.size.y * 0.3), 6.0, 13.0))
	_label(marker, "缺图\n%s.png" % id, slot, font_size, MUTED, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)


func _build_map() -> void:
	_rect(self, Rect2(Vector2.ZERO, CANVAS), INK)
	_rect(self, Rect2(0, 0, CANVAS.x, 4), Color(CYAN, 0.5))
	_label(self, "全地点图标美术预览 · 示意位置", Rect2(40, 26, 820, 30), 22, CREAM)
	_label(self, "48 px · %d 个地点" % location_ids.size(), Rect2(870, 32, 370, 24), 14, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_panel(self, MAP_RECT.grow(8.0), Color(0.05, 0.07, 0.11, 0.9), Color(PANEL_EDGE, 0.9), 1, 3)
	map_draw_rect = MAP_RECT
	var map_texture := _load_image_texture(MAP_IMAGE)
	if map_texture != null:
		# 等比放入预留区域并居中；换底图后锚点仍落在实际画面上。
		var source := Vector2(map_texture.get_width(), map_texture.get_height())
		if source.x > 0.0 and source.y > 0.0:
			var fit := Vector2(MAP_RECT.size.x, MAP_RECT.size.x * source.y / source.x)
			if fit.y > MAP_RECT.size.y:
				fit = Vector2(MAP_RECT.size.y * source.x / source.y, MAP_RECT.size.y)
			map_draw_rect = Rect2(MAP_RECT.position + (MAP_RECT.size - fit) * 0.5, fit)
		var view := TextureRect.new()
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.texture = map_texture
		view.position = map_draw_rect.position
		view.size = map_draw_rect.size
		view.stretch_mode = TextureRect.STRETCH_SCALE
		view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(view)
	else:
		_rect(self, MAP_RECT, Color(0.08, 0.1, 0.15, 1))
		_label(self, "底图缺图：%s" % MAP_IMAGE, Rect2(MAP_RECT.position + Vector2(24, 24), Vector2(560, 28)), 16, MUTED)
	for id in location_ids:
		_place_map_marker(id)
	_label(self, "美术叠加预览 · 示意位置，正式热点待校准", Rect2(40, 758, 900, 24), 14, MUTED)


func _place_map_marker(id: String) -> void:
	var anchor_norm: Vector2 = location_anchors.get(id, Vector2(0.5, 0.5))
	var anchor := map_draw_rect.position + Vector2(anchor_norm.x * map_draw_rect.size.x, anchor_norm.y * map_draw_rect.size.y)
	# 青色小点：示意锚点位置，标记尖端落在同一点上。
	_dot(self, anchor, 8.0, Color(CYAN, 0.16))
	_dot(self, anchor, 4.6, Color(CYAN, 0.5))
	_dot(self, anchor, 2.4, CYAN)
	var state := "selected" if id == selected_id else "normal"
	var marker_size := Vector2(MAP_MARKER_HEIGHT * FRAME_VIEW.x / FRAME_VIEW.y, MAP_MARKER_HEIGHT)
	var marker_pos := anchor - Vector2(marker_size.x * FRAME_TIP.x, marker_size.y * FRAME_TIP.y)
	var offset: Vector2 = MAP_NAME_OFFSETS.get(id, Vector2.ZERO)
	var name_top_left := Vector2(anchor.x - MAP_NAME_SIZE.x * 0.5 + offset.x, marker_pos.y + MAP_NAME_BASE_OFFSET_Y + offset.y)
	if offset.length_squared() > 0.0:
		# 名称避让后与真实锚点之间的短引线，先画线让标记盖住引线起点。
		_line(self, anchor, name_top_left + MAP_NAME_SIZE * 0.5, Color(CYAN, 0.45), 1.0)
	var marker := _build_marker(self, id, state, MAP_MARKER_HEIGHT)
	marker.position = marker_pos
	var color := PINK if state == "selected" else CREAM
	_label(self, _location_name(id), Rect2(name_top_left, MAP_NAME_SIZE), MAP_NAME_FONT_SIZE, color, HORIZONTAL_ALIGNMENT_CENTER)


func _build_board() -> void:
	_rect(self, Rect2(Vector2.ZERO, CANVAS), INK)
	_rect(self, Rect2(0, 0, CANVAS.x, 4), Color(PINK, 0.5))
	_label(self, "全地点图标 · %d 地点对照" % location_ids.size(), Rect2(40, 18, 760, 32), 22, CREAM)
	_label(self, "每格：96 px 默认大标记 · 下排 48 px 默认／悬停／选中 · 中文名 16 px", Rect2(40, 54, 1200, 22), 13, MUTED)
	if location_ids.is_empty():
		_label(self, "地点目录加载失败：%s" % CATALOG_PATH, Rect2(40, 120, 1200, 30), 18, PINK)
		return
	for i in location_ids.size():
		var row := floori(float(i) / float(BOARD_COLUMNS))
		var col := i % BOARD_COLUMNS
		var items_in_row := mini(BOARD_COLUMNS, location_ids.size() - row * BOARD_COLUMNS)
		var row_left := BOARD_MARGIN + (CANVAS.x - BOARD_MARGIN * 2.0 - items_in_row * BOARD_CELL.x) * 0.5
		var cell := Rect2(row_left + col * BOARD_CELL.x, BOARD_TOP + row * BOARD_CELL.y, BOARD_CELL.x, BOARD_CELL.y)
		_build_board_cell(location_ids[i], cell)
	_label(self, "暖白符号 · 深蓝紫金属牌 · 青色悬停 · 洋红选中", Rect2(40, 762, 1200, 22), 13, Color(MUTED, 0.75))


func _build_board_cell(id: String, area: Rect2) -> void:
	var inner := area.grow(-6.0)
	_panel(self, inner, Color(0.05, 0.07, 0.11, 0.85), Color(PANEL_EDGE, 0.7), 1, 3)
	var center_x := inner.position.x + inner.size.x * 0.5
	var big := _build_marker(self, id, "normal", BOARD_BIG_MARKER)
	big.position = Vector2(center_x - big.size.x * 0.5, inner.position.y + 6.0)
	var name_y := big.position.y + big.size.y + 6.0
	_label(self, _location_name(id), Rect2(inner.position.x + 6.0, name_y, inner.size.x - 12.0, 24.0), BOARD_NAME_FONT_SIZE, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	var small_w := BOARD_SMALL_MARKER * FRAME_VIEW.x / FRAME_VIEW.y
	var gap := 8.0
	var total := small_w * float(MARKER_STATES.size()) + gap * float(MARKER_STATES.size() - 1)
	var start_x := center_x - total * 0.5
	var small_y := name_y + 26.0
	for si in MARKER_STATES.size():
		var marker := _build_marker(self, id, MARKER_STATES[si], BOARD_SMALL_MARKER)
		marker.position = Vector2(start_x + float(si) * (small_w + gap), small_y)


func _build_sizes() -> void:
	_rect(self, Rect2(Vector2.ZERO, CANVAS), INK)
	_rect(self, Rect2(0, 0, CANVAS.x, 4), Color(PINK, 0.5))
	_label(self, "地点图标 · 外框与符号尺寸对照", Rect2(40, 22, 800, 32), 24, CREAM)
	_label(self, "上行：完整标记约 140 px；下行：真实尺寸 40 / 48 / 56 px，默认／悬停／选中", Rect2(40, 58, 1100, 24), 14, MUTED)
	var ids := _sample_ids()
	if ids.is_empty():
		_label(self, "缺少样板地点，请检查 %s" % CATALOG_PATH, Rect2(40, 120, 1200, 30), 18, MUTED)
		return
	var columns := ids.size()
	var margin := 40.0
	var column_width := (CANVAS.x - margin * 2.0) / float(columns)
	for i in columns:
		var id: String = ids[i]
		var left := margin + column_width * float(i)
		if i > 0:
			_rect(self, Rect2(left, 96, 1, 620), Color(PANEL_EDGE, 0.55))
		_build_sizes_column(id, Rect2(left, 96, column_width, 620))
	_label(self, "完整标记尺寸；符号、外框与状态独立", Rect2(40, 700, 1200, 24), 13, MUTED)
	_build_legend(Rect2(40, 728, 1200, 28), ids[0])


func _build_sizes_column(id: String, area: Rect2) -> void:
	var center_x := area.position.x + area.size.x * 0.5
	var big := _build_marker(self, id, "normal", 140.0)
	big.position = Vector2(center_x - big.size.x * 0.5, area.position.y + 4.0)
	var name_y := big.position.y + big.size.y + 6.0
	_label(self, _location_name(id), Rect2(area.position.x, name_y, area.size.x, 26), 18, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	_label(self, "140 px · 默认", Rect2(area.position.x, name_y + 26.0, area.size.x, 18), 11, Color(MUTED, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	_rect(self, Rect2(area.position.x + 16.0, area.position.y + 218.0, area.size.x - 32.0, 1.0), Color(PANEL_EDGE, 0.7))
	_label(self, "真实尺寸 · 默认／悬停／选中", Rect2(area.position.x + 16.0, area.position.y + 226.0, area.size.x - 32.0, 18), 12, Color(CYAN, 0.85))
	var sizes := [40.0, 48.0, 56.0]
	for row in sizes.size():
		var marker_height: float = sizes[row]
		var slot_y := area.position.y + 254.0 + float(row) * 104.0
		_label(self, "%d px" % int(marker_height), Rect2(area.position.x + 12.0, slot_y + 30.0, 38.0, 20.0), 12, MUTED)
		var state_index := 0
		for state in MARKER_STATES:
			var marker := _build_marker(self, id, state, marker_height)
			var origin_x := area.position.x + 54.0 + float(state_index) * (marker.size.x + 10.0)
			marker.position = Vector2(origin_x, slot_y + (56.0 - marker_height) * 0.5 + 12.0)
			state_index += 1


func _build_legend(area: Rect2, thumb_id: String) -> void:
	var x := area.position.x
	var y := area.position.y
	var entries := [
		["normal", "默认", Color(MUTED, 0.9)],
		["hover", "悬停（青）", CYAN],
		["selected", "选中（洋红）", PINK],
	]
	for entry in entries:
		var thumb := _build_marker(self, thumb_id, entry[0], 28.0)
		thumb.position = Vector2(x, y + 2.0)
		x += thumb.size.x + 6.0
		_label(self, entry[1], Rect2(x, y, 240.0, 28.0), 13, entry[2], HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_CENTER)
		x += 214.0


func _save_and_quit() -> void:
	var dir := output_dir
	if not DirAccess.dir_exists_absolute(dir):
		var make_err := DirAccess.make_dir_recursive_absolute(dir)
		if make_err != OK:
			push_error("ICON PREVIEW: 无法创建输出目录 %s（错误码 %d）" % [dir, make_err])
			get_tree().quit(1)
			return
	var path := dir.path_join("icon_preview_%s.png" % mode)
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		push_error("ICON PREVIEW: 保存截图失败 %s（错误码 %d）" % [path, err])
		get_tree().quit(1)
		return
	print("ICON PREVIEW OK: %s -> %s (%dx%d)" % [mode, path, image.get_width(), image.get_height()])
	get_tree().quit(0)

