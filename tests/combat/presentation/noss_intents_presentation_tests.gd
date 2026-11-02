extends Node
## Formal B23 through the real main scene, with QA-only memory fixtures and paths.
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []
var output := ""
var capture := false
var started := 0
var finished := false
var app: Control
var phase_lines_advanced := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("NOSS INTENT PRESENTATION: " + message)

func report() -> void:
	var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":screenshots,"elapsedMs":Time.get_ticks_msec()-started},"\t"))
		file.close()

func _process(_delta: float) -> void:
	if started > 0 and not finished and Time.get_ticks_msec()-started > 145000:
		finished = true
		check(false,"whole suite finishes within 145 wall-clock seconds")
		report()
		get_tree().quit(2)

func advance_phase_dialogue() -> void:
	if not is_instance_valid(app) or not is_instance_valid(app.view): return
	var interlude: Node = app.view.get_node_or_null("NossPhaseDialogue")
	if interlude != null:
		phase_lines_advanced += 1
		interlude.advance_line()

func settle() -> void:
	var deadline := Time.get_ticks_msec()+20000
	await get_tree().process_frame
	while Game.battle_busy or Game.transition_locked:
		advance_phase_dialogue()
		await get_tree().process_frame
		if Time.get_ticks_msec() > deadline:
			check(false,"real battle/phase playback completes within twenty seconds")
			report()
			get_tree().quit(2)
			return
	await get_tree().process_frame
	await get_tree().process_frame

func open_boss() -> Control:
	Game.save_enabled = false
	Game.pending_save_kind = ""
	Game.training_mode = false
	Game.tutorial_mode = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.state = Game.initial_state()
	Game.state.currentWeek = 2
	Game.state.currentDay = 7
	Game.state.currentScene = "battle"
	Game.state.currentPlaceId = "tower"
	Game.state.activeEventId = "E23"
	Game.state.activeNodeId = "battle"
	Game.state.battleId = "B23"
	Game.page = "battle"
	Game.initialize_combat()
	if not is_instance_valid(app):
		app = preload("res://scenes/main.tscn").instantiate()
		add_child(app)
	else:
		app.swap_view()
	await settle()
	var battle: Control = app.view
	check(battle.initialized and battle.model.battle_id == "B23" and not Game.training_mode,"actual main opens formal B23")
	check(Game.valid_combat(battle.model.snapshot()),"formal opening combat snapshot validates")
	return battle

func synced(battle: Control, label: String) -> void:
	check(battle.shown_player_hp == battle.model.player_hp,label+" player HP matches model")
	check(battle.shown_player_block == battle.model.block,label+" player block matches model")
	check(battle.shown_enemies.size() == battle.model.enemies.size(),label+" enemy count matches model")
	for i in battle.model.enemies.size():
		check(battle.shown_enemies[i].hp == battle.model.enemies[i].hp and battle.shown_enemies[i].block == battle.model.enemies[i].block,label+" unit "+str(i)+" HP/block agree")
		for id in ["alien_sin","strength"]:
			check(battle.model.buffs.enemy_count(battle.shown_enemies[i],battle.model.buffs.definition(id)) == battle.model.buffs.count(battle.model,id,i),label+" unit "+str(i)+" "+id+" agrees")
	check(Game.valid_combat(battle.model.snapshot()),label+" snapshot validates")

func turn(battle: Control, label: String) -> void:
	var previous: int = battle.model.turn
	battle.end_turn_pressed()
	await settle()
	check(battle.model.turn == previous+1,label+" advances exactly one round")
	synced(battle,label)

