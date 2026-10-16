class_name CombatCard
extends DemoUI
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
const RARITY_COLORS := {"C": Color("a6adb7"), "B": Color("5aa9ff"), "A": Color("f25b69"), "S": Color("f2c35c")}

func rarity_color() -> Color:
	return RARITY_COLORS.get(data.get("rarity", ""), CYAN)

func setup(card_uid: String, definition: Dictionary, read_only: bool = false) -> void:
	uid = card_uid
	data = definition
	preview_only = read_only
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(180,230)
	pivot_offset = Vector2(90,115)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if managed_input else Control.MOUSE_FILTER_PASS
	queue_redraw()

func _ready() -> void:
	if data.has("rarity"):
		label(self, "%s · %s" % [data.rarity, data.get("archetype", "诺伦")], Vector2(14,10), Vector2(137,20), 10, INK)
		label(self, data.name, Vector2(14,34), Vector2(151,35), 22, INK)
		var text: String = data.get("cardText", data.get("description", ""))
		var font_size := 11 if text.length() > 90 else (12 if text.length() > 60 else 14)
		while font_size > 10 and base_font.get_multiline_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,152,font_size,-1,TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y > 112:
			font_size -= 1
		var description := label(self, text, Vector2(14,82), Vector2(152,114), font_size, CREAM)
		description.add_theme_constant_override("line_spacing", 0)
		var kind: String = {"attack":"攻击", "skill":"技能", "power":"能力"}.get(data.get("type"), "卡牌")
		label(self, kind + (" · 消耗" if data.get("exhaust", false) else ""), Vector2(14,204), Vector2(96,19), 11, rarity_color())
		cost_label = label(self, "费用 %d" % int(data.cost), Vector2(113,204), Vector2(57,19), 11, CREAM)
	else:
		label(self, "LEGACY / TEST", Vector2(17,12), Vector2(150,19), 10, INK)
		label(self, data.get("name", "临时攻击"), Vector2(17,37), Vector2(150,35), 23, INK)
		var art := image_asset(self, data.get("artAssetId", ""), Vector2(18,78), Vector2(144,67), true)
		if art == null: label(self, "╱╱", Vector2(54,72), Vector2(110,73), 53, PINK)
		label(self, data.get("description", ""), Vector2(18,151), Vector2(149,38), 16, CREAM)
		label(self, "旧版测试卡 · 无费用", Vector2(18,197), Vector2(155,23), 12, MUTED)
	card_button = Button.new()
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

func _draw() -> void:
	var pts := PackedVector2Array([Vector2(0,12),Vector2(12,0),Vector2(164,0),Vector2(180,16),Vector2(180,216),Vector2(166,230),Vector2(0,230)])
	draw_colored_polygon(pts, Color("202a31") if hovered or selected else INK)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, CREAM if selected else rarity_color(), 2.5 if selected else 1.3, true)
	if selected or hovered:
		draw_polyline(outline, Color(0.95,0.25,0.55,0.16) if selected else Color(0.2,0.85,0.95,0.13), 8.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(12,5),Vector2(160,5),Vector2(175,20),Vector2(175,68),Vector2(5,78),Vector2(5,12)]),rarity_color())
	if data.has("rarity"):
		draw_line(Vector2(14,198),Vector2(166,198),rarity_color().darkened(0.55),1)
		return
	draw_colored_polygon(PackedVector2Array([Vector2(8,85),Vector2(172,76),Vector2(172,138),Vector2(8,149)]),Color("222736"))
	for i in range(5):
		draw_line(Vector2(18,90+i*10),Vector2(42+(i%2)*16,90+i*10),Color("4c6e71"),1)
		draw_line(Vector2(124,90+i*10),Vector2(163,90+i*10),Color("4c6e71"),1)
	draw_line(Vector2(18,189),Vector2(162,189),Color("37465c"),1)
	draw_circle(Vector2(158,24),3,PINK)

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()
	refresh_pose()

func set_enabled(value: bool) -> void:
	enabled = value and not preview_only
	if is_instance_valid(card_button): card_button.disabled = not value
	if value and (hovered or selected): refresh_pose()

func hover(value: bool) -> void:
	if hovered == value: return
	hovered = value
	queue_redraw()
	refresh_pose()

func move_home(value: Vector2) -> void:
	home = value
	refresh_pose(true)

func drag_to(point: Vector2) -> void:
	if preview_only or not enabled: return
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
		cost_label.text = "费用 %d" % value
		cost_label.modulate = CYAN if value < int(data.get("cost", 0)) else Color.WHITE
