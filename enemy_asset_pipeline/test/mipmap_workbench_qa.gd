extends Node
## Actual formal workbench rendering with runtime-generated mipmaps; no save/apply.
var OUTPUT := "res://enemy_asset_pipeline/test/evidence/mipmaps"
var bench: Control
var checks := 0
var failures: Array[String] = []
var started := 0

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func unlock(node: Control) -> void:
	var deadline := Time.get_ticks_msec()+30000
	while node.tools_locked():
		if Time.get_ticks_msec() > deadline:
			verify(false,"workbench unlock timeout")
			return
		await get_tree().process_frame
	await get_tree().process_frame

func capture(label: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	verify(get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(label+".png")) == OK,"capture "+label)

func _process(_delta: float) -> void:
	if started > 0 and Time.get_ticks_msec()-started > 90000:
		verify(false,"mipmap QA timeout")
		finish()

func _ready() -> void:
	started = Time.get_ticks_msec()
	var output_env := OS.get_environment("QA_OUT_DIR")
	if not output_env.is_empty(): OUTPUT = output_env
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	bench = preload("res://enemy_asset_pipeline/workbench.tscn").instantiate()
	add_child(bench)
	await unlock(bench)
	verify(bench.character_mipmaps,"formal workbench enables character mipmaps")
	bench.roster.clear()
	bench.roster.append("visual:rogue_drone")
	bench.selected_actor = 1
	await bench.rebuild()
	await unlock(bench)
	var actor: Node2D = bench.view.get_actor(1)
	verify(actor != null and actor.kind == "rogue_drone","rogue drone loaded in actual formal workbench")
	verify(actor.use_mipmapped_textures,"actor uses mipmapped runtime textures")
	verify(actor.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,"sprite uses linear mipmap filtering")
	bench.left_panel.hide()
	bench.right_panel.hide()
	actor.set_mipmap_sampling(false)
	actor.set_pose("idle")
	var off_texture: Texture2D = actor.sprite.texture
	verify(off_texture != null and not off_texture.get_image().has_mipmaps(),"control texture has no mipmaps")
	await capture("rogue-idle-off")
	actor.set_mipmap_sampling(true)
	actor.set_pose("idle")
	var on_texture: Texture2D = actor.sprite.texture
	verify(on_texture != null and on_texture.get_image().has_mipmaps(),"on texture has generated mipmaps")
	await capture("rogue-idle-on")
	for pose in ["move","pierce","damaged"]:
		if not pose in bench.view.available_poses(1): continue
		actor.set_pose(pose)
		verify(actor.sprite.texture != null and actor.sprite.texture.get_image().has_mipmaps(),"mipmaps retained for "+pose)
		await capture("rogue-"+pose+"-on")
	verify(actor.use_mipmapped_textures and actor.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,"filter state survives pose changes")
	finish()

func finish() -> void:
	started = 0
	var mode := "headless" if DisplayServer.get_name() == "headless" else "render"
	var file := FileAccess.open(OUTPUT.path_join(mode+"-result.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false}, "\t"))
	print("MIPMAP_WORKBENCH_QA checks=%d failures=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
