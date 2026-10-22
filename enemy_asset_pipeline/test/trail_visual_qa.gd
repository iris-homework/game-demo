extends Node2D
## GPU check of the runtime fixture: mesh, shader, facing and cleanup.
const Fixture = preload("res://enemy_asset_pipeline/test/runtime_tests.gd")
const Actor = preload("res://scripts/combat/pose_actor.gd")
const Catalog = preload("res://enemy_asset_pipeline/runtime/pipeline_catalog.gd")
const Resolver = preload("res://scripts/combat/enemy_visual_resolver.gd")
var failures: Array[String] = []
var checks := 0

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("101923"))
	var factory := Fixture.new()
	var raw: Dictionary = factory._trail_profile()
	var file_path := "user://trail_gpu_fixture.json"
	var file := FileAccess.open(file_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"schemaVersion":1,"profiles":{"trail_actor":raw}}))
	file.close()
	Catalog.set_preview_path(file_path)
	var visual := Resolver.new().resolve({"id":"preview_trail_actor","combatVisualId":"trail_actor"},{})
	var actors: Array[Node2D] = []
	for index in 2:
		var actor := Actor.new()
		add_child(actor)
		actor.setup_enemy(visual,Vector2(350+index*600,350),-1.0 if index == 0 else 1.0)
		actor.set_pose("slash")
		actor.set_process(false)
		actor._process(0.055)
		actors.append(actor)
		verify(factory._visible_mesh_count(actor)>0,"GPU scene has visible trail meshes")
		var title := Label.new()
		title.text = "XSXB 拖尾 · 前后层 · "+("朝左" if index == 0 else "镜像朝右")
		title.position = Vector2(200+index*600,180)
		title.add_theme_font_size_override("font_size",24)
		add_child(title)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	verify(image.save_png("res://enemy_asset_pipeline/test/evidence/godot-trail-gpu.png") == OK,"GPU trail screenshot saved")
	for actor in actors:
		actor._process(0.06)
		verify(factory._all_meshes_hidden(actor),"GPU trail ends and clears")
	Catalog.clear_preview()
	DirAccess.remove_absolute(file_path)
	factory.free()
	var result := FileAccess.open("res://enemy_asset_pipeline/test/evidence/trail-gpu-result.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("PIPELINE_TRAIL_GPU_QA checks=%d failures=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
