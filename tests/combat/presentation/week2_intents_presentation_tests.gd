extends Node
## Actual main-scene playback in an isolated copied project. Saves stay disabled.
const CASES := [
	["E17", "B17", "warden_shield", 1, 85],
	["E18", "B18", "chip_broker", 1, 72],
	["E19", "B19", "mutant_mouse", 2, 42],
	["E20", "B20", "luggage_lurker", 2, 45],
	["E21", "B21", "penitent_ascetic", 1, 80],
	["E22", "B22", "scavenger_hooker", 1, 78]]
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []
var output := ""
var capture := false
var started := 0
var finished := false
var app: Control

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("WEEK TWO PRESENTATION: " + message)

func report() -> void:
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":screenshots,"elapsedMs":Time.get_ticks_msec()-started}, "\t"))
		file.close()

func _process(_delta: float) -> void:
	if started > 0 and not finished and Time.get_ticks_msec()-started > 115000:
		finished = true
		check(false,"whole suite completes inside 115 seconds of wall time")
		report()
		get_tree().quit(2)

func settle() -> void:
	var deadline := Time.get_ticks_msec()+15000
	await get_tree().process_frame
	while Game.battle_busy or Game.transition_locked:
		await get_tree().process_frame
		if Time.get_ticks_msec() > deadline:
			check(false,"actual scene playback completes inside fifteen seconds")
			report()
			get_tree().quit(2)
			return
	await get_tree().process_frame
	await get_tree().process_frame

func open_battle(c: Array) -> Control:
	Game.save_enabled = false
	Game.pending_save_kind = ""
	Game.training_mode = false
	Game.tutorial_mode = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.state = Game.initial_state()
	Game.state.currentWeek = 2
	Game.state.currentDay = 1
	Game.state.currentScene = "battle"
	Game.state.currentPlaceId = Game.battles[c[1]].placeId
	Game.state.activeEventId = c[0]
	for node_id in Game.events[c[0]].nodes:
		if Game.events[c[0]].nodes[node_id].get("type", "") == "battle":
			Game.state.activeNodeId = node_id
			break
	Game.state.battleId = c[1]
	Game.page = "battle"
	Game.initialize_combat()
	if not is_instance_valid(app):
		app = preload("res://scenes/main.tscn").instantiate()
		add_child(app)
	else:
		app.swap_view()
	await settle()
	var battle: Control = app.view
	check(battle.initialized and battle.model.battle_id == c[1] and not Game.training_mode,c[1]+" opens through the actual main view using formal event context")
	return battle

func synced(battle: Control, label: String) -> void:
	check(battle.shown_player_hp == battle.model.player_hp,label+" player HP presentation matches model")
	check(battle.shown_player_block == battle.model.block,label+" player block presentation matches model")
	check(battle.shown_enemies.size() == battle.model.enemies.size(),label+" enemy display count matches model")
	for i in battle.model.enemies.size():
		var shown: Dictionary = battle.shown_enemies[i]
		var enemy: Dictionary = battle.model.enemies[i]
		check(shown.hp == enemy.hp and shown.block == enemy.block,label+" unit "+str(i)+" HP and block match model")
		for buff in ["strength", "electric_charge"]:
			check(battle.model.buffs.enemy_count(shown,battle.model.buffs.definition(buff)) == battle.model.buffs.count(battle.model,buff,i),label+" unit "+str(i)+" "+buff+" matches model")

