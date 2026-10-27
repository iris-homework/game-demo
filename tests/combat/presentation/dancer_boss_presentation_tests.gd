extends "res://tests/combat/cards/noren_cards_visual.gd"
## Headless scene/animation contracts. No pointer warp or screen capture.
var saw_blackout := false
var transition_locked := true
var phase_snapshots_stable := true
var phase_snapshot: Dictionary = {}
var hard_light_cues := true

func check_boss_bars(view: Control, title: String) -> void:
	check(view.enemy_summary_plates.size() == view.shown_enemies.size(),title+" has one fixed bar per Boss")
	for i in view.enemy_summary_plates.size():
		var plate: Control = view.enemy_summary_plates[i]
		var track_center_x: float = plate.global_position.x+plate.track.get_center().x
		check(is_equal_approx(track_center_x,720) and plate.size == Vector2(600,68),title+" visible Boss health track centered at screen top")
		var name_label: Label = plate.get_child(0)
		check(is_equal_approx(name_label.get_global_rect().get_center().x,track_center_x) and name_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,title+" Boss name aligns with health track center")
		check(is_equal_approx(plate.global_position.y,96+i*80),title+" Boss bars stack vertically with 12px gaps")
		check(plate.hp == view.shown_enemies[i].hp and plate.block == int(view.shown_enemies[i].get("block",0)),title+" fixed bar uses displayed hit snapshot")
		check(plate.hp_label.position.x > plate.track.end.x and plate.mouse_filter == Control.MOUSE_FILTER_IGNORE,title+" wide bar keeps HP readable and targeting unobstructed")
		check(not plate.get_global_rect().intersects(view.turn_label.get_global_rect()),title+" Boss bar leaves turn indicator clear")
		for child in view.get_children():
			if child is Button and child.text == "调试结果":
				check(not plate.get_global_rect().intersects(child.get_global_rect()),title+" debug button leaves Boss bars clear")

func wait_with_observation(view: Control) -> void:
	var start := Time.get_ticks_msec()
	var blackout_started := -1
	var blackout_ended := -1
	var pulse_started := -1
	var pulse_ended := -1
	var previous_progress := -1.0
	var pulse_locked := true
	var pulse_monotonic := true
	var flash_seen := false
	var peak_synchronized := false
	var blackout_stays_black := true
	var banners: Dictionary = {}
	var hand_waits_for_reveal := true
	while Game.battle_busy or Game.transition_locked:
		if is_instance_valid(view.turn_banner):
			banners[view.turn_banner.get_instance_id()] = view.turn_banner.title
		if is_instance_valid(view.dancer_blackout):
			if blackout_started < 0: blackout_started = Time.get_ticks_msec()
			blackout_ended = Time.get_ticks_msec()
			saw_blackout = true
			hard_light_cues = hard_light_cues and is_equal_approx(view.dancer_blackout.modulate.a, 1.0)
		if is_instance_valid(view.stage.dancer_lights):
			hard_light_cues = hard_light_cues and is_equal_approx(view.stage.dancer_lights.modulate.a, 1.0)
		if is_instance_valid(view.dancer_blackout):
			transition_locked = transition_locked and Game.battle_busy and view.end_button.disabled
			blackout_stays_black = blackout_stays_black and not is_instance_valid(view.dancer_reveal_flash)
			hand_waits_for_reveal = hand_waits_for_reveal and view.cards.is_empty()
			if phase_snapshot.is_empty(): phase_snapshot = view.model.snapshot()
			phase_snapshots_stable = phase_snapshots_stable and phase_snapshot == view.model.snapshot()
		elif is_instance_valid(view.stage.dancer_lights) and view.stage.dancer_lights.reveal_progress < 1.0:
			var progress: float = view.stage.dancer_lights.reveal_progress
			if pulse_started < 0:
				pulse_started = Time.get_ticks_msec()
				peak_synchronized = progress < 0.12 and is_instance_valid(view.dancer_reveal_flash) and view.dancer_reveal_flash.color.a >= 0.25
			pulse_ended = Time.get_ticks_msec()
			pulse_monotonic = pulse_monotonic and progress >= previous_progress
			previous_progress = progress
			pulse_locked = pulse_locked and Game.battle_busy and view.end_button.disabled and view.shown_encounter_phase == 2
			hand_waits_for_reveal = hand_waits_for_reveal and view.cards.is_empty()
			phase_snapshots_stable = phase_snapshots_stable and phase_snapshot == view.model.snapshot()
			if is_instance_valid(view.dancer_reveal_flash):
				flash_seen = true
				pulse_locked = pulse_locked and view.dancer_reveal_flash.mouse_filter == Control.MOUSE_FILTER_IGNORE
		await get_tree().process_frame
		if Time.get_ticks_msec()-start > 20000:
			check(false,"dancer presentation timeout")
			get_tree().quit(2)
			return
	await get_tree().process_frame
	var blackout_seconds := float(blackout_ended - blackout_started) / 1000.0
	check(blackout_started >= 0 and blackout_seconds >= 0.9 and blackout_seconds < 1.35, "blackout lasts one second during actual phase transition")
	check(blackout_stays_black,"opening flash never leaks into blackout")
	var pulse_seconds := float(pulse_ended - pulse_started) / 1000.0
	check(peak_synchronized and flash_seen,"warm exposure flash and peak spotlights start together on first revealed frame")
	check(pulse_monotonic and pulse_started >= 0 and pulse_seconds >= 0.5 and pulse_seconds < 0.85,"opening light pulse settles once in about 0.65 seconds")
	check(pulse_locked,"gameplay remains locked throughout opening light pulse")
	check(is_equal_approx(view.stage.dancer_lights.reveal_progress,1.0) and not is_instance_valid(view.dancer_reveal_flash),"opening accents clean up and steady lighting remains")
	check(banners.values().count("第%d回合" % view.model.turn) == 1,"phase transition presents exactly one new player round banner")
	check(hand_waits_for_reveal,"old hand retires and new hand waits until the formation is revealed")
	print("Observed dancer blackout: %.3f seconds" % blackout_seconds)
	print("Observed dancer opening pulse: %.3f seconds" % pulse_seconds)

