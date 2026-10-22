extends "res://tests/combat/cards/noren_cards_visual.gd"
var impact_samples: Array = []
var current_view: Control

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://actor_hud_unused.json"
	Game.meta_path = "user://actor_hud_meta_unused.json"
	output = "res://artifacts/qa/actor-hud-2026-10-16/%d-" % DisplayServer.window_get_size().x
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(0.5).timeout
	Game.start_training("B04")
	await idle()
	var view = app.view
	check(view.player_plate.hp == 100 and view.player_plate.block == 0,"Initial player HP and zero block")
	check(view.player_plate.badges.is_empty(),"Zero statuses are hidden")
	check(view.enemy_plates[0].hp == view.model.enemies[0].hp,"Initial enemy HP")
	check(view.player_plate.global_position.distance_to(view.stage.player.to_global(Vector2.ZERO)+Vector2(-98,12)) < 0.1,"Player strip follows projected feet")
	for node in view.get_children():
		if node is Label: check(not(node.position.y > 300 and node.text == Game.display_name(Game.PLAYER_REFERENCE)),"Removed standalone player name")
	await shot("single-unblocked")
	await install_hand([2,1,4,1,3])
	view = app.view
	view.model.player_hp = 74
	view.shown_player_hp = 74
	view.model.block = 25
	view.model.parry = 2
	view.model.turn_damage_bonus = 4
	view.model.next_attack_bonus = 2
	view.model.turn_discount = 1
	view.model.stance_discount = true
	view.model.powers = ["high_pressure","dissection"]
	view.model.enemies[0].hp = 74
	view.model.enemies[0].bleed = 4
	view.model.enemies[0].weak = 2
	view.model.enemies[1].block = 18
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.refresh_resources(); view.refresh_hp(); view.refresh_enemy_hud()
	await get_tree().process_frame
	check(view.player_plate.block == 25 and view.player_plate.hp == 74,"Block changes styling without replacing HP")
	check(view.player_plate.badges.size() == 7 and view.player_plate.size.y == 100,"All active effects wrap to a second row")
	check(view.enemy_plates[0].badges.size() == 2,"Enemy bleed and weakness icons")
	check(view.enemy_plates[1].block == 18,"Enemy shield displays independent block")
	for badge in view.player_plate.badges:
		check(badge.tooltip_text.length() > 25,"Status has full effect and duration text: "+badge.symbol)
	await shot("three-statuses")
	var bleed: Control = view.enemy_plates[0].badges[0]
	await pointer(bleed.global_position+Vector2(12,12))
	await get_tree().create_timer(0.85).timeout
	check(bleed.hovered,"Pointer hovers enemy status rather than underlying target")
	await shot("bleed-tooltip")
	var parry: Control = view.player_plate.badges[0]
	await pointer(parry.global_position+Vector2(12,12))
	await get_tree().create_timer(0.85).timeout
	check(parry.hovered,"Pointer hovers player status")
	await shot("parry-tooltip")
	var snap: Dictionary = view.model.snapshot()
	view.stage.player.position += Vector2(170,-35)
	view.stage.zoom = 1.25
	view.stage._update_camera()
	await get_tree().process_frame
	view.update_target_rects()
	check(view.player_plate.global_position.distance_to(view.stage.player.to_global(Vector2.ZERO)+Vector2(-98,12)) < 0.1,"Movement and camera transform preserve anchor")
	check(view.player_plate.scale == Vector2.ONE,"Health UI keeps constant screen size")
	check(view.model.snapshot() == snap,"Presentation never mutates the model")
	await shot("camera-follow")
	view.commit()
	app.swap_view()
	await idle()
	view = app.view
	check(view.player_plate.block == 25 and view.player_plate.badges.size() == 7,"Restore rebuilds shield and all effects")
	# Full turn: three two-hit enemies; sample displayed shield at each impact.
	await install_hand([2,1,4,1,3])
	view = app.view
	current_view = view
	view.model.block = 25
	view.model.parry = 2
	view.refresh_resources()
	view.stage.phase_changed.connect(on_phase)
	view.end_turn_pressed()
	await idle()
	check(impact_samples == [15,5,0,0,0,0],"Shield follows six individual impacts, not final committed turn: "+str(impact_samples))
	check(view.player_plate.block == 0 and view.player_plate.hp == 65,"Turn finishes with correct HP and red bar")
	check(view.player_plate.badges.is_empty(),"Consumed parry is removed")
	for i in view.enemy_plates.size():
		check(view.enemy_plates[i].hp == view.model.enemies[i].hp,"Counterattack health aligns for enemy %d" % i)
	await shot("after-turn")
	var enemy: Node2D = view.stage.enemies[0]
	enemy.modulate.a = 0
	view.update_target_rects()
	check(not view.enemy_plates[0].visible,"Vanished actor hides its health and icons")
	print("ACTOR HUD: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)

func on_phase(phase: String) -> void:
	if phase == "impact" and current_view.stage.active_defender == current_view.stage.player:
		capture_impact.call_deferred()

func capture_impact() -> void:
	impact_samples.append(current_view.player_plate.block)
	check(current_view.player_plate.hp == current_view.shown_player_hp,"Player HP tracks impact display snapshot")
	check(not current_view.player_plate.get_global_rect().intersects(current_view.enemy_plates[0].get_global_rect()),"Melee strips do not overlap")
	await shot("impact-%d" % impact_samples.size())
