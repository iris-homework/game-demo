extends DemoUI
var detail: Control
var selected_id := ""
var line_layer: Node2D
const ORIGIN := Vector2(35,148)
const ROUTES = [["camp","junkyard"],["junkyard","alley"],["alley","bar"],["alley","hive"],["hive","market"],["hive","clinic"],["hive","hotel"],["hotel","block5"],["tower","mall"],["tower","hospital"],["hospital","block5"],["garden","block5"],["block5","power"],["power","pump"],["pump","port"]]

func _ready() -> void:
	background("city", 0.45)
	chrome("城市地图")
	label(self, "CITY NETWORK", Vector2(38,109), Vector2(400,40), 18, CYAN)
	label(self, "沃斯市 / 地点导航", Vector2(35,154), Vector2(580,48), 34)
	panel(self, Vector2(1036,111), Vector2(367,713), Color("171321f5"), Color("50405a"))
	for route in ROUTES:
		var a: Array = Game.place_data(route[0]).mapPosition
		var b: Array = Game.place_data(route[1]).mapPosition
		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(a[0]+62,a[1]+22)+ORIGIN,Vector2(b[0]+62,b[1]+22)+ORIGIN])
		line.width = 2
		line.default_color = Color("8da5a559")
		add_child(line)
	for p in Game.places:
		var open: bool = Game.meets(p.unlockCondition)
		var available: Array = Game.available_events(p.id) if open else []
		var title: String = ("◆ " if not available.is_empty() else "· " if open else "× ") + p.name
		var pos := Vector2(p.mapPosition[0],p.mapPosition[1]) + ORIGIN
		var b := button(self, title, pos, Vector2(145,47), func(): select_place(p.id), not available.is_empty())
		b.add_theme_font_size_override("font_size", 17)
		if not open: b.add_theme_color_override("font_color", Color("8c8099"))
		b.tooltip_text = p.description if open else p.lockHint
	var targets: Array = Game.available_events()
	selected_id = targets[0].placeId if not targets.is_empty() else Game.state.currentPlaceId
	select_place(selected_id)
	tag("◆ 可触发事件", Vector2(40,801), PINK, 175)
	tag("· 已开放", Vector2(230,801), CYAN, 140)
	tag("× 待解锁", Vector2(385,801), MUTED, 140)
	button(self, "周次档案", Vector2(858,797), Vector2(145,42), show_weeks)
	fade_in()

func select_place(id: String) -> void:
	selected_id = id
	if is_instance_valid(detail):
		remove_child(detail)
		detail.queue_free()
	detail = Control.new()
	add_child(detail)
	var p := Game.place_data(id)
	var open := Game.meets(p.unlockCondition)
	label(detail, "当前追踪", Vector2(1060,136), Vector2(310,31), 15, PINK)
	label(detail, Game.objective(), Vector2(1060,177), Vector2(313,83), 23)
	rect(detail, Vector2(1060,290), Vector2(317,1), Color("524157"))
	label(detail, p.name, Vector2(1060,322), Vector2(313,55), 32)
	label(detail, p.description, Vector2(1060,399), Vector2(313,155), 19, MUTED)
	var available := Game.available_events(id)
	var status := "区域内暂无可触发事件"
	if not open: status = "尚未开放\n" + p.lockHint
	elif not available.is_empty(): status = "可触发事件  /  %s" % available.size() + "\n" + available[0].title
	label(detail, status, Vector2(1060,595), Vector2(313,100), 18, CYAN if open else MUTED)
	button(detail, "进入地点    →" if open else "尚未解锁", Vector2(1060,725), Vector2(317,65), func(): Game.visit(id), true).disabled = not open

func show_weeks() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "周次档案"
	dialog.dialog_text = "第一周：%s\n\n第二周：内容待设计\n第三周：内容待设计\n\n后续周数暂不进入空剧情，当前周保持为 1。" % ("已完成" if Game.state.flags.get("week1Complete",false) else "进行中")
	dialog.ok_button_text = "返回城市"
	add_child(dialog)
	dialog.popup_centered(Vector2i(580,310))
