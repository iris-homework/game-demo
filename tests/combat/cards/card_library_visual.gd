extends Node
var app: Control
var checks := 0
var failures := 0
var output := "res://artifacts/qa/card-library-fullscreen-2026-10-10/"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await get_tree().create_timer(0.45).timeout

func mouse(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var point := get_viewport().get_final_transform() * pos
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await get_tree().process_frame
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame

func click_button(button: Button) -> void:
	await mouse(button.get_global_rect().get_center())
	await settle()

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle()

func shot(id: String) -> void:
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output+id+".png") == OK,"Screenshot " + id)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = output + "test_checkpoint.json"
	Game.meta_path = output + "test_meta.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(Game.save_path+suffix): DirAccess.remove_absolute(Game.save_path+suffix)
	output += "%dx%d-" % [get_window().size.x,get_window().size.y]
	Game.state = {}
	Game.page = "menu"
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle()
	check(app.view.continue_button.disabled and not app.view.library_button.disabled,"Library available with no adventure or save")
	await shot("menu")
	await click_button(app.view.library_button)
	check(Game.page == "card_library" and Game.state.is_empty(),"Mouse opens library without starting adventure")
	var view = app.view
	check(view.scroll.size.x > 1360 and view.scroll.size.y > 770,"Card grid uses almost the whole game canvas")
	check(view.close_button.text == "×" and view.close_button.position.x > 1300 and view.close_button.position.y < 40,"Close cross is at the upper right")
	check(view.card_views.size() == 4,"Library shows all four authored test card types")
	var ids := []
	for card in view.card_views:
		ids.append(card.data.id)
		check(card.preview_only and not card.enabled,"Card is a read-only preview")
		check(view.scroll.get_global_rect().encloses(Rect2(card.global_position,card.size*card.scale)),"Full card face fits the scroll viewport")
	check(ids == ["test_attack","test_reward_01","test_reward_02","test_reward_03"],"Base card and all unowned rewards are visible")
	var card := view.card_views[1] as CombatCard
	var pos := card.position
	await mouse(card.get_global_transform() * Vector2(90,110))
	await settle()
	check(Game.state.is_empty() and Game.page == "card_library" and not card.selected and card.position == pos,"Preview click neither claims nor lifts a card")
	await shot("library")
	await click_button(view.close_button)
	check(Game.page == "menu" and Game.state.is_empty(),"Top-right cross restores main menu")
	check(not FileAccess.file_exists(Game.save_path),"Browsing without a save does not create one")
	# Existing adventure and persisted bytes must survive every library visit.
	Game.state = Game.initial_state()
	Game.state.credits = 731
	Game.state.deck = ["test_reward_02","test_reward_02"]
	var adventure := Game.state.duplicate(true)
	check(Game.save_game(),"Create isolated adventure fixture")
	var saved := FileAccess.get_file_as_bytes(Game.save_path)
	var revision := Game.revision
	Game.menu()
	await settle()
	app.view.library_button.grab_focus()
	await key(KEY_ENTER)
	check(Game.page == "card_library","Enter activates focused library entry")
	check(app.view.definitions.size() == 4,"Owned duplicates do not duplicate catalogue definitions")
	check(Game.state == adventure and Game.revision == revision,"Library entry leaves adventure and revision unchanged")
	await key(KEY_ESCAPE)
	check(Game.page == "menu" and Game.state == adventure,"Escape returns to menu without resuming or changing adventure")
	await click_button(app.view.new_button)
	check(app.view.library_button.disabled,"New-adventure confirmation blocks library entry")
	await key(KEY_ESCAPE)
	check(not app.view.library_button.disabled and Game.state == adventure,"Cancel restores library button and preserves adventure")
	await click_button(app.view.training_toggle)
	var training_button: Button = app.view.find_child("training_B12",true,false)
	check(training_button.is_visible_in_tree() and not app.view.library_button.get_global_rect().intersects(training_button.get_global_rect()),"Expanded training and library controls do not overlap")
	await shot("menu-expanded")
	await click_button(app.view.library_button)
	await click_button(app.view.close_button)
	await click_button(app.view.continue_button)
	check(Game.page == "dialogue" and Game.state == adventure,"Continue resumes the same adventure after library visit")
	check(FileAccess.get_file_as_bytes(Game.save_path) == saved,"Library navigation leaves saved bytes unchanged")
	# Data expansion uses definitions automatically, with stable IDs and scrolling.
	var original := Game.card_catalog.duplicate(true)
	Game.card_catalog["test_reward_01"] = Game.reward_rules.cards.test_reward_01.duplicate(true)
	Game.card_catalog.test_reward_01.name = "目录优先测试"
	Game.card_catalog.test_reward_01.sortOrder = 0
	var catalog := Game.library_cards()
	check(catalog.size() == 4 and catalog[0].name == "目录优先测试","Formal catalogue wins ID collisions and sortOrder")
	catalog[0].name = "copy only"
	check(Game.card_catalog.test_reward_01.name == "目录优先测试","Library definitions cannot mutate source catalogues")
	for i in range(28):
		var extra: Dictionary = Game.reward_rules.cards.test_reward_03.duplicate(true)
		extra.id = "qa_card_%02d" % i
		extra.name = "扩展测试 %02d" % i
		Game.card_catalog[extra.id] = extra
	Game.menu()
	await settle()
	await click_button(app.view.library_button)
	view = app.view
	check(view.card_views.size() == 32,"Expanded catalogue automatically populates grid")
	var fully_visible := 0
	for preview in view.card_views:
		if view.scroll.get_global_rect().encloses(Rect2(preview.global_position,preview.size*preview.scale)): fully_visible += 1
	check(fully_visible >= 21,"At least 21 complete cards visible without scrolling")
	await shot("library-capacity-32-test-cards")
	for i in range(8): await mouse(Vector2(600,500),MOUSE_BUTTON_WHEEL_DOWN)
	await settle()
	check(view.scroll.scroll_vertical > 0,"Wheel over cards scrolls the catalogue")
	await key(KEY_END)
	var last: CombatCard = view.card_views.back()
	check(view.scroll.get_global_rect().encloses(Rect2(last.global_position,last.size*last.scale)),"Last card fully accessible at end of scroll")
	await key(KEY_HOME)
	check(view.scroll.scroll_vertical == 0,"Home returns to first row")
	Game.card_catalog = original
	Game.menu()
	check(Game.state == adventure and FileAccess.get_file_as_bytes(Game.save_path) == saved,"Expansion fixture and navigation preserve adventure")
	print("CARD LIBRARY VISUAL: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
