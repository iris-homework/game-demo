extends DemoUI
## Independent workbench. Runtime changes and presets never enter adventure saves.
const PreviewBattle = preload("res://tests/combat/workbench/battle_background_preview_view.gd")
const Guides = preload("res://tests/combat/workbench/battle_background_preview_guides.gd")
const CharacterNames = preload("res://tests/combat/workbench/workbench_character_names.gd")
const PROFILE_PATH := "res://tests/combat/workbench/background_profiles.json"
const PLAYER_VISUAL_ID := "noren"
@export var profile_path := PROFILE_PATH
@export var character_mipmaps := false
const PLACE_IDS := ["hive","alley","bar","garden","port","pump","junkyard","hotel","tower","block5","church"]
const POSE_LABELS := {"hit":"打击","idle":"待机","move":"移动","slash":"挥砍","pierce":"突刺","block":"格挡","damaged":"受伤","gun_idle":"持枪待机","shoot":"射击","retreat":"后撤","gun_block":"持枪格挡","gun_damaged":"持枪受伤","bite":"张嘴","bite_close":"咬合","laser":"掌心射线","evade":"闪避","blunt":"钝击"}
var view: Control
var rebuilding := true
var camera_busy := false
var capturing := false
var finished := false
var selected_place := "hive"
var roster: Array[String] = ["robot"]
var enemy_choices: Array[Dictionary] = []
var selected_actor := 0
var profiles: Dictionary = {}
var saved_profiles: Dictionary = {}
var settings: Dictionary = {}
var restored_hand: Array = ["noren_01","noren_02","noren_03","noren_04","noren_12"]
var catalog: Array = []
var hand_signature := ""
var left_panel: PanelContainer
var right_panel: PanelContainer
var left_tabs: TabContainer
var actor_tabs: TabBar
var place_picker: OptionButton
var enemy_picker: OptionButton
var pose_picker: OptionButton
var target_picker: OptionButton
var stance_picker: OptionButton
var action_picker: OptionButton
var speed_picker: OptionButton
var attack_info: Label
var loop_toggle: CheckBox
var pause_button: Button
var add_enemy_button: Button
var remove_enemy_button: Button
var status: Label
var actor_info: Label
var profile_info: Label
var hand_list: ItemList
var card_list: ItemList
var search: LineEdit
var guides: Node2D
var fade: TextureRect
var close_dialog: ConfirmationDialog
var sliders: Dictionary = {}
var captions: Dictionary = {}
var mutations: Array[BaseButton] = []
var hint: Label
var actor_x: SpinBox
var actor_y: SpinBox
var syncing := false
var loop_running := false
var guides_enabled := false

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://battle_workbench_unused.json"
	Game.meta_path = "user://battle_workbench_meta_unused.json"
	Game.state = Game.initial_state("noren")
	Game.start_training("B04")
	Game.training_scenery_place_id = selected_place
	preload("res://tests/combat/workbench/battle_background_preview_visuals.gd").prepare()
	catalog = Game.library_cards()
	_load_profiles()
	_build_enemy_choices()
	_build_controls()
	get_tree().auto_accept_quit = false
	await rebuild()

func tools_locked() -> bool:
	return rebuilding or camera_busy or capturing or not is_instance_valid(view) or Game.battle_busy or Game.transition_locked or view.preview_busy or is_instance_valid(view.pile_overlay)

func modal_open() -> bool:
	return capturing or close_dialog.visible or place_picker.get_popup().visible or enemy_picker.get_popup().visible or pose_picker.get_popup().visible or target_picker.get_popup().visible or stance_picker.get_popup().visible or action_picker.get_popup().visible or speed_picker.get_popup().visible

func tool_contains(point: Vector2) -> bool:
	return (left_panel.visible and left_panel.get_global_rect().has_point(point)) or (right_panel.visible and right_panel.get_global_rect().has_point(point))

