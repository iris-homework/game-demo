extends Node
## Imported source PNGs in the actual F6 test bench; no production save writes.
const OUTPUT := "res://enemy_asset_pipeline/test/evidence/auto-discovery"
var bench: Control
var checks := 0
var failures: Array[String] = []

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	verify(get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(label+".png")) == OK,"capture "+label)

func idle() -> void:
	while bench.tools_locked(): await get_tree().process_frame
	await get_tree().process_frame

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	bench = preload("res://enemy_asset_pipeline/test/test_workbench.tscn").instantiate()
	add_child(bench)
	await idle()
	verify(bench.test_mode and not Game.save_enabled,"isolated F6 workbench")
	await bench.refresh_draft()
	await idle()
	verify(bench.roster[0] == "visual:warden_shield","imported shield character selected by draft")
	var actor: Node2D = bench.view.get_actor(1)
	verify(actor.pipeline_active and actor.kind == "warden_shield","pipeline actor uses discovered source artwork")
	for pose in ["idle","move","pierce","damaged"]:
		verify(bench.view.available_poses(1).has(pose),"discovered action available: "+pose)
		actor.set_pose(pose)
		verify(actor.sprite.texture != null,"PNG loaded: "+pose)
		verify(actor.sprite.transform.x.length() > 0.0 and actor.sprite.transform.y.length() > 0.0,"calibration applied: "+pose)
		await shot("shield-"+pose)
	actor.set_pose("idle")
	var snapshot: Dictionary = bench.view.model.snapshot()
	for action in ["move","pierce","damaged"]:
		verify(await bench.view.preview_action(1,action,0),"imported action presentation completed: "+action)
		await idle()
		verify(bench.view.model.snapshot() == snapshot,"presentation does not resolve damage: "+action)
		verify(actor.position.is_equal_approx(actor.home),"actor returns home: "+action)
	verify(actor.hit_effect_texture != null,"discovered VFX is available as an effect asset")
	await shot("shield-workbench")
	bench.queue_free()
	await get_tree().process_frame
	var mode := "headless" if DisplayServer.get_name() == "headless" else "render"
	FileAccess.open(OUTPUT.path_join("workbench-"+mode+"-result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false},"\t"))
	print("ASSET_SCAN_WORKBENCH checks=%d failures=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
