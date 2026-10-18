extends Node
## Rendered, program-driven QA; does not claim physical mouse validation.
var preview: Node
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var output := ""
var sampling := false
var coverage_samples := 0
var uncovered_frames := 0

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func idle() -> bool:
	var deadline := Time.get_ticks_msec()+20000
	while Game.battle_busy or Game.transition_locked:
		if Time.get_ticks_msec() > deadline:
			verify(false,"Timed out waiting for battle presentation")
			return false
		await get_tree().process_frame
	await get_tree().process_frame
	return true

func covers_canvas(stage: Control) -> bool:
	if not is_instance_valid(stage.scenery): return false
	var bounds: Rect2 = stage.scenery.get_global_rect()
	return bounds.position.x <= 0.1 and bounds.position.y <= 0.1 and bounds.end.x >= 1439.9 and bounds.end.y >= 899.9

func _process(_delta: float) -> void:
	if sampling and is_instance_valid(preview.app.view):
		coverage_samples += 1
		if not covers_canvas(preview.app.view.stage): uncovered_frames += 1

func shot(id: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output.path_join(id+".png")
	verify(get_viewport().get_texture().get_image().save_png(path) == OK,"Screenshot saved: "+id)
	captures.append(path)

func check_scene(place_id: String) -> void:
	var view: Control = preview.app.view
	var stage: Control = view.stage
	var asset_id: String = Game.assets[Game.place_data(place_id).backgroundAssetId].battleAssetId
	verify(view.battle.placeId == place_id,"Battle view selects "+place_id)
	verify(is_instance_valid(stage.scenery) and stage.scenery.texture == Game.texture(asset_id),"Expected imported texture is displayed: "+place_id)
	verify(covers_canvas(stage),"Full canvas is covered: "+place_id)
	if not is_instance_valid(stage.scenery): return
	var ground_start: float = Game.assets[asset_id].get("groundStart",0.5)
	var horizon: float = stage.scenery.get_global_rect().position.y+stage.scenery.size.y*ground_start
	for actor in stage.actors_root.get_children():
		verify(actor.global_position.y > horizon,"Actor feet lie on the foreground ground: "+place_id)
	verify(stage.scenery.z_index < view.player_plate.z_index,"Scenery stays behind actor HUD: "+place_id)

func find_attack(view: Control) -> String:
	for uid in view.model.hand:
		if view.model.instances[uid] == "noren_01": return uid
	return ""

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "res://artifacts/qa/battle-scenery-2026-10-18/render"
	DirAccess.make_dir_recursive_absolute(output)
	preview = preload("res://scenes/battle_scenery_preview.tscn").instantiate()
	add_child(preview)
	if not await idle():
		finish()
		return
	verify(Game.training_mode and not Game.save_enabled,"Preview uses isolated training with saving disabled")
	verify(preview.app.view.battle.placeId == "hive","Preview opens directly on hive")
	for i in preview.PLACE_IDS.size():
		var snapshot: Dictionary = preview.app.view.model.snapshot()
		verify(preview.switch_to(i),"Scene selector accepts index %d" % i)
		if not await idle(): break
		verify(preview.app.view.model.snapshot() == snapshot,"Changing scene preserves combat snapshot")
		check_scene(preview.PLACE_IDS[i])
		await shot("%02d-%s-wide" % [i+1,preview.PLACE_IDS[i]])
	verify(preview.switch_to(1),"Return to hive for actual combat")
	await idle()
	var view: Control = preview.app.view
	var uid := find_attack(view)
	for attempt in 4:
		if not uid.is_empty(): break
		await view.end_turn_pressed()
		await idle()
		uid = find_attack(view)
	verify(not uid.is_empty(),"A real starting-deck attack is available")
	if not uid.is_empty():
		var prior_hp: int = view.model.enemies[0].hp
		var prior_hand: int = view.model.hand.size()
		sampling = true
		view.select_card(uid)
		await view.play_selected(0)
		await idle()
		verify(view.model.enemies[0].hp == prior_hp-6 and view.model.hand.size() == prior_hand-1,"Direct strike resolves once through the real battle flow")
		verify(view.stage.zoom > 1.0,"Attack actually enters the zoomed camera")
		verify(view.stage.player.position.distance_to(view.stage.player.home) > 100,"Attacker reaches its target before return")
		verify(covers_canvas(view.stage),"Zoomed scenery covers the full canvas")
		await shot("10-hive-attack-zoom")
		var turn_before: int = view.model.turn
		await view.end_turn_pressed()
		await idle()
		sampling = false
		verify(view.model.turn == turn_before+1,"Enemy turn finishes and deals the next hand")
		for actor in view.stage.actors_root.get_children():
			verify(actor.position.distance_to(actor.home) < 0.1 and actor.modulate == Color.WHITE,"Living actor returns to its grounded home")
		verify(is_equal_approx(view.stage.zoom,1.0),"Camera returns to its wide view")
		verify(coverage_samples > 10 and uncovered_frames == 0,"Scenery covers canvas throughout attack, shake and return")
		check_scene("hive")
		await shot("11-hive-returned")
	verify(not Game.save_enabled and Game.training_mode,"Training stays isolated after scene changes and combat")
	finish()

func finish() -> void:
	var result := {"checks":checks,"failures":failures.size(),"failureMessages":failures,"screenshots":captures,"cameraFrames":coverage_samples,"uncoveredFrames":uncovered_frames,"programDriven":true,"physicalInput":false}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("BATTLE SCENERY VISUAL: %d checks, %d failures; %s" % [checks,failures.size(),output])
	get_tree().quit(0 if failures.is_empty() else 1)