func rebuild() -> void:
	if is_instance_valid(view) and tools_locked(): return
	rebuilding = true
	finished = false
	loop_toggle.button_pressed = false
	Game.battle_busy = false
	Game.transition_locked = false
	Game.training_scenery_place_id = selected_place
	Game.initialize_combat()
	var initial := CombatModel.new()
	initial.restore(Game.state.combat)
	var definitions: Array = []
	var seen: Dictionary = {}
	for key in roster:
		var definition: Dictionary = _enemy_definition(key)
		var id: String = definition.id
		seen[id] = int(seen.get(id,0))+1
		if seen[id] > 1: definition.id = id+"_test_%d" % seen[id]
		definition.erase("formationSlot")
		definition.maxHp = 100
		definitions.append(definition)
	var model := CombatModel.new()
	model.initialize("B04",100,100,initial.profile,definitions,Game.card_catalog)
	Game.commit_combat(model)
	await _replace_view()
	view.replace_test_hand(restored_hand)
	_sync_actor_tabs()
	status.text = "已重置 · 敌人各100 HP · 可真实出牌"

func _replace_view() -> void:
	rebuilding = true
	if is_instance_valid(view):
		remove_child(view)
		view.queue_free()
		await get_tree().process_frame
	view = PreviewBattle.new()
	add_child(view)
	move_child(view,0)
	for child in view.get_children():
		if child is Button and child.name == "current_deck_button":
			for connection in child.pressed.get_connections(): child.pressed.disconnect(connection.callable)
			child.pressed.connect(func():
				left_panel.show()
				left_tabs.current_tab = 1)
		elif child is Button and child.text == "调试结果": child.text = "重置本轮"
	view.preview_finished.connect(func(result: String):
		finished = true
		loop_toggle.button_pressed = false
		status.text = "演练结束：%s · 点击重置本轮继续" % result)
	var deadline := Time.get_ticks_msec()+15000
	while not view.initialized or Game.battle_busy:
		if Time.get_ticks_msec() > deadline:
			status.text = "初始化超时，请查看Godot日志。"
			return
		await get_tree().process_frame
	settings = _profile(selected_place)
	if is_instance_valid(guides): guides.queue_free()
	guides = Guides.new()
	guides.stage = view.stage
	guides.visible = guides_enabled
	guides.z_index = 40
	add_child(guides)
	fade = TextureRect.new()
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.z_index = -1
	view.add_child(fade)
	_apply_map()
	_enable_character_mipmaps()
	_sync_sliders()
	rebuilding = false
	hand_signature = ""
	_sync_actor_tabs()

func _enable_character_mipmaps() -> void:
	if not character_mipmaps or not is_instance_valid(view) or not is_instance_valid(view.stage): return
	for actor in view.stage.actors_root.get_children():
		if actor.has_method("set_mipmap_sampling"): actor.call("set_mipmap_sampling",true)

func switch_place(index: int) -> bool:
	if tools_locked() or finished: return false
	view.cancel_selection()
	selected_place = PLACE_IDS[posmod(index,PLACE_IDS.size())]
	Game.training_scenery_place_id = selected_place
	await _replace_view()
	place_picker.select(PLACE_IDS.find(selected_place))
	status.text = "已切换地图；战斗与手牌保留"
	return true

func _profile(id: String) -> Dictionary:
	if not profiles.has(id):
		var place_asset: String = Game.place_data(id).backgroundAssetId
		var asset: String = Game.assets.get(place_asset,{}).get("battleAssetId","")
		profiles[id] = {"scale":1.0,"x":0.0,"y":0.0,"brightness":1.0,"saturation":1.0,"contrast":1.0,"ground":float(Game.assets.get(asset,{}).get("groundStart",0.5)),"fade_start":650.0,"fade_strength":0.0}
	return profiles[id]

func _apply_map() -> void:
	if not is_instance_valid(view) or not is_instance_valid(view.stage.scenery): return
	var stage: Control = view.stage
	var artwork: TextureRect = stage.scenery
	var dimensions := artwork.texture.get_size()
	var horizon: float = stage.position.y+stage.floor_y-155.0
	var ground := float(settings.ground)
	var factor := maxf(1440.0/dimensions.x,maxf(horizon/(ground*dimensions.y),(900.0-horizon)/((1.0-ground)*dimensions.y)))*float(settings.scale)
	var scaled := dimensions*factor
	stage.scenery_base_rect = Rect2(Vector2((1440-scaled.x)*0.5+settings.x,horizon-ground*scaled.y+settings.y),scaled)
	if artwork.material == null:
		var material := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = "shader_type canvas_item; uniform float brightness=1.0; uniform float saturation=1.0; uniform float contrast=1.0; void fragment(){vec4 c=texture(TEXTURE,UV); float g=dot(c.rgb,vec3(0.2126,0.7152,0.0722)); COLOR=vec4(clamp(((mix(vec3(g),c.rgb,saturation)-0.5)*contrast+0.5)*brightness,vec3(0.0),vec3(1.0)),c.a);}"
		material.shader = shader
		artwork.material = material
	for key in ["brightness","saturation","contrast"]: artwork.material.set_shader_parameter(key,settings[key])
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.025,0.03,0.045,0),Color(0.025,0.03,0.045,settings.fade_strength)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(0,1)
	fade.texture = texture
	fade.position = Vector2(0,settings.fade_start)
	fade.size = Vector2(1440,900-settings.fade_start)
	guides.ground_start = ground
	stage._update_camera()
	profile_info.text = "当前地点%s · 仅保存测试参数" % ("有未保存修改" if _dirty(selected_place) else "参数已同步")

