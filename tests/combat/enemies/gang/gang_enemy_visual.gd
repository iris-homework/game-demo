extends "res://tests/combat/cards/noren_cards_visual.gd"
## B04 art, opt-in formation and presentation callbacks; no pointer or save writes.
const Resolver = preload("res://scripts/combat/enemy_visual_resolver.gd")
const Ghost = preload("res://scripts/combat/return_ghost_fx.gd")
var attack_contacts := 0
var ghost_passes := 0

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless": await shot(label)

func observe_ghosts(phase: String, stage: Control) -> void:
	if phase != "home_glitch": return
	ghost_passes += 1
	var count := 0
	for child in stage.world.get_children():
		if child.get_script() != Ghost: continue
		count += 1
		for echo in child.echoes:
			check(echo.material.get_shader_parameter("white_key_enabled") == false,"Corrected RGBA poses retain transparent return silhouettes")
	check(count == 4,"All four surviving actors keep their return silhouettes")

func resolver_contract() -> void:
	var resolver := Resolver.new()
	var definitions := {"gang":{"combatVisualId":"gang_boss","formationSlot":"triangle_right"}}
	var legacy := {"id":"gang"}
	var before := legacy.duplicate(true)
	var visual := resolver.resolve(legacy,definitions)
	check(visual.id == "gang_boss" and visual.formation_slot == "triangle_right" and legacy == before,"Legacy art/formation resolution remains read-only")
	check(resolver.resolve({"id":"gang","formationSlot":"triangle_left_back"},definitions).formation_slot == "triangle_left_back","Saved formation takes precedence")
	check(resolver.resolve({"combatVisualId":"finn"},{}).source_facing == -1,"Existing left-facing source convention remains the default")
	var original: Dictionary = resolver.catalog.gang_boss.duplicate(true)
	for mutation in ["sourceFacing", "whiteKey"]:
		var profile := original.duplicate(true)
		profile.id = "qa_bad_gang"
		if mutation == "sourceFacing": profile.sourceFacing = "up"
		else: profile.poses.idle.whiteKey = "true"
		resolver.catalog.qa_bad_gang = profile
		var rejected := resolver.resolve({"combatVisualId":"qa_bad_gang"},{})
		check(rejected.id == "finn" and not rejected.diagnostics.is_empty(),"Malformed optional field rejects the entire visual: "+mutation)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://gang_visual_unused.json"
	Game.meta_path = "user://gang_visual_meta_unused.json"
	output = "res://artifacts/qa/gang-alley-2026-10-19/visuals/"
	var args := OS.get_cmdline_user_args()
	if args.has("--output-dir") and args.find("--output-dir")+1 < args.size():
		output = args[args.find("--output-dir")+1].trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(output)
	resolver_contract()
	Game.state = Game.initial_state()
	var adventure: Dictionary = Game.state.duplicate(true)
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	var view = app.view
	var stage = view.stage
	stage.phase_changed.connect(func(phase): observe_ghosts(phase,stage))
	var identities := ["gang_henchman","gang_henchman","gang_boss"]
	check(stage.enemies.size() == 3,"B04 renders two henchmen and the boss")
	if stage.enemies.size() != 3:
		get_tree().quit(1)
		return
	var snapshot: Dictionary = view.model.snapshot()
	for i in 3:
		var actor = stage.enemies[i]
		check(actor.kind == identities[i] and actor.facing == -1 and actor.sprite.scale.x < 0,"Gang source artwork mirrors left on battle entry: "+str(i))
		check(actor.poses.size() == 4 and actor.attack_style_override == "pierce","Four authored poses use the existing attack timing: "+str(i))
		check(view.target_at_point(stage.contact(actor)) == i,"Each enemy torso is independently targetable: "+str(i))
		check(stage.get_global_rect().encloses(stage.target_rect(i)),"Each initial target remains within the clipped stage: "+str(i))
		check(actor.sprite.material == null,"Corrected RGBA idle retains source alpha without white-key: "+str(i))
		if i == 2:
			check(not actor.white_key_poses.get("idle",false),"Corrected boss idle is transparent and disables paper removal")
	check(stage.enemies[0].home.x == stage.enemies[1].home.x and stage.enemies[1].home.y-stage.enemies[0].home.y == 200 and stage.enemies[0].home.y < stage.enemies[2].home.y and stage.enemies[2].home.y < stage.enemies[1].home.y,"Henchmen retain their aligned left column with a larger depth gap")
	check(stage.enemies[2].home.x > stage.enemies[0].home.x,"Boss occupies the right triangle vertex")
	check(stage.enemy_home(0,3) == Vector2(980,stage.floor_y-110),"Unconfigured three-enemy encounter retains its original layout")
	await capture("01-idle-triangle")
	for pose in ["move","pierce","damaged"]:
		for actor in stage.enemies:
			actor.set_pose(pose)
			check(actor.pose == pose and actor.sprite.material == null,"Transparent gang action preserves source alpha: "+actor.kind+"/"+pose)
		await capture("02-"+pose)
	for actor in stage.enemies: actor.set_pose("idle")
	for i in 3:
		var actor = stage.enemies[i]
		await stage.attack(actor,stage.player,"slash",[{"damage":1,"blocked":0,"killed":false}],func(_hit,_index):
			attack_contacts += 1
			check(actor.pose == "pierce" and actor.sprite.material == null,"Contact displays the authored punch/kick once: "+str(i)))
		await stage.return_home()
		check(actor.position == actor.home and actor.facing == -1 and actor.pose == "idle","Gang actor returns to its triangle vertex facing left: "+str(i))
		for j in 3:
			check(view.target_at_point(stage.contact(stage.enemies[j])) == j,"Targets remain individually selectable after attack/return: %d/%d" % [i,j])
	check(attack_contacts == 3 and ghost_passes == 3 and view.model.snapshot() == snapshot,"Presentation callbacks and ghosts never mutate combat rules or HP")
	await capture("03-returned")
	app.swap_view()
	await idle()
	check(app.view.model.snapshot() == snapshot and app.view.stage.enemies[2].home.x > app.view.stage.enemies[0].home.x,"View rebuild restores the snapshot and opt-in triangle formation")
	Game.menu()
	await idle()
	check(Game.state == adventure and not Game.training_mode,"Leaving the visual test restores adventure state")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"attackContacts":attack_contacts,"ghostPasses":ghost_passes,"physicalInput":false,"pointerInput":false},"\t"))
	print("GANG ENEMY VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
