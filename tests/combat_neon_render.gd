extends "res://tests/combat_neon_visual.gd"
## Deterministic view-action rendering. Deliberately no physical/global-pointer claim.
func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://neon_render_unused.json"
	Game.meta_path = "user://neon_render_meta_unused.json"
	output = "res://artifacts/qa/combat-neon-2026-10-13/%d-render/" % DisplayServer.window_get_size().x
	DirAccess.make_dir_recursive_absolute(output)
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle(0.5)
	Game.start_training("B04")
	await idle()
	var view = app.view
	view.model.enemies[0].hp = 20
	view.model.enemies[0].maxHp = 20
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.commit()
	view.refresh_enemy_hud()
	view.stage.phase_changed.connect(on_phase)
	var ui: Rect2 = view.end_button.get_global_rect()
	await shot("01-wide")
	view.select_card(view.model.hand[0])
	await view.play_selected(0)
	verify(view.model.enemies[0].hp == 19 and is_equal_approx(view.stage.zoom,1.65),"Slash settles in near view with exactly one hit")
	await shot("02-near")
	view.preview_attack_style = "pierce"
	phases.clear()
	view.select_card(view.model.hand[0])
	await view.play_selected(0)
	verify(view.model.enemies[0].hp == 18 and not phases.has("approach"),"Same-target pierce has no repeated dash")
	await view.end_turn_pressed()
	verify(view.shown_player_hp == 99 and view.model.player_hp == 99 and view.model.turn == 2,"Enemy attack resolves once")
	verify(view.stage.player.position == view.stage.player.home and view.stage.enemies[0].position == view.stage.enemies[0].home and is_equal_approx(view.stage.zoom,1),"Return and camera complete before next turn")
	await shot("03-returned")
	var snapshot: Dictionary = view.model.snapshot()
	await view.preview_defense(false)
	await view.preview_defense(true)
	verify(view.model.snapshot() == snapshot,"Guard previews do not change combat results")
	var uid: String = view.model.hand[0]
	view.model.card_catalog[view.model.instances[uid]].effects = [{"type":"damage","amount":1},{"type":"damage","amount":2}]
	var old_hits := sampled_hits
	view.select_card(uid)
	await view.play_selected(0)
	verify(sampled_hits == old_hits+2 and view.model.enemies[0].hp == 15,"Multi-hit still matches model and effect count")
	await settle(0.5)
	var remaining_fx := 0
	for child in view.stage.world.get_children():
		if child.get_script() == preload("res://scripts/combat/prismatic_slash_fx.gd"): remaining_fx += 1
	verify(remaining_fx == 0,"All temporary neon ribbons are released")
	verify(view.end_button.get_global_rect() == ui and view.stage.clip_contents,"UI bounds unchanged; battlefield remains clipped")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"mode":"rendered direct view calls, no pointer coverage"},"\t"))
	print("NEON RENDER: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
