extends Node
## Regression for mirrored/affine silhouettes and the real F6 workbench return.
const Ghost = preload("res://scripts/combat/return_ghost_fx.gd")
const OUTPUT := "res://artifacts/qa/return-ghost-transform-2026-10-21"
var bench: Control
var checks := 0
var failures: Array[String] = []
var cycle := ""
var seen_hurt := false
var reveals := 0
var capture_done := false

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func geometry_cases() -> void:
	var source := Sprite2D.new()
	add_child(source)
	var transforms: Array[Transform2D] = [
		Transform2D(Vector2(-0.099,0),Vector2(0,0.099),Vector2(70.29,-122.76)),
		Transform2D(Vector2(0.12,0.03),Vector2(0.02,0.09),Vector2(-85,-110)),
		Transform2D(Vector2(-0.12,0.03),Vector2(0.02,0.09),Vector2(85,-110)),
	]
	for transform_value in transforms:
		source.transform = transform_value
		var ghost := Ghost.new()
		add_child(ghost)
		ghost.setup(source)
		for progress in [0.0,0.5,1.0]:
			ghost.set_progress(progress)
			for index in ghost.echoes.size():
				var echo: Sprite2D = ghost.echoes[index]
				var expected := transform_value
				expected.origin += Vector2(Ghost.OFFSETS[index]*(1.0-progress),0)
				verify(echo.transform.is_equal_approx(expected),"Affine silhouette stays aligned at progress %s: %s" % [progress,transform_value])
		ghost.free()
	source.free()

func observe_phase(value: String) -> void:
	if value != "home_glitch": return
	reveals += 1
	var stage: Control = bench.view.stage
	var ghosts: Array = stage.world.get_children().filter(func(node): return node.get_script() == Ghost)
	verify(ghosts.size() == 2,cycle+": both survivors have silhouettes")
	for actor in [stage.player,stage.enemies[0]]:
		var matches: Array = ghosts.filter(func(node): return node.position.is_equal_approx(actor.home))
		verify(matches.size() == 1,cycle+": silhouette is at actor home")
		if matches.size() != 1: continue
		var ghost: Node2D = matches[0]
		verify(ghost.scale.is_equal_approx(Vector2.ONE*stage.depth_scale(actor.home)),cycle+": same depth scale")
		for index in ghost.echoes.size():
			var echo: Sprite2D = ghost.echoes[index]
			var expected: Transform2D = actor.sprite.transform
			expected.origin += Vector2(Ghost.OFFSETS[index],0)
			verify(echo.transform.is_equal_approx(expected),cycle+": full sprite orientation and foot anchor preserved")
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.10).timeout
		await RenderingServer.frame_post_draw
		verify(get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(cycle+".png")) == OK,cycle+": screenshot")
		capture_done = true

func _process(_delta: float) -> void:
	if is_instance_valid(bench) and is_instance_valid(bench.view) and is_instance_valid(bench.view.stage):
		var expected := "gun_damaged" if cycle.begins_with("ranged") else "damaged"
		if bench.view.stage.player.pose == expected: seen_hurt = true

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit(2))
	geometry_cases()
	bench = preload("res://enemy_asset_pipeline/test/test_workbench.tscn").instantiate()
	add_child(bench)
	while bench.tools_locked(): await get_tree().process_frame
	verify(not Game.save_enabled and bench.test_mode,"isolated F6 test bench")
	bench.view.stage.phase_changed.connect(observe_phase)
	for stance in ["melee","ranged"]:
		cycle = stance+"-hurt-return"
		seen_hurt = false
		capture_done = false
		bench.view.stage.player.set_combat_stance(stance)
		var snapshot: Dictionary = bench.view.model.snapshot()
		verify(await bench.view.preview_action(1,"laser",0),cycle+": actual robot attack preview")
		await get_tree().process_frame
		verify(seen_hurt,cycle+": Noren really showed the damaged pose")
		verify(bench.view.model.snapshot() == snapshot,cycle+": presentation keeps model snapshot unchanged")
		verify(bench.view.stage.world.get_children().filter(func(node): return node.get_script() == Ghost).is_empty(),cycle+": temporary ghosts cleaned")
		if DisplayServer.get_name() != "headless": verify(capture_done,cycle+": captured reveal")
	verify(reveals == 2,"both stance return sequences observed")
	bench.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var mode := "headless" if DisplayServer.get_name() == "headless" else "render"
	FileAccess.open(OUTPUT.path_join(mode+"-result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false},"\t"))
	print("RETURN_GHOST_TRANSFORM checks=%d failures=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