func shot(name: String) -> void:
	if not capture or DisplayServer.get_name() == "headless": return
	for resolution in [Vector2i(1280,800),Vector2i(1600,1000)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var filename := name+"_%dx%d.png" % [resolution.x,resolution.y]
		var error := get_viewport().get_texture().get_image().save_png(output.path_join(filename))
		check(error == OK,"GPU screenshot saved: "+filename)
		if error == OK: screenshots.append(filename)

func tooltip_shot(battle: Control, index: int, name: String) -> void:
	if not capture or DisplayServer.get_name() == "headless": return
	var card: Control = battle.enemy_intents[index]._make_custom_tooltip("")
	battle.add_child(card)
	card.position = Vector2(40,135)
	card.z_index = 200
	await shot(name)
	battle.remove_child(card)
	card.queue_free()
	await get_tree().process_frame

func restore_fixture_health(battle: Control) -> void:
	battle.model.player_hp = battle.model.max_hp
	battle.shown_player_hp = battle.model.player_hp
	battle.refresh_hp()

func kill_only_noss(battle: Control) -> void:
	check(battle.model.enemies[0].hp > 0 and battle.model.enemies[1].hp > 0,"both hands are alive before the independent Noss kill")
	battle.model.enemies[2].hp = 1
	battle.model.enemies[2].block = 0
	battle.shown_enemies = battle.model.enemies.duplicate(true)
	battle.refresh_enemy_hud()
	var uid: String = battle.model.hand[0]
	battle.model.instances[uid] = "noren_01"
	var old_lines := phase_lines_advanced
	battle.select_card(uid)
	battle.play_selected(2)
	await settle()
	check(battle.model.encounter_phase == 2 and battle.model.enemies.size() == 1 and battle.model.enemies[0].id == "noss_phase2" and battle.model.enemies[0].hp == 160,"killing only Noss enters the full-health second phase")
	check(phase_lines_advanced-old_lines == 6,"all six real phase-dialogue lines advance")
	check(battle.stage.enemies.size() == 1 and battle.enemy_portraits.size() == 1 and battle.targets.size() == 1 and battle.stage.enemies[0].kind == "noss_phase2","both surviving hand actors and HUD targets retire at the phase change")
	check(battle.model.energy == 3 and battle.model.hand.size() == 5,"phase change provides one fresh full-energy five-card player turn")
	synced(battle,"body-only phase change")

func test_first_phase() -> Control:
	var battle: Control = await open_boss()
	check(battle.model.enemies.map(func(e): return e.maxHp) == [40,40,100],"phase one displays 40/40/100 HP")
	check(battle.enemy_intents[1].kind == "block_ally_deferred" and battle.enemy_intents[1].value_label.text == "+12" and battle.enemy_intents[1].tooltip_data.plain.contains("全部敌人行动结束后"),"right hand displays the deferred guard instruction")
	await shot("phase1_opening")
	await tooltip_shot(battle,1,"guard_tooltip")
	var hp: int = battle.model.player_hp
	await turn(battle,"phase-one opening")
	check(battle.model.player_hp == hp-18 and battle.shown_enemies[2].block == 12,"opening deals eighteen and leaves Noss twelve guard through the player turn")
	hp = battle.model.player_hp
	await turn(battle,"phase-one second turn")
	check(battle.model.player_hp == hp-8 and battle.shown_enemies[2].block == 0,"next turn deals eight and expires the previous deferred shield")
	await kill_only_noss(battle)
	restore_fixture_health(battle)
	return battle

func test_sin_discharge(battle: Control) -> void:
	var hp: int = battle.model.player_hp
	await turn(battle,"six-arm verdict")
	check(battle.model.player_hp == hp-18 and battle.model.weak == 2 and battle.shown_player_weak == 2,"three swords deal eighteen and apply two weakness")
	var extra: Label = battle.enemy_intents[0].find_child("IntentSinAmount",true,false)
	check(battle.enemy_intents[0].icon_views.size() == 2 and battle.enemy_intents[0].value_label.text == "10" and extra != null and extra.text == "+3","聚日 shows attack ten plus three 异罪")
	check(battle.enemy_intents[0].tooltip_data.plain.contains("异罪") and battle.enemy_intents[0].tooltip_data.plain.contains("完全格挡"),"聚日 tooltip explains the special status and blocked-hit counterplay")
	hp = battle.model.player_hp
	await turn(battle,"聚日")
	check(battle.model.player_hp == hp-10 and battle.model.buffs.count(battle.model,"alien_sin",0) == 3 and battle.enemy_intents[0].value_label.text == "30","聚日 deals ten, grants three 异罪 and previews thirty")
	var badges: Array = battle.enemy_plates[0].badges.filter(func(b): return b.symbol == "alien_sin")
	check(badges.size() == 1 and badges[0].amount == 3 and badges[0].tooltip_text.contains("异罪"),"three-layer 异罪 badge is visible with the renamed description")
	await shot("sin_three")
	await tooltip_shot(battle,0,"sun_tooltip")
	# A real triple attack is completely blocked; each segment must still discharge.
	battle.model.enemies[0].block = 100
	battle.shown_enemies = battle.model.enemies.duplicate(true)
	battle.refresh_enemy_hud()
	var uid: String = battle.model.hand[0]
	battle.model.instances[uid] = "noren_35"
	var enemy_hp: int = battle.model.enemies[0].hp
	var layers: Array = [3]
	var damage_previews: Array = ["30"]
	battle.select_card(uid)
	battle.play_selected(0)
	var deadline := Time.get_ticks_msec()+20000
	while Game.battle_busy or Game.transition_locked:
		var shown: int = battle.model.buffs.enemy_count(battle.shown_enemies[0],battle.model.buffs.definition("alien_sin"))
		if layers.back() != shown:
			layers.append(shown)
			damage_previews.append(battle.enemy_intents[0].value_label.text)
		await get_tree().process_frame
		if Time.get_ticks_msec() > deadline: break
	await settle()
	check(layers == [3,2,1,0] and damage_previews == ["30","26","22","18"],"three real blocked impacts reveal individual 异罪 reductions and 30/26/22/18 previews")
	check(battle.model.enemies[0].hp == enemy_hp and battle.model.enemies[0].block > 0 and battle.model.buffs.count(battle.model,"alien_sin",0) == 0,"the real triple is completely blocked while removing all 异罪")
	synced(battle,"three-hit discharge")
	await shot("sin_removed")
	hp = battle.model.player_hp
	await turn(battle,"discharged sun")
	check(battle.model.player_hp == hp-18 and battle.model.buffs.count(battle.model,"alien_sin",0) == 0,"zero-layer sun resolves eighteen once and leaves no stale badge")
	hp = battle.model.player_hp
	await turn(battle,"reform light wheel")
	check(battle.model.player_hp == hp and battle.model.enemies[0].block == 12 and battle.model.buffs.count(battle.model,"strength",0) == 1,"fourth step grants twelve shield and one strength without attacking")
	check(battle.enemy_intents[0].value_label.text == "7×3","one strength raises the next sword preview to seven times three")
	restore_fixture_health(battle)
	hp = battle.model.player_hp
	await turn(battle,"grown six-arm verdict")
	check(battle.model.player_hp == hp-21,"the next real triple resolves twenty-one damage")

func test_full_sin_heavy() -> void:
	var battle: Control = await open_boss()
	await kill_only_noss(battle)
	restore_fixture_health(battle)
	await turn(battle,"fresh verdict for full heavy")
	await turn(battle,"fresh 聚日 for full heavy")
	var hp: int = battle.model.player_hp
	var saw_charge := false
	var charge_held := true
	var saw_impact := false
	var impact_stable := true
	battle.end_turn_pressed()
	var deadline := Time.get_ticks_msec()+20000
	while Game.battle_busy or Game.transition_locked:
		var layers: int = battle.model.buffs.enemy_count(battle.shown_enemies[0],battle.model.buffs.definition("alien_sin"))
		if battle.stage.phase == "halo_charge":
			saw_charge = true
			charge_held = charge_held and layers == 3 and battle.shown_player_hp == hp and battle.enemy_intents[0].value_label.text == "30"
		if battle.stage.phase == "halo_burst":
			saw_impact = true
			impact_stable = impact_stable and layers == 0 and battle.shown_player_hp == hp-30 and battle.enemy_intents[0].value_label.text == "30"
		await get_tree().process_frame
		if Time.get_ticks_msec() > deadline: break
	await settle()
	check(saw_charge and charge_held,"full 异罪 and thirty preview persist through the actual halo charge with no early HP loss")
	check(saw_impact and impact_stable,"actual halo impact clears 异罪 while keeping the captured thirty-damage preview")
	check(battle.model.player_hp == hp-30 and battle.model.buffs.count(battle.model,"alien_sin",0) == 0,"full heavy resolves thirty once and consumes all three layers")
	synced(battle,"full 异罪 heavy")

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in output.to_lower() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("NOSS INTENT PRESENTATION: use copied project, QA user storage and absolute QA_OUT_DIR")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused_checkpoint.json")
	Game.meta_path = output.path_join("unused_meta.json")
	capture = OS.get_environment("QA_CAPTURE") == "1"
	started = Time.get_ticks_msec()
	Engine.time_scale = 6.0
	var battle: Control = await test_first_phase()
	await test_sin_discharge(battle)
	await test_full_sin_heavy()
	Engine.time_scale = 1.0
	if is_instance_valid(app):
		await preload("res://scripts/combat/audio_cleanup.gd").release(app,get_tree())
		app.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	finished = true
	report()
	print("NOSS INTENT PRESENTATION: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
