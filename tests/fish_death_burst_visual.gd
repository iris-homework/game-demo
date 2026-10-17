extends "res://tests/fish_death_visual.gd"
const Burst = preload("res://scripts/combat/fish_death_burst_fx.gd")
var burst_count := 0
var spit_count := 0
var scenario := "melee"

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	# Capture even when the test window is covered by the chat window on macOS.
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(output+name+".png")

func on_effect(node: Node) -> void:
	if node.get_script() == Burst: burst_count += 1
	if node.get_script() == preload("res://scripts/combat/pollution_spit_fx.gd"): spit_count += 1

func on_phase(value: String) -> void:
	super.on_phase(value)
	if value != "fish_death_burst": return
	var view = app.view
	check(Game.battle_busy,"Death burst keeps combat locked")
	var effects := get_tree().get_nodes_in_group("fish_death_burst_fx")
	check(effects.size() == 1,"Exactly one full-body death burst")
	check(view.shown_player_pollution >= 5,"Death pollution already displayed once before burst")
	var snapshot: Dictionary = view.model.snapshot()
	if scenario in ["melee","ranged"]:
		await get_tree().create_timer(0.10).timeout
		await shot(scenario+"-01-body-burst")
		check(view.model.snapshot() == snapshot,"Explosion does not apply another model effect")
		await get_tree().create_timer(0.10).timeout
		await shot(scenario+"-02-green-splash")

func prepare_case(name: String) -> void:
	scenario = name
	print("FISH DEATH BURST case: "+name)
	await install_fish()
	burst_count = 0
	spit_count = 0
	app.view.stage.world.child_entered_tree.connect(on_effect)

func sync_view() -> void:
	app.view.shown_enemies = app.view.model.enemies.duplicate(true)
	app.view.refresh_resources()
	app.view.refresh_enemy_hud()
	app.view.commit()

func verify_retired() -> void:
	await idle()
	var view = app.view
	check(burst_count == 1,"Fish death produces one burst")
	check(not view.stage.enemies[0].alive and is_zero_approx(view.stage.enemies[0].modulate.a),"Dead fish body remains hidden")
	check(view.stage.enemies[1].alive,"Other fish survives independently")
	check(get_tree().get_nodes_in_group("fish_death_burst_fx").is_empty(),"All burst fragments and water release")
	var snapshot: Dictionary = view.model.snapshot()
	await view.stage.retire_actor(view.stage.enemies[0])
	check(burst_count == 1 and view.model.snapshot() == snapshot,"Repeated death presentation cannot burst or apply status again")
	await shot(scenario+"-03-complete")

func _ready() -> void:
	output = "res://artifacts/qa/fish-death-burst-2026-10-17/"+("headless/" if DisplayServer.get_name() == "headless" else "render/")
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = "user://fish_death_burst_unused.json"
	Game.meta_path = "user://fish_death_burst_meta_unused.json"
	Game.state = Game.initial_state()
	get_tree().create_timer(100).timeout.connect(func(): get_tree().quit(2))
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B11")
	await idle()
	for stance in ["melee","ranged"]:
		await prepare_case(stance)
		app.view.model.stance = stance
		app.view.stage.player.set_combat_stance(stance)
		app.view.model.enemies[0].hp = 6
		sync_view()
		app.view.select_card("card_000")
		await app.view.play_selected(0)
		check(app.view.shown_player_pollution == 5 and spit_count == 0,"Death adds five stacks without a mouth-to-player spit")
		await verify_retired()
	# Restored dead snapshots do not replay the death burst.
	var saved: Dictionary = app.view.model.snapshot()
	app.swap_view()
	await idle()
	check(app.view.model.snapshot() == saved and not app.view.stage.enemies[0].alive,"Restore preserves dead fish and combat snapshot")
	check(get_tree().get_nodes_in_group("fish_death_burst_fx").is_empty(),"Restore does not replay explosion")
	await prepare_case("parry")
	app.view.model.enemies[0].hp = 1
	app.view.model.block = 6
	app.view.model.parry = 2
	sync_view()
	await app.view.end_turn_pressed()
	check(app.view.shown_player_pollution == 8 and spit_count == 1,"Parry death adds five; surviving fish still spits three")
	await verify_retired()
	await prepare_case("status")
	app.view.model.enemies[0].hp = 1
	app.view.model.enemies[0].intent = {"type":"wait","amount":0}
	app.view.model.buffs.apply(app.view.model,"pollution",1,0)
	sync_view()
	await app.view.end_turn_pressed()
	check(app.view.shown_player_pollution == 8 and spit_count == 1,"Status death adds five; surviving fish still spits three")
	await verify_retired()
	# The last enemy's burst must complete before training exits.
	await prepare_case("last-enemy")
	app.view.model.enemies[0].hp = 0
	app.view.stage.enemies[0].alive = false
	app.view.stage.enemies[0].modulate.a = 0
	app.view.model.enemies[1].hp = 6
	sync_view()
	app.view.select_card("card_000")
	await app.view.play_selected(1)
	await idle()
	check(burst_count == 1 and not Game.training_mode,"Last enemy bursts once and then exits training")
	check(get_tree().get_nodes_in_group("fish_death_burst_fx").is_empty(),"Victory leaves no burst nodes")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false},"\t"))
	rules.fixtures.free()
	rules.free()
	print("FISH DEATH BURST: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
