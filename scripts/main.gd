extends Control
const VIEWS = {
	"menu": preload("res://scenes/menu.tscn"),
	"map": preload("res://scenes/map.tscn"),
	"place": preload("res://scenes/place.tscn"),
	"dialogue": preload("res://scenes/dialogue.tscn"),
	"battle": preload("res://scenes/battle.tscn"),
	"result": preload("res://scenes/result.tscn"),
	"cyberware": preload("res://scenes/cyberware.tscn")
}
var view: Control
var debug_panel: Control
var toast: Control
var shown_page := ""
var transition: ColorRect
var transition_count := 0

func _ready() -> void:
	Game.changed.connect(show_page)
	Game.notice.connect(show_notice)
	show_page()

func show_page() -> void:
	if Game.transition_locked: return
	if shown_page != Game.page and (shown_page == "battle" or Game.page == "battle") and is_instance_valid(view):
		play_transition()
	else: swap_view()

func swap_view() -> void:
	if is_instance_valid(debug_panel):
		debug_panel.queue_free()
		debug_panel = null
	if is_instance_valid(view):
		remove_child(view)
		view.queue_free()
	view = VIEWS.get(Game.page,VIEWS.menu).instantiate()
	shown_page = Game.page
	add_child(view)

func play_transition() -> void:
	Game.transition_locked = true
	transition_count += 1
	transition = ColorRect.new()
	transition.size = Vector2(1440,900)
	transition.mouse_filter = Control.MOUSE_FILTER_STOP
	transition.z_index = 100
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/glitch.gdshader")
	transition.material = mat
	add_child(transition)
	var cover := create_tween()
	cover.tween_method(func(value): mat.set_shader_parameter("coverage",value),0.0,1.0,0.58)
	await cover.finished
	swap_view()
	await get_tree().process_frame
	var reveal := create_tween()
	reveal.tween_method(func(value): mat.set_shader_parameter("fade",value),1.0,0.0,0.32)
	await reveal.finished
	transition.queue_free()
	Game.transition_locked = false

func show_notice(message: String) -> void:
	if is_instance_valid(toast): toast.queue_free()
	var ui := DemoUI.new()
	toast = ui
	add_child(ui)
	ui.z_index = 110
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.panel(ui,Vector2(320,104),Vector2(800,62),Color("132639"),DemoUI.CYAN)
	ui.label(ui,message,Vector2(342,114),Vector2(760,48),18)
	# 后一条提示会提前释放旧节点；计时器捕获 WeakRef，避免访问已释放的 lambda 对象。
	var toast_ref: WeakRef = weakref(ui)
	get_tree().create_timer(4.0).timeout.connect(func():
		var notice_ui = toast_ref.get_ref()
		if is_instance_valid(notice_ui): notice_ui.queue_free())

func _input(event: InputEvent) -> void:
	if Game.transition_locked:
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.is_pressed() or event.is_echo(): return
	if Game.battle_busy:
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F1 and Game.config.developmentMode and not Game.state.is_empty():
		toggle_debug()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if is_instance_valid(debug_panel):
			debug_panel.queue_free()
			debug_panel = null
		elif Game.page in ["map", "menu"] and view.has_method("handle_escape") and view.handle_escape():
			pass
		elif Game.page == "menu" and not Game.state.is_empty(): Game.resume()
		else: Game.menu()
	elif is_instance_valid(debug_panel): get_viewport().set_input_as_handled()

func toggle_debug() -> void:
	if Game.page == "battle" and view.has_method("cancel_selection"): view.cancel_selection()
	if is_instance_valid(debug_panel):
		debug_panel.queue_free()
		debug_panel = null
		return
	var ui := DemoUI.new()
	debug_panel = ui
	add_child(ui)
	ui.z_index = 80
	ui.rect(ui,Vector2.ZERO,Vector2(1440,900),Color(0,0,0,0.75))
	ui.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.panel(ui,Vector2(330,182),Vector2(780,546))
	ui.label(ui,"开发面板 / 验收状态",Vector2(367,209),Vector2(650,58),32)
	ui.label(ui,"仅修改当前检查点；时间不会因普通操作自动推进。",Vector2(369,278),Vector2(670,46),18,DemoUI.MUTED)
	ui.button(ui,"0 CR",Vector2(370,340),Vector2(210,54),func(): debug_change("credits",0))
	ui.button(ui,"300 CR",Vector2(610,340),Vector2(210,54),func(): debug_change("credits",300))
	ui.button(ui,"日期 +1",Vector2(850,340),Vector2(210,54),func(): debug_change("day",1))
	ui.button(ui,"HP 50",Vector2(370,420),Vector2(150,54),func(): debug_change("hp",50))
	ui.button(ui,"HP 90",Vector2(550,420),Vector2(150,54),func(): debug_change("hp",90))
	ui.button(ui,"HP 1",Vector2(730,420),Vector2(150,54),func(): debug_change("hp",1))
	ui.button(ui,"HP 100",Vector2(910,420),Vector2(150,54),func(): debug_change("hp",100))
	ui.label(ui,"事件 %s / 节点 %s\n存档：%s" % [Game.state.activeEventId,Game.state.activeNodeId,ProjectSettings.globalize_path(Game.save_path)],Vector2(369,522),Vector2(676,88),15,DemoUI.MUTED)
	ui.button(ui,"关闭 / F1",Vector2(850,638),Vector2(209,48),toggle_debug)

func debug_change(kind: String, value: int) -> void:
	match kind:
		"credits": Game.state.credits = value
		"day": Game.apply_actions([{"op":"advanceDay","days":value}])
		"hp":
			Game.state.currentHp = clampi(value,0,int(Game.state.maxHp))
			if Game.state.currentScene == "battle" and not Game.state.combat.is_empty():
				Game.state.combat.playerHp = Game.state.currentHp
	Game.checkpoint()
	show_notice("测试状态已更新。")
