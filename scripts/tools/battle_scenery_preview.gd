extends Node
## Isolated, playable preview of the real battle view. No adventure files are written.
const PLACE_IDS := ["garden", "hive", "port", "pump", "junkyard", "hotel", "tower", "block5", "church", "alley", "bar"]
const PREVIEW_BATTLE := "B04"
var app: Control
var controls: DemoUI
var selector: OptionButton
var previous_button: Button
var next_button: Button
var restart_button: Button
var selected_index := 1
var original_battle: Dictionary

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://battle_scenery_preview_unused.json"
	Game.meta_path = "user://battle_scenery_preview_meta_unused.json"
	original_battle = Game.battles[PREVIEW_BATTLE].duplicate(true)
	# Training initializes the combat model synchronously. Set the view's location
	# before creating main, so its first battle never renders the original alley.
	Game.start_training(PREVIEW_BATTLE)
	apply_place()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	build_controls()

func apply_place() -> void:
	var preview_battle := original_battle.duplicate(true)
	preview_battle.placeId = PLACE_IDS[selected_index]
	preview_battle.name = "战斗场景预览"
	Game.battles[PREVIEW_BATTLE] = preview_battle

func can_switch() -> bool:
	return is_instance_valid(app) and Game.training_mode and app.shown_page == "battle" and not Game.battle_busy and not Game.transition_locked and app.view.selected_uid.is_empty() and not is_instance_valid(app.deck_browser) and not is_instance_valid(app.card_console) and not is_instance_valid(app.view.pile_overlay)

func switch_to(index: int) -> bool:
	if not can_switch(): return false
	selected_index = posmod(index, PLACE_IDS.size())
	apply_place()
	app.swap_view()
	selector.select(selected_index)
	return true

func restart() -> void:
	if Game.battle_busy or Game.transition_locked: return
	if Game.training_mode: Game.restore_training()
	# Disconnect only the app's page listener during this synchronous restart;
	# its existing view is replaced once after the new in-memory model is ready.
	Game.changed.disconnect(app.show_page)
	Game.start_training(PREVIEW_BATTLE)
	apply_place()
	Game.changed.connect(app.show_page)
	app.swap_view()

func build_controls() -> void:
	controls = DemoUI.new()
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.z_index = 80
	add_child(controls)
	controls.cut_panel(controls, Vector2(35,207), Vector2(628,49), DemoUI.INK, DemoUI.CYAN, 9)
	previous_button = controls.button(controls,"‹",Vector2(43,213),Vector2(42,36),func(): switch_to(selected_index-1))
	selector = OptionButton.new()
	selector.position = Vector2(93,213)
	selector.size = Vector2(240,36)
	selector.add_theme_font_size_override("font_size",17)
	for place_id in PLACE_IDS:
		selector.add_item(Game.place_data(place_id).name)
	selector.select(selected_index)
	selector.item_selected.connect(func(index: int):
		if not switch_to(index): selector.select(selected_index))
	controls.add_child(selector)
	next_button = controls.button(controls,"›",Vector2(341,213),Vector2(42,36),func(): switch_to(selected_index+1))
	restart_button = controls.button(controls,"重新演练",Vector2(393,213),Vector2(116,36),restart)
	restart_button.add_theme_font_size_override("font_size",16)
	controls.label(controls,"%d 张 · 可出牌" % PLACE_IDS.size(),Vector2(521,219),Vector2(130,26),14,DemoUI.MUTED)
	selector.tooltip_text = "切换背景保留当前演练；出牌或选牌期间请先完成或取消。"

func _process(_delta: float) -> void:
	if not is_instance_valid(selector): return
	var available := can_switch()
	selector.disabled = not available
	previous_button.disabled = not available
	next_button.disabled = not available
	restart_button.disabled = Game.battle_busy or Game.transition_locked or (Game.page == "battle" and not available)

func _exit_tree() -> void:
	if not original_battle.is_empty(): Game.battles[PREVIEW_BATTLE] = original_battle
