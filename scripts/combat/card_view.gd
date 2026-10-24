class_name CombatCard
extends DemoUI
class CardButton extends Button:
	func _get_tooltip(_at_position: Vector2) -> String:
		# CombatCard draws the larger art + current description in one preview.
		return ""

signal chosen(uid: String)
var uid := ""
var data: Dictionary = {}
var home := Vector2.ZERO
var home_scale := 1.0
var home_rotation := 0.0
var home_z := 10
var lifted_z := 30
var selection_home := Vector2.ZERO
var center_on_selection := false
var managed_input := false
var enabled := false
var selected := false
var hovered := false
var dragging := false
var preview_only := false
var hover_tween: Tween
var card_button: Button
var cost_label: Label
var effect_label: Label
var rank_label: Label
var face_texture: Texture2D
var face_font: Font
var face_template_id := FaceArt.TEMPLATE_ID
var fixed_layer: Control
var cost_changed := false
var rules_changed := false
var cost_ink_bounds := Rect2()
var allow_zoom_preview := true
var zoom_layer: CanvasLayer
var zoom_card: CombatCard
var zoom_description: Label
var hover_generation := 0
const EFFECT_SIZE := Vector2(150,88)
const RARITY_COLORS := {"C": Color("a6adb7"), "B": Color("5aa9ff"), "A": Color("f25b69"), "S": Color("f2c35c")}
const FaceArt = preload("res://scripts/combat/card_face_art.gd")
const FACE_SCALE := 230.0 / 1448.0
const FACE_RECT := Rect2(3.75, 0, 172.5, 230)
const FACE_RULES := Rect2(118, 956, 853, 369)
const FACE_RULE_COLOR := Color("f5f0e7")
const ZOOM_SCALE := 2.2

func rarity_color() -> Color:
	return RARITY_COLORS.get(data.get("rarity", ""), CYAN)

func setup(card_uid: String, definition: Dictionary, read_only: bool = false) -> void:
	uid = card_uid
	data = definition
	preview_only = read_only
	var art := FaceArt.resolve(definition)
	face_texture = art.get("texture")
	face_font = art.get("font")
	face_template_id = art.get("template_id", FaceArt.TEMPLATE_ID)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(180,230)
	pivot_offset = Vector2(90,115)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if managed_input else Control.MOUSE_FILTER_PASS
	queue_redraw()

