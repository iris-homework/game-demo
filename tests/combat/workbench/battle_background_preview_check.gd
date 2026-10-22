extends Node
## Program-driven rendering and input checks; no claim of physical mouse testing.
var bench: Control
var checks := 0
var failures: Array[String] = []
var output := ""
var started := 0

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _process(_delta: float) -> void:
	if started > 0 and Time.get_ticks_msec()-started > 110000:
		verify(false,"QA watchdog: timed out")
		finish()

func idle() -> void:
	var deadline := Time.get_ticks_msec()+20000
	while bench.tools_locked():
		if Time.get_ticks_msec() > deadline:
			verify(false,"Battle did not unlock")
			return
		await get_tree().process_frame
	await get_tree().process_frame

func invariant() -> bool:
	var model: CombatModel = bench.view.model
	var seen: Dictionary = {}
	for pile in [model.hand,model.draw_pile,model.discard_pile,model.exhaust_pile]:
		for uid in pile:
			if seen.has(uid) or not model.instances.has(uid) or not model.card_catalog.has(model.instances[uid]): return false
			seen[uid] = true
	return seen.size() == model.instances.size()

func shot(id: String) -> void:
	await RenderingServer.frame_post_draw
	verify(get_viewport().get_texture().get_image().save_png(output.path_join(id+".png")) == OK,"Screenshot "+id)

func send_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventKey.new()
	event.keycode = key
	Input.parse_input_event(event)
	await get_tree().process_frame

