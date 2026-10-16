extends "res://tests/card_console_visual.gd"

func click(button: Button) -> void:
	# Battle hit testing polls the live pointer, so synchronize it with injected events.
	Input.warp_mouse(get_viewport().get_final_transform() * button.get_global_rect().get_center())
	await get_tree().create_timer(0.08).timeout
	await super.click(button)

func idle() -> void:
	var start := Time.get_ticks_msec()
	while Game.battle_busy or Game.transition_locked:
		await get_tree().process_frame
		if Time.get_ticks_msec()-start > 20000:
			check(false,"Battle settled within timeout")
			get_tree().quit(1)
			return
	await get_tree().create_timer(0.25).timeout

func deck_button() -> Button:
	return app.view.get_node("current_deck_button") as Button

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	Game.save_enabled = false
	Game.save_path = "user://current_deck_qa.json"
	Game.meta_path = "user://current_deck_meta_qa.json"
	Game.state = Game.initial_state()
	Game.state.deck = ["noren_23","noren_23","noren_40"]
	Game.page = "map"
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await idle()
	check(Game.save_game(),"Create isolated save fixture")
	var saved := FileAccess.get_file_as_bytes(Game.save_path)
	var original: Dictionary = Game.state.duplicate(true)
	var revision := Game.revision
	check(deck_button().position == Vector2(976,16),"Deck button at upper right")
	await shot("map-button")
	await click(deck_button())
	await idle()
	var browser = app.deck_browser
	check(is_instance_valid(browser) and browser.current_deck_mode,"Click opens current deck overlay")
	check(browser.counter.text == "6 种 / 13 张" and browser.display_counts.noren_23 == 2,"Owned deck counts include starters and duplicates")
	check(browser.card_views.size() == 6,"Only owned cards appear")
	for card in browser.card_views:
		check(card.preview_only and not card.enabled,"Cards remain read-only")
	check(app.view.process_mode == Node.PROCESS_MODE_DISABLED,"Underlying view paused")
	await key(KEY_A,true,true)
	check(not is_instance_valid(app.card_console),"Deck modal blocks console shortcut")
	await shot("owned-deck")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.deck_browser) and Game.page == "map","Esc returns to original map")
	check(app.view.process_mode != Node.PROCESS_MODE_DISABLED and not deck_button().disabled,"Underlying controls restored")
	check(Game.state == original and Game.revision == revision and FileAccess.get_file_as_bytes(Game.save_path) == saved,"Browsing preserves state, revision and saved bytes")
	# The dialogue toolbar must accommodate history, deck, skip and menu together.
	Game.page = "dialogue"
	app.swap_view()
	await idle()
	check(not deck_button().get_rect().intersects(app.view.history_button.get_rect()) and not deck_button().get_rect().intersects(app.view.skip_button.get_rect()),"Dialogue toolbar buttons do not overlap")
	await shot("dialogue-button")
	var dialogue = app.view
	await click(deck_button())
	await idle()
	var visible: int = dialogue.text_label.visible_characters
	await get_tree().create_timer(0.15).timeout
	check(dialogue.text_label.visible_characters == visible,"Dialogue reveal pauses while browsing")
	await click(app.deck_browser.close_button)
	check(app.view == dialogue and Game.page == "dialogue","Close button retains original dialogue view")
	dialogue.open_history()
	Game.open_current_deck()
	check(not is_instance_valid(app.deck_browser),"History modal prevents nested deck modal")
	dialogue.close_history()
	# Battle browsing must use the frozen battle deck, regardless of later ownership.
	Game.start_training("B04")
	await idle()
	var battle = app.view
	var model: CombatModel = battle.model
	var discarded: String = model.hand.pop_back()
	var exhausted: String = model.hand.pop_back()
	model.discard_pile.append(discarded)
	model.exhaust_pile.append(exhausted)
	Game.commit_combat(model)
	app.swap_view()
	await idle()
	battle = app.view
	Game.state.deck.append("noren_36") # Fixture: future ownership must not enter this battle.
	var snapshot: Dictionary = battle.model.snapshot()
	Game.battle_busy = true
	Game.open_current_deck()
	check(not is_instance_valid(app.deck_browser),"Busy battle rejects opening")
	Game.battle_busy = false
	battle.show_pile("抽牌堆",battle.model.draw_pile)
	Game.open_current_deck()
	check(not is_instance_valid(app.deck_browser),"Existing battle modal rejects opening")
	battle.close_pile()
	await idle()
	await shot("battle-button")
	await click(deck_button())
	await idle()
	browser = app.deck_browser
	check(is_instance_valid(browser),"Battle deck button opens browser")
	if not is_instance_valid(browser):
		get_tree().quit(1)
		return
	check(browser.counter.text == "6 种 / 13 张" and not browser.display_counts.has("noren_36"),"Battle view excludes cards added after battle initialization")
	var expected := {}
	for id in snapshot.instances.values(): expected[id] = int(expected.get(id,0))+1
	check(browser.display_counts == expected,"All instances counted across draw, hand, discard and exhaust")
	await shot("battle-deck")
	await key(KEY_F6)
	check(not Game.battle_busy and battle.model.snapshot() == snapshot,"Deck blocks underlying battle shortcut")
	await click(browser.close_button)
	check(app.view == battle and Game.page == "battle" and not Game.battle_busy,"Close returns to same battle without transition")
	check(battle.model.snapshot() == snapshot and Game.state.combat == snapshot,"Browsing never reorders or changes combat")
	check(FileAccess.get_file_as_bytes(Game.save_path) == saved,"Battle browser leaves disk save unchanged")
	# Snapshot definitions also support old saved battles.
	var legacy := CombatModel.new()
	legacy.initialize("B04",100,100,Game.prototype_rules,[Game.enemy_catalog[Game.battles.B04.enemyIds[0]]])
	Game.commit_combat(legacy)
	app.swap_view()
	await idle()
	await click(deck_button())
	await idle()
	check(app.deck_browser.card_views.size() > 0 and app.deck_browser.display_counts.size() == 1,"Legacy battle cards remain visible")
	await key(KEY_ESCAPE)
	Game.finish_training("lose")
	await idle()
	Game.open_card_library()
	await idle()
	check(not app.view.current_deck_mode and app.view.card_views.size() == 6,"Main menu library still works")
	await click(app.view.close_button)
	check(Game.page == "menu","Original library close still returns to menu")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(Game.save_path+suffix): DirAccess.remove_absolute(Game.save_path+suffix)
	print("CURRENT DECK VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