func formation(battle: Control, c: Array) -> void:
	check(battle.stage.enemies.size() == c[3] and battle.targets.size() == c[3],c[1]+" formal number of actors and targets")
	battle.update_target_rects()
	var areas: Array[Rect2] = []
	for i in battle.stage.enemies.size():
		var actor: Node2D = battle.stage.enemies[i]
		check(actor.kind == c[2] and actor.poses.get("idle") is Texture2D and actor.poses.get("damaged") is Texture2D,c[1]+" unit "+str(i)+" owns the expected idle and recoil resources")
		check(actor.sprite.texture != null and actor.is_visible_in_tree() and actor.pipeline_diagnostics.is_empty(),c[1]+" unit "+str(i)+" displays its authored pose without pipeline errors")
		check(battle.model.enemies[i].maxHp == c[4],c[1]+" unit "+str(i)+" shows designed maximum HP")
		var area: Rect2 = battle.targets[i].get_global_rect()
		areas.append(area)
		check(area.size.x > 5 and area.size.y > 5 and get_viewport().get_visible_rect().intersects(area),c[1]+" unit "+str(i)+" has a visible nonempty target")
		var reachable := false
		for x in [0.1,0.3,0.5,0.7,0.9]:
			for y in [0.1,0.3,0.5,0.7,0.9]:
				if battle.target_at_point(area.position+area.size*Vector2(x,y)) == i: reachable = true
		check(reachable,c[1]+" unit "+str(i)+" can be targeted through its actual hit-test")
	if areas.size() == 2:
		check(areas[0] != areas[1] and not areas[0].encloses(areas[1]) and not areas[1].encloses(areas[0]),c[1]+" paired targets have distinct exposed areas")
		check(battle.stage.enemies[0].home != battle.stage.enemies[1].home,c[1]+" paired actors occupy distinct formation positions")

func compound(battle: Control, index: int, value: String, label_name: String, secondary: String, words: Array, label: String) -> void:
	var intent: Control = battle.enemy_intents[index]
	var extra: Label = intent.find_child(label_name,true,false)
	check(intent.icon_views.size() == 2 and intent.icon_views.all(func(icon): return icon.texture != null and icon.is_visible_in_tree()),label+" shows two real intent icons")
	check(intent.value_label.text == value and extra != null and extra.text == secondary and extra.is_visible_in_tree(),label+" shows separate primary and secondary numeric values")
	for word in words: check(intent.tooltip_data.plain.contains(word),label+" tooltip explains "+word)
	var tooltip: Object = intent._make_custom_tooltip("")
	check(tooltip is Control,label+" creates the actual formatted tooltip")
	if tooltip is Node: tooltip.free()

