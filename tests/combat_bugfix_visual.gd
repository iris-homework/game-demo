extends "res://tests/hand_number_keys_visual.gd"
const FishRules = preload("res://tests/fish_rules_tests.gd")
var fish_rules := FishRules.new()
var contact_states: Array = []

func canonical(value):
	return JSON.parse_string(JSON.stringify(value))

func test_debug_modal() -> void:
	await install_hand([2,1,4])
	var view = app.view
	view.exhaust_button.disabled = true
	view.end_button.grab_focus()
	var before: Dictionary = view.model.snapshot()
	var adventure: Dictionary = Game.state.duplicate(true)
	var original_mode: int = view.process_mode
	var card_point: Vector2 = view.cards["card_000"].get_global_transform()*Vector2(90,50)
	await key(KEY_F1)
	check(is_instance_valid(app.debug_panel), "F1 opens the developer panel")
	check(view.process_mode == Node.PROCESS_MODE_DISABLED, "Developer panel suspends battle input processing")
	check(view.find_children("*","BaseButton",true,false).all(func(node): return node.disabled and node.focus_mode == Control.FOCUS_NONE), "Underlying battle buttons cannot receive mouse or keyboard focus")
	await pointer(card_point,1)
	await pointer(Vector2(720,400))
	await pointer(Vector2(720,400),0)
	await key(KEY_1)
	await key(KEY_F6)
	await pointer(view.end_button.get_global_rect().get_center(),1)
	await pointer(view.end_button.get_global_rect().get_center(),0)
	check(view.selected_uid.is_empty() and view.held_card_uid.is_empty(), "Mouse and number keys cannot grab underlying cards")
	check(view.model.snapshot() == before and Game.state == adventure and not Game.battle_busy, "Blocked card, turn and preview input never spends resources or starts combat playback")
	await shot("debug-modal-blocks-battle")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.debug_panel) and Game.page == "battle", "Escape closes only the developer panel")
	check(view.process_mode == original_mode and not view.end_button.disabled and view.exhaust_button.disabled, "Close restores processing and preserves each button's original disabled state")
	check(get_viewport().gui_get_focus_owner() == view.end_button, "Close restores the original keyboard focus")
	await pointer(Vector2(720,400),0)
	check(view.model.snapshot() == before, "A stale mouse release after closing cannot play a card")
	await key(KEY_1)
	await pointer(Vector2(720,400),1)
	await pointer(Vector2(720,400),0)
	await idle()
	check(view.model.block == 5 and view.model.energy == 2 and view.model.discard_pile == ["card_000"], "Normal card play resumes and resolves exactly once")
	await key(KEY_F1)
	await key(KEY_F1)
	check(not is_instance_valid(app.debug_panel) and view.process_mode == original_mode, "F1 also restores battle input on close")
	await key(KEY_F1)
	var close_button: Button
	for node in app.debug_panel.find_children("*","Button",true,false):
		if node.text == "关闭 / F1": close_button = node
	await pointer(close_button.get_global_rect().get_center(),1)
	await pointer(close_button.get_global_rect().get_center(),0)
	check(not is_instance_valid(app.debug_panel) and view.process_mode == original_mode, "The panel's own close button remains usable")
	await key(KEY_F1)
	var hp_button: Button
	for node in app.debug_panel.find_children("*","Button",true,false):
		if node.text == "HP 50": hp_button = node
	await pointer(hp_button.get_global_rect().get_center(),1)
	await pointer(hp_button.get_global_rect().get_center(),0)
	await idle()
	check(not is_instance_valid(app.debug_panel) and app.view.model.player_hp == 50, "Developer actions still update the checkpoint and close the rebuilt panel")
	check(app.view.process_mode == original_mode and app.debug_background_buttons.is_empty(), "View rebuild clears the old modal's input state")

func install_fish_case(number: int, form: String, health: Array, bleed: int) -> void:
	await idle()
	if not Game.training_mode: Game.start_training("B11")
	await idle()
	var m: CombatModel = fish_rules.fish_fixture()
	m.instances["card_000"] = "noren_%02d" % number
	m.stance = form
	m.buffs.apply(m,"pollution",2)
	for index in health.size(): m.enemies[index].hp = health[index]
	if bleed > 0: m.buffs.apply(m,"bleed",bleed,0)
	Game.commit_combat(m)
	app.swap_view()
	await idle()
	contact_states.clear()
	var view = app.view
	view.stage.phase_changed.connect(func(phase):
		if phase in ["impact","shoot"] and view.stage.active_attacker == view.stage.player:
			contact_states.append([view.shown_enemies.map(func(enemy): return int(enemy.hp)),view.shown_player_pollution]))

func test_fish_case(number: int, form: String, health: Array, bleed: int = 0) -> void:
	await install_fish_case(number,form,health,bleed)
	var view = app.view
	var m: CombatModel = view.model
	var expected := CombatModel.new()
	expected.restore(m.snapshot())
	var result := expected.play_card("card_000",0)
	var expected_contacts: Array = []
	var shown_health := health.duplicate()
	for hit in result.hits:
		shown_health[int(hit.target)] = int(hit.hpAfter)
		expected_contacts.append([shown_health.duplicate(),int(hit.playerPollutionAfter)])
	view.select_card("card_000",false)
	view.play_selected(0)
	var committed: Dictionary = canonical(m.snapshot())
	var title := "Card %02d %s" % [number,form]
	check(view.shown_player_pollution == 2 and view.shown_enemies[0].hp == health[0], title+": pollution and enemy HP stay unchanged before impact")
	check(committed == canonical(expected.snapshot()) and canonical(Game.state.combat) == committed, title+": full rules result is committed once before playback")
	await shot("before-impact-%02d-%s" % [number,form])
	await idle()
	check(contact_states == expected_contacts, title+": every hit reveals only its own chronological death pollution: "+str(contact_states))
	check(canonical(m.snapshot()) == committed, title+": presentation never recalculates damage, status or card piles")
	if result.outcome.is_empty():
		check(view.shown_player_pollution == m.buffs.count(m,"pollution"), title+": final HUD agrees with the model")
		check(not view.stage.enemies[0].alive and view.stage.enemies[1].alive, title+": only the killed fish retires")
	else:
		check(result.outcome == "win" and not Game.training_mode and Game.page == "menu", title+": last enemy death still exits training normally")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://combat_bugfix_unused.json"
	Game.meta_path = "user://combat_bugfix_meta_unused.json"
	output = "res://artifacts/qa/combat-bugfix-2026-10-20/window/"
	var args := OS.get_cmdline_user_args()
	if args.has("--output-dir"): output = args[args.find("--output-dir")+1].trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state = Game.initial_state()
	var original: Dictionary = Game.state.duplicate(true)
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	var deadline := Time.get_ticks_msec()+5000
	while not get_window().has_focus() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	Game.start_training("B11")
	await idle()
	await test_debug_modal()
	await test_fish_case(1,"melee",[6,30])
	await test_fish_case(1,"ranged",[9,30])
	await test_fish_case(35,"ranged",[4,30],2)
	await test_fish_case(38,"melee",[4,4])
	await test_fish_case(38,"ranged",[6,6])
	check(Game.state == original and not Game.training_mode, "All test training restores the exact original adventure")
	fish_rules.fixtures.free()
	fish_rules.free()
	app.queue_free()
	app = null
	await get_tree().process_frame
	await get_tree().process_frame
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false},"\t"))
	print("COMBAT BUGFIX VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
