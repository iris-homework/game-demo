class_name DemoUI
extends Control
const INK := Color("070e19")
const PANEL := Color("111b2b")
const PINK := Color("f04b88")
const CYAN := Color("58e1eb")
const CREAM := Color("f3ebde")
const MUTED := Color("aaa4b8")
var base_font: Font
var hp_fill: ColorRect
var hp_label: Label

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
	s.set_corner_radius_all(2)
	s.border_width_left = 3
	s.shadow_color = Color(0.04,0.65,0.75,0.1)
	s.shadow_size = 3
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
	b.add_theme_stylebox_override("normal", style(PINK if accent else Color("142234"), PINK if accent else Color("44657b")))
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
	rect(self,Vector2.ZERO,Vector2(1440,95),Color("09111ff5"))
	rect(self,Vector2(0,94),Vector2(1440,1),Color("2f6178"))
	label(self,Game.display_name("noren") + "  /  " + section,Vector2(36,8),Vector2(385,36),20,CREAM)
	panel(self,Vector2(37,51),Vector2(277,17),Color("382333"),Color("805071"))
	hp_fill = rect(self,Vector2(40,54),Vector2(271,11),PINK)
	hp_label = label(self,"",Vector2(327,44),Vector2(140,33),18)
	refresh_hp()
	if not Game.status_changed.is_connected(refresh_hp): Game.status_changed.connect(refresh_hp)
	for day in range(1,8):
		var current: bool = day == int(Game.state.get("currentDay",1))
		var x := 477+(day-1)*70
		panel(self,Vector2(x,20),Vector2(65,42),Color("164250") if current else Color("111c2a"),CYAN if current else Color("354457"))
		label(self,"第 %d 天" % day,Vector2(x+9,26),Vector2(60,28),15,CREAM if current else MUTED)
	label(self,"WEEK 01 / 时间推进规则待定",Vector2(583,69),Vector2(420,23),11,MUTED)
	var faction: String = {"":"自由佣兵","company":"公司特遣部","resistance":"革命军"}.get(Game.state.get("faction",""),"自由佣兵")
	label(self,faction,Vector2(1026,13),Vector2(214,31),17,CYAN)
	label(self,"%d CR" % int(Game.state.get("credits",0)),Vector2(1026,49),Vector2(210,30),17)
	button(self,"退出演练" if Game.training_mode else "菜单",Vector2(1263,23),Vector2(145,49),Game.menu)
	if section != "战斗":
		label(self,"MIDNIGHT / W01",Vector2(36,864),Vector2(600,24),12,MUTED)
		label(self,"检查点自动保存 · F1 开发面板",Vector2(1080,859),Vector2(340,27),13,MUTED)

func refresh_hp() -> void:
	if not is_instance_valid(hp_fill): return
	var maximum := int(Game.state.get("maxHp",100))
	var hp := int(Game.state.get("currentHp",100))
	hp_fill.size.x = 271.0*hp/maxi(maximum,1)
	hp_label.text = "%d / %d" % [hp,maximum]

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