func check_pose_scale(view: Control) -> void:
	var landmarks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dancer_pose_landmarks.json")).headWidthPx
	for actor in view.stage.enemies:
		var widths: Dictionary = landmarks[actor.kind]
		actor.set_pose("idle")
		var reference: float = widths.idle * actor.sprite.transform.x.length()
		for pose in widths:
			actor.set_pose(pose)
			var displayed: float = widths[pose] * actor.sprite.transform.x.length()
			check(absf(displayed/reference - 1.0) < 0.06, actor.kind + "/" + pose + " retains idle body scale despite crouch")
		actor.set_pose("idle")

func observe_enemy_round(view: Control) -> Dictionary:
	var observed := {"hpSteps":[],"sawSoulBlock":false,"sawSoulStrength":false,"blockPreserved":true,"sawHeal":false,"sawVulnerable":false}
	var hp: int = view.shown_player_hp
	var started := Time.get_ticks_msec()
	while Game.battle_busy or Game.transition_locked:
		if view.shown_player_hp != hp:
			hp = view.shown_player_hp
			observed.hpSteps.append(hp)
		if int(view.shown_player_buffs.get("vulnerable",0)) == 3: observed.sawVulnerable = true
		for popup in get_tree().get_nodes_in_group("combat_damage_numbers"):
			if popup.get_parent() != view: continue
			if popup.value == "格挡+10": observed.sawSoulBlock = true
			if popup.value == "力量+2" and observed.sawSoulBlock:
				observed.sawSoulStrength = true
				observed.blockPreserved = observed.blockPreserved and view.shown_enemies[1].block == 10
			if popup.value == "恢复+10" and not observed.sawHeal:
				observed.sawHeal = true
				check(view.shown_enemies[0].hp == 80,"healing popup accompanies the authoritative 70-to-80 HP display change")
		await get_tree().process_frame
		if Time.get_ticks_msec()-started > 20000:
			check(false,"three-step Boss intent playback timed out")
			get_tree().quit(2)
			return observed
	await get_tree().process_frame
	return observed

