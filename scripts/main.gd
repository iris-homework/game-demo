extends Control
const VIEWS = {
	"menu": preload("res://scenes/menu.tscn"),
	"map": preload("res://scenes/map.tscn"),
	"place": preload("res://scenes/place.tscn"),
	"dialogue": preload("res://scenes/dialogue.tscn"),
	"battle": preload("res://scenes/battle.tscn"),
	"result": preload("res://scenes/result.tscn"),
	"defeat": preload("res://scenes/defeat.tscn"),
	"cyberware": preload("res://scenes/cyberware.tscn"),
	"card_library": preload("res://scenes/card_library.tscn")
}
var view: Control
var debug_panel: Control
var debug_background_buttons: Array = []
var debug_background_process_mode := Node.PROCESS_MODE_INHERIT
var debug_previous_focus: Control
var toast: Control
var card_console: Control
var console_buttons: Array = []
var view_process_mode := Node.PROCESS_MODE_INHERIT
var shown_page := ""
var transition: ColorRect
var transition_count := 0
var deck_browser: Control
var technology_browser: Control
var technology_background_buttons: Array = []
var technology_background_process_mode := Node.PROCESS_MODE_INHERIT
var technology_previous_focus: Control
var deck_background_buttons: Array = []
var deck_background_process_mode := Node.PROCESS_MODE_INHERIT
var deck_previous_focus: Control
var exit_dialog: Control
var exit_cancel: Button
var exit_ok: Button
var exit_action := ""
var exit_background_buttons: Array = []
var exit_background_process_mode := Node.PROCESS_MODE_INHERIT

func _ready() -> void:
	Game.changed.connect(show_page)
	Game.notice.connect(show_notice)
	Game.current_deck_requested.connect(open_current_deck)
	Game.technology_loadout_requested.connect(open_technology_loadout)
	Game.menu_requested.connect(open_exit_confirmation.bind("menu"))
	Game.quit_requested.connect(open_exit_confirmation.bind("quit"))
	show_page()

func show_page() -> void:
	if Game.transition_locked: return
	if shown_page != Game.page and (shown_page == "battle" or Game.page == "battle") and is_instance_valid(view):
		play_transition()
	else: swap_view()

func swap_view() -> void:
	if is_instance_valid(technology_browser): close_technology_loadout()
	if is_instance_valid(exit_dialog): close_exit_confirmation()
	if is_instance_valid(deck_browser): close_current_deck()
	if is_instance_valid(card_console): close_card_console()
	if is_instance_valid(debug_panel): close_debug()
	if is_instance_valid(view):
		remove_child(view)
		view.queue_free()
	if Game.page == "place" and Game.state.get("currentPlaceId") == "market":
		view = preload("res://scenes/black_market.tscn").instantiate()
	elif Game.page == "place" and Game.state.get("currentPlaceId") == "mall":
		view = preload("res://scenes/technology_shop.tscn").instantiate()
	else:
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
	ui.cut_panel(ui,Vector2(320,104),Vector2(800,62),DemoUI.INK,DemoUI.CYAN,14)
	ui.label(ui,message,Vector2(342,114),Vector2(760,48),18)
	# 后一条提示会提前释放旧节点；计时器捕获 WeakRef，避免访问已释放的 lambda 对象。
	var toast_ref: WeakRef = weakref(ui)
	get_tree().create_timer(4.0).timeout.connect(func():
		var notice_ui = toast_ref.get_ref()
		if is_instance_valid(notice_ui): notice_ui.queue_free())

func _input(event: InputEvent) -> void:
	if is_instance_valid(exit_dialog):
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			close_exit_confirmation()
		elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
			if get_viewport().gui_get_focus_owner() == null:
				exit_cancel.grab_focus()
				get_viewport().set_input_as_handled()
		elif event is InputEventKey and not (event.is_action("ui_accept") or event.is_action("ui_left") or event.is_action("ui_right") or event.is_action("ui_up") or event.is_action("ui_down")):
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(technology_browser):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_technology_loadout()
		return
	if is_instance_valid(deck_browser):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_current_deck()
		return
	if is_instance_valid(card_console): return
	if preload("res://scripts/card_console.gd").is_toggle_event(event):
		get_viewport().set_input_as_handled()
		if Game.config.developmentMode and not Game.battle_busy and not Game.transition_locked and not Game.is_run_over():
			open_card_console()
		return
	if Game.transition_locked:
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.is_pressed() or event.is_echo(): return
	if Game.battle_busy:
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F1 and Game.config.developmentMode and not Game.state.is_empty() and not Game.is_run_over():
		toggle_debug()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if is_instance_valid(debug_panel):
			close_debug()
		elif Game.page in ["map", "menu", "place", "result", "dialogue", "defeat"] and view.has_method("handle_escape") and view.handle_escape():
			pass
		elif Game.page == "menu":
			if not Game.state.is_empty() and Game.can_continue(): Game.resume()
		else: Game.request_menu()
	elif is_instance_valid(debug_panel): get_viewport().set_input_as_handled()

