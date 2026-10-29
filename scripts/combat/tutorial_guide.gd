extends DemoUI
## Read-only teaching UI. Combat rules, card movement and saving remain with their owners.
const GUIDE_POSITION := Vector2(30, 100)
const GUIDE_SIZE := Vector2(560, 330)
const COLLAPSED_SIZE := Vector2(250, 36)
const HOVER_SECONDS := 0.7
const LESSONS := [
	{
		"title":"能量与出牌",
		"body":"每回合恢复 3 点能量，剩余不会累积。\n卡牌左上角显示费用；能量不足可结束回合。\n选中卡牌后点击有效目标，或拖至目标松开。",
		"task":"试一试：打出「护身」，观察能量与格挡。",
		"done":"已打出护身；留意左下能量和诺伦血条旁的格挡。"
	},
	{
		"title":"认识卡牌类型",
		"body":"攻击：造成伤害。技能：格挡、抽牌、换形态。\n能力：本场持续，打出后进入消耗区。\n悬停放大卡牌看类型；特殊牌以牌面为准。",
		"task":"试一试：打出教学牌「剖解经验」，查看消耗区。",
		"done":"已打出能力牌；剖解经验本场持续，卡牌不再循环抽回。"
	},
	{
		"title":"抽牌堆与弃牌堆",
		"body":"打出的普通牌、回合末剩余手牌进入弃牌堆。\n需要抽牌而抽牌堆为空时，弃牌会洗回。\n消耗牌不再洗回。点击两侧牌堆查看内容。",
		"task":"试一试：分别打开抽牌堆与弃牌堆，再关闭面板。",
		"done":"已查看两个牌堆；列表只供查看，不改变实际抽牌顺序。"
	},
	{
		"title":"诺伦：形态与弹药",
		"body":"近战：每实际打出一段攻击回 1 发弹药。\n远程：通常每张攻击耗 1 发，伤害 ×1.5。\n切远程：下张攻击 -1 费；切近战：抽 2 张。\n悬停诺伦可查看完整机制。",
		"task":"试一试：用「拉开距离」切远程，再用「贴近」切回。",
		"done":"已切换过形态；同形态重复使用不会触发切入奖励。"
	},
	{
		"title":"查看敌人机制",
		"body":"悬停敌人或头顶意图，查看下次行动与机制。\n鱼每段攻击实际扣血时，追加 2 层污染；\n完全格挡可避免追加污染。鱼死亡时施加 3 层。",
		"task":"试一试：鼠标停在鱼或意图图标上，等说明展开。",
		"done":"已悬停查看敌人；结束回合前先判断它准备做什么。"
	},
	{
		"title":"查看 Buff 与减益",
		"body":"悬停血条下方的小图标，查看名称、层数和效果。\n剖解经验或贴近可产生能力／弹反状态。\n污染在自身回合末造成当前层数伤害，再减 1 层。",
		"task":"试一试：取消选牌，悬停任意状态图标，等说明展开。",
		"done":"已悬停查看状态；不同状态的消退方式以说明为准。"
	},
	{
		"title":"自由实战",
		"body":"结束回合后，敌人按头顶意图行动。\n轮到你时，恢复 3 能量并抽 5 张牌。\n继续练习并击败鱼，或点击右上「退出教程」。\n本场不影响冒险进度，也不发放奖励。",
		"task":"试一试：结束一次回合，再用学到的机制击败变异鱼。",
		"done":"已完成一次回合循环；可收起提示，继续练习。"
	}
]

var battle_view
var step_index := 0
var collapsed := false
var completed: Dictionary = {}
var inspected_piles: Dictionary = {}
var panel_view: Panel
var title_label: Label
var body_label: Label
var task_label: Label
var previous_button: Button
var next_button: Button
var collapse_button: Button
var expand_button: Button
var hovered_inspection: Control
var hover_elapsed := 0.0
var initial_stance := "melee"
var highlights: Array[Rect2] = []
var guidance_targets: Array[Dictionary] = []
var leader_paths: Array[PackedVector2Array] = []
var progress_segments: Array[ColorRect] = []
var step_label: Label
var task_caption: Label
var task_panel: Panel
var visual_time := 0.0
var target_label_style: StyleBoxFlat

