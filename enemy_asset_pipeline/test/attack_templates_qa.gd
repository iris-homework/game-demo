extends Node
## Real shared stage + isolated catalogs. Synthetic profiles do not publish user art.
const Catalog := preload("res://enemy_asset_pipeline/runtime/pipeline_catalog.gd")
const Runtime := preload("res://enemy_asset_pipeline/runtime/pipeline_runtime_profile.gd")
const Bench := preload("res://tests/combat/workbench/battle_background_preview.gd")
const OUTPUT := "res://enemy_asset_pipeline/test/evidence/attack-templates"
var bench: Control
var checks := 0
var failures: Array[String] = []
var phases: Array[String] = []
var samples: Array = []
var monitor_actor: Node2D
var screenshots: Dictionary = {}
var started := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _process(_delta: float) -> void:
	if started > 0 and Time.get_ticks_msec() - started > 100000:
		check(false, "attack template QA timeout")
		finish()
	if is_instance_valid(monitor_actor): samples.append(monitor_actor.position)

func config(style: String) -> Dictionary:
	return {"type":style, "movement":"stationary" if style in ["shoot", "laser"] else "approach",
		"windupPose":"bite" if style == "bite" else "idle", "strikePose":"bite_close" if style == "bite" else style,
		"recoveryPose":"idle", "windup":0.12, "impactDelay":0.03, "recovery":0.1,
		"flightTime":0.28 if style in ["shoot", "laser"] else 0.0, "muzzle":[714,700], "contact":[0,-62],
		"muzzleTexture":"", "projectileTexture":"", "impactTexture":""}

func visual(id: String, textures: Dictionary, attack: Dictionary, anchor: Array, factor: float) -> Dictionary:
	var poses: Dictionary = {}
	var frames: Dictionary = {}
	for key in textures:
		poses[key] = {"texture":textures[key], "anchor":anchor, "scale":factor}
		frames[key] = [{"texture":textures[key], "transform":[factor,0,0,factor,-anchor[0]*factor,-anchor[1]*factor], "duration":0.12}]
	return {"id":id, "sourceFacing":"right" if id == "qa_shoot" else "left", "targetRect":[-65,-145,130,155],
		"attackStyleOverride":attack.type, "poses":poses, "pipelineFrames":frames,
		"pipelineAttacks":{attack.type:attack}, "pipelineMotion":{"speed":2300,"reach":100,"windup":0.045,"recovery":0.12}}

func write_catalog(name_value: String, profiles: Dictionary) -> String:
	var path := OUTPUT.path_join(name_value + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schemaVersion":1,"profiles":profiles,"bindings":{}}, "\t"))
	file.close()
	return path

func idle() -> void:
	while bench.tools_locked(): await get_tree().process_frame
	await get_tree().process_frame

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(label + ".png")) == OK, "capture " + label)

func on_phase(value: String) -> void:
	phases.append(value)
	if value in ["bite_open", "bite_close", "projectile_flight", "impact"] and not screenshots.has(value):
		screenshots[value] = true
		shot("phase-" + value)

