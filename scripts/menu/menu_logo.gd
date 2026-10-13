extends Control
## 主菜单专用字标：实时字体绘制，随 canvas_items 缩放保持清晰。
## 常驻循环特效直接作用于字芯；每轮保留短暂的完整清晰字形。

const WORDMARK := "午夜委托"
const ICE := Color("edfaff")
const CYAN := Color("55ecd9")
const MAGENTA := Color("ff376d")
var logo_font: FontVariation
var cyan_edge: Label
var pink_edge: Label
var core: Label
var glitch_bands: Array[Control] = []
var glitch_inks: Array[Label] = []
var glow_layers: Array[Label] = []
var animation_time := 0.0
var motion_enabled := true
var effect_strength := 0.0
const CYCLE_SECONDS := 3.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	logo_font = FontVariation.new()
	# 中文字标使用独立抗锯齿字体；自动采样适配画布，避开 MSDF 笔画缺损。
	var source_font := get_theme_default_font()
	if source_font is FontFile:
		var sharp_font := source_font.duplicate() as FontFile
		sharp_font.multichannel_signed_distance_field = false
		sharp_font.oversampling = 0.0
		logo_font.base_font = sharp_font
	else:
		logo_font.base_font = source_font
	logo_font.variation_embolden = 0.55
	logo_font.variation_transform = Transform2D.IDENTITY
	# 多层低透明度外扩描边形成霓虹晕，锐利字芯最后绘制。
	_ink(self, Vector2(1, 3), Color("090c1b"), 3)
	_glow(Vector2.ZERO, CYAN, 14, 0.08)
	_glow(Vector2.ZERO, CYAN, 9, 0.12)
	_glow(Vector2.ZERO, CYAN, 5, 0.14)
	_glow(Vector2(0, 2), MAGENTA, 3, 0.10)
	# 常态彩边与字芯对齐，不再以亚像素错位叠出双重轮廓。
	pink_edge = _ink(self, Vector2.ZERO, Color(MAGENTA, 0.45), 1)
	cyan_edge = _ink(self, Vector2.ZERO, Color(CYAN, 0.7), 1)
	core = _ink(self, Vector2.ZERO, ICE)
	core.name = "clear_core"
	# 故障时用完整覆盖字形的五段替换正文，只有两段轻微横移。
	_band(0, 60, 0, ICE)
	_band(60, 10, 3, CYAN)
	_band(70, 27, 0, ICE)
	_band(97, 9, -3, Color("ffd5e5"))
	_band(106, 39, 0, ICE)
	set_motion_enabled(bool(get_tree().root.get_meta("menu_motion_enabled", true)))

func _process(delta: float) -> void:
	if not motion_enabled or not DisplayServer.window_is_focused() or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		return
	animation_time += minf(delta, 0.1)
	_apply_phase(fposmod(animation_time, CYCLE_SECONDS))

func set_motion_enabled(value: bool) -> void:
	motion_enabled = value
	# 关闭时立即回到清晰静态帧，再开启从静稳阶段开始。
	animation_time = 0.0
	_apply_phase(0.0)
	set_process(value)

func _apply_phase(phase: float) -> void:
	# 霓虹故障每 3 秒触发一次：持续 0.60 秒，清晰间隔 2.40 秒。
	# 平滑进入／回弹／归位；亮度、色差、笔画使用同一连续包络。
	var progress := clampf((phase - 0.30) / 0.60, 0.0, 1.0)
	effect_strength = pow(sin(PI * progress), 2.0)
	var glitch := effect_strength > 0.00001
	core.visible = not glitch
	for band in glitch_bands:
		band.visible = glitch
	# 从零位移起止，不再直接从 +3px 跳到 -2px。
	var displacement := 3.0 * sin(TAU * progress) * effect_strength
	glitch_inks[1].position.x = 7.0 + displacement
	glitch_inks[3].position.x = 7.0 - displacement
	glitch_inks[1].add_theme_color_override("font_color", ICE.lerp(CYAN, effect_strength))
	glitch_inks[3].add_theme_color_override("font_color", ICE.lerp(Color("ffd5e5"), effect_strength))
	cyan_edge.position.x = 7.0 - 2.0 * effect_strength
	pink_edge.position.x = 7.0 + 2.0 * effect_strength
	for glow in glow_layers:
		glow.modulate.a = 1.0 + 0.65 * effect_strength

func _glow(offset: Vector2, color: Color, outline: int, opacity: float) -> void:
	var layer := _ink(self, offset, color, outline)
	# 只在 CanvasItem 上应用一次透明度，避免字色与描边 alpha 相乘后过暗。
	layer.self_modulate.a = opacity
	glow_layers.append(layer)

func _ink(host: Control, offset: Vector2, color: Color, outline: int = 0) -> Label:
	var ink := Label.new()
	ink.text = WORDMARK
	ink.position = Vector2(7, 0) + offset
	ink.size = Vector2(384, 145)
	ink.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ink.add_theme_font_override("font", logo_font)
	ink.add_theme_font_size_override("font_size", 92)
	ink.add_theme_color_override("font_color", color)
	ink.add_theme_color_override("font_outline_color", color)
	ink.add_theme_constant_override("outline_size", outline)
	host.add_child(ink)
	return ink

func _band(top: float, height: float, shift: float, color: Color) -> void:
	var band := Control.new()
	band.position = Vector2(0, top)
	band.size = Vector2(410, height)
	band.clip_contents = true
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	glitch_inks.append(_ink(band, Vector2(shift, -top), color))
	band.visible = false
	glitch_bands.append(band)

func _draw() -> void:
	# 装饰线保持静止；留足放大正体字的上下空间。
	draw_polyline(PackedVector2Array([Vector2(8, 20), Vector2(19, 9), Vector2(79, 9)]), CYAN, 2, true)
	draw_line(Vector2(84, 9), Vector2(103, 9), Color(CYAN, 0.35), 2, true)
	draw_polyline(PackedVector2Array([Vector2(9, 150), Vector2(281, 150), Vector2(293, 140), Vector2(374, 140)]), Color(CYAN, 0.65), 1.5, true)
	draw_line(Vector2(10, 155), Vector2(66, 155), MAGENTA, 4, true)
	for i in 3:
		var x := 354.0 + i * 9.0
		draw_line(Vector2(x, 156), Vector2(x + 5, 149), MAGENTA, 3, true)
