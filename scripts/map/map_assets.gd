class_name MidnightMapAssets
extends RefCounted
## 地图界面专用素材读取与缓存。
##
## 只读取工程内既有美术：assets/icons/map 的符号与状态外框、
## assets/map 的城市总览底图、人物立绘。
## 全部通过 ResourceLoader 使用已导入资源（导出包同样可用），
## 不读取 PNG 源文件；符号按 alpha 主体范围裁切导入纹理的像素副本，
## 原素材不做任何改写，结果缓存在静态字典里复用。

const ICON_DIR := "res://assets/icons/map/"
const CATALOG_PATH := "res://assets/icons/map/locations.json"
const MAP_PATHS := ["res://assets/map/map.jpg", "res://assets/map/map.png"]
const PORTRAIT_PATHS := ["res://assets/characters/noren.png"]
const FRAME_PATHS := {
	"normal": "res://assets/icons/map/marker_frame.svg",
	"hover": "res://assets/icons/map/marker_frame_hover.svg",
	"selected": "res://assets/icons/map/marker_frame_selected.svg",
}
const FRAME_CANVAS := Vector2(64.0, 72.0)
const FRAME_TIP := Vector2(32.0 / 64.0, 67.0 / 72.0)
const SYMBOL_SAFE_RECT := Rect2(12.0, 12.0, 40.0, 34.0)
const ALPHA_CUTOFF := 16
const ALPHA_MARGIN := 2

static var _frames := {}
static var _symbols := {}
static var _icons := {}
static var _catalog_loaded := false
static var _map_texture: Texture2D = null
static var _map_attempted := false
static var _portrait_texture: Texture2D = null
static var _portrait_attempted := false
static var _avatar_texture: Texture2D = null

static func avatar_texture(source: Texture2D = null) -> Texture2D:
	if _avatar_texture != null:
		return _avatar_texture
	if source == null:
		source = portrait_texture()
	var image := _rgba_image_of(source)
	if image == null:
		return null
	var dimensions := image.get_size()
	var crop := Rect2i(Vector2i(Vector2(dimensions) * Vector2(0.27, 0.005)),
		Vector2i(Vector2(dimensions) * Vector2(0.42, 0.28)))
	var head := image.get_region(crop)
	head.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	head.generate_mipmaps()
	_avatar_texture = ImageTexture.create_from_image(head)
	return _avatar_texture

static func frame(state_name: String) -> Texture2D:
	var key := state_name if FRAME_PATHS.has(state_name) else "normal"
	if _frames.has(key):
		return _frames[key]
	var texture := _load_svg(FRAME_PATHS[key])
	_frames[key] = texture
	return texture

static func frames() -> Dictionary:
	return {"normal": frame("normal"), "hover": frame("hover"), "selected": frame("selected")}

static func symbol(place_id: String) -> Texture2D:
	if _symbols.has(place_id):
		return _symbols[place_id]
	var texture := _build_symbol(place_id)
	_symbols[place_id] = texture
	return texture

static func map_texture() -> Texture2D:
	if _map_attempted:
		return _map_texture
	_map_attempted = true
	for path in MAP_PATHS:
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Texture2D:
				_map_texture = res
				break
	return _map_texture

static func portrait_texture() -> Texture2D:
	if _portrait_attempted:
		return _portrait_texture
	_portrait_attempted = true
	for path in PORTRAIT_PATHS:
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Texture2D:
				_portrait_texture = res
				break
	return _portrait_texture

static func icon_file(place_id: String) -> String:
	_ensure_catalog()
	return str(_icons.get(place_id, place_id + ".png"))

static func _ensure_catalog() -> void:
	if _catalog_loaded:
		return
	_catalog_loaded = true
	if FileAccess.file_exists(CATALOG_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary and parsed.get("locations", []) is Array:
			for item in parsed.locations:
				if item is Dictionary and item.has("id"):
					_icons[str(item.id)] = str(item.get("icon", str(item.id) + ".png"))
	# 商场使用透明边缘修正版；locations.json 缺失时也能工作。
	_icons["mall"] = "mall-v2.png"
	var defaults := {
		"bar": "bar.png", "junkyard": "junkyard.png", "alley": "alley.png", "camp": "camp.png",
		"tower": "tower.png", "port": "port.png", "block5": "block5.png", "power": "power.png",
		"hive": "hive.png", "pump": "pump.png", "garden": "garden.png", "hotel": "hotel.png",
		"mall": "mall-v2.png", "market": "market.png", "hospital": "hospital.png", "clinic": "clinic.png",
	}
	for key in defaults:
		if not _icons.has(key):
			_icons[key] = defaults[key]

static func _load_svg(path: String) -> Texture2D:
	# 优先使用已导入资源；只有编辑器尚未导入时才回退解析 SVG 文本。
	if ResourceLoader.exists(path):
		var imported = load(path)
		if imported is Texture2D:
			return imported
	if FileAccess.file_exists(path):
		var svg := FileAccess.get_file_as_string(path)
		if not svg.is_empty():
			var image := Image.new()
			if image.load_svg_from_string(svg, 4.0) == OK and not image.is_empty():
				image.generate_mipmaps()
				return ImageTexture.create_from_image(image)
	return null

static func _build_symbol(place_id: String) -> Texture2D:
	var path := ICON_DIR + icon_file(place_id)
	if not ResourceLoader.exists(path):
		return null
	var imported = load(path)
	if not (imported is Texture2D):
		return null
	# 从导入资源获取像素，运行时不会读取 PNG 源文件。
	var texture: Texture2D = imported
	var image := _rgba_image_of(texture)
	if image == null:
		return texture
	var source := image.get_size()
	var body := _alpha_body_region(image)
	if body.size.x <= 0 or body.size.y <= 0:
		return texture
	var region := _expand_and_clamp(body, ALPHA_MARGIN, source)
	if region.position == Vector2i.ZERO and region.size == source:
		return texture
	# 在导入纹理的像素副本上裁切和降采样，避免 1K 原图缩成 20px 时闪烁。
	# 保持原始文件不变；导出包仍通过 ResourceLoader 读取资源。
	var cropped := image.get_region(region)
	var ratio := minf(128.0 / cropped.get_width(), 128.0 / cropped.get_height())
	if ratio < 1.0:
		cropped.resize(maxi(1, int(cropped.get_width() * ratio)), maxi(1, int(cropped.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	cropped.generate_mipmaps()
	return ImageTexture.create_from_image(cropped)

## 读取导入纹理的像素副本；VRAM 压缩或非 RGBA8 时先解压／转换。
static func _rgba_image_of(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _alpha_body_region(image: Image) -> Rect2i:
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
			min_x = mini(min_x, row_min)
			max_x = maxi(max_x, row_max)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	if max_x < 0 or max_y < 0:
		return Rect2i()
	return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))

static func _expand_and_clamp(rect: Rect2i, margin: int, size: Vector2i) -> Rect2i:
	var left := maxi(rect.position.x - margin, 0)
	var top := maxi(rect.position.y - margin, 0)
	var right := mini(rect.position.x + rect.size.x + margin, size.x)
	var bottom := mini(rect.position.y + rect.size.y + margin, size.y)
	return Rect2i(Vector2i(left, top), Vector2i(maxi(right - left, 1), maxi(bottom - top, 1)))
