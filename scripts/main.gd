extends Control
const VIEWS = {
	"menu": preload("res://scenes/menu.tscn"),
	"map": preload("res://scenes/map.tscn"),
	"place": preload("res://scenes/place.tscn"),
	"dialogue": preload("res://scenes/dialogue.tscn"),
	"battle": preload("res://scenes/battle.tscn"),
	"result": preload("res://scenes/result.tscn")
}
var view: Control
var debug_panel: Control
var toast: Control

func _ready() -> void:
	Game.changed.connect(show_page)
	Game.notice.connect(show_notice)
	show_page()

func show_page() -> void:
	if is_instance_valid(debug_panel):
		debug_panel.queue_free()
		debug_panel = null
	if is_instance_valid(view):
		remove_child(view)
		view.queue_free()
	view = VIEWS.get(Game.page, VIEWS.menu).instantiate()
	add_child(view)

func show_notice(message: String) -> void:
	if is_instance_valid(toast): toast.queue_free()
	var ui := DemoUI.new()
	toast = ui
	add_child(ui)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.panel(ui, Vector2(320,98), Vector2(800,65), Color("241e30"), DemoUI.CYAN)
	ui.label(ui, message, Vector2(342,108), Vector2(760,48), 18)
	get_tree().create_timer(4.0).timeout.connect(func(): if is_instance_valid(ui): ui.queue_free())

func _input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	if not event.is_pressed() or event.is_echo(): return
	if event.keycode == KEY_F1 and Game.config.developmentMode and not Game.state.is_empty():
		toggle_debug()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		if is_instance_valid(debug_panel):
			debug_panel.queue_free()
			debug_panel = null
		elif Game.page == "menu" and not Game.state.is_empty(): Game.resume()
		else: Game.menu()
		get_viewport().set_input_as_handled()
	elif is_instance_valid(debug_panel):
		get_viewport().set_input_as_handled()

func toggle_debug() -> void:
	if is_instance_valid(debug_panel):
		debug_panel.queue_free()
		debug_panel = null
		return
	var ui := DemoUI.new()
	debug_panel = ui
	add_child(ui)
	ui.rect(ui, Vector2.ZERO, Vector2(1440,900), Color(0,0,0,0.7))
	ui.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.panel(ui, Vector2(360,200), Vector2(720,480))
	ui.label(ui, "开发面板", Vector2(400,230), Vector2(640,60), 34)
	ui.label(ui, "信用点初始值尚未定稿。以下仅用于验收 E03 分支。\n修改会保存到当前检查点。", Vector2(400,300), Vector2(640,90), 20, DemoUI.MUTED)
	ui.button(ui, "设为 0 CR", Vector2(400,420), Vector2(290,65), func(): set_credits(0))
	ui.button(ui, "设为 300 CR", Vector2(720,420), Vector2(290,65), func(): set_credits(300), true)
	ui.label(ui, "事件 %s  /  节点 %s\n存档：%s" % [Game.state.activeEventId,Game.state.activeNodeId,ProjectSettings.globalize_path(Game.save_path)], Vector2(400,510), Vector2(630,80), 15, DemoUI.MUTED)
	ui.button(ui, "关闭  /  F1", Vector2(790,600), Vector2(220,48), toggle_debug)

func set_credits(amount: int) -> void:
	Game.state.credits = amount
	Game.checkpoint()
	show_notice("开发测试信用点已设为 %s CR" % amount)