func _ready() -> void:
	started = Time.get_ticks_msec()
	Game.save_enabled = false
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var hit := config("hit")
	hit.muzzle = [0,0]
	var bite := config("bite")
	bite.muzzle = [0,0]
	var shoot := config("shoot")
	var profiles := {
		"qa_hit":visual("qa_hit", {"idle":"res://assets/combat_test/01a_warden_shield/warden_shield_idle.png", "move":"res://assets/combat_test/01a_warden_shield/warden_shield_move.png", "hit":"res://assets/combat_test/01a_warden_shield/warden_shield_attack.png"}, hit, [637.5,1238], 0.10),
		"qa_bite":visual("qa_bite", {"idle":"res://assets/combat_test/06b_luggage_lurker/luggage_lurker_idle.png", "move":"res://assets/combat_test/06b_luggage_lurker/luggage_lurker_move.png", "bite":"res://assets/combat_test/06b_luggage_lurker/luggage_lurker_attack_bite.png", "bite_close":"res://assets/combat_test/06b_luggage_lurker/luggage_lurker_idle.png"}, bite, [779.5,893], 0.10),
		"qa_shoot":visual("qa_shoot", {"idle":"res://assets/combat_test/noren/noren_gun_idle.png", "shoot":"res://assets/combat_test/noren/noren_shoot_planted.png", "laser":"res://assets/combat_test/noren/noren_shoot_planted.png"}, shoot, [714,1210], 0.099)}
	var problems: Array[String] = []
	check(Runtime.parse(profiles.qa_bite, "qa_bite", problems) != null, "explicit idle closure texture accepted without VFX PNG")
	var bad: Dictionary = profiles.qa_bite.duplicate(true)
	bad.pipelineAttacks.bite.strikePose = "missing_close"
	problems.clear()
	check(Runtime.parse(bad, "qa_bite", problems) == null and not problems.is_empty(), "missing closure rejects runtime template")
	bad = profiles.qa_shoot.duplicate(true)
	bad.pipelineAttacks.shoot.movement = "approach"
	problems.clear()
	check(Runtime.parse(bad,"qa_shoot",problems) == null, "remote approach is invalid")
	bad = profiles.qa_hit.duplicate(true)
	bad.pipelineAttacks.hit.impactTexture = "res://../outside.png"
	problems.clear()
	check(Runtime.parse(bad,"qa_hit",problems) == null, "unsafe effect path rejected")
	var laser := config("laser")
	laser.muzzle = [714,700]
	profiles.qa_shoot.pipelineAttacks.laser = laser
	# A legacy melee template must not shadow the chosen ranged default when
	# the actual model intent has no explicit animation.
	profiles.qa_shoot.pipelineAttacks.pierce = hit.duplicate(true)
	profiles.qa_shoot.pipelineAttacks.pierce.strikePose = "shoot"
	Catalog.set_published_path(write_catalog("isolated-published",profiles))
	Catalog.clear_preview()
	bench = Bench.new()
	add_child(bench)
	await idle()
	for key in profiles:
		bench.enemy_choices.append({"id":"visual:" + key, "name":key, "tooltip":"isolated QA fixture"})
	bench._refresh_enemy_picker()
	for key in ["qa_hit", "qa_bite", "qa_shoot"]:
		bench.roster.assign(["visual:" + key])
		bench.selected_actor = 1
		await bench.rebuild()
		await idle()
		var stage: Control = bench.view.stage
		var actor: Node2D = stage.enemies[0]
		check(actor.kind == key and not actor.pipeline_attacks.is_empty(), "published template reaches actor: " + key)
		var style: String = actor.attack_style_override
		var snapshot: Dictionary = bench.view.model.snapshot()
		var home: Vector2 = actor.position
		phases.clear()
		samples.clear()
		monitor_actor = actor
		stage.phase_changed.connect(on_phase)
		check(await bench.view.preview_action(1,style,0), "full preview completes: " + style)
		monitor_actor = null
		check(bench.view.model.snapshot() == snapshot, "preview does not mutate model: " + style)
		check(actor.position.is_equal_approx(actor.home), "preview returns home: " + style)
		check(phases.count("impact") == 1, "one impact phase: " + style)
		if style == "shoot":
			var stationary := true
			for point in samples:
				if not point.is_equal_approx(home): stationary = false
			check(stationary, "ranged actor stays in place for entire preview")
			check(phases.find("projectile_flight") < phases.find("impact"), "projectile precedes impact")
		else:
			check(phases.has("approach"), "melee approaches before contact")
		if style == "bite":
			check(phases.find("bite_open") < phases.find("bite_close") and phases.find("bite_close") < phases.find("impact"), "bite opens then closes then impacts")
		# Exercise the authoritative model once, then replay its actual hit list.
		var hp: int = bench.view.model.player_hp
		var result: Dictionary = bench.view.model.end_turn()
		var resolved_hp: int = bench.view.model.player_hp
		check(resolved_hp < hp, "real enemy action resolves damage once: " + style)
		var callback_count := [0]
		var callback_pose := [""]
		var model_after: Dictionary = bench.view.model.snapshot()
		await stage.attack(actor, stage.player, "pierce", result.attacks[0].hits, func(_hit, _index):
			callback_count[0] += 1
			callback_pose[0] = actor.pose)
		check(callback_count[0] == result.attacks[0].hits.size(), "one callback per resolved hit: " + style)
		check(callback_pose[0] == actor.pipeline_attacks[style].strikePose, "contact occurs in strike pose: " + style)
		check(bench.view.model.snapshot() == model_after, "presentation never resolves damage again: " + style)
		await stage.return_home()
		if style == "shoot":
			# Explicit previews can inspect a second template without changing defaults.
			check(await bench.view.preview_action(1,"laser",0), "second attack template selectable independently")
			await stage.attack(actor, stage.player, "laser", [{"damage":0,"blocked":0,"killed":false}], func(_hit, _index): pass)
			check(stage.active_attack_config.type == "laser", "explicit intent action wins over default shoot")
			await stage.return_home()
			bench.view.preview_speed = 0.25
			var saved_scale := Engine.time_scale
			var completed := [false]
			_preview_async(completed)
			await get_tree().process_frame
			check(is_equal_approx(Engine.time_scale, saved_scale * 0.25), "quarter speed owns preview time scale")
			bench.view.pause_preview(true)
			check(is_zero_approx(Engine.time_scale), "pause stops preview")
			bench.view.pause_preview(false)
			check(is_equal_approx(Engine.time_scale, saved_scale * 0.25), "resume retains quarter speed")
			while not completed[0]: await get_tree().process_frame
			check(is_equal_approx(Engine.time_scale, saved_scale), "completion restores previous speed")
			bench.view.preview_speed = 1.0
			var turn_hp: int = bench.view.model.player_hp
			phases.clear()
			await bench.view.end_turn_pressed()
			check(bench.view.model.player_hp == turn_hp - 6, "actual enemy-turn UI presents exactly one model attack")
			check(phases.has("projectile_flight") and not phases.has("approach"), "actual default enemy turn uses ranged template")
		bench.guides_enabled = true
		bench.guides.show()
		bench._sync_actor_controls()
		await shot(key + "-workbench")
		stage.phase_changed.disconnect(on_phase)
	# Draft overrides are isolated from the published profile.
	var draft: Dictionary = profiles.qa_shoot.duplicate(true)
	draft.pipelineAttacks.shoot.flightTime = 0.7
	Catalog.set_preview_path(write_catalog("isolated-preview",{"qa_shoot":draft}))
	check(Catalog.get_profile("qa_shoot").pipelineAttacks.shoot.flightTime == 0.7,"draft selects its own template")
	Catalog.clear_preview()
	check(Catalog.get_profile("qa_shoot").pipelineAttacks.shoot.flightTime == 0.28,"clearing draft restores published template")
	check(not Game.save_enabled,"formal saving remains disabled")
	bench.queue_free()
	await get_tree().process_frame
	Catalog.clear_published_path()
	finish()

func _preview_async(completed: Array) -> void:
	completed[0] = await bench.view.preview_action(1,"shoot",0)

func finish() -> void:
	started = 0
	Engine.time_scale = 1.0
	var mode := "headless" if DisplayServer.get_name() == "headless" else "render"
	var file := FileAccess.open(OUTPUT.path_join(mode+"-result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false,"fixtureNote":"06b explicitly uses idle as closure; remote fixture uses noren artwork pending mirror_inspector final calibration"},"\t"))
	print("ATTACK_TEMPLATES_QA checks=%d failures=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
