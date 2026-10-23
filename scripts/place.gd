extends DemoUI

func _ready() -> void:
	var p := Game.place_data(Game.state.currentPlaceId)
	background(p.backgroundAssetId, 0.30)
	chrome("地点探索")
	tag("LOCATION / " + p.id.to_upper(), Vector2(68,137), CYAN, 300)
	label(self, p.name, Vector2(64,211), Vector2(745,95), 64)
	label(self, p.description, Vector2(69,333), Vector2(650,130), 23)
	cut_panel(self, Vector2(827,129), Vector2(542,641), Color("090b12ed"), CREAM)
	rect(self,Vector2(860,217),Vector2(100,4),PINK)
	label(self, "此地的故事", Vector2(859,159), Vector2(455,55), 30)
	label(self, "每完成一个事件推进1天 · 地图最多3个事件", Vector2(861,228), Vector2(453,45), 16, MUTED)
	var available := Game.available_events(p.id)
	if available.is_empty():
		label(self, "此刻，一切安静。", Vector2(861,350), Vector2(455,60), 27)
		label(self, "这里暂时没有新的事件。\n未开放的服务与后续内容待设计。", Vector2(861,425), Vector2(455,100), 20, MUTED)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(859,290)
	scroll.size = Vector2(485,460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(455,0)
	scroll.add_child(content)
	var y := 0
	for e in available:
		label(content, "刷新时间：" + Game.event_refresh_time_label(e), Vector2(2,y), Vector2(450,32), 16, CYAN)
		button(content, e.title + "    →", Vector2(0,y+42), Vector2(455,60), func(): Game.start_event(e.id), true)
		label(content, e.description, Vector2(2,y+116), Vector2(451,72), 18, MUTED)
		if not e.demoNote.is_empty():
			label(content, e.demoNote, Vector2(2,y+191), Vector2(451,65), 15, CYAN)
			y += 275
		else: y += 205
	content.custom_minimum_size.y = y
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
	fade_in()
