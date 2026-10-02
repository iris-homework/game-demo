extends DemoUI

func _ready() -> void:
	var p := Game.place_data(Game.state.currentPlaceId)
	background(p.backgroundAssetId, 0.30)
	chrome("地点探索")
	tag("LOCATION / " + p.id.to_upper(), Vector2(68,137), CYAN, 300)
	label(self, p.name, Vector2(64,211), Vector2(840,95), 64)
	label(self, p.description, Vector2(69,333), Vector2(650,130), 23)
	panel(self, Vector2(827,129), Vector2(542,641), Color("171321ed"), Color("5f486a"))
	label(self, "此地的故事", Vector2(859,159), Vector2(455,55), 30)
	label(self, "主线优先 · 一次性事件完成后不重复触发", Vector2(861,228), Vector2(453,45), 16, MUTED)
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
		label(content, ("可选" if e.optional else "主线") + "  /  " + e.id, Vector2(2,y), Vector2(450,32), 16, CYAN if e.optional else PINK)
		button(content, e.title + "    →", Vector2(0,y+42), Vector2(455,60), func(): Game.start_event(e.id), true)
		label(content, e.description, Vector2(2,y+116), Vector2(451,72), 18, MUTED)
		if not e.demoNote.is_empty():
			label(content, e.demoNote, Vector2(2,y+191), Vector2(451,65), 15, CYAN)
			y += 275
		else: y += 205
	content.custom_minimum_size.y = y
	if not p.get("services",[]).is_empty():
		button(self,"治疗 · 回复 30% 最大 HP",Vector2(69,605),Vector2(460,63),func(): Game.heal_at(p.id),true)
		label(self,"原型验证：免费；不推进日期；生命回复至上限。",Vector2(69,675),Vector2(650,30),16,CYAN)
	button(self, "← 返回城市地图", Vector2(69,710), Vector2(290,61), Game.go_map)
	fade_in()