func _ready() -> void:
	if face_texture != null:
		build_fixed_face()
	elif data.has("rarity"):
		label(self, "费用", Vector2(10,9), Vector2(38,14), 9, INK).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_label = label(self, str(int(data.cost)), Vector2(10,18), Vector2(38,34), 26, INK)
		cost_label.add_theme_font_override("font", button_font)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		var title := label(self, data.name, Vector2(60,12), Vector2(105,47), 19, CREAM)
		title.add_theme_font_override("font", button_font)
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var rank_font := FontVariation.new()
		rank_font.base_font = base_font
		rank_font.variation_embolden = 1.8
		rank_font.spacing_top = -8
		rank_font.spacing_bottom = -8
		rank_label = label(self, str(data.rarity).to_upper(), Vector2(56,61), Vector2(68,49), 44, rarity_color())
		rank_label.add_theme_font_override("font", rank_font)
		rank_label.size = Vector2(68,49)
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rank_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		rank_label.add_theme_color_override("font_outline_color", INK)
		rank_label.add_theme_constant_override("outline_size", 3)
		rank_label.add_theme_color_override("font_shadow_color", rarity_color().darkened(0.65))
		rank_label.add_theme_constant_override("shadow_offset_x", 1)
		rank_label.add_theme_constant_override("shadow_offset_y", 1)
		var text: String = data.get("cardText", data.get("description", ""))
		effect_label = label(self, text, Vector2(15,110), EFFECT_SIZE, 14, CREAM)
		effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		effect_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		effect_label.add_theme_constant_override("line_spacing", 0)
		fit_effect_text()
		var kind: String = {"attack":"攻击", "skill":"技能", "power":"能力"}.get(data.get("type"), "卡牌")
		label(self, kind + (" · 消耗" if data.get("exhaust", false) else ""), Vector2(14,206), Vector2(152,18), 10, rarity_color()).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		label(self, "LEGACY / TEST", Vector2(17,12), Vector2(150,19), 10, INK)
		label(self, data.get("name", "临时攻击"), Vector2(17,37), Vector2(150,35), 23, INK)
		var art := image_asset(self, data.get("artAssetId", ""), Vector2(18,78), Vector2(144,67), true)
		if art == null: label(self, "╱╱", Vector2(54,72), Vector2(110,73), 53, PINK)
		effect_label = label(self, data.get("description", ""), Vector2(18,151), Vector2(149,38), 16, CREAM)
		label(self, "旧版测试卡 · 无费用", Vector2(18,197), Vector2(155,23), 12, MUTED)
	card_button = CardButton.new()
	card_button.flat = true
	# Select on mouse-down so aiming starts without waiting for the release.
	if not preview_only: card_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	card_button.disabled = not enabled and not preview_only
	card_button.position = Vector2.ZERO
	card_button.size = size
	card_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if preview_only:
		card_button.mouse_default_cursor_shape = Control.CURSOR_ARROW
		card_button.mouse_filter = Control.MOUSE_FILTER_PASS
		card_button.mouse_force_pass_scroll_events = true
		card_button.focus_mode = Control.FOCUS_NONE
	for state_name in ["normal","hover","pressed","disabled","focus"]:
		card_button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	card_button.tooltip_text = data.get("description", "") + "\n攻击牌选中后居中置顶，非攻击牌选中后跟随鼠标。非攻击牌选中期间左键优先出牌，不触发其他按钮；自身技能／能力可在画面内任意位置使用，指定敌人的技能仍需点击敌人。Esc／右键取消。"
	if preview_only: card_button.tooltip_text = data.get("description", "")
	card_button.pressed.connect(func(): if enabled: chosen.emit(uid))
	if managed_input:
		card_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		card_button.mouse_entered.connect(func(): hover(true))
		card_button.mouse_exited.connect(func(): hover(false))
	add_child(card_button)
	if not allow_zoom_preview: card_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func(): if not is_visible_in_tree(): hide_zoom_preview())

func build_fixed_face() -> void:
	# The hit/animation footprint remains 180x230. The 3:4 artwork is letterboxed.
	fixed_layer = Control.new()
	fixed_layer.position = FACE_RECT.position
	fixed_layer.scale = Vector2.ONE * FACE_SCALE
	fixed_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fixed_layer)
	var cost_bounds := face_cost_rect()
	var cost_size: int = face_cost_sizes()[0]
	cost_label = label(fixed_layer, str(int(data.cost)), cost_bounds.position, cost_bounds.size, cost_size, face_base_cost_color())
	cost_label.add_theme_font_override("font", fixed_font(cost_size))
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	fit_fixed_cost()
	cost_label.hide()
	var rules := face_rules_rect()
	effect_label = label(fixed_layer, data.get("cardText", data.get("description", "")), rules.position, rules.size, 70, FACE_RULE_COLOR)
	effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	effect_label.add_theme_constant_override("line_spacing", 15)
	fit_effect_text()
	effect_label.hide()

func face_rules_rect() -> Rect2:
	return FACE_RULES

func face_cost_rect() -> Rect2:
	return Rect2(39, 79, 160, 180)

func face_cost_center() -> Vector2:
	# The no-character master uses Pillow's text anchor; match its visible ink center.
	return Vector2(119, 169)

func face_cost_sizes() -> Array:
	return [152, 138, 124, 108]

func face_base_cost_color() -> Color:
	return Color("eeeee7") if data.get("rarity") == "C" else rarity_color()

func face_cost_background() -> Color:
	return Color("b53660") if data.get("rarity") == "C" else Color("101016")

func fixed_font(font_size: int) -> FontVariation:
	var result := FontVariation.new()
	result.base_font = face_font
	# Use the template typeface with a compact line box; no synthetic bold/stretch.
	result.spacing_top = -roundi(font_size * 0.20)
	result.spacing_bottom = -roundi(font_size * 0.20)
	return result

