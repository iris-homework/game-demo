extends DemoUI
## Real production views, a borrowed unsaved Game session, and candidate audio.
signal closed
const Bank := preload("res://enemy_asset_pipeline/runtime/audio_preview_bank.gd")
const Session := preload("res://enemy_asset_pipeline/runtime/audio_preview_session.gd")
const Hooks := preload("res://enemy_asset_pipeline/runtime/audio_scene_hooks.gd")
const Cleanup := preload("res://scripts/combat/audio_cleanup.gd")
const PAGES := {
	"dialogue":preload("res://scenes/dialogue.tscn"), "battle":preload("res://scenes/battle.tscn"),
	"map":preload("res://scenes/map.tscn"), "place":preload("res://scenes/place.tscn"),
	"result":preload("res://scenes/result.tscn"), "defeat":preload("res://scenes/defeat.tscn")}
const SCENARIOS := {"dialogue":"对话", "choices":"剧情选项", "battle":"战斗交互", "mall":"沃斯商场", "market":"黑市", "reward":"奖励选卡", "map":"地图"}
const CUE_LABELS := {"ui_click":"按钮点击", "ui_cancel":"取消／返回", "ui_error":"操作失败", "card_hover":"卡牌悬停", "card_select":"选中卡牌", "card_deselect":"取消选牌", "card_play":"成功出牌", "card_draw":"抽牌", "card_discard":"弃牌", "card_shuffle":"洗牌", "card_exhaust":"消耗牌", "dialogue_blip":"对话逐字", "dialogue_advance":"对话推进", "trade_success":"交易成功", "coin":"信用点", "reward":"领取奖励", "victory":"战斗胜利", "defeat":"战败", "technology":"科技激活", "stance":"形态切换", "ammo":"获得弹药", "block":"获得格挡", "parry":"弹反", "turn_start":"回合开始", "heal":"治疗", "transition":"场景切换", "energy":"能量恢复"}
var bank: Node
var session := Session.new()
var hooks: Node
var viewport: SubViewport
var view: Control
var modal: Control
var status: Label
var binding_label: Label
var selected_label: Label
var cue_picker: OptionButton
var category_picker: OptionButton
var library_list: ItemList
var search: LineEdit
var scene_buttons: Array[Button] = []
var close_button: Button
var config_path := "res://enemy_asset_pipeline/audio_preview_bindings.json"
var current_scenario := "dialogue"
var closing := false
var route_busy := false
var route_queued := false
var setting_scene := false
var modal_previous_mode := Node.PROCESS_MODE_INHERIT
var previous_page := ""
var volume: HSlider
var recent: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 180
	mouse_filter = Control.MOUSE_FILTER_STOP
	if bank == null:
		bank = Bank.new()
		add_child(bank)
	session.begin()
	hooks = Hooks.new()
	hooks.bank = bank
	add_child(hooks)
	_build()
	bank.cue_played.connect(_cue_played)
	bank.library_changed.connect(_refresh_binding)
	Game.changed.connect(_queue_route)
	Game.notice.connect(_notice)
	Game.current_deck_requested.connect(_open_deck)
	Game.technology_loadout_requested.connect(_open_loadout)
	Game.menu_requested.connect(_return_to_map)
	Game.quit_requested.connect(close_preview)
	_load_bindings()
	_refresh_library()
	await open_scenario("dialogue")

