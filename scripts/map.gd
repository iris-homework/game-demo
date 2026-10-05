extends DemoUI
var detail: Control
var selected_id := ""
var hotspots: Dictionary = {}
var map_rect := Rect2(34,162,976,660)

func _ready() -> void:
	rect(self,Vector2.ZERO,Vector2(1440,900),INK)
	var map_asset: String = Game.map_config.cityMapAssetId
	var texture := Game.texture(map_asset)
	if texture:
		var factor := minf(map_rect.size.x/texture.get_width(),map_rect.size.y/texture.get_height())
		var dimensions := texture.get_size()*factor
		map_rect = Rect2(map_rect.position+(map_rect.size-dimensions)/2.0,dimensions)
		image_asset(self,map_asset,map_rect.position,map_rect.size,false)
	else:
		cut_panel(self,map_rect.position,map_rect.size,Color("10151e"),Color("45515d"))
		for x in range(72,1000,48):
			for y in range(194,758,48): rect(self,Vector2(x,y),Vector2(2,2),Color("29333d"))
		label(self,"CITY / OFFLINE",Vector2(67,178),Vector2(800,89),52,Color("ffffff0d"))
		label(self,"城市地图插画待补",Vector2(62,773),Vector2(850,42),25,MUTED)
		label(self,"以下为地区热点调试层 · 正式插画和精确锚点待接入",Vector2(38,124),Vector2(790,37),14,MUTED)
	chrome("城市地区")
	for p in Game.places:
		var anchor := map_rect.position + Vector2(p.mapAnchor[0],p.mapAnchor[1])*map_rect.size
		var dimensions := Vector2(p.hitArea.size[0],p.hitArea.size[1])*map_rect.size
		var open: bool = Game.meets(p.unlockCondition)
		var available: Array = Game.available_events(p.id) if open else []
		var completed := false
		for e in Game.events.values():
			if e.placeId == p.id and e.id in Game.state.completedEventIds: completed = true
		var status := "×" if not open else "✓" if completed and available.is_empty() else "·"
		var hotspot := button(self,status+" "+p.name,anchor-dimensions/2.0,dimensions,func(): select_place(p.id))
		hotspot.add_theme_font_size_override("font_size",16)
		var fill := Color(0.02,0.06,0.12,0.25) if texture else Color("171e2a")
		hotspot.add_theme_stylebox_override("normal",style(fill,Color("73818b") if open else Color("303e52")))
		hotspot.set_meta("idle_style",hotspot.get_theme_stylebox("normal"))
		hotspot.set_meta("idle_color",CREAM if open else Color("7d8297"))
		hotspots[p.id] = hotspot
		hotspot.tooltip_text = p.description if open else p.lockHint
		if not open: hotspot.add_theme_color_override("font_color",Color("7d8297"))
		if not available.is_empty():
			var main_event: bool = not available[0].optional
			var marker := button(self,("!" if main_event else "?")+str(available.size()),anchor+Vector2(dimensions.x/2-10,-dimensions.y/2-20),Vector2(40,33),func(): select_place(p.id),main_event)
			marker.add_theme_font_size_override("font_size",13)
			marker.tooltip_text = available[0].title
	cut_panel(self,Vector2(1035,120),Vector2(370,716),PANEL,CREAM)
	rect(self,Vector2(1059,242),Vector2(72,4),PINK)
	var available := Game.available_events()
	select_place(available[0].placeId if not available.is_empty() else Game.state.currentPlaceId)
	button(self,"周次档案",Vector2(844,112),Vector2(163,40),show_weeks).add_theme_font_size_override("font_size",16)

func select_place(id: String) -> void:
	selected_id = id
	for place_id in hotspots:
		var hotspot: Button = hotspots[place_id]
		var selected: bool = place_id == id
		hotspot.add_theme_stylebox_override("normal",style(CREAM,CYAN) if selected else hotspot.get_meta("idle_style"))
		hotspot.add_theme_color_override("font_color",INK if selected else hotspot.get_meta("idle_color"))
	if is_instance_valid(detail):
		remove_child(detail)
		detail.queue_free()
	detail = Control.new()
	add_child(detail)
	var p := Game.place_data(id)
	var open := Game.meets(p.unlockCondition)
	label(detail,"地区事件 / " + p.id.to_upper(),Vector2(1061,143),Vector2(316,30),14,CYAN)
	label(detail,p.name,Vector2(1059,189),Vector2(319,54),32)
	label(detail,p.description,Vector2(1061,266),Vector2(311,133),18,MUTED)
	if not open:
		label(detail,"尚未开放\n"+p.lockHint,Vector2(1061,440),Vector2(312,115),21,MUTED)
	else:
		var available := Game.available_events(id)
		if available.is_empty(): label(detail,"此地暂无新的事件。",Vector2(1061,423),Vector2(311,52),20)
		var scroll := ScrollContainer.new()
		scroll.position = Vector2(1057,417)
		scroll.size = Vector2(327,226)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		detail.add_child(scroll)
		var list := VBoxContainer.new()
		list.custom_minimum_size.x = 302
		list.add_theme_constant_override("separation",15)
		scroll.add_child(list)
		for e in available:
			var b := button(list,("主线 / " if not e.optional else "可选 / ")+e.title,Vector2.ZERO,Vector2(303,57),func(): Game.start_event(e.id),not e.optional)
			b.custom_minimum_size = Vector2(303,57)
			b.add_theme_font_size_override("font_size",16)
			b.tooltip_text = e.description+"\n"+e.demoNote
		if not p.get("services",[]).is_empty():
			button(detail,"治疗 · 回复 30% 最大 HP",Vector2(1059,659),Vector2(319,51),func(): Game.heal_at(id),true).add_theme_font_size_override("font_size",17)
		button(detail,"进入地区    →",Vector2(1059,742),Vector2(319,59),func(): Game.visit(id)).add_theme_font_size_override("font_size",19)

func show_weeks() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "周次档案"
	dialog.dialog_text = "第一周：%s / 第 %d 天\n\n第二周：内容待设计\n第三周：内容待设计\n\n时间不会因移动、对话或治疗自动推进。" % ["已完成" if Game.state.flags.get("week1Complete",false) else "进行中",Game.state.currentDay]
	dialog.ok_button_text = "返回城市"
	add_child(dialog)
	dialog.popup_centered(Vector2i(590,310))
