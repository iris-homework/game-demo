extends "res://tests/combat/cards/noren_cards_visual.gd"
## Program-driven battle view checks; isolated from formal saves.

func _ready() -> void:
	Game.save_enabled=false
	Game.save_path="user://parry_ammo_visual_unused.json"
	Game.meta_path="user://parry_ammo_visual_meta_unused.json"
	output="res://artifacts/qa/parry-ammo-2026-10-19/window/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state=Game.initial_state()
	var adventure: Dictionary=Game.state.duplicate(true)
	app=preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	await install_hand([1],"ranged")
	var view=app.view
	view.model.ammo=7;view.model.parry=3;view.model.block=999
	for enemy in view.model.enemies:
		enemy.intent={"type":"attack","amount":4,"hits":3}
	view.shown_enemies=view.model.enemies.duplicate(true)
	view.refresh_resources();view.refresh_enemy_hud();view.commit()
	check(view.resources_label.text.ends_with("7 / 10"),"HUD shows configured ten-ammo capacity")
	check(view.model.buffs.player_badges(view.model)[0].description.contains("50%") and view.model.buffs.player_badges(view.model)[0].description.contains("最多 3 层"),"Parry tooltip shows half damage and three charges")
	view.end_turn_pressed()
	var seen: Array=[]
	var committed: Dictionary={}
	var stable := true
	var started:=Time.get_ticks_msec()
	while Game.battle_busy:
		if view.presenting_enemy_turn:
			if committed.is_empty(): committed=view.model.snapshot()
			stable=stable and view.model.snapshot()==committed
			if not view.resources_label.text in seen: seen.append(view.resources_label.text)
		await get_tree().process_frame
		if Time.get_ticks_msec()-started>30000:
			check(false,"Parry presentation timed out")
			get_tree().quit(1)
			return
	await idle()
	print("PARRY AMMO DISPLAY: ",seen)
	check(stable,"Animation never repeats parry model effects")
	check(["7 / 10","8 / 10","9 / 10","10 / 10"].all(func(suffix): return seen.any(func(line): return line.ends_with(suffix))),"Ammo display advances once at each of three counter contacts")
	check(view.model.ammo==10 and view.resources_label.text.ends_with("10 / 10") and view.model.parry==0,"Enemy turn finishes at ten ammo with all three charges spent")
	check(view.model.enemies.all(func(e): return e.hp==114 and e.bleed==0),"Each twelve-damage multi-hit attack receives one six-damage counter without bleed")
	check(view.shown_enemies.all(func(e): return e.hp==114 and e.bleed==0),"Displayed enemy state matches model after counters")
	check(Game.valid_combat(Game.state.combat),"Final ten-ammo snapshot validates")
	await shot("three-counters-ten-ammo")
	view.model.profile.ammoCap=6;view.model.ammo=6
	view.refresh_resources()
	check(view.resources_label.text.ends_with("6 / 6"),"Older snapshot capacity is displayed from its profile")
	Game.menu();await idle()
	check(Game.state==adventure and not Game.training_mode,"Training restores adventure")
	app.queue_free()
	view=null
	app=null
	await get_tree().process_frame
	await get_tree().process_frame
	print("PARRY AMMO VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
