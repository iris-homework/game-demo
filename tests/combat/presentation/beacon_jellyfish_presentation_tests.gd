extends Node
## Real scene playback under headless/Dummy; state assertions, no pixel QA.
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("JELLYFISH PRESENTATION: " + message)

func settle() -> void:
	var start := Time.get_ticks_msec()
	while Game.battle_busy or Game.transition_locked:
		await get_tree().process_frame
		if Time.get_ticks_msec()-start > 25000:
			check(false,"battle playback completes within timeout")
			get_tree().quit(2)
			return
	await get_tree().process_frame

func _ready() -> void:
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(2))
	Game.save_enabled = false
	Game.save_path = "user://jellyfish-unused.json"
	Game.meta_path = "user://jellyfish-meta-unused.json"
	Engine.time_scale = 4.0
	Game.state = Game.initial_state()
	var adventure := Game.state.duplicate(true)
	var app := preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_enemy_training("beacon_jellyfish")
	await settle()
	var battle: Control = app.view
	var hp: int = battle.model.player_hp
	check(battle.model.battle_id == "training_beacon_jellyfish" and Game.battles[battle.model.battle_id].enemyIds == Game.battles.B15.enemyIds and battle.model.enemies[0].id == "beacon_jellyfish" and battle.model.enemies[0].hp == 36 and battle.enemy_intents[0].value_label.text == "10", "Published practice reuses formal B15 enemies with thirty-six HP and attack ten")
	var badges: Array = battle.enemy_plates[0].badges.filter(func(b): return b.symbol == "soft")
	check(badges.size() == 1 and badges[0].amount == 1 and badges[0].is_visible_in_tree() and badges[0].tooltip_text.contains("3点格挡"), "Actual HUD displays innate soft and its tooltip from battle start")
	var uid: String = battle.model.hand[0]
	battle.model.instances[uid] = "noren_35"
	battle.model.stance = "melee"
	battle.shown_enemies = battle.model.enemies.duplicate(true)
	battle.refresh_enemy_hud()
	battle.select_card(uid)
	battle.play_selected(0)
	var observed: Array = []
	while Game.battle_busy:
		var shown: int = battle.shown_enemies[0].block
		if observed.is_empty() or observed.back() != shown: observed.append(shown)
		await get_tree().process_frame
	await settle()
	check(observed.has(3) and observed.has(4) and observed.has(5), "Three real attack callbacks display block three, four, five in sequence")
	check(battle.model.enemies[0].hp == 34 and battle.shown_enemies[0].hp == 34 and battle.enemy_plates[0].block == 5 and battle.shown_enemies[0].block == 5, "Model, presentation and HP plate agree after the three hits")
	var after_card: Dictionary = battle.model.snapshot()
	battle.refresh_enemy_hud()
	check(battle.model.snapshot() == after_card, "Refreshing passive/block presentation never applies extra block")
	battle.end_turn_pressed()
	await settle()
	var weak: Label = battle.enemy_intents[0].find_child("IntentWeakAmount",true,false)
	check(battle.model.player_hp == hp-10 and battle.shown_player_hp == hp-10 and battle.shown_enemies[0].block == 0, "First enemy turn clears its soft block and applies ten damage once")
	check(battle.enemy_intents[0].value_label.text == "8" and weak != null and weak.text == "2" and battle.enemy_intents[0].tooltip_data.plain.contains("2 层虚弱"), "Second intent shows attack eight plus weakness two and detailed tooltip")
	check(battle.model.weak == 0 and battle.shown_player_weak == 0, "The preview does not apply weakness early")
	battle.end_turn_pressed()
	await settle()
	check(battle.model.player_hp == hp-18 and battle.shown_player_hp == hp-18 and battle.model.weak == 2 and battle.shown_player_weak == 2, "Second attack resolves eight damage and two weak stacks exactly once")
	check(battle.enemy_intents[0].value_label.text == "10" and battle.enemy_intents[0].find_child("IntentWeakAmount",true,false) == null, "Loop returns to plain attack ten without a stale weak marker")
	badges = battle.enemy_plates[0].badges.filter(func(b): return b.symbol == "soft")
	check(badges.size() == 1 and badges[0].amount == 1, "Innate passive remains visible after both enemy turns")
	Game.finish_training("lose")
	await settle()
	check(Game.state == adventure, "Leaving practice restores the original adventure")
	Engine.time_scale = 1.0
	app.audio_player.stop_all()
	# Allow the Dummy audio mixer to release queued Ogg playback references.
	await get_tree().create_timer(0.5).timeout
	app.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	print("JELLYFISH PRESENTATION: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
