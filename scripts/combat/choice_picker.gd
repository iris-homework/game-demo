extends DemoUI
class ChoiceCard extends CombatCard:
	func face_highlight() -> StyleBoxFlat:
		var highlight := super.face_highlight()
		highlight.border_color = CYAN
		highlight.shadow_color = Color(0.2,1.0,0.88,0.42 if selected else 0.24)
		highlight.shadow_size = 9 if selected else 5
		return highlight

signal closed
signal picked(value)
var heading := "选择"
var options: Array = []
var option_buttons: Array[Button] = []
var cancel_button: Button
var resolved := false
# Card choices stage a UID locally; the battle commits only after confirmation.
var card_mode := false
var model: CombatModel
var selected_index := -1
var confirm_button: Button
var card_views: Array[CombatCard] = []
var selection_label: Label
var scroll: ScrollContainer
var hand_layout: Dictionary = {}
var card_homes: Array[Dictionary] = []
var card_tweens: Array[Tween] = []
const CENTER_SCALE := 1.5
const CENTER_POSITION := Vector2(585,248)

func _ready() -> void:
	z_index = 75
	mouse_filter = Control.MOUSE_FILTER_STOP
	if card_mode:
		build_card_choices()
	else:
		build_text_choices()
	wire_focus()

func build_text_choices() -> void:
	rect(self,Vector2.ZERO,Vector2(1440,900),Color(0.01,0.02,0.04,0.94))
	panel(self,Vector2(240,120),Vector2(960,660),INK,CYAN)
	label(self,heading,Vector2(280,146),Vector2(720,50),29)
	cancel_button = button(self,"取消",Vector2(1000,146),Vector2(150,42),cancel)
	scroll = ScrollContainer.new()
	scroll.position = Vector2(280,222)
	scroll.size = Vector2(880,514)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",12)
	scroll.add_child(column)
	for option in options:
		var btn := Button.new()
		btn.text = option.text
		btn.custom_minimum_size = Vector2(850,70)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size",18)
		btn.pressed.connect(choose.bind(option.value))
		column.add_child(btn)
		option_buttons.append(btn)