func fit_fixed_cost() -> void:
	# Center visible numeral ink, not the CJK font's asymmetric ascent/descent box.
	var file := face_font as FontFile
	if file == null: return
	var bounds := face_cost_rect()
	var font_size: int = face_cost_sizes()[0]
	for candidate in face_cost_sizes():
		font_size = candidate
		if file.get_string_size(cost_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, candidate).x <= bounds.size.x: break
	var typeface := fixed_font(font_size)
	cost_label.add_theme_font_override("font", typeface)
	cost_label.add_theme_font_size_override("font_size", font_size)
	cost_label.size = bounds.size
	var ink := Rect2()
	var pen := 0.0
	for i in cost_label.text.length():
		var glyph := file.get_glyph_index(font_size, cost_label.text.unicode_at(i), 0)
		file.render_glyph(0, Vector2i(font_size, 0), glyph)
		var glyph_box := Rect2(Vector2(pen, 0) + file.get_glyph_offset(0, Vector2i(font_size, 0), glyph), file.get_glyph_size(0, Vector2i(font_size, 0), glyph))
		ink = glyph_box if i == 0 else ink.merge(glyph_box)
		pen += file.get_glyph_advance(0, font_size, glyph).x
	var baseline := Vector2((bounds.size.x - pen) / 2.0, (bounds.size.y - typeface.get_height(font_size)) / 2.0 + typeface.get_ascent(font_size))
	cost_label.position = face_cost_center() - baseline - ink.get_center()
	cost_ink_bounds = Rect2(cost_label.position + baseline + ink.position, ink.size)

func _draw() -> void:
	if face_texture != null:
		draw_texture_rect(face_texture, FACE_RECT, false)
		# Erase only baked fields whose live values changed. The static face stays exact.
		if cost_changed:
			var center := Vector2(119, 168)
			var radius := 92.0
			var color := face_cost_background()
			draw_circle(FACE_RECT.position + center * FACE_SCALE, radius * FACE_SCALE, color)
		if rules_changed:
			var rules := face_rules_rect()
			draw_rect(Rect2(FACE_RECT.position + (rules.position - Vector2(2, 2)) * FACE_SCALE, (rules.size + Vector2(4, 4)) * FACE_SCALE), Color("1c1c25"))
		if selected or hovered:
			var edge := Rect2(FACE_RECT.position + Vector2(40, 36) * FACE_SCALE, Vector2(1024, 1396) * FACE_SCALE)
			draw_style_box(face_highlight(), edge)
		return
	var pts := PackedVector2Array([Vector2(0,12),Vector2(12,0),Vector2(164,0),Vector2(180,16),Vector2(180,216),Vector2(166,230),Vector2(0,230)])
	draw_colored_polygon(pts, Color("202a31") if hovered or selected else INK)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, CREAM if selected else rarity_color(), 2.5 if selected else 1.3, true)
	if selected or hovered:
		draw_polyline(outline, Color(0.95,0.25,0.55,0.16) if selected else Color(0.2,0.85,0.95,0.13), 8.0, true)
	if data.has("rarity"):
		var accent := rarity_color()
		draw_colored_polygon(PackedVector2Array([Vector2(12,5),Vector2(160,5),Vector2(175,20),Vector2(175,59),Vector2(5,59),Vector2(5,12)]), Color("202632"))
		draw_colored_polygon(PackedVector2Array([Vector2(12,5),Vector2(48,5),Vector2(54,11),Vector2(54,49),Vector2(47,56),Vector2(5,56),Vector2(5,12)]), accent)
		draw_colored_polygon(PackedVector2Array([Vector2(8,65),Vector2(172,65),Vector2(172,197),Vector2(8,197)]), Color("141a24"))
		draw_line(Vector2(60,59),Vector2(166,59),accent.darkened(0.45),1)
		# Frame the central rank without putting decoration behind the rules text.
		for x in [17.0, 133.0]:
			draw_line(Vector2(x,84),Vector2(x+30,84),accent.darkened(0.48),1)
			draw_line(Vector2(x+8,88),Vector2(x+22,88),accent.darkened(0.7),1)
		draw_line(Vector2(15,202),Vector2(165,202),accent.darkened(0.55),1)
		draw_colored_polygon(PackedVector2Array([Vector2(158,5),Vector2(164,5),Vector2(175,16),Vector2(175,22)]),accent)
		return
	draw_colored_polygon(PackedVector2Array([Vector2(12,5),Vector2(160,5),Vector2(175,20),Vector2(175,68),Vector2(5,78),Vector2(5,12)]),rarity_color())
	draw_colored_polygon(PackedVector2Array([Vector2(8,85),Vector2(172,76),Vector2(172,138),Vector2(8,149)]),Color("222736"))
	for i in range(5):
		draw_line(Vector2(18,90+i*10),Vector2(42+(i%2)*16,90+i*10),Color("4c6e71"),1)
		draw_line(Vector2(124,90+i*10),Vector2(163,90+i*10),Color("4c6e71"),1)
	draw_line(Vector2(18,189),Vector2(162,189),Color("37465c"),1)
	draw_circle(Vector2(158,24),3,PINK)