func open_exit_confirmation(action: String) -> void:
	if action not in ["menu", "quit"] or Game.battle_busy or Game.transition_locked: return
	if not is_instance_valid(view) or is_instance_valid(exit_dialog): return
	if is_instance_valid(technology_browser) or is_instance_valid(deck_browser) or is_instance_valid(card_console) or is_instance_valid(debug_panel): return
	if "pile_overlay" in view and is_instance_valid(view.pile_overlay): return
	if action == "quit":
		if Game.page != "menu": return
		if is_instance_valid(view.confirm_dialog) and view.confirm_dialog.visible: return
		if is_instance_valid(view.scenery_dialog): return
	elif Game.page == "menu": return
	if view.has_method("cancel_selection"): view.cancel_selection()
	exit_action = action
	exit_background_process_mode = view.process_mode
	view.process_mode = Node.PROCESS_MODE_DISABLED
	exit_background_buttons.clear()
	get_viewport().gui_release_focus()
	for node in view.find_children("*", "BaseButton", true, false):
		exit_background_buttons.append([node, node.disabled, node.focus_mode])
		node.disabled = true
		node.focus_mode = Control.FOCUS_NONE
	var ui := DemoUI.new()
	exit_dialog = ui
	ui.name = "exit_confirmation"
	ui.z_index = 120
	ui.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ui)
	var shade := ui.rect(ui, Vector2.ZERO, Vector2(1440, 900), Color(0, 0, 0, 0.64))
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.panel(ui, Vector2(400, 300), Vector2(640, 300), DemoUI.PANEL, DemoUI.CYAN)
	var title := "退出游戏" if action == "quit" else "返回主菜单"
	var message := "确定要退出游戏吗？" if action == "quit" else "确定要返回主菜单吗？"
	if action == "menu":
		if Game.training_mode:
			message += "\n本次演练将结束，不影响冒险进度。"
		elif Game.state.get("currentScene") == "battle" and not Game.state.get("battleStart", {}).is_empty() and Game.state.get("combat", {}).get("outcome", "").is_empty():
			message += "\n再次继续委托时，将从本场战斗开局重来。"
	ui.label(ui, title, Vector2(432, 326), Vector2(576, 44), 29)
	ui.label(ui, message, Vector2(432, 391), Vector2(576, 90), 19, DemoUI.MUTED)
	exit_cancel = ui.button(ui, "取消", Vector2(432, 520), Vector2(176, 48), close_exit_confirmation)
	exit_cancel.name = "exit_cancel"
	exit_ok = ui.button(ui, title, Vector2(630, 520), Vector2(378, 48), confirm_exit, true)
	exit_ok.name = "exit_ok"
	for pair in [[exit_cancel, exit_ok], [exit_ok, exit_cancel]]:
		var current: Button = pair[0]
		var neighbor: NodePath = current.get_path_to(pair[1])
		current.focus_mode = Control.FOCUS_ALL
		current.focus_next = neighbor
		current.focus_previous = neighbor
		current.focus_neighbor_left = neighbor
		current.focus_neighbor_right = neighbor
		current.focus_neighbor_top = neighbor
		current.focus_neighbor_bottom = neighbor
	exit_cancel.grab_focus()

func close_exit_confirmation() -> void:
	if not is_instance_valid(exit_dialog): return
	get_viewport().gui_release_focus()
	remove_child(exit_dialog)
	exit_dialog.queue_free()
	exit_dialog = null
	exit_cancel = null
	exit_ok = null
	exit_action = ""
	if is_instance_valid(view): view.process_mode = exit_background_process_mode
	for item in exit_background_buttons:
		if is_instance_valid(item[0]):
			item[0].disabled = item[1]
			item[0].focus_mode = item[2]
			if item[0].has_method("refresh_feedback"): item[0].refresh_feedback()
	exit_background_buttons.clear()

func confirm_exit() -> void:
	if not is_instance_valid(exit_dialog) or Game.battle_busy or Game.transition_locked: return
	var action := exit_action
	close_exit_confirmation()
	if action == "menu": Game.menu()
	elif action == "quit": get_tree().quit()

func toggle_debug() -> void:
	if is_instance_valid(debug_panel):
		close_debug()
		return
	if view.has_method("cancel_selection"): view.cancel_selection()
	# GUI mouse filtering alone cannot stop the battle's _input handlers.
	debug_previous_focus = get_viewport().gui_get_focus_owner()
	debug_background_process_mode = view.process_mode
	view.process_mode = Node.PROCESS_MODE_DISABLED
	debug_background_buttons.clear()
	for node in view.find_children("*", "BaseButton", true, false):
		debug_background_buttons.append([node, node.disabled, node.focus_mode])
		node.release_focus()
		node.disabled = true
		node.focus_mode = Control.FOCUS_NONE
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

func close_debug() -> void:
	if not is_instance_valid(debug_panel): return
	remove_child(debug_panel)
	debug_panel.queue_free()
	debug_panel = null
	if is_instance_valid(view): view.process_mode = debug_background_process_mode
	for item in debug_background_buttons:
		if is_instance_valid(item[0]):
			item[0].disabled = item[1]
			item[0].focus_mode = item[2]
	debug_background_buttons.clear()
	if is_instance_valid(debug_previous_focus): debug_previous_focus.grab_focus()
	debug_previous_focus = null

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

