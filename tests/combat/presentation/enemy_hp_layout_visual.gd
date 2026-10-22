extends "res://tests/combat/cards/noren_cards_visual.gd"
var watched: Control
var sampled_frames := 0
var layer_errors := 0
var sync_errors := 0

func sample_layout() -> void:
	if not is_instance_valid(watched) or not is_instance_valid(watched.stage): return
	if watched.enemy_plates.size() != watched.stage.enemies.size(): return
	watched.update_target_rects()
	sampled_frames += 1
	for plate in [watched.player_plate]+watched.enemy_plates:
		if plate.z_index != -1: layer_errors += 1
	for index in watched.shown_enemies.size():
		var fixed_plate: Control = watched.enemy_summary_plates[index]
		var foot_plate: Control = watched.enemy_plates[index]
		var enemy: Dictionary = watched.shown_enemies[index]
		if fixed_plate.hp != enemy.hp or fixed_plate.block != int(enemy.get("block",0)) or fixed_plate.hp != foot_plate.hp:
			sync_errors += 1

func check_idle_layout(title: String) -> void:
	var view: Control = app.view
	view.update_target_rects()
	check(view.enemy_plates.all(func(p): return p.z_index == -1),title+" foot bars draw behind all actors")
	check(view.stage.world.get_child(0).z_index == -2,title+" ground draws behind foot bars")
	check(view.enemy_summary_plates.size() == view.model.enemies.size(),title+" fixed row per enemy")
	for p in view.enemy_summary_plates:
		var viewport: ScrollContainer = p.get_parent().get_parent()
		check(viewport.get_global_rect().end.y <= 270 and p.global_position.x > 1000,title+" readout viewport above stage at right")
		check(p.mouse_filter == Control.MOUSE_FILTER_IGNORE,title+" fixed HP does not intercept targeting")
		check(p.hp_label.position.x > p.TRACK.end.x and p.hp_label.text == "%d / %d" % [p.hp,p.max_hp],title+" HP text beside rectangular bar")
	for i in range(1,view.enemy_summary_plates.size()):
		check(view.enemy_summary_plates[i].position.y-view.enemy_summary_plates[i-1].get_rect().end.y == 12,title+" independent enemy blocks separated by 12 pixels")
	for index in view.stage.enemies.size():
		check(view.target_at_point(view.stage.contact(view.stage.enemies[index])) == index,title+" target stays selectable "+str(index))

func install_attack(view: Control) -> String:
	for uid in view.model.instances:
		if view.model.instances[uid] != "noren_01": continue
		if not uid in view.model.hand:
			view.model.draw_pile.erase(uid)
			view.model.discard_pile.erase(uid)
			view.model.hand.append(uid)
		view.commit()
		app.swap_view()
		return uid
	return ""

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://enemy_hp_layout_unused.json"
	Game.meta_path = "user://enemy_hp_layout_meta_unused.json"
	output = "res://artifacts/qa/enemy-hp-style-2026-10-17/%d-" % DisplayServer.window_get_size().x
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	RenderingServer.frame_pre_draw.connect(sample_layout)
	Game.start_training("B04")
	await idle()
	watched = app.view
	check_idle_layout("Single")
	await shot("single")
	watched = null
	Game.finish_training("lose")
	await idle()
	await get_tree().create_timer(3.0).timeout
	Game.start_training("B11")
	await idle()
	var uid := install_attack(app.view)
	await idle()
	watched = app.view
	check_idle_layout("Two fish")
	for i in 2:
		var foot: Vector2 = watched.stage.enemies[i].to_global(Vector2.ZERO)
		check(watched.enemy_plates[i].global_position.is_equal_approx(foot+Vector2(-98,12)),"Fish foot bar retains exact original anchor, no art avoidance")
	await shot("fish-idle")
	var anchors: Array = watched.enemy_summary_plates.map(func(p): return p.global_position)
	watched.select_card(uid)
	await watched.play_selected(0)
	await idle()
	check(watched.enemy_summary_plates[0].hp == 24 and watched.enemy_summary_plates[1].hp == 30,"Damage updates only chosen enemy in fixed list")
	check(watched.enemy_summary_plates.map(func(p): return p.global_position) == anchors,"Fixed rows stay in place during approach and zoom")
	await shot("fish-after-attack")
	await watched.end_turn_pressed()
	await idle()
	check_idle_layout("Fish returned")
	await shot("fish-pollution")
	watched.model.buffs.apply(watched.model,"pollution",999,0)
	watched.model.enemies[0].block = 999
	watched.shown_enemies = watched.model.enemies.duplicate(true)
	watched.refresh_enemy_hud()
	check(watched.enemy_summary_plates[0].block == 999,"Three-digit shield synchronizes")
	check_idle_layout("Fish with statuses")
	await shot("fish-shield-status")
	# Existing helper installs three differently positioned actors; model remains isolated.
	watched = null
	await install_hand([1,36],"ranged")
	watched = app.view
	check_idle_layout("Three enemies")
	await shot("three-idle")
	watched.select_card("card_001")
	await watched.play_selected(1)
	await idle()
	check_idle_layout("Three after ranged hits")
	await shot("three-ranged")
	check(sampled_frames > 30,"Sampled actual animated frames")
	check(layer_errors == 0,"Foot bars remain behind actor art throughout animation")
	check(sync_errors == 0,"Fixed and foot HP/block match every sampled display state")
	watched = null
	RenderingServer.frame_pre_draw.disconnect(sample_layout)
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("ENEMY HP LAYOUT: %d checks, %d failures, %d frames, %d layer errors, %d sync errors" % [checks,failures,sampled_frames,layer_errors,sync_errors])
	get_tree().quit(0 if failures == 0 else 1)