func set_selected(value: bool) -> void:
	selected = value
	if selected: hide_zoom_preview()
	queue_redraw()
	refresh_pose()

func set_enabled(value: bool) -> void:
	enabled = value and not preview_only
	if not value: hide_zoom_preview()
	if is_instance_valid(card_button): card_button.disabled = not value
	if value and (hovered or selected): refresh_pose()

func hover(value: bool) -> void:
	if hovered == value: return
	hovered = value
	hover_generation += 1
	if value and allow_zoom_preview and not selected:
		show_zoom_after_delay(hover_generation)
	else:
		hide_zoom_preview()
	queue_redraw()
	refresh_pose()

func move_home(value: Vector2) -> void:
	home = value
	refresh_pose(true)

func drag_to(point: Vector2) -> void:
	if preview_only or not enabled: return
	hide_zoom_preview()
	dragging = true
	if hover_tween: hover_tween.kill()
	rotation = 0.0
	scale = Vector2.ONE
	global_position = point - pivot_offset
	z_index = maxi(50,lifted_z+1)

func stop_drag() -> void:
	if not dragging: return
	dragging = false
	refresh_pose()

func refresh_pose(force: bool = false) -> void:
	if preview_only or dragging: return
	if not enabled and not force: return
	if hover_tween: hover_tween.kill()
	hover_tween = create_tween().set_parallel(true)
	var lifted := hovered or selected
	z_index = (maxi(50,lifted_z+1) if selected else lifted_z) if lifted else home_z
	var anchor := selection_home if selected and center_on_selection else home
	hover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self,"position",anchor + Vector2(0,-150 if selected else (-140 if lifted else 0)),0.14)
	hover_tween.tween_property(self,"scale",Vector2.ONE * (1.12 if lifted else home_scale),0.14)
	hover_tween.tween_property(self,"rotation",0.0 if lifted else home_rotation,0.14)

func show_cost(value: int) -> void:
	if is_instance_valid(cost_label):
		cost_label.text = str(value)
		var discounted := value < int(data.get("cost", 0))
		cost_label.add_theme_color_override("font_color", (CYAN if discounted else face_base_cost_color()) if face_texture != null else (Color("07514d") if discounted else INK))
		cost_label.add_theme_color_override("font_outline_color", CYAN if value < int(data.get("cost", 0)) else Color.TRANSPARENT)
		cost_label.add_theme_constant_override("outline_size", 1 if value < int(data.get("cost", 0)) else 0)
		if face_texture != null:
			fit_fixed_cost()
			cost_changed = value != int(data.get("cost", 0))
			cost_label.visible = cost_changed
			queue_redraw()
		if is_instance_valid(zoom_card): zoom_card.show_cost(value)

func show_preview(preview: Dictionary) -> void:
	if not is_instance_valid(effect_label): return
	var text: String = preview.get("cardText", data.get("cardText", data.get("description", "")))
	if text.is_empty(): return
	effect_label.text = text
	fit_effect_text()
	card_button.tooltip_text = preview.get("description", data.get("description", text))
	if face_texture != null:
		rules_changed = text != str(data.get("cardText", data.get("description", "")))
		effect_label.visible = rules_changed
		queue_redraw()
	if is_instance_valid(zoom_card):
		zoom_card.show_preview(preview)
		zoom_description.text = card_button.tooltip_text