func open_card_console() -> void:
	if is_instance_valid(exit_dialog): return
	if is_instance_valid(technology_browser) or is_instance_valid(card_console) or is_instance_valid(debug_panel) or is_instance_valid(deck_browser): return
	if "pile_overlay" in view and is_instance_valid(view.pile_overlay): return
	if view.has_method("cancel_selection"): view.cancel_selection()
	view_process_mode = view.process_mode
	view.process_mode = Node.PROCESS_MODE_DISABLED
	console_buttons.clear()
	for node in view.find_children("*", "BaseButton", true, false):
		console_buttons.append([node, node.disabled, node.focus_mode])
		node.release_focus()
		node.disabled = true
		node.focus_mode = Control.FOCUS_NONE
	card_console = preload("res://scripts/card_console.gd").new()
	card_console.closed.connect(close_card_console)
	add_child(card_console)

func close_card_console() -> void:
	if not is_instance_valid(card_console): return
	remove_child(card_console)
	card_console.queue_free()
	card_console = null
	if is_instance_valid(view): view.process_mode = view_process_mode
	for item in console_buttons:
		if is_instance_valid(item[0]):
			item[0].disabled = item[1]
			item[0].focus_mode = item[2]
	console_buttons.clear()
	if is_instance_valid(view) and view.has_method("refresh_library"): view.refresh_library()

func open_current_deck() -> void:
	if is_instance_valid(exit_dialog): return
	if Game.state.is_empty() or Game.battle_busy or Game.transition_locked: return
	if is_instance_valid(technology_browser) or is_instance_valid(deck_browser) or is_instance_valid(card_console) or is_instance_valid(debug_panel): return
	if "pile_overlay" in view and is_instance_valid(view.pile_overlay): return
	# Result pages nest their toolbar inside reward_view, created at runtime.
	var trigger := view.find_child("current_deck_button", true, false) as Button
	if trigger == null or trigger.disabled: return
	if view.has_method("cancel_selection"): view.cancel_selection()
	deck_previous_focus = get_viewport().gui_get_focus_owner()
	deck_background_process_mode = view.process_mode
	view.process_mode = Node.PROCESS_MODE_DISABLED
	deck_background_buttons.clear()
	for node in view.find_children("*", "BaseButton", true, false):
		deck_background_buttons.append([node,node.disabled,node.focus_mode])
		node.release_focus()
		node.disabled = true
		node.focus_mode = Control.FOCUS_NONE
	deck_browser = preload("res://scripts/card_library.gd").new()
	deck_browser.setup_current_deck(Game.state.get("combat", {}) if Game.page == "battle" else {})
	deck_browser.closed.connect(close_current_deck)
	add_child(deck_browser)

func close_current_deck() -> void:
	if not is_instance_valid(deck_browser): return
	remove_child(deck_browser)
	deck_browser.queue_free()
	deck_browser = null
	if is_instance_valid(view): view.process_mode = deck_background_process_mode
	for item in deck_background_buttons:
		if is_instance_valid(item[0]):
			item[0].disabled = item[1]
			item[0].focus_mode = item[2]
	deck_background_buttons.clear()
	if is_instance_valid(deck_previous_focus): deck_previous_focus.grab_focus()
	deck_previous_focus = null

func open_technology_loadout() -> void:
	if Game.page != "map" or Game.state.get("currentScene") != "map" or Game.training_mode or Game.battle_busy or Game.transition_locked: return
	if is_instance_valid(technology_browser) or is_instance_valid(exit_dialog) or is_instance_valid(deck_browser) or is_instance_valid(card_console) or is_instance_valid(debug_panel): return
	var trigger := view.get_node_or_null("technology_loadout_button") as Button
	if trigger == null or trigger.disabled: return
	if view.has_method("cancel_selection"): view.cancel_selection()
	technology_previous_focus = get_viewport().gui_get_focus_owner()
	technology_background_process_mode = view.process_mode
	view.process_mode = Node.PROCESS_MODE_DISABLED
	technology_background_buttons.clear()
	for node in view.find_children("*", "BaseButton", true, false):
		technology_background_buttons.append([node,node.disabled,node.focus_mode])
		node.release_focus()
		node.disabled = true
		node.focus_mode = Control.FOCUS_NONE
	technology_browser = preload("res://scripts/technology_loadout.gd").new()
	technology_browser.closed.connect(close_technology_loadout)
	add_child(technology_browser)

func close_technology_loadout() -> void:
	if not is_instance_valid(technology_browser): return
	get_viewport().gui_release_focus()
	remove_child(technology_browser)
	technology_browser.queue_free()
	technology_browser = null
	if is_instance_valid(view): view.process_mode = technology_background_process_mode
	for item in technology_background_buttons:
		if is_instance_valid(item[0]):
			item[0].disabled = item[1]
			item[0].focus_mode = item[2]
	technology_background_buttons.clear()
	if is_instance_valid(technology_previous_focus): technology_previous_focus.grab_focus()
	technology_previous_focus = null
