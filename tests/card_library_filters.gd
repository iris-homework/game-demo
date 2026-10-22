extends Node
## Catalogue filters exercise the real browser without writing adventure saves.
const Library = preload("res://scripts/card_library.gd")
var checks := 0
var failures: Array[String] = []
var view: Control
var output := "res://artifacts/qa/library-filters-2026-10-22"
var visual := false

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func ids() -> Array:
	return view.definitions.map(func(card): return str(card.id))

func activate(node_name: String) -> void:
	var control: Button = view.get_node(node_name)
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
	await get_tree().process_frame

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		get_viewport().push_input(event, true)
	await get_tree().process_frame

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func shot(name_text: String) -> void:
	if not visual: return
	await get_tree().create_timer(0.2).timeout
	RenderingServer.force_draw()
	var name_prefix := "%dx%d-" % [get_window().size.x, get_window().size.y]
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name_prefix + name_text + ".png")) == OK, "Capture " + name_text)

func remove_view() -> void:
	remove_child(view)
	view.queue_free()
	await settle()

func _ready() -> void:
	visual = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	Game.save_enabled = false
	Game.save_path = output.path_join("isolated-checkpoint.json")
	Game.meta_path = output.path_join("isolated-meta.json")
	Game.state = Game.initial_state()
	Game.state.deck = ["noren_05", "noren_05", "noren_26", "noren_36"]
	var original_state: Dictionary = Game.state.duplicate(true)
	var original_catalog: Dictionary = Game.card_catalog.duplicate(true)
	var original_revision: int = Game.revision
	var original_page: String = Game.page
	view = Library.new()
	add_child(view)
	await settle()
	check(view.owned_only and ids().size() == 7, "Default scope shows seven owned kinds")
	check(view.counter.text == "7 种 / 14 张", "Owned counter preserves duplicate quantities")
	check(view.get_node("scope_owned").button_pressed and not view.get_node("scope_all").button_pressed, "Default ownership is visibly selected")
	await shot("01-owned")
	await activate("scope_all")
	check(ids().size() == 40 and not view.owned_only, "Pointer activation opens all forty definitions")
	check(view.get_node("scope_all").button_pressed and not view.get_node("scope_owned").button_pressed, "Scope selection persists independently of focus")
	for rarity in ["C", "B", "A", "S"]:
		view.set_filter("rarity", rarity)
		check(ids().size() == {"C":4,"B":23,"A":9,"S":4}[rarity], "Rarity catalogue " + rarity)
	view.clear_filters()
	await activate("filter_rarity_B")
	await activate("filter_cost_0")
	await activate("filter_type_skill")
	check(ids() == ["noren_05", "noren_08", "noren_12", "noren_15", "noren_34"], "Three categories intersect to five B zero-cost skills in catalogue order")
	for selected in ["filter_rarity_B", "filter_cost_0", "filter_type_skill"]:
		check(view.get_node(selected).button_pressed, "Persistent category selection " + selected)
	check(not view.get_node("filter_rarity_all").button_pressed, "Only one rarity is selected")
	await shot("02-combined")
	await activate("scope_owned")
	check(ids() == ["noren_05"] and view.display_counts.noren_05 == 2, "Scope switch preserves categories and two owned copies")
	check(view.counter.text.contains("2 张"), "Filtered quantity counts only matching copies")
	await activate("filter_rarity_S")
	check(ids().is_empty(), "Incompatible combination produces a genuine empty result")
	check(view.find_children("*", "Label", true, false).any(func(node): return node.is_visible_in_tree() and "没有" in node.text), "Empty result explains there are no matching cards")
	await shot("03-empty")
	await activate("clear_filters")
	check(view.owned_only and ids().size() == 7, "Clear resets categories while retaining owned scope")
	check(view.get_node("filter_rarity_all").button_pressed and view.get_node("filter_cost_all").button_pressed and view.get_node("filter_type_all").button_pressed, "Clear restores all category indicators")
	await activate("scope_all")
	view.get_node("filter_type_power").grab_focus()
	await key(KEY_ENTER)
	check(ids() == ["noren_23", "noren_36", "noren_40"], "Enter activates focused type filter")
	view.clear_filters()
	view.set_filter("rarity", "S")
	view.set_filter("cost", "3+")
	view.set_filter("type", "attack")
	check(ids() == ["noren_26"], "Three-plus bucket includes the authored three-cost finisher")
	view.clear_filters()
	await settle()
	await key(KEY_END)
	await settle()
	var last: Control = view.card_views.back()
	check(view.scroll.scroll_vertical > 0 and view.scroll.get_global_rect().encloses(last.get_global_rect()), "End reaches the final full card after adding the filter toolbar")
	await key(KEY_HOME)
	check(view.scroll.scroll_vertical == 0, "Home returns to the first row")
	await shot("04-all")
	var buttons := view.find_children("*", "Button", true, false).filter(func(node): return str(node.name).begins_with("filter_") or str(node.name).begins_with("scope_") or node.name in ["clear_filters", "close_library"])
	var toolbar_valid := true
	for i in buttons.size():
		toolbar_valid = toolbar_valid and Rect2(0,0,1440,900).encloses(buttons[i].get_global_rect())
		toolbar_valid = toolbar_valid and not buttons[i].get_global_rect().intersects(view.scroll.get_global_rect())
		for j in range(i + 1, buttons.size()):
			toolbar_valid = toolbar_valid and not buttons[i].get_global_rect().intersects(buttons[j].get_global_rect())
	check(toolbar_valid, "All toolbar hit areas fit the canvas without overlapping each other or the card grid")
	check(view.card_views.all(func(card): return card.preview_only and not card.enabled), "Filtered previews remain read-only")
	check(Game.state == original_state and Game.card_catalog == original_catalog and Game.revision == original_revision and Game.page == original_page, "All filtering preserves adventure, catalogues, revision and page")
	await remove_view()
	# Deliberately different saved definitions prove filtering follows the battle,
	# rather than today's catalogue, current discounts or later owned additions.
	var frozen: Dictionary = Game.card_catalog.noren_05.duplicate(true)
	frozen.cost = 4
	frozen.rarity = "S"
	frozen.type = "power"
	var old: Dictionary = Game.prototype_rules.cards.test_attack.duplicate(true)
	var snapshot := {"cardCatalog":{"noren_05":frozen,"test_attack":old}, "instances":{"hand":"noren_05","exhausted":"noren_05","draw":"test_attack"}, "costDiscount":3}
	var original_snapshot: Dictionary = snapshot.duplicate(true)
	view = Library.new()
	view.setup_current_deck(snapshot)
	add_child(view)
	await settle()
	check(ids().size() == 2 and view.counter.text == "2 种 / 3 张", "Frozen deck includes all instances and legacy definitions")
	check(view.get_node_or_null("scope_all") == null, "Current deck cannot switch into the global catalogue")
	view.set_filter("rarity", "S")
	view.set_filter("cost", "3+")
	view.set_filter("type", "power")
	check(ids() == ["noren_05"] and view.counter.text.contains("2 张"), "Frozen rarity, four-cost base price and type override current definitions and discounts")
	await shot("05-frozen-deck")
	view.clear_filters()
	check("test_attack" in ids(), "Unclassified legacy card remains discoverable under all categories")
	check(snapshot == original_snapshot and Game.state == original_state, "Frozen data and actual ownership are unchanged")
	await remove_view()
	view = Library.new()
	add_child(view)
	await settle()
	check(view.owned_only and ids().size() == 7 and view.get_node("filter_rarity_all").button_pressed, "Reopening starts with owned scope and clear categories")
	await remove_view()
	Game.page = "dialogue"
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle()
	var dialogue: Control = app.view
	Game.open_current_deck()
	await settle()
	view = app.deck_browser
	check(is_instance_valid(view) and view.current_deck_mode and dialogue.process_mode == Node.PROCESS_MODE_DISABLED, "Actual adventure opens the filtered deck and pauses the underlying view")
	await activate("filter_type_power")
	check(ids() == ["noren_36"], "Current adventure filters only owned powers")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.deck_browser) and app.view == dialogue and Game.page == "dialogue", "Escape closes filtered deck and restores the same adventure page")
	Game.open_current_deck()
	await settle()
	view = app.deck_browser
	check(ids().size() == 7, "Reopened adventure overlay clears prior filtering")
	await activate("close_library")
	check(not is_instance_valid(app.deck_browser) and dialogue.process_mode != Node.PROCESS_MODE_DISABLED, "Close button restores underlying input after filtering")
	check(Game.state == original_state and Game.revision == original_revision, "Actual overlay navigation leaves adventure and revision unchanged")
	remove_child(app)
	app.queue_free()
	await settle()
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "Browser creates no save or meta files")
	print("CARD LIBRARY FILTERS: %d checks, %d failures" % [checks, failures.size()])
	var report := FileAccess.open(output.path_join("result-%s.json" % ("%dx%d" % [get_window().size.x,get_window().size.y] if visual else "headless")), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"visual":visual}, "\t"))
	report.close()
	get_tree().quit(0 if failures.is_empty() else 1)