func _build() -> void:
	rect(self,Vector2.ZERO,Vector2(1440,900),Color("0a0e19"))
	label(self,"音效与正式场景模拟",Vector2(22,14),Vector2(790,43),28)
	label(self,"正式页面与交易规则 · 测试状态2000信用点 · 冒险保存关闭",Vector2(24,58),Vector2(1080,26),16,CYAN)
	close_button = button(self,"返回战斗制作台",Vector2(1195,20),Vector2(224,43),close_preview)
	var index := 0
	for kind in SCENARIOS:
		var b := button(self,SCENARIOS[kind],Vector2(22+index*137,96),Vector2(128,40),open_scenario.bind(kind))
		b.name = "scenario_"+kind
		scene_buttons.append(b)
		index += 1
	button(self,"重置当前模拟",Vector2(22,148),Vector2(190,36),func(): await open_scenario(current_scenario))
	button(self,"补满战斗资源",Vector2(225,148),Vector2(190,36),_refill)
	var enabled := CheckButton.new()
	enabled.text = "启用场景音效"
	enabled.button_pressed = true
	enabled.position = Vector2(438,148)
	enabled.size = Vector2(210,36)
	enabled.toggled.connect(func(value: bool): hooks.enabled = value)
	add_child(enabled)
	var frame := SubViewportContainer.new()
	frame.name = "ProductionPreview"
	frame.position = Vector2(22,197)
	frame.size = Vector2(1440,900)
	frame.scale = Vector2.ONE * 0.72
	frame.stretch = false
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(frame)
	viewport = SubViewport.new()
	viewport.name = "ProductionViewport"
	viewport.size = Vector2i(1440,900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	frame.add_child(viewport)
	panel(self,Vector2(1080,92),Vector2(340,718),Color("121b2a"),Color("33475e"))
	var column := VBoxContainer.new()
	column.position = Vector2(1094,106)
	column.size = Vector2(312,690)
	column.add_theme_constant_override("separation",8)
	add_child(column)
	var heading := Label.new()
	heading.text = "候选库 · 试听与动作绑定"
	heading.add_theme_font_size_override("font_size",20)
	column.add_child(heading)
	search = LineEdit.new()
	search.placeholder_text = "搜索文件名／用途"
	search.text_changed.connect(func(_value): _refresh_library())
	column.add_child(search)
	category_picker = OptionButton.new()
	category_picker.add_item("全部分类")
	var categories: Array = []
	for entry in bank.entries:
		if not entry.category in categories: categories.append(entry.category)
	for category in categories: category_picker.add_item(category)
	category_picker.item_selected.connect(func(_value): _refresh_library())
	column.add_child(category_picker)
	library_list = ItemList.new()
	library_list.custom_minimum_size = Vector2(312,213)
	library_list.add_theme_font_size_override("font_size",14)
	library_list.item_selected.connect(_select_candidate)
	library_list.item_activated.connect(func(_value): _audition())
	column.add_child(library_list)
	selected_label = Label.new()
	selected_label.text = "选中候选，双击试听"
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_label.add_theme_font_size_override("font_size",13)
	column.add_child(selected_label)
	var row := HBoxContainer.new()
	column.add_child(row)
	_small_button(row,"试听所选",_audition)
	_small_button(row,"停止全部",bank.stop_all)
	cue_picker = OptionButton.new()
	for cue in bank.cues():
		cue_picker.add_item(CUE_LABELS.get(cue,cue))
		cue_picker.set_item_metadata(cue_picker.item_count-1,cue)
	cue_picker.item_selected.connect(func(_value): _refresh_binding())
	column.add_child(cue_picker)
	binding_label = Label.new()
	binding_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	binding_label.add_theme_font_size_override("font_size",13)
	column.add_child(binding_label)
	row = HBoxContainer.new()
	column.add_child(row)
	_small_button(row,"绑定所选",_bind_selected)
	_small_button(row,"此动作静音",func(): bank.bind(_selected_cue(),""))
	_small_button(row,"试听动作",func(): bank.play_cue(_selected_cue()))
	var volume_label := Label.new()
	volume_label.text = "候选总音量（原战斗刀枪声保持原设置）"
	volume_label.add_theme_font_size_override("font_size",13)
	column.add_child(volume_label)
	volume = HSlider.new()
	volume.min_value = -40
	volume.max_value = 0
	volume.step = 1
	volume.value = bank.master_volume_db
	volume.value_changed.connect(func(value: float): bank.master_volume_db = value)
	column.add_child(volume)
	row = HBoxContainer.new()
	column.add_child(row)
	_small_button(row,"保存音效方案",save_bindings)
	_small_button(row,"重新扫描",func(): bank.scan(); _refresh_library())
	status = label(self,"",Vector2(22,851),Vector2(1390,42),14,CYAN)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refresh_binding()

func _small_button(parent: Node, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size",14)
	b.custom_minimum_size.y = 31
	b.pressed.connect(action)
	parent.add_child(b)

func _selected_cue() -> String:
	return str(cue_picker.get_item_metadata(cue_picker.selected))

func _selected_path() -> String:
	var selected := library_list.get_selected_items()
	return "" if selected.is_empty() else str(library_list.get_item_metadata(selected[0]))

func _refresh_library() -> void:
	if not is_instance_valid(library_list): return
	library_list.clear()
	var category := "" if category_picker.selected == 0 else category_picker.get_item_text(category_picker.selected)
	for entry in bank.entries:
		var relative: String = entry.path.trim_prefix("res://assets/audio/incoming/")
		if not category.is_empty() and entry.category != category: continue
		var searchable := relative.to_lower()
		for cue in bank.bindings:
			if bank.bindings[cue] == entry.path: searchable += " "+CUE_LABELS.get(cue,cue)
		if not search.text.is_empty() and not searchable.contains(search.text.to_lower()): continue
		library_list.add_item(relative)
		library_list.set_item_metadata(library_list.item_count-1,entry.path)
		library_list.set_item_tooltip(library_list.item_count-1,relative)
	selected_label.text = "%d / %d 个候选 · 双击试听" % [library_list.item_count,bank.entries.size()]

func _select_candidate(_index: int) -> void:
	selected_label.text = _selected_path().trim_prefix("res://assets/audio/incoming/")

func _audition() -> void:
	bank.stop_all()
	if not bank.audition(_selected_path()): _notice("请先选择可读取的音效文件。")

func _bind_selected() -> void:
	if _selected_path().is_empty():
		_notice("请先选择候选音效。")
		return
	bank.bind(_selected_cue(),_selected_path())

func _refresh_binding() -> void:
	if not is_instance_valid(binding_label): return
	var path: String = bank.bindings.get(_selected_cue(),"")
	binding_label.text = "当前："+("静音" if path.is_empty() else path.get_file())

func save_bindings() -> bool:
	var file := FileAccess.open(config_path,FileAccess.WRITE)
	if file == null:
		_notice("音效方案保存失败："+error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({"schemaVersion":1,"volumeDb":bank.master_volume_db,"bindings":bank.bindings},"\t"))
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	status.text = "音效方案已保存到 "+config_path if ok else "音效方案写入失败。"
	return ok

func _load_bindings() -> void:
	if not FileAccess.file_exists(config_path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not data is Dictionary or data.get("schemaVersion") != 1 or not data.get("bindings") is Dictionary: return
	for cue in data.bindings:
		if data.bindings[cue] is String: bank.bind(str(cue),data.bindings[cue])
	var level: Variant = data.get("volumeDb",-12.0)
	if (level is float or level is int) and is_finite(float(level)):
		bank.master_volume_db = clampf(float(level),-40,0)
		volume.value = bank.master_volume_db

func open_scenario(kind: String) -> void:
	if closing or route_busy or Game.battle_busy or Game.transition_locked: return
	route_busy = true
	await _clear_page()
	bank.stop_all()
	setting_scene = true
	if not session.reset(kind):
		setting_scene = false
		route_busy = false
		return
	current_scenario = kind
	setting_scene = false
	route_busy = false
	await _show_page()

func _queue_route() -> void:
	if setting_scene or closing or route_queued: return
	route_queued = true
	_route_deferred.call_deferred()

func _route_deferred() -> void:
	route_queued = false
	if closing: return
	if route_busy:
		_queue_route()
		return
	await _show_page()

func _show_page() -> void:
	if closing or route_busy: return
	route_busy = true
	await _clear_page()
	var page: String = Game.page
	if page == "place" and Game.state.currentPlaceId == "mall": view = preload("res://scenes/technology_shop.tscn").instantiate()
	elif page == "place" and Game.state.currentPlaceId == "market": view = preload("res://scenes/black_market.tscn").instantiate()
	elif PAGES.has(page): view = PAGES[page].instantiate()
	else:
		view = DemoUI.new()
		label(view,"从顶部选择要试听的正式场景",Vector2(280,380),Vector2(900,80),34)
	viewport.add_child(view)
	hooks.attach(view)
	if page != previous_page:
		bank.play_cue("victory" if page == "result" else "defeat" if page == "defeat" else "transition")
	previous_page = page
	route_busy = false
	status.text = "当前模拟：%s · 候选%d个 · 购买／选卡只影响本次模拟" % [SCENARIOS.get(current_scenario,current_scenario),bank.entries.size()]

func _clear_page() -> void:
	_close_modal()
	hooks.attach(null)
	if not is_instance_valid(view): return
	view.process_mode = Node.PROCESS_MODE_DISABLED
	await Cleanup.release(view,get_tree())
	view.free()
	view = null

func _return_to_map() -> void:
	if not Game.battle_busy: Game.go_map()

func _open_deck() -> void:
	if Game.battle_busy or not is_instance_valid(view) or is_instance_valid(modal): return
	var browser := preload("res://scripts/card_library.gd").new()
	browser.setup_current_deck(Game.state.get("combat",{}) if Game.page == "battle" else {})
	_open_modal(browser)

func _open_loadout() -> void:
	if Game.battle_busy or not is_instance_valid(view) or is_instance_valid(modal): return
	_open_modal(preload("res://scripts/technology_loadout.gd").new())

func _open_modal(value: Control) -> void:
	modal_previous_mode = view.process_mode
	if view.has_method("cancel_selection"): view.cancel_selection()
	view.process_mode = Node.PROCESS_MODE_DISABLED
	modal = value
	modal.process_mode = Node.PROCESS_MODE_ALWAYS
	modal.closed.connect(_close_modal)
	view.add_child(modal)

func _close_modal() -> void:
	if not is_instance_valid(modal): return
	modal.free()
	modal = null
	if is_instance_valid(view): view.process_mode = modal_previous_mode

func _refill() -> void:
	if Game.battle_busy or not is_instance_valid(view) or not "model" in view: return
	view.model.energy = int(view.model.profile.get("energyPerTurn",3))
	view.model.ammo = 10
	Game.commit_combat(view.model)
	view.refresh_resources()
	status.text = "本次模拟的能量／弹药已补满。"

func _cue_played(cue: String, path: String) -> void:
	recent.append(CUE_LABELS.get(cue,cue)+" → "+path.get_file())
	if recent.size() > 2: recent.pop_front()
	status.text = "  |  ".join(recent)

func _notice(message: String) -> void:
	if not is_instance_valid(status): return
	status.text = message
	for word in ["不足", "无法", "失败", "无效", "不能", "请先"]:
		if word in message:
			bank.play_cue("ui_error")
			break

func _process(_delta: float) -> void:
	var locked := closing or route_busy or Game.battle_busy or Game.transition_locked
	for b in scene_buttons: b.disabled = locked
	close_button.disabled = locked

func close_preview() -> void:
	if closing or route_busy or Game.battle_busy or Game.transition_locked: return
	closing = true
	await _clear_page()
	await Cleanup.release(bank,get_tree())
	bank.stop_all()
	session.restore()
	Game.status_changed.emit()
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(bank): bank.stop_all()
	session.restore()
