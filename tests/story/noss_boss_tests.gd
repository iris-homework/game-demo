extends Node
## Must run from a copied project with QA user storage and absolute QA_OUT_DIR.
var output := ""
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("NOSS BOSS: " + message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func fresh(week: int = 2, day: int = 7, difficulty: String = "normal") -> void:
	if Game.training_mode: Game.restore_training()
	Game.save_enabled = false
	Game.pending_save_kind = ""
	Game.transition_locked = false
	Game.battle_busy = false
	Game.tutorial_mode = false
	Game.save_path = output.path_join("checkpoint.json")
	Game.meta_path = output.path_join("meta.json")
	Game.state = Game.initial_state("", difficulty)
	Game.state.currentWeek = week
	Game.state.currentDay = day
	Game.state.currentScene = "map"
	Game.state.currentPlaceId = "tower"
	Game.page = "map"
	Game.refresh_event_pool()

func start_boss(difficulty: String = "normal") -> CombatModel:
	fresh(2, 7, difficulty)
	check(Game.start_event("E23"), "second-week day-seven Boss starts through map event")
	Game.skip_dialogue(Game.revision)
	check(Game.page == "battle" and Game.state.battleId == "B23", "intro/skip enters formal B23")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	return model

func phase_two(model: CombatModel) -> void:
	for i in model.enemies.size(): model.enemy_damage(i, 999)
	model.resolve_outcome()
	check(model.advance_encounter_phase(), "full first formation advances into phase two")

func test_gates_and_dialogue() -> void:
	for week in [1, 2]:
		for day in [1, 6, 7]:
			fresh(week, day)
			var eligible: bool = week == 2 and day == 7
			check(Game.event_in_refresh_range(Game.events.E23) == eligible, "week/day gate %d/%d" % [week, day])
			if not eligible: check(not Game.start_event("E23"), "cannot start unoffered Noss early")
	fresh()
	check(Game.state.refreshedEventIds == ["E23"], "Boss reserves pool and replaces ordinary commissions on day seven")
	check(Game.state.flags.get("nossBossAppeared", false), "second-week Boss appearance latches separately")
	check(not Game.start_event("E17"), "ordinary event cannot bypass day-seven clear-out")
	check(Game.start_event("E23"), "Boss intro starts")
	var visited: Array = []
	while Game.page == "dialogue" and visited.size() < 30:
		visited.append(Game.state.activeNodeId)
		Game.advance(Game.revision)
	check(visited.size() == 11 and Game.page == "battle", "all eleven authored introduction lines reach combat")
	for id in ["noss", "noss_phase2"]:
		check(Game.texture(id) != null and not Game.assets[id].whiteKey, id + " portrait loads with native alpha")
	check(Game.events.E23.phaseTwoDialogue.size() == 6, "six authored transition lines")
	check(Game.valid_save(Game.state), "new Boss opening save validates")
	var intent_tip := preload("res://scripts/combat/intent_tooltip.gd").describe({"displayName":"诺斯", "intent":Game.enemy_catalog.noss.intentSequence[1]}, "强化 +1")
	check(intent_tip.unit.contains("金手") and intent_tip.summary.contains("敕令之手"), "Noss companion tooltip names gold hands rather than gang henchmen")
	check(Game.enemy_catalog.noss_phase2.intentSequence[2].animation == "halo_burst" and Game.enemy_catalog.noss_phase2.intentSequence[0].animation == "shoot", "phase-two heavy uses halo explosion and retains follow-up double swords")
	var heavy_tip := preload("res://scripts/combat/intent_tooltip.gd").describe({"intent":Game.enemy_catalog.noss_phase2.intentSequence[2]}, "攻击 30")
	check(heavy_tip.title == "太阳之下" and heavy_tip.summary.contains("30"), "heavy intent tooltip explains halo detonation and correct damage")
	check(not Game.battle_exit("win", Game.revision), "cannot forge victory during first phase")

func test_phase_rules_and_validation() -> void:
	for difficulty in ["normal", "advanced"]:
		var model := start_boss(difficulty)
		var bonus := 5 if difficulty == "advanced" else 0
		check(model.enemies.size() == 3 and model.enemies[0].maxHp == 40 + bonus and model.enemies[2].maxHp == 100 + bonus, difficulty + " first-phase group HP")
		check(Game.valid_combat(model.snapshot()), "first phase snapshot accepted")
		model.enemy_damage(2, 999)
		model.resolve_outcome()
		check(model.outcome == "win" and model.enemies[0].hp > 0 and model.enemies[1].hp > 0, "Noss death ends first phase while both hands may still live")
		check(model.advance_encounter_phase(), "defeating Noss alone unlocks phase two and retires remaining hands")
		check(model.enemies.size() == 1 and model.enemies[0].id == "noss_phase2" and model.enemies[0].hp == (170 if difficulty == "advanced" else 160), difficulty + " phase-two single-enemy bonus applied once")
		check(model.turn == 2 and model.outcome.is_empty() and model.energy == 3 and model.hand.size() == 5, "transition opens one fresh player turn")
		check(Game.valid_combat(model.snapshot()), "second phase frozen definition accepted")
		check(not model.advance_encounter_phase(), "second phase cannot transition twice")
		var restored := CombatModel.new()
		restored.restore(model.snapshot())
		check(same(restored.snapshot(), model.snapshot()), "phase-two restore neither rebuffs HP nor redraws")
		for key in ["encounterPhase", "enemies", "phaseTwoEnemies", "intent"]:
			var bad := model.snapshot()
			match key:
				"encounterPhase": bad.encounterPhase = 1
				"enemies": bad.enemies.append(bad.enemies[0].duplicate(true))
				"phaseTwoEnemies": bad.profile.phaseTwoEnemies[0].maxHp = -1
				"intent": bad.enemies[0].intent.amount = 999
			check(not Game.valid_combat(bad), "malformed Noss snapshot rejected: " + key)
	var model := start_boss()
	model.draw_cards()
	var uid := "qa_noss_aoe"
	model.instances[uid] = uid
	model.card_catalog[uid] = {"id":uid,"name":"QA multi-hit","type":"attack","target":"all","cost":0,"effects":[{"type":"damage","amount":999,"hits":4}]}
	model.hand.append(uid)
	model.block = 20
	model.energy = 1
	var result := model.play_card(uid, 0)
	check(result.get("phaseChanged", false) and model.enemies[0].hp == 160, "killing multi-hit AoE does not spill into new phase")
	check(model.turn == 2 and model.energy == 3 and model.block == 0, "old player turn closes exactly once")
	# End-turn damage sources must use the same transition without duplicating cleanup.
	model = start_boss()
	for enemy in model.enemies:
		enemy.hp = 1
		enemy.intent = {"type":"attack", "amount":2, "hits":1}
	model.parry = 3
	result = model.end_turn()
	check(result.get("phaseChanged", false) and model.encounter_phase == 2 and model.turn == 2, "enemy-turn parry advances once")
	check(model.enemies[0].hp == 160 and result.attacks.all(func(a): return a.id != "noss_phase2"), "new phase does not act in the old enemy turn")

func test_save_restart_and_completion() -> void:
	var model := start_boss("advanced")
	var opening: Dictionary = Game.state.battleStart.duplicate(true)
	phase_two(model)
	check(Game.commit_combat(model) and Game.valid_battle_start(Game.state), "phase-two live model agrees with frozen opening")
	check(Game.save_game() and Game.load_game(), "in-progress phase two can save/reload")
	check(same(Game.state.combat, opening) and Game.state.combat.encounterPhase == 1, "reload follows existing full-battle restart policy")
	model = start_boss()
	phase_two(model)
	model.enemy_damage(0, 999)
	model.resolve_outcome()
	check(Game.commit_combat(model) and Game.battle_exit("win", Game.revision), "actual phase-two victory enters authored outcome")
	check(Game.page == "dialogue" and Game.state.activeNodeId == "win_01" and not Game.is_week_complete(), "week does not finish before victory dialogue/rewards")
	var count := 0
	while Game.page == "dialogue" and count < 20:
		Game.advance(Game.revision)
		count += 1
	check(count == 7 and Game.has_battle_reward() and Game.state.battleReward.battleType == "boss", "seven victory lines lead to Boss reward")
	check(not Game.is_week_complete(), "pending reward does not finish week")
	check(Game.claim_reward_credits(Game.revision), "Boss credits claimed")
	var selected: String = Game.state.battleReward.options[0]
	check(Game.card_catalog[selected].rarity == "S" and Game.choose_reward_card(selected, Game.revision), "Boss gives one real S-grade choice")
	check(Game.claim_rewards(Game.revision) and Game.is_week_complete() and Game.state.flags.week2Complete, "reward exit ends second week")
	check(Game.is_run_over() and not Game.start_second_week(Game.revision), "no unimplemented third-week entry")
	check(Game.valid_save(Game.state) and Game.save_game() and Game.load_game() and Game.is_week_complete(), "finished second-week summary reloads")
	Game.menu()
	Game.resume()
	check(Game.page == "result" and Game.is_week_complete(), "continue restores second-week summary")
	check(not Game.claim_rewards(Game.revision), "duplicate reward exit rejected")
	var menu_view = load("res://scenes/menu.tscn").instantiate()
	check(menu_view._summary_text() == "第二周已完成 · 继续可查看结算", "menu does not advertise re-entering second week after Noss")
	menu_view.free()
	model = start_boss()
	model.player_hp = 0
	model.resolve_outcome()
	check(not model.advance_encounter_phase(), "dead player never enters a new phase")
	Game.commit_combat(model)
	check(Game.battle_exit("lose", Game.revision) and Game.page == "defeat", "formal Noss loss uses final defeat route")

func test_training() -> void:
	fresh(2, 3, "advanced")
	var before := Game.state.duplicate(true)
	Game.page = "menu"
	Game.start_enemy_training("noss_sovereign")
	check(Game.training_mode and Game.state.combat.profile.difficulty == "normal", "training uses full Noss formation in normal difficulty")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	phase_two(model)
	check(Game.valid_combat(model.snapshot()), "training second-phase snapshot validates")
	Game.commit_combat(model)
	Game.menu()
	check(same(Game.state, before), "training restores adventure, difficulty, inventory and progress exactly")

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func record_heavy_sequence(stage: Node) -> void:
	# Optional real rendered frames, kept at their measured times for preview.
	if DisplayServer.get_name() == "headless": return
	var folder := output.path_join("heavy_sequence")
	DirAccess.make_dir_recursive_absolute(folder)
	var started := Time.get_ticks_usec()
	var frames: Array = []
	var images: Array[Image] = []
	while Time.get_ticks_usec()-started < 1650000:
		await RenderingServer.frame_post_draw
		var filename := "%03d.png" % frames.size()
		var blasts := get_tree().get_nodes_in_group("noss_halo_burst")
		frames.append({"file":filename,"seconds":(Time.get_ticks_usec()-started)/1000000.0,
			"phase":stage.phase if is_instance_valid(stage) else "finished",
			"burstAge":float(blasts[0].elapsed) if not blasts.is_empty() else -1.0})
		images.append(get_viewport().get_texture().get_image())
		await get_tree().create_timer(0.025).timeout
	# Encode after capture: PNG compression must not interrupt the animation.
	for i in images.size(): images[i].save_png(folder.path_join(frames[i].file))
	FileAccess.open(folder.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(frames,"\t"))
	for key in ["heavy_charge","heavy_burst","heavy_shockwave"]:
		var best := -1
		var error := INF
		for i in frames.size():
			if key == "heavy_charge" and frames[i].phase != "halo_charge": continue
			if key != "heavy_charge" and frames[i].burstAge < 0.0: continue
			var distance: float = absf(frames[i].seconds-0.35) if key == "heavy_charge" else absf(frames[i].burstAge-(0.045 if key == "heavy_burst" else 0.20))
			if distance < error:
				error = distance
				best = i
		if best >= 0: images[best].save_png(output.path_join(key+".png"))

func check_first_phase_bars(view) -> void:
	var bars: Array = view.enemy_summary_plates
	check(bars.size() == 3 and bars[2].hp == view.shown_enemies[2].hp, "Noss main bar retains original target index")
	var main: Rect2 = Rect2(bars[2].global_position+bars[2].track.position,bars[2].track.size)
	var left: Rect2 = Rect2(bars[0].global_position+bars[0].track.position,bars[0].track.size)
	var right: Rect2 = Rect2(bars[1].global_position+bars[1].track.position,bars[1].track.size)
	check(main.size.x > left.size.x*2 and left.size == right.size, "one long main track and two equally small hand tracks")
	check(main.end.y < left.position.y and left.position.y == right.position.y and left.end.x < right.position.x, "hands sit side by side below the main Boss")
	check(is_equal_approx(main.position.x,left.position.x) and is_equal_approx(main.end.x,right.end.x), "hand pair aligns with both ends of main track")
	check(is_equal_approx(main.get_center().x,720) and main.position.y == 140, "main track remains centered in upper battlefield")
	for i in bars.size():
		check(bars[i].get_global_rect().end.y <= 216 and bars[i].mouse_filter == Control.MOUSE_FILTER_IGNORE, "compact top summary fits without intercepting targeting " + str(i))
		check(bars[i].hp_label.text == "%d / %d" % [view.shown_enemies[i].hp,view.shown_enemies[i].maxHp], "each readout follows its own shown HP " + str(i))

func test_first_phase_bar_updates(view) -> void:
	var original: Array = view.shown_enemies.duplicate(true)
	var model_before: Dictionary = view.model.snapshot()
	var anchors: Array = view.enemy_summary_plates.map(func(p): return p.global_position)
	view.shown_enemies[0].hp = 17
	view.shown_enemies[0].block = 999
	view.shown_enemies[1].hp = 0
	view.refresh_enemy_hud()
	check_first_phase_bars(view)
	check(view.enemy_summary_plates.map(func(p): return p.global_position) == anchors, "damaged/dead hands keep stable left/right anchors")
	check(view.enemy_summary_plates[0].status_label.text == "格挡 999" and view.enemy_summary_plates[1].status_label.text == "已击败", "small bars preserve three-digit guard and defeated state")
	check(not view.targets[0].disabled and view.targets[1].disabled and not view.targets[2].disabled, "hand HP hierarchy preserves target mapping")
	await shot("phase1_bar_damage")
	view.shown_enemies[2].hp = 0
	view.refresh_enemy_hud()
	check(view.enemy_summary_plates[2].hp == 0 and view.enemy_summary_plates[0].hp == 17 and not view.targets[0].disabled, "defeated main Boss keeps hands and empty main bar in place")
	check(same(view.model.snapshot(),model_before), "bar refresh never mutates combat model")
	view.shown_enemies = original
	view.refresh_enemy_hud()

func test_views() -> void:
	start_boss()
	var view = load("res://scenes/battle.tscn").instantiate()
	add_child(view)
	await get_tree().create_timer(3.5).timeout
	check(view.stage.enemies.size() == 3 and not Game.battle_busy, "actual battle view displays usable first-phase formation")
	check_first_phase_bars(view)
	await shot("phase1")
	if DisplayServer.get_name() != "headless":
		var original_size := DisplayServer.window_get_size()
		DisplayServer.window_set_size(Vector2i(1600,1000))
		await get_tree().create_timer(0.2).timeout
		check_first_phase_bars(view)
		await shot("phase1_1600")
		DisplayServer.window_set_size(original_size)
		await get_tree().create_timer(0.2).timeout
	await test_first_phase_bar_updates(view)
	var hp_before: int = view.model.player_hp
	await view.end_turn_pressed()
	check(view.model.player_hp == hp_before - 18 and view.shown_player_hp == view.model.player_hp, "real phase-one hand and sword playback reveals model damage exactly once")
	var transitioned := CombatModel.new()
	transitioned.restore(Game.state.combat)
	transitioned.kill_enemies()
	Game.commit_combat(transitioned)
	# Exercise the existing full console-reconciliation path: it retires the
	# old hand, presents the phase and actually animates the fresh draw.
	view.call_deferred("resume_console_combat")
	var interlude: Node
	for frame in 150:
		interlude = view.get_node_or_null("NossPhaseDialogue")
		if interlude != null: break
		await get_tree().create_timer(0.02).timeout
	check(interlude != null and Game.battle_busy, "real phase transition opens modal dialogue under input lock")
	if interlude != null:
		for i in 3: interlude.advance_line()
		await shot("transition_dialogue")
		for i in 3: interlude.advance_line()
	for frame in 250:
		if not Game.battle_busy: break
		await get_tree().create_timer(0.02).timeout
	check(not Game.battle_busy and view.shown_draw_count >= 0 and view.shown_discard_count >= 0, "real phase reconciliation completes fresh hand deal with non-negative counts")
	check(view.stage.enemies.size() == 1 and view.enemy_portraits.size() == 1 and view.shown_encounter_phase == 2, "actual transition rebuilds single long-leg actor and target HUD")
	check(view.enemy_summary_plates.size() == 1 and view.enemy_summary_plates[0].track == view.EnemyHPSummary.BOSS_TRACK, "phase two removes both small hand bars and retains one large Boss bar")
	check(Game.state.dialogueHistory.filter(func(e): return e.has("phaseKey")).size() == 6, "transition records every authored line")
	for i in 6: Game.record_encounter_line(i, Game.events.E23.phaseTwoDialogue[i])
	check(Game.state.dialogueHistory.filter(func(e): return e.has("phaseKey")).size() == 6, "transition history deduplicates on replay")
	check(view.enemy_intents[0].get_global_rect().end.y <= view.stage.enemies[0].sprite.to_global(Vector2.ZERO).y + 20, "intent icon stays above phase-two halo instead of masking its face")
	await shot("phase2")
	# Restore fixture health so all three authored attacks can be observed.
	view.model.player_hp = view.model.max_hp
	view.shown_player_hp = view.model.player_hp
	view.refresh_hp()
	await view.end_turn_pressed() # Six-arm attack, then 聚日.
	await view.end_turn_pressed()
	check(view.model.buffs.count(view.model,"alien_sin",0) == 3 and view.enemy_intents[0].value_label.text == "30", "聚日 reveals three 异罪 and previews thirty damage")
	hp_before = view.model.player_hp
	var heavy_phases: Array[String] = []
	view.stage.phase_changed.connect(func(phase: String):
		if phase == "halo_charge":
			heavy_phases.append(phase)
			if OS.get_environment("QA_SEQUENCE") == "1": call_deferred("record_heavy_sequence",view.stage)
			check(view.shown_player_hp == hp_before, "real heavy charge reveals no premature damage")
			if OS.get_environment("QA_SEQUENCE") != "1":
				await get_tree().create_timer(0.35).timeout
				await shot("heavy_charge")
		if phase == "halo_burst":
			heavy_phases.append(phase)
			if OS.get_environment("QA_SEQUENCE") != "1":
				await get_tree().create_timer(0.045).timeout
				await shot("heavy_burst")
				await get_tree().create_timer(0.13).timeout
				await shot("heavy_shockwave"))
	await view.end_turn_pressed()
	check(view.model.player_hp == hp_before - 30 and view.shown_player_hp == view.model.player_hp, "phase-two halo explosion reveals committed thirty damage once")
	check(heavy_phases == ["halo_charge","halo_burst"], "real phase-two intent dispatches charge then explosion")
	await get_tree().create_timer(0.3).timeout
	view.free()
	Game.battle_busy = false
	# Actual dialogue pages, reward button and final-week summary.
	fresh()
	Game.start_event("E23")
	var dialogue = load("res://scenes/dialogue.tscn").instantiate()
	add_child(dialogue)
	await get_tree().create_timer(0.4).timeout
	await shot("intro")
	dialogue.free()
	var model := start_boss()
	phase_two(model)
	model.enemy_damage(0, 999)
	model.resolve_outcome()
	Game.commit_combat(model)
	Game.battle_exit("win", Game.revision)
	Game.skip_dialogue(Game.revision)
	var rewards = load("res://scenes/result.tscn").instantiate()
	add_child(rewards)
	await get_tree().create_timer(0.4).timeout
	check(rewards.reward_view.exit_button.text.contains("第二周"), "reward exit visibly names second week")
	await shot("rewards")
	rewards.free()
	Game.claim_rewards(Game.revision)
	var summary = load("res://scenes/result.tscn").instantiate()
	add_child(summary)
	await get_tree().create_timer(0.4).timeout
	check(summary.week_end_view.next_week_button == null and summary.week_end_view.return_button != null, "second-week summary has menu exit without unimplemented next week")
	await shot("week2_complete")
	summary.free()

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in output.to_lower() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("NOSS BOSS: isolated QA project and absolute QA_OUT_DIR required")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	test_gates_and_dialogue()
	test_phase_rules_and_validation()
	test_save_restart_and_completion()
	test_training()
	if OS.get_environment("QA_CAPTURE") == "1": await test_views()
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures}, "\t"))
	file.close()
	print("NOSS BOSS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