func _dirty(id: String) -> bool:
	return profiles.has(id) and profiles[id] != saved_profiles.get(id,_defaults_for(id))

func _defaults_for(id: String) -> Dictionary:
	var place_asset: String = Game.place_data(id).backgroundAssetId
	var asset: String = Game.assets.get(place_asset,{}).get("battleAssetId","")
	return {"scale":1.0,"x":0.0,"y":0.0,"brightness":1.0,"saturation":1.0,"contrast":1.0,"ground":float(Game.assets.get(asset,{}).get("groundStart",0.5)),"fade_start":650.0,"fade_strength":0.0}

func _load_profiles() -> void:
	if not FileAccess.file_exists(profile_path): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	if not data is Dictionary: return
	var limits := {"scale":[1.0,1.8],"x":[-500.0,500.0],"y":[-500.0,500.0],"brightness":[0.3,1.5],"saturation":[0.0,1.5],"contrast":[0.3,1.5],"ground":[0.15,0.85],"fade_start":[480.0,820.0],"fade_strength":[0.0,1.0]}
	for id in PLACE_IDS:
		if not data.get(id) is Dictionary: continue
		var clean := _defaults_for(id)
		for key in clean:
			var value = data[id].get(key)
			if (value is float or value is int) and is_finite(float(value)):
				clean[key] = clampf(float(value),limits[key][0],limits[key][1])
		profiles[id] = clean
	saved_profiles = profiles.duplicate(true)