func _ready() -> void:
	started = Time.get_ticks_msec()
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "res://tests/combat/workbench/runtime/qa"
	DirAccess.make_dir_recursive_absolute(output)
	bench = preload("res://tests/combat/workbench/battle_background_preview.tscn").instantiate()
	bench.profile_path = output.path_join("profiles.json")
	add_child(bench)
	await idle()
	verify(not Game.save_enabled and Game.training_mode,"Independent unsaved training")
	verify(Game.save_path.contains("workbench_unused") and Game.meta_path.contains("workbench_meta_unused"),"Direct save calls target test files")
	verify(bench.left_tabs.get_tab_title(0) == "地图" and bench.left_tabs.get_tab_title(1) == "卡牌","Left map/card tabs")
	verify(bench.left_panel.position.x < 100 and bench.right_panel.position.x > 1000,"Exactly two side control panels")
	verify(bench.actor_tabs.tab_count == 2 and bench.roster == ["robot"],"Noren plus one enemy by default")
	verify(bench.view.model.hand.size() == 5 and invariant(),"Initial deterministic test hand")
	await shot("01-map-panels")
	bench.view.get_node("current_deck_button").pressed.emit()
	verify(bench.left_tabs.current_tab == 1,"Battle library button opens test card tab")
	bench.search.text = "直击"
	bench._filter_cards()
	verify(bench.card_list.item_count == 1,"Card name search")
	bench.card_list.select(0)
	bench._add_selected_card()
	verify(bench.view.model.hand.size() == 6 and invariant(),"Card added directly to real hand")
	var duplicates := ["noren_01","noren_01","noren_02","noren_03","noren_12"]
	verify(bench.view.replace_test_hand(duplicates),"Repeated cards accepted")
	verify(bench.view.model.instances[bench.view.model.hand[0]] == bench.view.model.instances[bench.view.model.hand[1]] and invariant(),"Repeated cards have distinct instances")
	verify(bench.view.remove_test_card(bench.view.model.hand[1]) and invariant(),"Hand remove keeps pile invariants")
	var unchanged: Dictionary = bench.view.model.snapshot()
	verify(not bench.view.replace_test_hand(["missing"]) and bench.view.model.snapshot() == unchanged,"Invalid card edit is atomic")
	verify(bench.view.replace_test_hand([]) and bench.view.cards.is_empty() and invariant(),"Clear hand clears visual cards")
	verify(bench.view.replace_test_hand(duplicates) and invariant(),"Restore test hand")
	verify(bench.view.refill_test_resources(),"Refill test resources")
	bench._sync_hand()
	await shot("02-card-panel")
	bench.search.grab_focus()
	await send_key(KEY_1)
	verify(bench.view.selected_uid.is_empty(),"Search input does not select combat card")
	bench.search.release_focus()
	bench.view.select_card(bench.view.model.hand[0])
	var hand_before: Array = bench.view.model.hand.duplicate()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = bench.left_panel.position+Vector2(35,160)
	bench.view._input(click)
	verify(bench.view.model.hand == hand_before and not Game.battle_busy,"Tool click does not play selected card")
	bench.view.cancel_selection()
	verify(bench.view.set_preview_stance("ranged") and bench.view.model.stance == "ranged","Noren ranged stance")
	verify(bench.view.set_preview_pose(0,"gun_block") and bench.view.stage.player.pose == "gun_block","Noren actual held pose")
	verify(not bench.view.set_preview_pose(0,"missing"),"Missing pose rejected")
	verify(bench.view.set_preview_stance("melee"),"Noren melee stance")
	bench.stance_picker.item_selected.emit(1)
	await get_tree().process_frame
	await get_tree().process_frame
	verify(bench.view.model.stance == "ranged","Stance selector signal changes real model")
	bench.stance_picker.item_selected.emit(0)
	await get_tree().process_frame
	await get_tree().process_frame
	for pose in bench.view.available_poses(0):
		verify(bench.view.set_preview_pose(0,pose),"Noren pose available: "+pose)
	bench.view.reset_preview_poses()
	var snapshot: Dictionary = bench.view.model.snapshot()
	verify(await bench.view.preview_action(0,"slash",1),"Noren slash demonstration")
	verify(bench.view.model.snapshot() == snapshot,"Action preview does not resolve model damage")
	verify(bench.view.stage.player.position.is_equal_approx(bench.view.stage.player.home),"Action preview returns home")
	verify(await bench.view.preview_action(1,"laser",0),"Robot laser demonstration")
	verify(bench.view.model.snapshot() == snapshot,"Enemy demonstration keeps model unchanged")
	for action in ["pierce","shoot","block","damaged"]:
		verify(await bench.view.preview_action(0,action,1),"Noren complete action "+action)
		verify(bench.view.model.snapshot() == snapshot,"Noren action keeps model unchanged "+action)
	bench.view.preview_action(0,"move",1)
	await get_tree().create_timer(0.06).timeout
	bench.view.pause_preview(true)
	# Pause is applied at a frame boundary; sample the frame that is displayed.
	await get_tree().process_frame
	var held_position: Vector2 = bench.view.stage.player.position
	await get_tree().create_timer(0.35,true,false,true).timeout
	verify(bench.view.preview_busy and bench.view.stage.player.position.is_equal_approx(held_position),"Pause freezes action while UI remains live")
	bench.view.pause_preview(false)
	await idle()
	verify(not bench.view.preview_busy,"Resume completes preview")
	var enemy_hp: int = bench.view.model.enemies[0].hp
	bench.view.select_card(bench.view.model.hand[0])
	await bench.view.play_selected(0)
	await idle()
	verify(bench.view.model.enemies[0].hp == enemy_hp-6 and invariant(),"Real card resolves once through production model")
	bench.left_tabs.current_tab = 0
	for i in bench.PLACE_IDS.size():
		var before: Dictionary = bench.view.model.snapshot()
		verify(await bench.switch_place(i),"Switch place "+bench.PLACE_IDS[i])
		await idle()
		verify(bench.view.model.snapshot() == before,"Scene change preserves model "+bench.PLACE_IDS[i])
		var bounds: Rect2 = bench.view.stage.scenery.get_global_rect()
		verify(bounds.position.x <= 0.1 and bounds.position.y <= 0.1 and bounds.end.x >= 1439.9 and bounds.end.y >= 899.9,"Scenery covers canvas "+bench.PLACE_IDS[i])
	bench.settings.brightness = 0.83
	bench.settings.scale = 1.2
	bench._apply_map()
	verify(bench.save_map(),"Map preset saves")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(bench.profile_path))
	verify(saved is Dictionary and is_equal_approx(float(saved[bench.selected_place].brightness),0.83),"Map preset on disk is correct")
	verify(bench.save_map(),"Existing map preset safely overwritten")
	await bench.preview_camera(true)
	verify(bench.view.stage.zoom > 1.0,"Close camera uses real stage framing")
	await bench.preview_camera(false)
	verify(is_equal_approx(float(bench.view.stage.zoom),1.0),"Wide camera restores framing")
	await bench.capture_current()
	verify(bench.left_panel.visible and bench.right_panel.visible and bench.status.text.contains("已保存"),"Screenshot capture restores panels and reports saved files")
	bench.selected_actor = 1
	await bench.change_roster("add")
	await idle()
	await bench.change_roster("add")
	await idle()
	verify(bench.roster.size() == 3 and bench.actor_tabs.tab_count == 4,"Three independently controlled enemies")
	for i in 3:
		bench.selected_actor = i+1
		var key: String = ["fish","gang","visual:warden_shield"][i]
		await bench.change_roster(key)
		await idle()
	verify(bench.view.stage.enemies[0].kind == "fish" and bench.view.stage.enemies[1].kind == "gang_boss" and bench.view.stage.enemies[2].kind == "warden_shield","Each enemy slot independently selects species")
	var all_poses_valid := true
	for action_key in bench.view.available_poses(3):
		if not bench.view.stage.enemies[2].poses.has(action_key): all_poses_valid = false
	verify(all_poses_valid,"Only actually loaded artwork appears in pose picker")
	var invented_action := false
	for i in bench.action_picker.item_count:
		var action_key: String = str(bench.action_picker.get_item_metadata(i))
		if not bench.view.available_poses(3).has(action_key) and not bench.view.stage.enemies[2].pipeline_attacks.has(action_key): invented_action = true
	verify(not invented_action,"Idle-only enemy has no invented action")
	bench.selected_actor = 1
	bench._sync_actor_controls()
	await shot("03-three-enemies")
	verify(await bench.view.preview_action(1,"bite",0),"Fish bite uses real animation")
	bench.selected_actor = 0
	bench.actor_tabs.current_tab = 0
	bench._sync_actor_controls()
	bench.action_picker.select(0)
	bench.loop_toggle.button_pressed = true
	await get_tree().create_timer(0.1).timeout
	verify(bench.loop_running and bench.view.preview_busy,"Loop starts action")
	bench.loop_toggle.button_pressed = false
	await idle()
	await get_tree().create_timer(0.4).timeout
	verify(not bench.loop_running,"Loop stops after current action")
	await send_key(KEY_TAB)
	verify(not bench.left_panel.visible and not bench.right_panel.visible,"Tab hides both panels")
	await shot("04-clean-battle")
	await send_key(KEY_TAB)
	verify(bench.left_panel.visible and bench.right_panel.visible,"Tab restores both panels")
	await send_key(KEY_BRACKETLEFT)
	verify(not bench.left_panel.visible and bench.right_panel.visible,"Independent left collapse")
	await send_key(KEY_BRACKETLEFT)
	await send_key(KEY_BRACKETRIGHT)
	verify(bench.left_panel.visible and not bench.right_panel.visible,"Independent right collapse")
	await send_key(KEY_BRACKETRIGHT)
	bench.selected_actor = 3
	await bench.change_roster("remove")
	await idle()
	verify(bench.roster.size() == 2 and invariant(),"Removing one slot rebuilds consistent combat")
	verify(not Game.save_enabled,"Saving stays disabled throughout")
	finish()

func finish() -> void:
	started = 0
	var report := {"checks":checks,"failures":failures,"resolution":str(get_viewport().get_visible_rect().size),"scope":"program-driven Godot rendering and synthetic input"}
	var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"\t"))
	print("WORKBENCH QA: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