func configure(view: Control) -> void:
	battle_view = view
	name = "TutorialGuide"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	initial_stance = str(battle_view.model.stance)
	target_label_style = _target_label_style()
	panel_view = panel(self, GUIDE_POSITION, GUIDE_SIZE, Color("0d1523f7"), Color("407a86"))
	panel_view.name = "TutorialPanel"
	panel_view.mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := style(Color("0d1523f7"), Color("426a7b"))
	frame.set_corner_radius_all(10)
	frame.border_width_left = 1
	frame.shadow_color = Color(0, 0, 0, 0.30)
	frame.shadow_size = 12
	panel_view.add_theme_stylebox_override("panel", frame)
	label(panel_view, "战斗入门  /  诺伦", Vector2(22, 13), Vector2(250, 18), 12, MUTED)
	step_label = label(panel_view, "", Vector2(358, 12), Vector2(83, 22), 14, CYAN)
	title_label = label(panel_view, "", Vector2(22, 35), Vector2(510, 35), 26, CREAM)
	for index in LESSONS.size():
		progress_segments.append(rect(panel_view, Vector2(22 + index * 74, 79), Vector2(66, 3), Color("29414e")))
	body_label = label(panel_view, "", Vector2(22, 94), Vector2(516, 112), 17, Color("ccd8df"))
	task_panel = panel(panel_view, Vector2(16, 215), Vector2(528, 59), Color("152b35"), Color("2d5962"))
	var task_style := style(Color("152b35"), Color("2d5962"))
	task_style.set_corner_radius_all(6)
	task_panel.add_theme_stylebox_override("panel", task_style)
	task_caption = label(panel_view, "现在试一试", Vector2(28, 220), Vector2(490, 16), 11, CYAN)
	task_label = label(panel_view, "", Vector2(28, 240), Vector2(498, 31), 14, CREAM)
	previous_button = _guide_button("TutorialPrevious", "上一步", Vector2(24, 288), Vector2(100, 30), _previous)
	next_button = _guide_button("TutorialNext", "下一步  →", Vector2(414, 288), Vector2(122, 30), _next)
	collapse_button = _guide_button("TutorialCollapse", "收起", Vector2(458, 10), Vector2(78, 28), _collapse)
	var hint := label(panel_view, "跟随指示线操作 · 可自由翻页", Vector2(132, 294), Vector2(273, 22), 12, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	expand_button = button(self, "展开新手教程", GUIDE_POSITION, COLLAPSED_SIZE, _expand)
	expand_button.name = "TutorialExpand"
	expand_button.add_theme_font_size_override("font_size", 16)
	expand_button.hide()
	battle_view.card_played.connect(_on_card_played)
	battle_view.pile_inspected.connect(_on_pile_inspected)
	_refresh_text()

func _guide_button(node_name: String, text: String, pos: Vector2, dimensions: Vector2, action: Callable) -> Button:
	var control := button(panel_view, text, pos, dimensions, action)
	control.name = node_name
	control.add_theme_font_size_override("font_size", 14)
	return control

func blocks_pointer(point: Vector2 = Vector2.INF) -> bool:
	if not is_visible_in_tree(): return false
	var surface: Control = expand_button if collapsed else panel_view
	var pointer := get_global_mouse_position() if point == Vector2.INF else point
	return is_instance_valid(surface) and surface.is_visible_in_tree() and surface.get_global_rect().has_point(pointer)

func set_step(index: int) -> void:
	step_index = clampi(index, 0, LESSONS.size() - 1)
	_refresh_text()
	_update_highlights()
	queue_redraw()

func _previous() -> void:
	set_step(step_index - 1)

func _next() -> void:
	if step_index == LESSONS.size() - 1:
		_collapse()
	else:
		set_step(step_index + 1)

func _collapse() -> void:
	collapsed = true
	panel_view.hide()
	expand_button.show()
	expand_button.grab_focus()
	_update_highlights()
	queue_redraw()

func _expand() -> void:
	collapsed = false
	panel_view.show()
	expand_button.hide()
	collapse_button.grab_focus()
	_update_highlights()
	queue_redraw()

func _refresh_text() -> void:
	if not is_instance_valid(title_label): return
	var lesson: Dictionary = LESSONS[step_index]
	title_label.text = lesson.title
	step_label.text = "%02d / %02d" % [step_index + 1, LESSONS.size()]
	for index in progress_segments.size():
		progress_segments[index].color = CYAN if index == step_index else (Color("377b79") if completed.get(index, false) else Color("29414e"))
	task_caption.text = "已练习 · 可以继续下一步" if completed.get(step_index, false) else "现在试一试"
	body_label.text = lesson.body
	task_label.text = lesson.done if completed.get(step_index, false) else str(lesson.task).trim_prefix("试一试：")
	task_label.add_theme_color_override("font_color", CYAN if completed.get(step_index, false) else MUTED)
	previous_button.disabled = step_index == 0
	next_button.text = "收起并练习" if step_index == LESSONS.size() - 1 else "下一步  →"
	expand_button.text = "新手教程 · 第 %d / %d 步" % [step_index + 1, LESSONS.size()]

func _mark_complete(index: int) -> void:
	if completed.get(index, false): return
	completed[index] = true
	_refresh_text()

func _on_card_played(uid: String) -> void:
	var definition: Dictionary = battle_view.model.card(uid)
	if definition.get("id", "") == "noren_02": _mark_complete(0)
	if definition.get("id", "") == "noren_40": _mark_complete(1)

func _on_pile_inspected(title: String) -> void:
	if title in ["抽牌堆", "弃牌堆"]:
		inspected_piles[title] = true
		if inspected_piles.size() == 2: _mark_complete(2)

func _process(delta: float) -> void:
	visual_time += delta
	if not is_instance_valid(battle_view): return
	# Keep modal overlays, animations and their input entirely with the battle.
	visible = battle_view.initialized and not Game.battle_busy and not Game.transition_locked and not is_instance_valid(battle_view.pile_overlay) and battle_view.model.outcome.is_empty()
	if str(battle_view.model.stance) != initial_stance: _mark_complete(3)
	if int(battle_view.model.turn) > 1: _mark_complete(6)
	if not visible:
		_clear_guidance()
		queue_redraw()
		hovered_inspection = null
		hover_elapsed = 0.0
		return
	_track_inspection(delta)
	_update_highlights()
	queue_redraw()

func _track_inspection(delta: float) -> void:
	if not battle_view.selected_uid.is_empty():
		hovered_inspection = null
		hover_elapsed = 0.0
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var lesson := -1
	if is_instance_valid(hovered):
		if (hovered is Button and hovered in battle_view.targets) or hovered in battle_view.enemy_intents:
			lesson = 4
		elif hovered.get_script() == preload("res://scripts/combat/status_badge.gd"):
			lesson = 5
	if lesson < 0:
		hovered_inspection = null
		hover_elapsed = 0.0
		return
	if hovered != hovered_inspection:
		hovered_inspection = hovered
		hover_elapsed = 0.0
	hover_elapsed += delta
	if hover_elapsed >= HOVER_SECONDS: _mark_complete(lesson)

## All target geometry is in this guide's canvas coordinates. Lines never own input.
func _clear_guidance() -> void:
	highlights.clear()
	guidance_targets.clear()
	leader_paths.clear()

func _target_rect(area: Rect2, caption: String, kind: String) -> void:
	area = area.intersection(Rect2(8, 84, 1424, 808))
	if not area.has_area() or guidance_targets.size() >= 2: return
	guidance_targets.append({"rect":area, "label":caption, "kind":kind})
	highlights.append(area)

func _target_control(control: Control, caption: String, kind: String) -> void:
	if not is_instance_valid(control) or not control.is_visible_in_tree(): return
	var area := get_global_transform().affine_inverse() * (control.get_global_transform() * Rect2(Vector2.ZERO, control.size))
	_target_rect(area.grow(5), caption, kind)

func _target_pile(draw: bool) -> void:
	# Counts are anchored to the actual pile controls, including window transforms.
	var count: Label = battle_view.draw_count if draw else battle_view.discard_count
	var origin := get_global_transform().affine_inverse() * count.global_position
	_target_rect(Rect2(origin - Vector2(5, 8), Vector2(56, 68)), "点击查看抽牌堆" if draw else "点击查看弃牌堆", "pile")

func _target_card(ids: Array, caption: String) -> void:
	for id in ids:
		for uid in battle_view.model.hand:
			if battle_view.model.card(uid).get("id", "") != id or not battle_view.cards.has(uid): continue
			if not battle_view.model.play_error(uid).is_empty():
				_target_control(battle_view.end_button, "能量不足时，先结束回合", "end_turn")
			elif battle_view.selected_uid == uid:
				_target_rect(Rect2(630, 465, 150, 112), "点击空地，打出选中的牌", "play_area")
			else:
				_target_control(battle_view.cards[uid], caption, "card")
			return
	# Missing cards may already be in discard; guide the next actionable turn.
	_target_control(battle_view.end_button, "结束回合，等待教学牌抽回", "end_turn")

func _update_highlights() -> void:
	_clear_guidance()
	if collapsed or not visible: return
	match step_index:
		0:
			_target_control(battle_view.energy_panel, "查看剩余能量", "resource")
			if not completed.get(0, false): _target_card(["noren_02"], "打出「护身」")
		1:
			if completed.get(1, false): _target_control(battle_view.exhaust_button, "查看已使用的能力牌", "exhaust")
			else: _target_card(["noren_40"], "打出「剖解经验」")
		2:
			if not inspected_piles.has("抽牌堆"): _target_pile(true)
			elif not inspected_piles.has("弃牌堆"): _target_pile(false)
			else:
				_target_pile(true)
				_target_pile(false)
		3:
			_target_control(battle_view.player_hover, "悬停诺伦，查看形态机制", "actor")
			if not completed.get(3, false):
				_target_card(["noren_04"] if battle_view.model.stance == "melee" else ["noren_03"], "使用形态切换牌")
			else: _target_control(battle_view.ammo_panel, "查看当前弹药", "resource")
		4:
			for intent in battle_view.enemy_intents:
				if intent.is_visible_in_tree():
					_target_control(intent, "悬停意图，查看敌人机制", "intent")
					break
		5:
			for plate in [battle_view.player_plate] + battle_view.enemy_plates:
				for badge in plate.badges:
					if badge.is_visible_in_tree():
						_target_control(badge, "悬停图标，查看状态效果", "status")
						break
				if not guidance_targets.is_empty(): break
			if guidance_targets.is_empty(): _target_card(["noren_40", "noren_03"], "先打出此牌，产生状态图标")
		6:
			_target_control(battle_view.end_button, "点击结束回合", "end_turn")
	for index in guidance_targets.size():
		leader_paths.append(_leader_path(guidance_targets[index], index))

func _leader_path(target: Dictionary, index: int) -> PackedVector2Array:
	var area: Rect2 = target.rect
	var center := area.get_center()
	var box := Rect2(panel_view.position, panel_view.size)
	var start := Vector2(box.end.x, box.position.y + 150 + index * 28)
	if target.kind == "actor":
		start = Vector2(box.end.x, box.end.y - 42)
		var rail_x := box.end.x + 26
		return PackedVector2Array([start, Vector2(rail_x, start.y), Vector2(rail_x, center.y), Vector2(area.end.x + 6, center.y)])
	# Side rails keep long links to the two piles outside characters and hand cards.
	if area.end.x < 225 and center.y > box.end.y:
		start = Vector2(box.position.x, box.end.y - 48 - index * 28)
		return PackedVector2Array([start, Vector2(12, start.y), Vector2(12, center.y), Vector2(area.position.x - 6, center.y)])
	if center.x > 1230 and center.y > box.end.y + 150:
		return PackedVector2Array([start, Vector2(1430, start.y), Vector2(1430, center.y), Vector2(area.end.x + 6, center.y)])
	if target.kind == "status":
		var left_side := center.x < 720
		var rail := 240.0 if left_side else 1180.0
		start = Vector2(box.position.x if left_side else box.end.x, box.end.y - 24)
		return PackedVector2Array([start, Vector2(rail, start.y), Vector2(rail, center.y), Vector2(area.position.x - 6 if left_side else area.end.x + 6, center.y)])
	var end := Vector2(center.x, area.position.y - 6)
	if target.kind == "card":
		start = Vector2(box.end.x - 24, box.end.y)
		var rail_y := maxf(box.end.y + 28, end.y - 48)
		return PackedVector2Array([start, Vector2(start.x, rail_y), Vector2(end.x, rail_y), end])
	if center.x < box.end.x and area.position.y > box.end.y:
		start = Vector2(clampf(center.x, box.position.x + 70, box.end.x - 30), box.end.y)
		return PackedVector2Array([start, Vector2(start.x, end.y - 16), end])
	return PackedVector2Array([start, Vector2(end.x, start.y), end])

func _draw_corners(area: Rect2, tint: Color) -> void:
	var length := minf(14, minf(area.size.x, area.size.y) * 0.3)
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var point: Vector2 = area.position + area.size * corner
		var direction: Vector2 = Vector2.ONE - corner * 2
		draw_polyline(PackedVector2Array([point + Vector2(direction.x * length, 0), point, point + Vector2(0, direction.y * length)]), tint, 2.0, true)

func _draw() -> void:
	if collapsed or not visible: return
	var pulse := 0.65 + sin(visual_time * 3.0) * 0.12
	for index in guidance_targets.size():
		var target: Dictionary = guidance_targets[index]
		var area: Rect2 = target.rect
		var points := leader_paths[index]
		draw_polyline(points, Color(0.02, 0.08, 0.12, 0.8), 5.5, true)
		draw_polyline(points, Color(CYAN, 0.7), 1.6, true)
		draw_circle(points[0], 3.5, CYAN)
		var tip := points[points.size() - 1]
		var direction := (tip - points[points.size() - 2]).normalized()
		var wing := direction.orthogonal() * 4.5
		draw_colored_polygon(PackedVector2Array([tip, tip - direction * 10 + wing, tip - direction * 10 - wing]), CYAN)
		_draw_corners(area, Color(CYAN, pulse))
	# Draw every tag after every line, so a second leader cannot cross its text.
	for target in guidance_targets:
		# Labels stay beside their targets, clamped to the visible combat canvas.
		var font := get_theme_font("font")
		var label_rect := _target_label_rect(target)
		draw_style_box(target_label_style, label_rect)
		draw_string(font, label_rect.position + Vector2(9, 18), target.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("d9fff7"))

func _target_label_rect(target: Dictionary) -> Rect2:
	var area: Rect2 = target.rect
	var font := get_theme_font("font")
	var text_size := font.get_string_size(target.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var label_size := Vector2(text_size.x + 18, 25)
	var label_pos := Vector2(area.get_center().x - label_size.x / 2, area.position.y - 45)
	if target.kind == "pile":
		label_pos = Vector2(area.end.x + 12 if area.get_center().x < 720 else area.position.x - label_size.x - 12, area.get_center().y - 12)
	elif target.kind == "resource" and area.position.y > 680:
		label_pos = Vector2(area.end.x + 12, area.get_center().y - 12)
	elif target.kind == "actor":
		label_pos = Vector2(area.end.x + 14, area.get_center().y - 43)
	elif target.kind == "status":
		label_pos.y = area.end.y + 8
	label_pos.x = clampf(label_pos.x, 9, 1431 - label_size.x)
	label_pos.y = clampf(label_pos.y, 84, 891 - label_size.y)
	return Rect2(label_pos, label_size)

func _target_label_style() -> StyleBoxFlat:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("0c2029f2")
	background.border_color = Color("326c70")
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	return background
