extends DemoUI

const TASK_CHARACTERS_PER_SECOND := 80.0

var _task_rows: Array[Dictionary] = []
var _typing_elapsed := 0.0
var _entry_revision := -1
var _place_id := ""
var _starting := false

func _ready() -> void:
	_place_id = str(Game.state.currentPlaceId)
	_entry_revision = Game.revision
	var p := Game.place_data(_place_id)
	var resident := bool(p.get("mapDisplay", {}).get("resident", false))
	var available := Game.available_events(p.id)
	background(p.backgroundAssetId, 0.30)
	chrome("地点服务" if resident else "任务简报")
	tag("LOCATION / " + str(p.get("displayCode", p.id)).to_upper(), Vector2(68,137), CYAN, 300)
	label(self, p.name, Vector2(64,211), Vector2(745,95), 64)
	label(self, p.description, Vector2(69,333), Vector2(650,180), 23)
	if not resident:
		_build_task_briefing(available)
	var service := Game.healing_service(p.id)
	if not service.is_empty():
		var heal_button := button(self,service.label,Vector2(69,605),Vector2(460,63),func(): Game.heal_at(p.id),true)
		heal_button.name = "heal_place"
		heal_button.disabled = not service.can_heal
		heal_button.tooltip_text = service.hint
		if service.credits_cost > 0:
			heal_button.icon = DemoUI.CREDIT_ICON
			heal_button.expand_icon = true
			heal_button.add_theme_constant_override("icon_max_width",24)
		label(self,service.hint,Vector2(69,673),Vector2(650,44),16,CYAN).name = "healing_hint"
	button(self, "← 返回城市地图", Vector2(69,744 if not service.is_empty() else 710), Vector2(290,61), Game.go_map).name = "return_map"
	set_process(not _task_rows.is_empty())
	fade_in()

func _build_task_briefing(available: Array) -> void:
	cut_panel(self, Vector2(827,129), Vector2(542,641), Color("090b12ed"), CREAM)
	rect(self,Vector2(860,217),Vector2(100,4),PINK)
	label(self, "任务信息", Vector2(859,159), Vector2(455,55), 30)
	if available.is_empty():
		# 兼容停在普通地点里的旧存档，以及当前已没有可用任务的地点。
		label(self, "这里暂时没有新的任务。", Vector2(861,350), Vector2(455,100), 24, MUTED)
		return
	var scroll := ScrollContainer.new()
	scroll.name = "task_scroll"
	scroll.position = Vector2(859,290)
	scroll.size = Vector2(485,450)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	# Keep the slanted button border and hover glow inside the scroll clip.
	var padding := MarginContainer.new()
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(padding)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 28)
	padding.add_child(content)
	for event in available:
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 18)
		content.add_child(block)
		var text := "%s\n\n%s" % [event.title, event.description]
		var info := label(block, text, Vector2.ZERO, Vector2(455,0), 22)
		info.name = "task_info_" + str(event.id)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
		info.visible_characters = 0
		var start := button(block, "开始任务", Vector2.ZERO, Vector2(455,60), _start_task.bind(str(event.id)), true)
		start.name = "event_" + str(event.id)
		start.custom_minimum_size.y = 60
		start.disabled = true
		_task_rows.append({"info":info, "button":start, "id":str(event.id)})

func _process(delta: float) -> void:
	_typing_elapsed += delta
	var count := int(_typing_elapsed * TASK_CHARACTERS_PER_SECOND)
	var finished := true
	for row in _task_rows:
		var info: Label = row.info
		var length := info.get_total_character_count()
		info.visible_characters = mini(count, length)
		var ready := count >= length
		row.button.disabled = not ready or _starting
		finished = finished and ready
	if finished:
		set_process(false)

func _start_task(id: String) -> void:
	if _starting or Game.page != "place" or Game.revision != _entry_revision or str(Game.state.currentPlaceId) != _place_id:
		return
	for row in _task_rows:
		if row.id != id or row.button.disabled:
			continue
		_starting = true
		for entry in _task_rows:
			entry.button.disabled = true
		if not Game.start_event(id):
			_starting = false
			# 被拒绝时恢复已显示完整信息的按钮；保存失败仍由全局重试弹层接管。
			_process(0.0)
		return