func fit_effect_text() -> void:
	if face_texture != null:
		var bounds := face_rules_rect()
		var font_sizes := [70, 66, 62, 58, 54, 50, 46, 42, 38, 36]
		for font_size in font_sizes:
			var typeface := fixed_font(font_size)
			effect_label.add_theme_font_override("font", typeface)
			effect_label.add_theme_font_size_override("font_size", font_size)
			var measured := typeface.get_multiline_string_size(effect_label.text, HORIZONTAL_ALIGNMENT_CENTER, bounds.size.x, font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
			var lines := maxi(1, ceili(measured.y / typeface.get_height(font_size)))
			if measured.y + (lines - 1) * 15 <= bounds.size.y: break
		effect_label.size = bounds.size
		return
	# Initial and calculated rules use the same bounds and wrapping budget.
	# A Label may expand to its text minimum before fitting; use the fixed design bounds.
	var bounds := EFFECT_SIZE if data.has("rarity") else effect_label.size
	var font_size := 14 if data.has("rarity") else 16
	while font_size > 10 and base_font.get_multiline_string_size(effect_label.text, effect_label.horizontal_alignment, bounds.x, font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y > bounds.y - 2:
		font_size -= 1
	effect_label.add_theme_font_size_override("font_size", font_size)
	effect_label.size = bounds

func face_highlight() -> StyleBoxFlat:
	var highlight := StyleBoxFlat.new()
	highlight.bg_color = Color.TRANSPARENT
	highlight.draw_center = false
	highlight.border_color = CREAM if selected else rarity_color().lightened(0.25)
	highlight.set_border_width_all(2 if selected else 1)
	highlight.set_corner_radius_all(4)
	highlight.shadow_color = Color(0.95, 0.25, 0.55, 0.32) if selected else Color(0.2, 0.85, 0.95, 0.22)
	highlight.shadow_size = 4
	return highlight

func show_zoom_after_delay(generation: int) -> void:
	await get_tree().create_timer(0.45).timeout
	if generation != hover_generation or not hovered or selected or dragging or not is_visible_in_tree() or not can_process(): return
	if not preview_only and not enabled: return
	show_zoom_preview()

func show_zoom_preview() -> void:
	if not allow_zoom_preview or is_instance_valid(zoom_layer): return
	zoom_layer = CanvasLayer.new()
	zoom_layer.layer = 15
	add_child(zoom_layer)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_layer.add_child(holder)
	var zoom_size := Vector2(180, 230) * ZOOM_SCALE
	# Stay beside the card, and above the hand, in the existing 1440x900 canvas.
	var origin := get_global_transform() * Vector2.ZERO
	var x := origin.x + 220
	if x + zoom_size.x > 1424: x = origin.x - zoom_size.x - 24
	if managed_input: x = 24
	holder.position = Vector2(clampf(x, 16, 1424 - zoom_size.x), clampf(origin.y - 180, 88, 800 - zoom_size.y - 132))
	rect(holder, Vector2(-8, -8), zoom_size + Vector2(16, 148), Color("090b12"))
	zoom_card = CombatCard.new()
	zoom_card.allow_zoom_preview = false
	zoom_card.managed_input = true
	zoom_card.setup(uid, data, true)
	# Keep the same resolved source even if resources changed since this view opened.
	zoom_card.face_texture = face_texture
	zoom_card.face_font = face_font
	zoom_card.face_template_id = face_template_id
	zoom_card.pivot_offset = Vector2.ZERO
	zoom_card.scale = Vector2.ONE * ZOOM_SCALE
	holder.add_child(zoom_card)
	if is_instance_valid(cost_label): zoom_card.show_cost(int(cost_label.text))
	zoom_card.show_preview({"cardText": effect_label.text, "description": card_button.tooltip_text})
	zoom_description = label(holder, card_button.tooltip_text, Vector2(8, zoom_size.y + 6), Vector2(zoom_size.x - 16, 126), 17, CREAM)
	zoom_description.clip_text = true

func hide_zoom_preview() -> void:
	hover_generation += 1
	if is_instance_valid(zoom_layer):
		zoom_layer.hide()
		zoom_layer.queue_free()
	zoom_layer = null
	zoom_card = null
	zoom_description = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_EXIT_TREE: hide_zoom_preview()