func screenshot_sizes(name: String) -> void:
	if not capture or DisplayServer.get_name() == "headless": return
	for resolution in [Vector2i(1280,800),Vector2i(1600,1000)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var filename := name+"_%dx%d.png" % [resolution.x,resolution.y]
		var error := get_viewport().get_texture().get_image().save_png(output.path_join(filename))
		check(error == OK,name+" saves GPU screenshot "+filename)
		if error == OK: screenshots.append(filename)

func turn(battle: Control, label: String) -> void:
	var previous: int = battle.model.turn
	battle.end_turn_pressed()
	await settle()
	check(battle.model.turn == previous+1,label+" real end-turn button advances exactly one round")
	synced(battle,label)

func test_cases() -> void:
	for c in CASES:
		var battle: Control = await open_battle(c)
		formation(battle,c)
		synced(battle,c[1]+" opening")
		match c[1]:
			"B17":
				await turn(battle,"shield opening fortify")
				check(battle.shown_enemies[0].block == 18,"shield opening grants eighteen visible block")
				compound(battle,0,"14","IntentBlockAmount","+8",["整次攻击","8 点格挡"],"shield attack and block")
				await screenshot_sizes("shield_compound")
				var hp: int = battle.model.player_hp
				await turn(battle,"shield attack-after-block")
				check(battle.model.player_hp == hp-14 and battle.shown_enemies[0].block == 8,"shield attack applies fourteen once then eight block")
			"B18":
				await turn(battle,"broker vulnerability setup")
				check(battle.enemy_intents[0].value_label.text == "12×2","broker preview includes the upcoming vulnerable double attack")
				await turn(battle,"broker vulnerable double attack")
				compound(battle,0,"12","IntentWeakAmount","2",["2 层虚弱"],"broker attack and weakness")
				await turn(battle,"broker weakness attack")
				check(battle.model.weak == 2 and battle.shown_player_weak == 2,"broker real playback applies and displays weakness once")
			"B19":
				await screenshot_sizes("mouse_pair")
				await turn(battle,"mouse pair real attack and pollution")
				check(battle.shown_player_pollution == 3 and battle.model.player_hp == 60,"two mice display ten attack damage and three pollution")
			"B20":
				compound(battle,0,"8","IntentChargeAmount","+4",["8 点格挡","4 层电能","完全格挡也减少"],"luggage box and charge")
				await screenshot_sizes("luggage_pair_compound")
				await turn(battle,"luggage pair charge and attack")
				check(battle.shown_enemies[0].block == 8 and battle.model.buffs.count(battle.model,"electric_charge",0) == 4,"luggage real compound action displays eight block and four charge")
				check(battle.enemy_intents[0].value_label.text == "9×2","luggage charged double attack previews nine twice")
				await turn(battle,"luggage charged attack and other box")
				check(battle.model.buffs.count(battle.model,"electric_charge",0) == 0 and battle.model.buffs.count(battle.model,"electric_charge",1) == 4 and battle.shown_enemies[1].block == 8,"luggage playback consumes one charge and grants the other box shield and charge")
			"B21":
				compound(battle,0,"+3","IntentHpLossAmount","−5",["5 点生命","3 层力量","无视格挡"],"ascetic life and strength")
				await screenshot_sizes("ascetic_compound")
				await turn(battle,"ascetic real self damage and growth")
				check(battle.shown_enemies[0].hp == 75 and battle.model.buffs.count(battle.model,"strength",0) == 3,"ascetic displays seventy-five HP and three strength")
			"B22":
				await turn(battle,"hook opening attack")
				compound(battle,0,"12","IntentStealAmount","≤8",["攻击前夺取","最多 8 点"],"hook steal and attack")
				battle.model.buffs.apply(battle.model,"block",20)
				battle.refresh_resources()
				await screenshot_sizes("hook_compound")
				var hp: int = battle.model.player_hp
				var observed := false
				battle.end_turn_pressed()
				var deadline := Time.get_ticks_msec()+15000
				while Game.battle_busy or Game.transition_locked:
					if battle.shown_player_block == 12 and battle.shown_enemies[0].block == 8: observed = true
					await get_tree().process_frame
					if Time.get_ticks_msec() > deadline: break
				await settle()
				check(observed,"hook playback visibly transfers eight from twenty player block before attack")
				check(battle.model.player_hp == hp and battle.shown_player_hp == hp and battle.model.block == 0 and battle.shown_enemies[0].block == 8,"remaining twelve block fully stops twelve damage and enemy keeps stolen eight")
				synced(battle,"hook steal completion")

func test_lethal_self_loss() -> void:
	var battle: Control = await open_battle(CASES[4])
	battle.model.enemies[0].hp = 5
	battle.shown_enemies = battle.model.enemies.duplicate(true)
	battle.refresh_enemy_hud()
	var retired := false
	var visible_zero := false
	battle.end_turn_pressed()
	var deadline := Time.get_ticks_msec()+15000
	while Game.battle_busy or Game.transition_locked:
		if is_instance_valid(battle):
			visible_zero = visible_zero or battle.shown_enemies[0].hp == 0
			retired = retired or not battle.stage.enemies[0].alive
		await get_tree().process_frame
		if Time.get_ticks_msec() > deadline: break
	await settle()
	check(visible_zero and retired,"lethal self loss visibly reaches zero HP and retires the authored actor")
	check(not Game.battle_busy and not Game.transition_locked and Game.page == "dialogue" and Game.state.activeEventId == "E21","lethal self loss finishes playback and reaches the formal victory dialogue")
	check(Game.state.combat.get("outcome", "") == "win" and Game.state.combat.enemies[0].hp == 0,"lethal self loss commits an actual winning combat snapshot")

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in output.to_lower() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("WEEK TWO PRESENTATION: use absolute QA_OUT_DIR and an isolated QA user directory")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused_checkpoint.json")
	Game.meta_path = output.path_join("unused_meta.json")
	capture = OS.get_environment("QA_CAPTURE") == "1"
	started = Time.get_ticks_msec()
	Engine.time_scale = 6.0
	await test_cases()
	await test_lethal_self_loss()
	Engine.time_scale = 1.0
	if is_instance_valid(app):
		await preload("res://scripts/combat/audio_cleanup.gd").release(app,get_tree())
		app.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	finished = true
	report()
	print("WEEK TWO PRESENTATION: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