func simulate_training_victory(view: Control) -> void:
	var notices: Array[String] = []
	var capture := func(message: String): notices.append(message)
	Game.notice.connect(capture)
	view.show_debug_results()
	var popups := view.get_children().filter(func(node): return node is ConfirmationDialog)
	check(popups.size() == 1,"Boss training opens the existing debug results dialog")
	if not popups.is_empty():
		var popup: ConfirmationDialog = popups[0]
		check(popup.ok_button_text == "模拟胜利","debug dialog exposes the simulated victory action")
		popup.hide()
		popup.confirmed.emit()
	await idle()
	Game.notice.disconnect(capture)
	check(not Game.training_mode and Game.page == "menu","debug simulated victory exits Boss training to menu")
	check(notices.any(func(message): return "演练结束：胜利" in message) and not notices.any(func(message): return "未能保存" in message),"debug victory reports training success without a false save failure")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://dancer_presentation_unused.json"
	Game.meta_path = "user://dancer_presentation_meta_unused.json"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	check(is_instance_valid(app.view.find_child("enemy_choice_dancer_duet",true,false)),"menu exposes Boss training")
	var backup := Game.state.duplicate(true)
	Game.start_training("B16")
	await idle()
	var view: Control = app.view
	check(view.stage.enemies.size() == 1 and view.model.enemies[0].hp == 80,"phase one: only black dancer, 80 HP")
	check(view.stage.enemies[0].kind == "dancer_black" and not view.stage.enemies[0].poses.is_empty(),"black art loaded")
	check(not view.stage.dancer_duet and not is_instance_valid(view.dancer_darkness),"phase one retains ordinary lighting")
	check_boss_bars(view,"Phase one")
	var bar_position: Vector2 = view.enemy_summary_plates[0].global_position
	view.stage.frame_attack(view.stage.player,view.stage.enemies[0],view.stage.enemies[0].position-Vector2(100,0))
	await view.stage.camera_tween.finished
	view.update_target_rects()
	check(view.enemy_summary_plates[0].global_position.is_equal_approx(bar_position),"Boss bar stays fixed while camera approaches target")
	await view.stage.camera_to(720,1.0,0.01).finished
	var phase_one_black_home: Vector2 = view.stage.enemies[0].home
	# Force a known lethal card without depending on the shuffled opening hand.
	var uid := str(view.model.hand[0])
	view.model.instances[uid] = "noren_01"
	view.model.enemies[0].hp = 1
	view.shown_enemies[0].hp = 1
	view.model.energy = 1
	view.model.block = 2
	view.model.buffs.apply(view.model,"pollution",3)
	view.shown_player_pollution = 3
	view.refresh_resources()
	var old_hand: Array = view.model.hand.duplicate()
	var old_turn: int = view.model.turn
	view.refresh_enemy_hud()
	view.select_card(uid)
	view.play_selected(0)
	await wait_with_observation(view)
	check(saw_blackout and transition_locked,"transition fully blacks out and locks gameplay")
	check(phase_snapshots_stable,"blackout and spotlights do not mutate committed combat")
	check(view.model.encounter_phase == 2 and view.shown_encounter_phase == 2,"model and presentation reach phase two")
	check(view.model.turn == old_turn+1 and view.model.energy == 3,"card-triggered second phase starts the next full-energy player round")
	check(view.model.hand.size() == 5 and view.cards.size() == 5 and view.cards.keys().all(func(card_uid): return card_uid in view.model.hand),"new player round deals exactly the fresh model hand")
	check(old_hand.all(func(card_uid): return not card_uid in view.model.hand),"old hand does not continue into the second phase when draw pile has fresh cards")
	check(view.model.player_hp == view.model.max_hp-1 and view.shown_player_hp == view.model.player_hp and view.shown_player_pollution == 2,"forced player-turn-end pollution displays once before the reveal")
	check(view.model.block == 0 and view.shown_player_block == 0 and str(view.model.turn) in view.turn_label.text,"new round HUD clears old block and shows the advanced turn")
	var phase_two_hp: int = view.model.player_hp
	var phase_two_pollution: int = view.model.buffs.count(view.model,"pollution")
	check(view.stage.enemies.size() == 2 and view.targets.size() == 2,"both phase-two enemies receive target and HUD")
	check_boss_bars(view,"Phase two")
	check(view.model.enemies.all(func(e): return e.hp == 80),"finishing phase-one card never damages the fresh 80-HP phase-two dancers")
	check(view.shown_enemies[1].block == 0 and view.model.buffs.count(view.model,"strength",0) == 0,"second phase reveal precedes the first enemy-turn soul-link trigger")
	check(view.model.enemies.all(func(e): return view.model.buffs.enemy_count(e,view.model.buffs.definition("soul_link")) == 1),"both dancers reveal one soul-link layer")
	check(view.stage.player.home.x == 720 and view.stage.enemies[0].home.x > 720 and view.stage.enemies[1].home.x < 720,"player centered between dancers")
	check(view.stage.enemies[0].facing == -1 and view.stage.enemies[1].facing == 1,"dancers face inward")
	var phase_two_black_home: Vector2 = view.stage.enemies[0].home
	check(is_equal_approx(phase_two_black_home.y,view.stage.player.home.y),"black dancer and player share horizontal foot line")
	var mirrored_home := Vector2(1440.0 - phase_two_black_home.x, phase_two_black_home.y)
	check(view.stage.enemies[1].home.is_equal_approx(mirrored_home),"white dancer mirrors black on the player's horizontal foot line")
	var dancer_distance: float = phase_two_black_home.x - view.stage.player.home.x
	check(dancer_distance >= 400.0 and dancer_distance > phase_one_black_home.x - view.stage.player.home.x,"both dancers stand farther from the centered player")
	check(view.stage.dancer_lights.actors[0] == view.stage.enemies[1] and view.stage.dancer_lights.actors[2] == view.stage.enemies[0],"spotlight anchors follow left white and right black")
	check(view.stage.dancer_lights.actors.size() == 3 and view.dancer_darkness.color.a >= 0.85,"three spotlight anchors and dark environment")
	check(not is_instance_valid(view.dancer_blackout),"blackout released after reveal")
	check(hard_light_cues,"blackout and spotlights switch without intermediate opacity")
	check(view.battle.placeId == "hive" and view.stage.scenery.texture == Game.texture("hive_battle_simplified"),"Boss training uses hive battle background")
	check_pose_scale(view)
	check(view.stage.enemies[1].kind == "dancer_white" and view.stage.enemies[1].poses.has("slash"),"white sword art loaded")
	for i in 2:
		check(view.target_at_point(view.stage.target_rect(i).get_center()) == i,"each flanking dancer is independently targetable")
	view.end_turn_pressed()
	var first_round: Dictionary = await observe_enemy_round(view)
	check(view.stage.player.position.is_equal_approx(view.stage.player.home),"round end returns player to center")
	check(view.stage.enemies[0].facing == -1 and view.stage.enemies[1].facing == 1,"round return preserves inward facing")
	check(view.stage.enemies[0].position.is_equal_approx(phase_two_black_home) and view.stage.enemies[1].position.is_equal_approx(mirrored_home),"enemy attacks return dancers to wider horizontally aligned homes")
	check(view.model.player_hp == phase_two_hp-phase_two_pollution-12,"black dancer attacks once with soul-link strength after the player's normal pollution tick")
	check(view.shown_player_weak == 2 and view.model.buffs.count(view.model,"weak") == 2,"white dancer's first weakness intent appears in the displayed player statuses")
	check(first_round.sawSoulBlock and first_round.sawSoulStrength and first_round.blockPreserved,"first round preserves white's ten block while the white connection gives black strength")
	# Isolated in-memory durability fixture keeps later animation checks independent
	# of the player character's authored HP; no encounter stats or save are changed.
	view.model.max_hp = 1000
	view.model.player_hp = 1000
	Game.state.maxHp = 1000
	view.shown_player_hp = 1000
	view.refresh_hp()
	check(view.model.enemies[0].intent.type == "attack" and view.model.enemies[0].intent.amount == 8 and view.model.enemies[1].intent.hits == 3,"second step displays black attack eight and white's three-hit attack")
	view.end_turn_pressed()
	var second_round: Dictionary = await observe_enemy_round(view)
	check(second_round.hpSteps == [999,987,984,981,978],"black attack and white's three impacts display separately after the one-point pollution tick")
	check(not second_round.sawVulnerable and view.shown_player_buffs.get("vulnerable",0) == 0 and view.model.buffs.count(view.model,"vulnerable") == 0,"second step has no vulnerability before either dancer attacks")
	check(view.shown_player_hp == view.model.player_hp and view.shown_player_weak == 1 and view.model.buffs.count(view.model,"weak") == 1,"second-step player HP and weakness match the committed model")
	check(second_round.sawSoulBlock and second_round.sawSoulStrength and second_round.blockPreserved,"second round keeps white's block through both connection events")
	view.model.enemies[0].hp = 70
	view.shown_enemies[0].hp = 70
	view.refresh_enemy_hud()
	check(view.model.enemies[0].intent.type == "strength_allies" and view.model.enemies[1].intent.type == "heal_ally","third step displays black reinforcement and white healing")
	view.end_turn_pressed()
	var third_round: Dictionary = await observe_enemy_round(view)
	check(third_round.sawHeal and view.model.enemies[0].hp == 80 and view.shown_enemies[0].hp == 80,"white healing traverses the real event and popup path exactly once")
	check(third_round.hpSteps.is_empty() and view.model.player_hp == 978 and view.shown_player_hp == view.model.player_hp,"third-step reinforcement and healing cause no player HP loss")
	check(view.shown_player_weak == 0 and view.model.buffs.count(view.model,"weak") == 0 and view.shown_player_buffs.get("vulnerable",0) == 0 and not third_round.sawVulnerable and view.shown_enemies[1].buffs.strength == 2 and view.model.buffs.count(view.model,"strength",1) == 2,"third step expires weakness and reinforces white by two without applying vulnerability")
	check(third_round.sawSoulBlock and third_round.sawSoulStrength and third_round.blockPreserved and view.shown_enemies[1].block == 10,"third round retains white's ten block throughout connection strength playback")
	check(view.model.enemies[0].intentIndex == 3 and view.model.enemies[1].intentIndex == 3 and view.model.enemies[1].intent.type == "weak","both three-step intent sequences wrap to the first action")
	# Rebuild view from the committed phase-two snapshot, without replaying blackout.
	app.swap_view()
	await idle()
	view = app.view
	check(view.stage.dancer_duet and view.stage.enemies.size() == 2 and view.stage.player.home.x == 720,"phase-two snapshot restores centered stage")
	check(view.stage.enemies[0].home.is_equal_approx(phase_two_black_home) and view.stage.enemies[1].home.is_equal_approx(mirrored_home),"phase-two snapshot restores wider horizontally aligned dancer positions")
	check(not is_instance_valid(view.dancer_blackout),"restored second phase does not replay transition")
	check_boss_bars(view,"Restored phase two")
	check(is_equal_approx(view.stage.dancer_lights.reveal_progress,1.0) and not is_instance_valid(view.dancer_reveal_flash),"restored second phase does not replay opening flash or light pulse")
	await simulate_training_victory(view)
	check(Game.state == backup,"Boss training restores original adventure")
	Game.start_training("B16")
	await idle()
	view = app.view
	view.model.enemies[0].hp = 1
	view.shown_enemies[0].hp = 1
	view.model.parry = 1
	view.shown_player_parry = 1
	saw_blackout = false
	phase_snapshot.clear()
	view.end_turn_pressed()
	await wait_with_observation(view)
	check(saw_blackout and view.stage.dancer_duet and view.targets.size() == 2,"lethal enemy-turn counter also presents second phase")
	check(view.model.player_hp == view.model.max_hp-15 and view.model.enemies.all(func(e): return e.hp == 80),"counter transition shows only the old-stage 15 attack and fresh 80-HP dancers")
	check(view.model.turn == 2 and view.model.energy == 3 and view.model.hand.size() == 5 and view.cards.size() == 5,"counter transition opens exactly one new player round and hand")
	check(view.dancer_darkness.z_index < view.player_plate.z_index,"stage darkness leaves player HP readable")
	check(phase_snapshots_stable,"counter transition preserves committed state")
	check(hard_light_cues,"counter transition also uses hard light cues")
	Game.finish_training("lose")
	await idle()
	check(Game.state == backup,"training loss also restores adventure")
	Game.start_training("B16")
	await idle()
	view = app.view
	check(view.model.encounter_phase == 1 and view.model.enemies[0].hp == 80,"debug phase-one case starts with an undefeated 80-HP dancer")
	await simulate_training_victory(view)
	check(Game.state == backup,"phase-one debug victory restores adventure without rewards or progress changes")
	Game.start_training("B11")
	await idle()
	view = app.view
	for i in view.enemy_summary_plates.size():
		var plate: Control = view.enemy_summary_plates[i]
		check(plate.size == Vector2(328,68) and plate.global_position.is_equal_approx(Vector2(1072,96+i*80)),"ordinary battle keeps original right-hand HP layout")
		check(plate.track == Rect2(18,44,170,12),"ordinary battle retains original HP track size")
	Game.finish_training("lose")
	await idle()
	app.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	print("DANCER PRESENTATION: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
