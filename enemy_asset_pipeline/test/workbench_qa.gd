extends Node
## Program-driven rendering of real backend output; no physical input claim.
var bench: Control
var checks := 0
var failures: Array[String] = []
var started := 0
const OUTPUT := "res://enemy_asset_pipeline/test/evidence"

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _process(_delta: float) -> void:
	if started > 0 and Time.get_ticks_msec()-started > 90000:
		verify(false,"Pipeline QA timeout")
		finish()

func idle() -> void:
	while bench.tools_locked(): await get_tree().process_frame
	await get_tree().process_frame

func shot(name_value: String) -> void:
	await RenderingServer.frame_post_draw
	verify(get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(name_value+".png")) == OK,"capture "+name_value)

func _ready() -> void:
	started = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	bench = preload("res://enemy_asset_pipeline/test/test_workbench.tscn").instantiate()
	add_child(bench)
	await idle()
	verify(bench.test_mode,"test scene selects isolated service")
	verify(not Game.save_enabled and Game.training_mode,"F6 starts unsaved battle directly")
	verify(bench.view.stage.player != null and bench.view.stage.enemies.size() == 1,"actual combat is visible")
	await bench.refresh_draft()
	await idle()
	verify(bench.roster[0] == "visual:gang_henchman","browser selection loads matching enemy")
	var actor: Node2D = bench.view.get_actor(1)
	verify(actor.pipeline_active,"compiled pipeline profile is active")
	verify(actor.pipeline_shadow["size"].is_equal_approx(Vector2(36,10)),"backend shadow calibration reaches actor")
	verify(is_equal_approx(actor.sprite.transform.x.length(),0.107),"native saved group scale reaches Godot without double scale")
	verify(bench.view.available_poses(1).has("pierce"),"authored actions appear in workbench")
	await shot("godot-draft")
	var snapshot: Dictionary = bench.view.model.snapshot()
	verify(await bench.view.preview_action(1,"pierce",0),"compiled enemy completes attack preview")
	await idle()
	verify(bench.view.model.snapshot() == snapshot,"attack preview does not resolve damage")
	verify(actor.position.is_equal_approx(actor.home),"authored attack returns home")
	verify(bench.view.replace_test_hand(["noren_01"]),"production test card installed")
	var hp: int = bench.view.model.enemies[0].hp
	bench.view.select_card(bench.view.model.hand[0])
	await bench.view.play_selected(0)
	await idle()
	verify(bench.view.model.enemies[0].hp == hp-6,"real card still resolves exactly one production hit")
	await bench.refresh_published()
	await idle()
	verify(not bench.view.get_actor(1).pipeline_active,"rollback restores isolated published fallback")
	verify(bench.view.get_actor(1).kind == "gang_henchman","clearing draft keeps repaired original enemy artwork")
	verify(not Game.save_enabled,"formal saving stays disabled")
	await shot("godot-workbench")
	finish()

func finish() -> void:
	started = 0
	var file := FileAccess.open(OUTPUT.path_join("workbench-result.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"program-driven real backend profile/rendering/card integration"},"\t"))
	print("PIPELINE_WORKBENCH_QA checks=%d failures=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
