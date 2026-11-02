extends Node
## Isolated presentation contracts: real pose playback, formation and projectile contact.
const Resolver := preload("res://scripts/combat/enemy_visual_resolver.gd")
const Stage := preload("res://scripts/combat/test_stage.gd")
var checks := 0
var failures := 0
var output := ""
var capture := false
var flight_seconds: Array[float] = []

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func screenshot(name: String) -> void:
	if not capture or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name+".png"))

func showing_pose(actor, pose_name: String, filename: String) -> bool:
	if actor.pose != pose_name or not actor.poses[pose_name].resource_path.ends_with(filename): return false
	# The actor intentionally wraps source PNGs in generated mipmapped textures;
	# that displayed ImageTexture has no resource_path. Compare its base pixels.
	var displayed: Image = actor.sprite.texture.get_image()
	var source: Image = actor.poses[pose_name].get_image()
	displayed.clear_mipmaps()
	source.clear_mipmaps()
	return displayed.get_size() == source.get_size() and displayed.get_data() == source.get_data()

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://noss_visual_unused.json"
	Game.meta_path = "user://noss_visual_meta_unused.json"
	if not "qa" in OS.get_user_data_dir().to_lower():
		push_error("Noss visual tests require an isolated QA user directory")
		get_tree().quit(2)
		return
	output = OS.get_environment("NOSS_VISUAL_QA_OUT")
	if output.is_empty(): output = OS.get_temp_dir().path_join("noss_visual_qa")
	DirAccess.make_dir_recursive_absolute(output)
	capture = OS.get_cmdline_user_args().has("--capture")
	var resolver := Resolver.new()
	var first: Array[Resolver.Visual] = []
	for id in ["noss_hand","noss_hand","noss"]:
		var visual := resolver.resolve({"id":"preview_"+id,"combatVisualId":id},{})
		check(visual.id == id and visual.diagnostics.is_empty(),id+" resolves explicitly")
		check(visual.source_facing == -1.0,id+" source faces left")
		for pose in visual.poses:
			check(visual.poses[pose] is Texture2D and not visual.white_key_poses[pose],id+" opaque gold/ivory kept by alpha: "+pose)
		first.append(visual)
	var phase_two := resolver.resolve({"id":"preview_noss_phase2","combatVisualId":"noss_phase2"},{})
	check(phase_two.id == "noss_phase2" and phase_two.diagnostics.is_empty(),"long-leg phase2 resolves")
	check(phase_two.poses.idle.resource_path.ends_with("noss_phase2_idle.png"),"phase2 uses selected long-leg copy")
	var stage := Stage.new()
	add_child(stage)
	stage.setup(577.0,first)
	var player_id: int = stage.player.get_instance_id()
	var player_home: Vector2 = stage.player.home
	stage.set_noss_encounter(first)
	check(stage.enemies.size() == 3 and stage.noss_encounter and not stage.dancer_duet,"first-phase three-actor formation")
	check(stage.player.get_instance_id() == player_id and stage.player.home == player_home,"formation preserves player")
	check(stage.enemies[0].home.x < stage.enemies[2].home.x and stage.enemies[1].home.x < stage.enemies[2].home.x,"hands stand in front of Noss")
	check(stage.enemies[0].home.y != stage.enemies[1].home.y,"hands occupy distinct target lanes")
	check(not is_instance_valid(stage.dancer_lights),"no dancer lighting in Noss encounter")
	await screenshot("phase1_idle")
	var shot_checks := {"count":0,"flight":0,"impact":0,"pose":""}
	stage.phase_changed.connect(func(phase: String):
		if phase == "impact" and stage.active_attacker != null and stage.active_attacker.kind in ["noss","noss_phase2"]:
			var impacts := get_tree().get_nodes_in_group("noss_sword_impact")
			check(impacts.size() == 1,"one bounded gold impact burst at each sword contact")
			var tails := get_tree().get_nodes_in_group("noss_sword_trail")
			if tails.size() == 1:
				flight_seconds.append(tails[0].elapsed)
				check(tails[0].elapsed >= 0.13 and tails[0].elapsed <= 0.23,"sword reaches target in accelerated flight window")
			check(impacts.size() == 1 and impacts[0].sparkles.size() >= 9,"contact emits its own sparkle burst")
			shot_checks.impact += 1
			if capture:
				var impact_number: int = shot_checks.impact
				await get_tree().create_timer(0.045).timeout
				await screenshot("sword_impact_%d" % impact_number)
		if phase != "projectile_flight": return
		var swords := get_tree().get_nodes_in_group("noss_light_sword")
		var muzzle := get_tree().get_nodes_in_group("noss_sword_muzzle")
		var trails := get_tree().get_nodes_in_group("noss_sword_trail")
		check(swords.size() == 1,"exactly one independently animated light sword")
		check(muzzle.size() == 1 and muzzle[0].duration <= 0.30,"visible bounded palm emission at launch")
		check(trails.size() == 1 and trails[0].projectile == swords[0],"one sampled trail follows this sword only")
		check(muzzle.size() == 1 and muzzle[0].sparkles.size() >= 6,"palm flash emits sparkling particles")
		if swords.size() == 1:
			var axis: Vector2 = (stage.player.position-stage.active_attacker.position).normalized()
			var tip_direction := Vector2.LEFT.rotated(swords[0].rotation)
			check(tip_direction.dot(axis) > 0.90,"left-facing sword flies tip first")
			check(swords[0].texture.resource_path.ends_with("noss_vfx_projectile.png"),"selected pure light sword texture")
		shot_checks.flight += 1
		var flight_number: int = shot_checks.flight
		await get_tree().create_timer(0.10).timeout
		check(is_instance_valid(trails[0]) and trails[0].samples.size() >= 3,"flight trail collects actual moving tail positions")
		if is_instance_valid(trails[0]) and trails[0].samples.size() >= 3:
			check(trails[0].samples[0].distance_to(trails[0].samples[-1]) > 5,"trajectory has measurable travel, not a fixed palm line")
			check(trails[0].sparkles.size() >= 6 and trails[0].sparkles.size() <= 64,"fast flight leaves a bounded field of sparkling particles")
			var particle: Dictionary = trails[0].sparkles[-1].duplicate()
			var brightness: float = trails[0].sparkle_brightness(particle,trails[0].elapsed)
			var oldest: Vector2 = trails[0].sparkles[0].point
			var newest: Vector2 = trails[0].sparkles[-1].point
			check(oldest.distance_to(newest) > 30,"sparkles spread along actual flight instead of remaining at the palm")
			if capture:
				await screenshot("sword_flight_%d" % flight_number)
			await get_tree().create_timer(0.035).timeout
			check(is_instance_valid(trails[0]) and absf(trails[0].sparkle_brightness(particle,trails[0].elapsed)-brightness) > 0.015,"particle brightness visibly changes across playback frames")
			if capture:
				await screenshot("sword_sparkles_%d" % flight_number))
	await stage.attack(stage.enemies[2],stage.player,"shoot",[{"damage":7,"blocked":0,"killed":false}],func(_hit,_index):
		shot_checks.count += 1
		shot_checks.pose = stage.enemies[2].pose)
	check(shot_checks.count == 1 and shot_checks.pose == "shoot" and shot_checks.flight == 1,"phase1 casts and reveals model hit once")
	check(stage.enemies[2].pose == "idle" and stage.player.pose == "idle","shot recovery restores idle")
	var fist := {"count":0,"pose":""}
	await stage.attack(stage.enemies[0],stage.player,"hit",[{"damage":5,"blocked":0,"killed":false}],func(_hit,_index):
		fist.count += 1
		fist.pose = stage.enemies[0].pose)
	check(fist.count == 1 and fist.pose == "attack_hit","golden hand punches with authored fist keypose")
	stage.enemies[0].set_pose("damaged")
	check(showing_pose(stage.enemies[0],"damaged","noss_hand_damaged.png"),"hand recoil uses own damaged texture pixels")
	stage.enemies[0].set_pose("idle")
	var phase_two_visuals: Array[Resolver.Visual] = [phase_two]
	stage.player.set_combat_stance("ranged")
	stage.player.position += Vector2(210,-25)
	stage.set_noss_encounter(phase_two_visuals)
	await get_tree().process_frame
	check(stage.enemies.size() == 1 and stage.enemies[0].kind == "noss_phase2","phase transition replaces all phase1 actors")
	check(stage.player.get_instance_id() == player_id and stage.player.combat_stance == "ranged","phase transition preserves player stance and identity")
	check(stage.player.position == player_home and stage.player.pose == "gun_idle","phase transition returns player to original home without changing stance")
	check(stage.actors_root.get_child_count() == 2,"no duplicate or hidden phase1 actors remain")
	await screenshot("phase2_idle")
	var phase_two_hits := {"count":0}
	await stage.attack(stage.enemies[0],stage.player,"shoot",[{"damage":8,"blocked":2,"killed":false},{"damage":8,"blocked":0,"killed":false}],func(_hit,_index): phase_two_hits.count += 1)
	check(phase_two_hits.count == 2 and shot_checks.flight == 3 and shot_checks.impact == 3,"phase2 multi-hit launches two swords and callbacks once per model hit")
	check(get_tree().get_nodes_in_group("noss_light_sword").is_empty(),"projectiles clean up after playback")
	await get_tree().create_timer(0.35).timeout
	check(get_tree().get_nodes_in_group("noss_sword_vfx").is_empty(),"muzzle, trail and impact all clean up within bounded lifetimes")
	var heavy := {"charge":0,"burst":0,"callbacks":0,"blocked":false}
	var boss_home: Vector2 = stage.enemies[0].position
	var target_home: Vector2 = stage.player.position
	stage.phase_changed.connect(func(phase: String):
		if phase == "halo_charge":
			heavy.charge += 1
			var rings := get_tree().get_nodes_in_group("noss_halo_charge")
			check(rings.size() == 1,"one heavy charge halo per attack")
			check(get_tree().get_nodes_in_group("noss_light_sword").is_empty(),"halo heavy never launches a sword")
			var target: Vector2 = stage.world.to_local(stage.player.to_global(stage.player.target_bounds.get_center()))
			check(rings.size() == 1 and rings[0].position.distance_to(target) < 1.0,"halo encloses target body rather than the caster")
			check(heavy.callbacks == heavy.charge-1,"charge causes no early hit callback")
			await get_tree().create_timer(0.35).timeout
			check(is_instance_valid(rings[0]) and not rings[0].bursting,"visible charge precedes detonation")
			if capture: await screenshot("heavy_charge_%d" % heavy.charge)
		if phase == "halo_burst":
			heavy.burst += 1
			var blasts := get_tree().get_nodes_in_group("noss_halo_burst")
			check(blasts.size() == 1,"one bounded light detonation at heavy contact")
			check(blasts.size() == 1 and is_instance_valid(blasts[0].burst_glow) and blasts[0].burst_glow.material is ShaderMaterial,"heavy owns a soft luminous explosion layer")
			check(blasts[0].burst_glow.mouse_filter == Control.MOUSE_FILTER_IGNORE,"large light explosion never intercepts targeting")
			await get_tree().create_timer(0.045).timeout
			check(is_instance_valid(blasts[0]) and float(blasts[0].burst_glow.material.get_shader_parameter("blast_age")) > 0.0,"explosion material clock advances with actual playback")
			if capture:
				await screenshot("heavy_burst_%d" % heavy.burst))
	for blocked in [false,true]:
		await stage.attack(stage.enemies[0],stage.player,"halo_burst",[{"damage":0 if blocked else 16,"blocked":16 if blocked else 0,"killed":false}],func(_hit,_index):
			heavy.callbacks += 1
			heavy.blocked = stage.player.pose == "gun_block"
			check(stage.player.pose == ("gun_block" if int(_hit.damage) == 0 else "gun_damaged"),"heavy respects stance-specific block and damaged poses")
			check(stage.phase == "halo_burst","heavy callback occurs precisely at detonation"))
		check(stage.enemies[0].position == boss_home and stage.player.position == target_home,"ritual preserves caster/target positions")
		check(stage.enemies[0].pose == "idle" and stage.player.pose == "gun_idle","heavy recovers to original player stance and regal idle")
	check(heavy.charge == 2 and heavy.burst == 2 and heavy.callbacks == 2 and heavy.blocked,"damaging and fully blocked heavies each reveal exactly one hit")
	await get_tree().create_timer(0.55).timeout
	check(get_tree().get_nodes_in_group("noss_heavy_vfx").is_empty(),"all heavy halos and blasts clean up")
	stage.enemies[0].set_pose("damaged")
	check(showing_pose(stage.enemies[0],"damaged","noss_phase2_damaged.png"),"phase2 uses regal long-leg damaged pose pixels")
	await screenshot("phase2_damaged")
	var summary := {"checks":checks,"failures":failures,"actualPresentationPlayback":true,"projectileFlights":shot_checks.flight,"flightSeconds":flight_seconds,"damageModelMutated":false,"physicalInput":false,"pixelValidation":capture and DisplayServer.get_name() != "headless"}
	FileAccess.open(output.path_join("summary.json"),FileAccess.WRITE).store_string(JSON.stringify(summary,"\t"))
	print("NOSS VISUALS: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