func build_card_choices() -> void:
	# Keep the battlefield visible, without an opaque dialog frame.
	rect(self,Vector2.ZERO,Vector2(1440,900),Color(0.01,0.02,0.03,0.76))
	var title := RichTextLabel.new()
	title.position = Vector2(260,126)
	title.size = Vector2(920,64)
	title.bbcode_enabled = true
	title.text = "[center]选择 [color=#64ffe1]1[/color] 张牌来[color=#efcd83]消耗[/color][/center]"
	title.add_theme_font_size_override("normal_font_size",34)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var hint := label(self,"被选中的牌将移入本场消耗区",Vector2(260,194),Vector2(920,32),18,MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i in options.size():
		var option: Dictionary = options[i]
		var uid := str(option.value)
		var spacing := minf(129.8,820.0/maxi(1,options.size()-1))
		var fallback := {"position":Vector2(625+(i-(options.size()-1)*0.5)*spacing,748),"scale":1.056,"rotation":0.0}
		var pose: Dictionary = hand_layout.get(uid,fallback)
		card_homes.append(pose)
		var card := ChoiceCard.new()
		card.allow_zoom_preview = false
		card.managed_input = true
		card.setup(uid,model.card(uid),true)
		card.pivot_offset = Vector2.ZERO
		card.position = pose.position
		card.scale = Vector2.ONE*float(pose.scale)
		card.rotation = float(pose.rotation)
		card.z_index = 2
		add_child(card)
		card.show_cost(model.card_cost(card.uid))
		card.show_preview(model.card_preview(card.uid))
		card_views.append(card)
		card_tweens.append(null)
		# Keep each hand slot clickable while its chosen card flies to the centre.
		var btn := Button.new()
		var centre: Vector2 = pose.position + (Vector2(90,115)*float(pose.scale)).rotated(float(pose.rotation))
		var hand_count := maxi(options.size(),model.hand.size())
		var hit_width := minf(129.8,800.0/maxi(1,hand_count-1))
		btn.position = Vector2(centre.x-hit_width*0.5, maxf(736,centre.y-115*float(pose.scale)))
		btn.size = Vector2(hit_width,900-btn.position.y)
		btn.z_index = 8
		btn.flat = true
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state_name in ["normal","hover","pressed","disabled","focus"]:
			btn.add_theme_stylebox_override(state_name,StyleBoxEmpty.new())
		btn.pressed.connect(select_candidate.bind(i))
		btn.mouse_entered.connect(refresh_card.bind(i))
		btn.mouse_exited.connect(refresh_card.bind(i))
		btn.focus_entered.connect(refresh_card.bind(i))
		btn.focus_exited.connect(refresh_card.bind(i))
		add_child(btn)
		option_buttons.append(btn)
	selection_label = label(self,"请选择一张手牌",Vector2(300,620),Vector2(810,40),23,CREAM)
	selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_button = button(self,"确认消耗  ✓",Vector2(1160,680),Vector2(230,64),confirm_choice)
	confirm_button.add_theme_color_override("font_color",CYAN)
	for state_name in ["normal","hover","pressed"]:
		var confirm_style := button_style(state_name,false)
		confirm_style.border_color = CYAN
		confirm_style.bg_color = Color("20545d") if state_name == "hover" else Color("13353c")
		confirm_button.add_theme_stylebox_override(state_name,confirm_style)
	confirm_button.disabled = true
	cancel_button = button(self,"取消",Vector2(50,688),Vector2(170,52),cancel)
	var help := label(self,"点击卡牌选择 · 确认后消耗 · Esc / 右键取消",Vector2(300,686),Vector2(840,32),16,MUTED)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if options.is_empty():
		selection_label.text = "没有可消耗的手牌"

func select_candidate(index: int) -> void:
	if resolved or index < 0 or index >= options.size(): return
	selected_index = index
	confirm_button.disabled = false
	selection_label.text = "消耗「%s」" % model.card(str(options[index].value)).get("name", "手牌")
	for i in card_views.size(): refresh_card(i)
	wire_focus(false)

func confirm_choice() -> void:
	if selected_index < 0: return
	choose(options[selected_index].value)

func refresh_card(index: int) -> void:
	if index >= option_buttons.size(): return
	var card := card_views[index]
	var active := index == selected_index
	var lifted := active or option_buttons[index].is_hovered() or option_buttons[index].has_focus()
	card.selected = active
	card.hovered = lifted
	card.queue_redraw()
	card.z_index = 5 if active else (3 if lifted else 2)
	if is_instance_valid(card_tweens[index]): card_tweens[index].kill()
	card_tweens[index] = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var pose := card_homes[index]
	var destination: Vector2 = CENTER_POSITION if active else pose.position+Vector2(0,-12 if lifted else 0)
	card_tweens[index].tween_property(card,"position",destination,0.23)
	card_tweens[index].tween_property(card,"scale",Vector2.ONE*(CENTER_SCALE if active else float(pose.scale)),0.23)
	card_tweens[index].tween_property(card,"rotation",0.0 if active else float(pose.rotation),0.23)

func wire_focus(initial := true) -> void:
	# Explicit neighbours keep Tab and directional focus inside the modal, including
	# the empty-options case where Cancel is the only focusable control.
	var controls: Array[Button] = option_buttons.duplicate()
	if card_mode and not confirm_button.disabled: controls.append(confirm_button)
	controls.append(cancel_button)
	for i in controls.size():
		var previous := controls[i].get_path_to(controls[posmod(i-1,controls.size())])
		var following := controls[i].get_path_to(controls[(i+1)%controls.size()])
		controls[i].focus_previous = previous
		controls[i].focus_next = following
		controls[i].focus_neighbor_top = previous
		controls[i].focus_neighbor_left = previous
		controls[i].focus_neighbor_bottom = following
		controls[i].focus_neighbor_right = following
	if initial: controls[0].grab_focus()

func choose(value) -> void:
	if resolved: return
	resolved = true
	picked.emit(value)

func cancel() -> void:
	if resolved: return
	resolved = true
	closed.emit()

func is_gui_key(event: InputEventKey) -> bool:
	for action in ["ui_accept","ui_focus_next","ui_focus_prev","ui_up","ui_down","ui_left","ui_right"]:
		if event.is_action(action): return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if resolved:
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if event.pressed and not event.echo: cancel()
		elif is_gui_key(event):
			# Let the focused Button handle both press and release, so accepting a
			# choice follows the same single-activation path as a mouse click.
			var focus := get_viewport().gui_get_focus_owner()
			if focus == null or not is_ancestor_of(focus):
				if option_buttons.is_empty(): cancel_button.grab_focus()
				else: option_buttons[0].grab_focus()
		else:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		cancel()

func _unhandled_key_input(_event: InputEvent) -> void:
	# GUI navigation that has no destination must not become a battle shortcut.
	get_viewport().set_input_as_handled()
