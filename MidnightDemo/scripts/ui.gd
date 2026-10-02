class_name DemoUI
extends Control
const INK := Color("100e19")
const PANEL := Color("1c1828")
const PINK := Color("f04b88")
const CYAN := Color("67daca")
const CREAM := Color("f3ebde")
const MUTED := Color("aaa4b8")
var base_font: Font

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists("res://assets/fonts/NotoSansCJKsc-Regular.otf"):
		base_font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	else:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
		base_font = system
	var t := Theme.new()
	t.default_font = base_font
	t.default_font_size = 20
	theme = t

func rect(parent: Node, pos: Vector2, dimensions: Vector2, color: Color) -> ColorRect:
	var n := ColorRect.new()
	n.position = pos
	n.size = dimensions
	n.color = color
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(n)
	return n

func panel(parent: Node, pos: Vector2, dimensions: Vector2, color: Color = PANEL, border: Color = Color("494053")) -> Panel:
	var n := Panel.new()
	n.position = pos
	n.size = dimensions
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_theme_stylebox_override("panel", style(color, border))
	parent.add_child(n)
	return n

func style(color: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(4)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func label(parent: Node, text: String, pos: Vector2, dimensions: Vector2, font_size: int = 22, color: Color = CREAM) -> Label:
	var n := Label.new()
	n.text = text
	n.position = pos
	n.size = dimensions
	n.add_theme_font_size_override("font_size", font_size)
	n.add_theme_color_override("font_color", color)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(n)
	n.size = dimensions
	return n

func button(parent: Node, text: String, pos: Vector2, dimensions: Vector2, action: Callable, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = dimensions
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", INK if accent else CREAM)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", CREAM)
	b.add_theme_color_override("font_disabled_color", Color("6c647b"))
	b.add_theme_stylebox_override("normal", style(PINK if accent else Color("241e30"), PINK if accent else Color("62536a")))
	b.add_theme_stylebox_override("hover", style(CREAM, CREAM))
	b.add_theme_stylebox_override("pressed", style(Color("a72b5b"), PINK))
	b.add_theme_stylebox_override("disabled", style(Color("17131f"), Color("393140")))
	b.add_theme_stylebox_override("focus", style(Color(0,0,0,0), CYAN, 2))
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func image_asset(parent: Node, id: String, pos: Vector2, dimensions: Vector2, cover: bool = true) -> TextureRect:
	var tex := Game.texture(id)
	if tex == null: return null
	var n := TextureRect.new()
	n.texture = tex
	n.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	n.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	n.position = pos
	n.size = dimensions
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(n)
	return n

func background(id: String, darkness: float = 0.3) -> void:
	rect(self, Vector2.ZERO, Vector2(1440,900), INK)
	if image_asset(self, id, Vector2.ZERO, Vector2(1440,900)) == null:
		for x in range(0, 1440, 90): rect(self, Vector2(x,0), Vector2(1,900), Color("282033"))
		for y in range(0, 900, 90): rect(self, Vector2(0,y), Vector2(1440,1), Color("282033"))
	rect(self, Vector2.ZERO, Vector2(1440,900), Color(0.035,0.018,0.06,darkness))
	# Film-like vertical shading keeps the image visible under the interface.
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.03,0.02,0.05,0.02),Color(0.03,0.02,0.05,0.9)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0,0)
	tex.fill_to = Vector2(0,1)
	var overlay := TextureRect.new()
	overlay.texture = tex
	overlay.size = Vector2(1440,900)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	if Game.texture(id) == null:
		label(self, "场景美术待补 / " + Game.place_data(Game.state.get("currentPlaceId", "")).get("name", ""), Vector2(64,828), Vector2(650,27), 15, MUTED)

func chrome(section: String) -> void:
	rect(self, Vector2.ZERO, Vector2(1440,82), Color("12101cec"))
	rect(self, Vector2(34,25), Vector2(5,32), PINK)
	label(self, "午夜委托", Vector2(53,17), Vector2(180,50), 29)
	label(self, "/  " + section, Vector2(220,24), Vector2(320,42), 19, MUTED)
	var faction: String = {"":"自由佣兵", "company":"公司特遣部", "resistance":"革命军"}.get(Game.state.get("faction", ""), "自由佣兵")
	label(self, "第一周   /   " + faction, Vector2(780,27), Vector2(320,40), 18, CYAN)
	label(self, "%s CR" % int(Game.state.get("credits", 0)), Vector2(1090,24), Vector2(180,42), 22)
	button(self, "菜单", Vector2(1300,20), Vector2(105,43), Game.menu)
	label(self, "W01   /   STORY PROTOTYPE", Vector2(36,858), Vector2(600,27), 13, MUTED)
	label(self, "自动保存检查点    ·    F1 开发面板", Vector2(1080,856), Vector2(340,28), 14, MUTED)

func tag(text: String, pos: Vector2, color: Color = CYAN, width: float = 180) -> void:
	panel(self, pos, Vector2(width,32), Color("191623"), color)
	label(self, text, pos + Vector2(12,2), Vector2(width-20,28), 14, color)

func portrait(id: String, side: String, active: bool = true, top: float = 150, height: float = 590) -> void:
	if id.is_empty(): return
	var x := 120.0 if side == "left" else 900.0
	var aid: String = Game.characters.get(id, {}).get("portraitAssetId", "")
	var pic := image_asset(self, aid, Vector2(x,top), Vector2(390,height), false)
	if pic:
		# Original RGB art is preserved; white paper is keyed only at render time.
		var shader := Shader.new()
		shader.code = "shader_type canvas_item; varying vec4 tint; void vertex(){ tint=COLOR; } void fragment(){ vec4 c=texture(TEXTURE,UV); float paper=smoothstep(0.94,0.995,min(c.r,min(c.g,c.b))); COLOR=vec4(c.rgb,c.a*(1.0-paper))*tint; }"
		var mat := ShaderMaterial.new()
		mat.shader = shader
		pic.material = mat
		pic.modulate = Color.WHITE if active else Color(0.72,0.66,0.79,0.95)
		pic.position.x += -20 if side == "left" else 20
		var tween := create_tween()
		tween.tween_property(pic, "position:x", x, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		var box := panel(self, Vector2(x+28,top+95), Vector2(330,height-135), Color("1e1728ce"), Color("59435f"))
		label(box, "◇", Vector2(126,45), Vector2(100,110), 76, Color("6d4b75"))
		label(box, Game.display_name(id), Vector2(22,195), Vector2(290,65), 32, CREAM if active else MUTED)
		label(box, "角色立绘待补", Vector2(22,265), Vector2(290,40), 17, MUTED)
		label(box, "CHARACTER / " + id.to_upper(), Vector2(22,320), Vector2(290,30), 12, Color("806988"))

func fade_in() -> void:
	modulate.a = 0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)
