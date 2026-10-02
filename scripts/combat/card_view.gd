class_name CombatCard
extends DemoUI
signal chosen(uid: String)
var uid := ""
var data: Dictionary = {}
var home := Vector2.ZERO
var enabled := false
var selected := false
var hover_tween: Tween
var card_button: Button

func setup(card_uid: String, definition: Dictionary) -> void:
	uid = card_uid
	data = definition
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(180,230)
	pivot_offset = Vector2(90,115)
	mouse_filter = Control.MOUSE_FILTER_PASS
	queue_redraw()

func _ready() -> void:
	label(self, "PROTOTYPE / 01", Vector2(17,12), Vector2(150,19), 10, CYAN)
	label(self, data.get("name", "临时攻击"), Vector2(17,37), Vector2(150,35), 23)
	# The temporary circuit motif is a vector UI template, not a formal card illustration.
	var art := image_asset(self, data.get("artAssetId", ""), Vector2(18,78), Vector2(144,67), true)
	if art == null:
		label(self, "╱╱", Vector2(52,72), Vector2(110,73), 53, CYAN)
	label(self, "攻击 1" if data.get("prototype",false) else data.get("description", ""), Vector2(18,151), Vector2(149,38), 23, CREAM)
	label(self, "临时测试卡 · 无费用" if data.get("cost") == null else "费用 %s" % data.cost, Vector2(18,197), Vector2(155,23), 12, MUTED)
	card_button = Button.new()
	card_button.flat = true
	card_button.position = Vector2.ZERO
	card_button.size = size
	card_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state_name in ["normal","hover","pressed","disabled","focus"]:
		card_button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	card_button.tooltip_text = data.get("description", "") + "\n点击选牌，再点击敌方；再次点击选牌可取消。"
	card_button.pressed.connect(func(): if enabled: chosen.emit(uid))
	card_button.mouse_entered.connect(func(): hover(true))
	card_button.mouse_exited.connect(func(): hover(false))
	add_child(card_button)

func _draw() -> void:
	var pts := PackedVector2Array([Vector2(0,12),Vector2(12,0),Vector2(164,0),Vector2(180,16),Vector2(180,216),Vector2(166,230),Vector2(0,230)])
	draw_colored_polygon(pts, Color("101b2b"))
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, PINK if selected else CYAN, 2.5 if selected else 1.3, true)
	draw_rect(Rect2(8,78,164,70),Color("0c2939"))
	for i in range(5):
		draw_line(Vector2(18,90+i*10),Vector2(42+(i%2)*16,90+i*10),Color("266373"),1)
		draw_line(Vector2(124,90+i*10),Vector2(163,90+i*10),Color("266373"),1)
	draw_line(Vector2(18,189),Vector2(162,189),Color("37465c"),1)
	draw_circle(Vector2(158,24),3,PINK)

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()
	hover(value)

func set_enabled(value: bool) -> void:
	enabled = value
	if is_instance_valid(card_button): card_button.disabled = not value

func hover(value: bool) -> void:
	if not enabled: return
	if hover_tween: hover_tween.kill()
	hover_tween = create_tween().set_parallel(true)
	var lifted := value or selected
	z_index = 25 if lifted else 10
	hover_tween.tween_property(self,"position",home + Vector2(0,-45 if lifted else 0),0.14)
	hover_tween.tween_property(self,"scale",Vector2.ONE * (1.06 if lifted else 1.0),0.14)