func save_map() -> bool:
	if tools_locked(): return false
	var pending := saved_profiles.duplicate(true)
	pending[selected_place] = settings.duplicate(true)
	var temporary := profile_path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null:
		status.text = "保存失败："+error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(pending,"\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary,profile_path)
	if error != OK:
		status.text = "保存失败："+error_string(error)
		return false
	saved_profiles = pending
	_apply_map()
	status.text = "已保存当前地图到 tests/combat/workbench/background_profiles.json"
	return true

func _build_enemy_choices() -> void:
	enemy_choices.clear()
	var seen: Dictionary = {}
	for id in Game.enemy_catalog:
		var definition: Dictionary = Game.enemy_catalog[id]
		var visual: String = str(definition.get("combatVisualId","unillustrated")).to_lower()
		enemy_choices.append({"id":id,"name":CharacterNames.name_for_visual(visual),"tooltip":str(id)})
		seen[visual] = true
	for visual in Game.enemy_visuals.catalog:
		var key := str(visual)
		if not seen.has(key.to_lower()):
			enemy_choices.append({"id":"visual:"+key,"name":CharacterNames.name_for_visual(key),"tooltip":"visual:"+key})

func _enemy_definition(key: String) -> Dictionary:
	if Game.enemy_catalog.has(key):
		var definition: Dictionary = Game.enemy_catalog[key].duplicate(true)
		# Display-only override for this test battle; the formal catalog keeps its Chinese name.
		definition.displayName = _enemy_name(key)
		return definition
	var visual := key.trim_prefix("visual:")
	return {"id":"preview_"+visual,"displayName":_enemy_name(key),"combatVisualId":visual,"intentSequence":[{"type":"attack","amount":6,"hits":1}],"prototype":true}

func _enemy_name(key: String) -> String:
	for choice in enemy_choices:
		if choice.id == key: return str(choice.name)
	if Game.enemy_catalog.has(key):
		return CharacterNames.name_for_visual(str(Game.enemy_catalog[key].get("combatVisualId","unillustrated")))
	return CharacterNames.name_for_visual(key.trim_prefix("visual:"))

func _panel(pos: Vector2, dimensions: Vector2) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.position = pos
	frame.size = dimensions
	frame.z_index = 90
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101923f5")
	style.border_color = Color("3d879b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	frame.add_theme_stylebox_override("panel",style)
	add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",7)
	frame.add_child(box)
	return box

func _text(parent: Node, value: String, font_size: int = 14, color: Color = DemoUI.MUTED) -> Label:
	var text := Label.new()
	text.text = value
	text.add_theme_font_size_override("font_size",font_size)
	text.add_theme_color_override("font_color",color)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(text)
	return text

func _button(parent: Node, title: String, callback: Callable, locked: bool = true) -> Button:
	var b := Button.new()
	b.text = title
	b.custom_minimum_size.y = 32
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size",14)
	b.pressed.connect(callback)
	parent.add_child(b)
	if locked: mutations.append(b)
	return b

func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",5)
	parent.add_child(row)
	return row

func _picker(parent: Node) -> OptionButton:
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(0,32)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_theme_font_size_override("font_size",14)
	picker.fit_to_longest_item = false
	parent.add_child(picker)
	return picker

func _refresh_enemy_picker() -> void:
	if not is_instance_valid(enemy_picker): return
	enemy_picker.clear()
	for index in enemy_choices.size():
		var choice: Dictionary = enemy_choices[index]
		enemy_picker.add_item(str(choice.name))
		# Keep duplicate formal enemies distinguishable without changing the label.
		enemy_picker.set_item_tooltip(index,str(choice.get("tooltip",choice.id)))

func _build_controls() -> void:
	var left := _panel(Vector2(16,90),Vector2(304,530))
	left_panel = left.get_parent()
	var top := _row(left)
	_text(top,"战斗测试台",17,DemoUI.CYAN).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(top,"收起 [",func(): left_panel.hide(),false)
	left_tabs = TabContainer.new()
	left_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_tabs.add_theme_font_size_override("font_size",16)
	left.add_child(left_tabs)
	var map := _tab_content("地图")
	var map_row := _row(map)
	_button(map_row,"‹",func(): switch_place(PLACE_IDS.find(selected_place)-1))
	place_picker = _picker(map_row)
	for id in PLACE_IDS: place_picker.add_item(Game.place_data(id).name)
	place_picker.item_selected.connect(func(index: int):
		if not await switch_place(index): place_picker.select(PLACE_IDS.find(selected_place)))
	_button(map_row,"›",func(): switch_place(PLACE_IDS.find(selected_place)+1))
	profile_info = _text(map,"",12)
	_add_slider(map,"scale","原图尺度",1.0,1.8,0.01)
	_add_slider(map,"x","水平偏移",-500,500,1)
	_add_slider(map,"y","垂直偏移",-500,500,1)
	_add_slider(map,"ground","原图地面分界",0.15,0.85,0.01)
	var color_grid := GridContainer.new()
	color_grid.columns = 2
	map.add_child(color_grid)
	_add_slider(color_grid,"brightness","亮度",0.3,1.5,0.01)
	_add_slider(color_grid,"saturation","饱和度",0,1.5,0.01)
	_add_slider(color_grid,"contrast","对比度",0.3,1.5,0.01)
	_add_slider(color_grid,"fade_strength","底部渐暗",0,1,0.01)
	_add_slider(map,"fade_start","渐暗起点",480,820,1)
	var save_row := _row(map)
	_button(save_row,"保存当前",save_map)
	_button(save_row,"恢复已存",func():
		if tools_locked(): return
		profiles[selected_place] = saved_profiles.get(selected_place,_defaults_for(selected_place)).duplicate(true)
		settings = profiles[selected_place]
		_sync_sliders()
		_apply_map())
	_button(save_row,"恢复初始",func():
		if tools_locked(): return
		profiles[selected_place] = _defaults_for(selected_place)
		settings = profiles[selected_place]
		_sync_sliders()
		_apply_map())
	var guide_toggle := CheckBox.new()
	guide_toggle.text = "显示脚底、地面与攻击点辅助线"
	guide_toggle.add_theme_font_size_override("font_size",13)
	guide_toggle.toggled.connect(func(value: bool):
		guides_enabled = value
		if is_instance_valid(guides): guides.visible = value)
	map.add_child(guide_toggle)
	var camera_row := _row(map)
	_button(camera_row,"全景",func(): preview_camera(false))
	_button(camera_row,"近景",func(): preview_camera(true))
	_button(camera_row,"截图",capture_current)
	_text(map,"边缘自动限制取景；放大后可调整偏移。",12)
	_build_cards()
	var common := _row(left)
	_button(common,"重置本轮",rebuild)
	_button(common,"补满能量／弹药",func():
		if not tools_locked(): view.refill_test_resources())
	status = _text(left,"正在准备…",12,DemoUI.CYAN)
	_build_actor_panel()
	hint = label(self,"[ 左栏  ·  ] 右栏  ·  Tab 双栏  ·  Ctrl+S 保存地图",Vector2(340,85),Vector2(740,25),13,DemoUI.CYAN)
	hint.z_index = 95
	close_dialog = ConfirmationDialog.new()
	close_dialog.title = "地图还有未保存修改"
	close_dialog.dialog_text = "返回调整后可逐个保存地图，或关闭并放弃未保存参数。"
	close_dialog.ok_button_text = "放弃并关闭"
	close_dialog.cancel_button_text = "返回调整"
	close_dialog.confirmed.connect(func(): get_tree().quit())
	add_child(close_dialog)
	settings = _profile(selected_place)
	_sync_sliders()

func _add_slider(parent: Node, key: String, title: String, minimum: float, maximum: float, increment: float) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var caption := _text(column,title,12)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(120,16)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = increment
	column.add_child(slider)
	sliders[key] = slider
	captions[key] = {"node":caption,"title":title}
	slider.value_changed.connect(func(value: float):
		if tools_locked():
			slider.set_value_no_signal(settings[key])
			return
		settings[key] = value
		caption.text = "%s  %.2f" % [title,value]
		_apply_map())

func _sync_sliders() -> void:
	for key in sliders:
		sliders[key].set_value_no_signal(settings[key])
		captions[key].node.text = "%s  %.2f" % [captions[key].title,settings[key]]

func _build_cards() -> void:
	var cards := _tab_content("卡牌")
	search = LineEdit.new()
	search.placeholder_text = "搜索牌名、编号或 ID"
	search.add_theme_font_size_override("font_size",14)
	search.text_changed.connect(func(_value: String): _filter_cards())
	cards.add_child(search)
	card_list = ItemList.new()
	card_list.custom_minimum_size.y = 155
	card_list.add_theme_font_size_override("font_size",14)
	cards.add_child(card_list)
	card_list.item_activated.connect(func(_index: int): _add_selected_card())
	_button(cards,"加入手牌 ＋（可重复）",_add_selected_card)
	_text(cards,"当前手牌 · 最多20张",13,DemoUI.CYAN)
	hand_list = ItemList.new()
	hand_list.custom_minimum_size.y = 130
	hand_list.add_theme_font_size_override("font_size",14)
	cards.add_child(hand_list)
	var row := _row(cards)
	_button(row,"移除所选",func():
		if tools_locked() or hand_list.get_selected_items().is_empty(): return
		view.remove_test_card(hand_list.get_item_metadata(hand_list.get_selected_items()[0])))
	_button(row,"清空手牌",func():
		if not tools_locked(): view.replace_test_hand([]))
	row = _row(cards)
	_button(row,"记住当前手牌",func():
		if tools_locked(): return
		restored_hand.clear()
		for uid in view.model.hand: restored_hand.append(view.model.instances[uid])
		status.text = "已记住本次手牌，重置本轮也会使用它")
	_button(row,"恢复手牌",func():
		if not tools_locked(): view.replace_test_hand(restored_hand))
	_text(cards,"选牌后点加入，或双击列表；记忆仅在本次窗口保留。",12)
	_filter_cards()

func _tab_content(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_tabs.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",6)
	scroll.add_child(column)
	return column

func _filter_cards() -> void:
	card_list.clear()
	for definition in catalog:
		var title := "%s · %02d %s" % [definition.get("rarity",""),int(definition.get("number",0)),definition.name]
		if not search.text.is_empty() and not (title+definition.id).to_lower().contains(search.text.to_lower()): continue
		var index := card_list.add_item(title)
		card_list.set_item_metadata(index,definition.id)
		card_list.set_item_tooltip(index,definition.get("description",definition.name))
		card_list.set_item_custom_fg_color(index,{"C":Color("cbd2dc"),"B":Color("69bcff"),"A":Color("ff8296"),"S":Color("ffd180")}.get(definition.get("rarity","C"),Color.WHITE))

func _add_selected_card() -> void:
	if tools_locked() or card_list.get_selected_items().is_empty(): return
	var id: String = card_list.get_item_metadata(card_list.get_selected_items()[0])
	if not view.add_test_card(id): status.text = "加入失败：手牌最多20张，或当前不可编辑"

func _sync_hand() -> void:
	var signature := str(view.model.hand)+str(view.model.instances)
	if signature == hand_signature: return
	hand_signature = signature
	hand_list.clear()
	for uid in view.model.hand:
		var definition: Dictionary = view.model.card(uid)
		var index := hand_list.add_item("%02d  %s" % [hand_list.item_count+1,definition.name])
		hand_list.set_item_metadata(index,uid)

func _build_actor_panel() -> void:
	var right := _panel(Vector2(1110,90),Vector2(314,530))
	right_panel = right.get_parent()
	var top := _row(right)
	_text(top,"角色与动作",17,DemoUI.CYAN).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(top,"收起 ]",func(): right_panel.hide(),false)
	actor_tabs = TabBar.new()
	actor_tabs.add_theme_font_size_override("font_size",14)
	actor_tabs.tab_changed.connect(func(index: int):
		if syncing: return
		if tools_locked():
			actor_tabs.set_current_tab(selected_actor)
			return
		loop_toggle.button_pressed = false
		selected_actor = index
		_sync_actor_controls())
	right.add_child(actor_tabs)
	var row := _row(right)
	add_enemy_button = _button(row,"＋敌人",func(): change_roster("add"))
	remove_enemy_button = _button(row,"移除当前敌人",func(): change_roster("remove"))
	actor_info = _text(right,"",13,DemoUI.CYAN)
	attack_info = _text(right,"",12)
	enemy_picker = _picker(right)
	_refresh_enemy_picker()
	enemy_picker.item_selected.connect(func(index: int): change_roster(enemy_choices[index].id))
	stance_picker = _picker(right)
	stance_picker.add_item("近战形态")
	stance_picker.add_item("远程形态")
	stance_picker.item_selected.connect(func(index: int):
		await get_tree().process_frame
		if tools_locked(): return
		view.set_preview_stance("melee" if index == 0 else "ranged")
		_sync_actor_controls())
	_text(right,"静态姿势 · 保持显示，便于检查素材",12)
	pose_picker = _picker(right)
	pose_picker.item_selected.connect(func(index: int):
		await get_tree().process_frame
		if not tools_locked(): view.set_preview_pose(selected_actor,pose_picker.get_item_metadata(index)))
	_text(right,"完整演示 · 只播放动作，不扣生命",12)
	action_picker = _picker(right)
	action_picker.item_selected.connect(func(_index: int): _sync_attack_info())
	speed_picker = _picker(right)
	for speed in [1.0, 0.5, 0.25]:
		speed_picker.add_item("演示速度 ×" + str(speed))
		speed_picker.set_item_metadata(speed_picker.item_count - 1, speed)
	speed_picker.item_selected.connect(func(index: int):
		if not tools_locked(): view.preview_speed = float(speed_picker.get_item_metadata(index)))
	target_picker = _picker(right)
	row = _row(right)
	_button(row,"播放一次",play_action)
	pause_button = _button(row,"暂停",toggle_pause,false)
	loop_toggle = CheckBox.new()
	loop_toggle.text = "循环播放"
	loop_toggle.add_theme_font_size_override("font_size",13)
	loop_toggle.toggled.connect(func(value: bool):
		if value: _run_loop())
	row.add_child(loop_toggle)
	row = _row(right)
	_button(row,"恢复待机／归位",func():
		if tools_locked(): return
		loop_toggle.button_pressed = false
		view.reset_preview_poses()
		_sync_actor_controls())
	_text(right,"站位微调（脚底坐标）",12)
	row = _row(right)
	actor_x = _coordinate(row,"X",80,1360)
	actor_y = _coordinate(row,"Y",20,460)
	actor_x.value_changed.connect(func(_value: float): _move_actor())
	actor_y.value_changed.connect(func(_value: float): _move_actor())
	_text(right,"更换／增减敌人会重置本轮。\n仅有待机素材的敌人只提供姿势预览。",12)

func _coordinate(parent: Node, title: String, minimum: float, maximum: float) -> SpinBox:
	_text(parent,title,13)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.custom_minimum_size.x = 110
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.add_theme_font_size_override("font_size",14)
	parent.add_child(spin)
	return spin

func _move_actor() -> void:
	if syncing or tools_locked(): return
	var actor: Node2D = view.get_actor(selected_actor)
	if actor == null: return
	actor.position = Vector2(actor_x.value,actor_y.value)
	actor.home = actor.position
	view.stage.update_depth()

func _sync_actor_tabs() -> void:
	syncing = true
	actor_tabs.clear_tabs()
	actor_tabs.add_tab(CharacterNames.name_for_visual(PLAYER_VISUAL_ID))
	for i in roster.size(): actor_tabs.add_tab("敌人%d" % (i+1))
	selected_actor = clampi(selected_actor,0,roster.size())
	actor_tabs.current_tab = selected_actor
	syncing = false
	_sync_actor_controls()

func _sync_actor_controls() -> void:
	if not is_instance_valid(view): return
	syncing = true
	var actor: Node2D = view.get_actor(selected_actor)
	if actor == null:
		syncing = false
		return
	if selected_actor == 0:
		actor_info.text = "%s · %s" % [CharacterNames.name_for_visual(PLAYER_VISUAL_ID),"近战" if view.model.stance == "melee" else "远程"]
	else:
		actor_info.text = _enemy_name(roster[selected_actor-1])
	enemy_picker.visible = selected_actor > 0
	stance_picker.visible = selected_actor == 0
	stance_picker.select(0 if view.model.stance == "melee" else 1)
	if selected_actor > 0:
		for i in enemy_choices.size():
			if enemy_choices[i].id == roster[selected_actor-1]: enemy_picker.select(i)
	pose_picker.clear()
	var poses: Array = view.available_poses(selected_actor)
	for pose in poses:
		pose_picker.add_item(POSE_LABELS.get(pose,pose))
		pose_picker.set_item_metadata(pose_picker.item_count-1,pose)
		if pose == actor.pose: pose_picker.select(pose_picker.item_count-1)
	action_picker.clear()
	var actions: Array = []
	if poses.has("move"): actions.append(["move","移动并归位"])
	for pose in ["hit","slash","pierce","shoot","laser","bite"]:
		if poses.has(pose) or actor.pipeline_attacks.has(pose): actions.append([pose,POSE_LABELS.get(pose,pose)+"完整演示"])
	for pose in ["block","damaged"]:
		if poses.has(pose): actions.append([pose,POSE_LABELS[pose]+"反馈"])
	for entry in actions:
		action_picker.add_item(entry[1])
		action_picker.set_item_metadata(action_picker.item_count-1,entry[0])
	_sync_attack_info()
	target_picker.clear()
	if selected_actor == 0:
		for i in roster.size():
			target_picker.add_item("目标：" + _enemy_name(roster[i]))
			target_picker.set_item_metadata(i,i+1)
	else:
		target_picker.add_item("目标：" + CharacterNames.name_for_visual(PLAYER_VISUAL_ID))
		target_picker.set_item_metadata(0,0)
	actor_x.set_value_no_signal(actor.position.x)
	actor_y.set_value_no_signal(actor.position.y)
	syncing = false

func change_roster(value: String) -> void:
	if tools_locked(): return
	if value == "add":
		if roster.size() >= 3: return
		roster.append("robot")
		selected_actor = roster.size()
	elif value == "remove":
		if roster.size() <= 1 or selected_actor == 0: return
		roster.remove_at(selected_actor-1)
		selected_actor = mini(selected_actor,roster.size())
	else:
		if selected_actor == 0: return
		roster[selected_actor-1] = value
	await rebuild()

func _sync_attack_info() -> void:
	if not is_instance_valid(view) or not is_instance_valid(attack_info): return
	var actor: Node2D = view.get_actor(selected_actor)
	if actor == null: return
	var key := str(action_picker.get_item_metadata(action_picker.selected)) if action_picker.selected >= 0 else ""
	var config: Dictionary = actor.pipeline_attacks.get(key, {})
	if is_instance_valid(guides):
		guides.focused_actor = actor
		guides.attack_key = key
	if config.is_empty():
		attack_info.text = "沿用游戏演出 · " + (actor.attack_style_override if not actor.attack_style_override.is_empty() else "默认动作")
		return
	var types := {"hit":"打击", "bite":"咬击", "shoot":"远程射击", "laser":"远程射线"}
	var movements := {"approach":"接近目标", "stationary":"原地", "retreat":"后撤"}
	attack_info.text = "%s · %s\n%s → %s → %s" % [types.get(config.type,config.type), movements.get(config.movement,config.movement), config.windupPose, config.strikePose, config.recoveryPose]

func play_action() -> void:
	if tools_locked() or finished or action_picker.selected < 0: return
	var action: String = action_picker.get_item_metadata(action_picker.selected)
	var target: int = target_picker.get_item_metadata(target_picker.selected)
	await view.preview_action(selected_actor,action,target)
	pause_button.text = "暂停"

func _run_loop() -> void:
	if loop_running: return
	loop_running = true
	while loop_toggle.button_pressed:
		if tools_locked() or finished or action_picker.item_count == 0:
			loop_toggle.button_pressed = false
			break
		await play_action()
		await get_tree().create_timer(0.35).timeout
	loop_running = false

func toggle_pause() -> void:
	if not is_instance_valid(view) or not view.preview_busy: return
	var paused := pause_button.text == "暂停"
	view.pause_preview(paused)
	pause_button.text = "继续" if paused else "暂停"

func preview_camera(close: bool) -> void:
	if tools_locked(): return
	view.cancel_selection()
	camera_busy = true
	view.set_busy(true)
	if close:
		var enemy: Node2D = view.stage.enemies[0]
		view.stage.frame_attack(view.stage.player,enemy,view.stage.player.position)
		await view.stage.camera_tween.finished
	else: await view.stage.wide()
	view.set_busy(false)
	camera_busy = false

func capture_current() -> void:
	if tools_locked(): return
	capturing = true
	var was_left := left_panel.visible
	var was_right := right_panel.visible
	left_panel.hide()
	right_panel.hide()
	hint.hide()
	await RenderingServer.frame_post_draw
	var directory := "res://tests/combat/workbench/captures"
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error == OK:
		var ignore_file := FileAccess.open(directory.path_join(".gdignore"),FileAccess.WRITE)
		if ignore_file: ignore_file.close()
	var basename := directory.path_join(selected_place+"-"+str(Time.get_ticks_msec()))
	if error == OK: error = get_viewport().get_texture().get_image().save_png(basename+".png")
	if error == OK:
		var file := FileAccess.open(basename+".json",FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"place":selected_place,"map":settings,"roster":roster,"combat":view.model.snapshot()},"\t"))
			file.flush()
			error = file.get_error()
		else: error = FileAccess.get_open_error()
	left_panel.visible = was_left
	right_panel.visible = was_right
	hint.show()
	capturing = false
	status.text = "截图与参数已保存到 tests/combat/workbench/captures" if error == OK else "截图失败："+error_string(error)

func request_close() -> void:
	for id in profiles:
		if _dirty(id):
			close_dialog.popup_centered(Vector2i(490,160))
			return
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: request_close()

func _process(_delta: float) -> void:
	if not is_instance_valid(left_panel) or not is_instance_valid(view): return
	var locked := tools_locked()
	for button in mutations: button.disabled = locked
	add_enemy_button.disabled = locked or roster.size() >= 3
	remove_enemy_button.disabled = locked or roster.size() <= 1 or selected_actor == 0
	for picker in [place_picker,enemy_picker,pose_picker,target_picker,stance_picker,action_picker,speed_picker]: picker.disabled = locked
	for slider in sliders.values(): slider.editable = not locked
	actor_x.editable = not locked
	actor_y.editable = not locked
	pause_button.disabled = not view.preview_busy
	if not locked:
		_sync_hand()
		loop_toggle.disabled = finished or action_picker.item_count == 0

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit and not (event.ctrl_pressed and event.keycode == KEY_S): return
	match event.keycode:
		KEY_TAB:
			var show_both := not (left_panel.visible or right_panel.visible)
			left_panel.visible = show_both
			right_panel.visible = show_both
		KEY_BRACKETLEFT: left_panel.visible = not left_panel.visible
		KEY_BRACKETRIGHT: right_panel.visible = not right_panel.visible
		KEY_S:
			if not event.ctrl_pressed: return
			save_map()
		_: return
	get_viewport().set_input_as_handled()
