extends "res://tests/combat/cards/noren_cards_visual.gd"
var hit_states: Array = []

func on_phase(phase: String) -> void:
	if phase != "impact" or app.view.stage.active_attacker == app.view.stage.player: return
	hit_states.append([app.view.stage.enemies.find(app.view.stage.active_attacker),app.view.shown_player_hp,app.view.shown_player_pollution])

func _ready() -> void:
	output = "res://artifacts/qa/enemy-round-death-2026-10-19/fish-rules/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = "user://fish_rules_visual_unused.json"
	Game.meta_path = "user://fish_rules_visual_meta_unused.json"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B11")
	await idle()
	var view: Control = app.view
	check(view.model.enemies.size() == 2,"Two fish in actual battle")
	check(view.stage.enemies.all(func(e): return e.kind == "fish"),"Both actors use fish art")
	check(view.model.enemies.all(func(e): return e.hp == 30),"Both start at 30 HP in enemy test")
	check(view.model.enemy_intent_text(view.model.enemies[0]) == "攻击 6","First opening intent")
	check(view.model.enemy_intent_text(view.model.enemies[1]) == "污染 2","Second opening intent")
	check(view.targets[0].tooltip_text.contains("追加 2 层污染"),"Fish passive tooltip")
	check(view.targets[0].tooltip_text.contains("死亡时，对你施加 3 层污染"),"Fish death tooltip uses three stacks independently of two-stack contact")
	view.stage.phase_changed.connect(on_phase)
	await shot("opening-two-fish")
	var opening_hp: int = view.model.player_hp
	var hp_offset := opening_hp - 100
	var expected_hp := [94 + hp_offset,80 + hp_offset,67 + hp_offset,47 + hp_offset]
	var expected_pollution := [4,9,14,17]
	var expected_hits := [
		[[0,94 + hp_offset,2]],
		[[0,88 + hp_offset,5],[0,86 + hp_offset,7],[1,80 + hp_offset,9]],
		[[1,69 + hp_offset,12],[1,67 + hp_offset,14]],
		[[0,47 + hp_offset,15]]
	]
	for round_index in 4:
		hit_states.clear()
		await view.end_turn_pressed()
		await idle()
		check(view.model.player_hp == expected_hp[round_index],"Round %d model HP" % round_index)
		check(view.shown_player_hp == expected_hp[round_index],"Round %d display HP" % round_index)
		check(view.shown_player_pollution == expected_pollution[round_index],"Round %d display pollution" % round_index)
		check(hit_states == expected_hits[round_index],"Round %d per-contact source / HP / stacks: %s" % [round_index,str(hit_states)])
		check(view.player_plate.statuses.any(func(b): return b.buffId == "pollution"),"Pollution badge displayed")
		await shot("round-%d" % (round_index + 1))
	# Render a status-only fatal tick, verifying no enemy attack animation follows.
	view.model.player_hp = 1
	view.shown_player_hp = 1
	view.model.buffs.apply(view.model,"pollution",999)
	view.refresh_resources()
	view.commit()
	hit_states.clear()
	await view.end_turn_pressed()
	await idle()
	check(hit_states.is_empty(),"Fatal pollution causes no fish attack animation")
	check(not Game.training_mode,"Fatal pollution finishes training")
	check(Game.state.currentHp == opening_hp,"Training restores adventure HP")
	# Enemy turn-end deaths must retire the correct actor before later actions.
	Game.start_training("B11")
	await idle()
	view = app.view
	view.model.enemies[0].hp = 1
	view.model.enemies[0].intent = {"type":"pollution","amount":2}
	view.model.buffs.apply(view.model,"pollution",1,0)
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.refresh_enemy_hud()
	view.commit()
	await view.end_turn_pressed()
	await idle()
	check(view.model.enemies[0].hp == 0 and not view.stage.enemies[0].alive,"Enemy pollution death retires first fish")
	check(view.stage.enemies[0].modulate.a == 0 and view.shown_enemies[0].hp == 0,"Dead fish and HUD fade together")
	check(view.model.enemies[1].hp == 30 and view.stage.enemies[1].alive,"Second fish survives independently")
	check(view.shown_player_pollution == 7 and view.model.buffs.count(view.model,"pollution") == 7,"Two active two-stack intents plus one three-stack death total seven")
	await shot("first-fish-pollution-death")
	view.model.buffs.apply(view.model,"pollution",999,1)
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.refresh_enemy_hud()
	view.commit()
	await shot("pollution-999-enemy")
	await view.end_turn_pressed()
	await idle()
	check(not Game.training_mode and Game.state.currentHp == opening_hp,"Last fish pollution death wins and restores training")
	await preload("res://scripts/combat/audio_cleanup.gd").release(app, get_tree())
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("FISH VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
