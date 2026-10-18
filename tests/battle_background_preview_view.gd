extends "res://scripts/battle.gd"
## Test-only adapter: production battle presentation, with no story/menu exits.
signal preview_finished(result: String)
const PreviewCard = preload("res://tests/battle_background_preview_card.gd")

func hand_position(index: int, count: int) -> Vector2:
	return super.hand_position(index, count) - Vector2(0, PreviewCard.REST_RAISE)

func create_card(uid: String, index: int, count: int, animate: bool) -> CombatCard:
	# The isolated trial uses its own card class; the production card is untouched.
	var card := PreviewCard.new()
	card.managed_input = true
	card.home_scale = HAND_SCALE
	card.home_rotation = hand_rotation(index, count)
	card.home_z = 10 + index
	card.setup(uid, model.card(uid))
	card.home = hand_position(index, count)
	add_child(card)
	card.chosen.connect(begin_card_aim)
	card.position = card.home
	card.visible = not animate
	card.z_index = card.home_z
	card.scale = Vector2.ONE * card.home_scale
	card.rotation = card.home_rotation
	cards[uid] = card
	return card

func chrome(section: String, show_days: bool = true) -> void:
	super.chrome(section, show_days)
	for child in get_children():
		if child is Button and child.text == "退出演练":
			for connection in child.pressed.get_connections():
				child.pressed.disconnect(connection.callable)
			child.text = "关闭试装"
			child.pressed.connect(func(): get_parent().request_close())

func set_preview_location(title: String) -> void:
	for child in get_children():
		if child is Label and (child.text == battle.name or child.get_meta("preview_title", false)):
			child.text = title + " · 试装"
			child.set_meta("preview_title", true)
		elif child is Label and child.text.begins_with("COMBAT //"):
			child.text = "BACKGROUND FITTING / 背景试装"

func finish(result: String) -> void:
	if Game.transition_locked or Game.battle_busy or is_instance_valid(pile_overlay): return
	cancel_selection()
	preview_finished.emit(result)

func show_debug_results() -> void:
	if Game.battle_busy or is_instance_valid(pile_overlay): return
	get_parent().rebuild(get_parent().enemy_count)

func _input(event: InputEvent) -> void:
	if get_parent().modal_open(): return
	# The battle handles mouse input before GUI dispatch. Keep tool clicks out of it.
	if event is InputEventMouse and get_parent().tool_contains(event.position): return
	super._input(event)
