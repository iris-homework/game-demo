extends "res://tests/combat/presentation/enemy_idle_motion_tests.gd"
## Material/lifecycle checks only. Tentacle shape and GPU pixels are separate QA.

func tentacle_strength(actor) -> float:
	var material = actor.sprite.material
	if material == null or not material is ShaderMaterial:
		return 0.0
	if material.shader == null or not material.shader.resource_path.ends_with("jellyfish_idle.gdshader"):
		return 0.0
	return float(material.get_shader_parameter("strength"))

func check_jellyfish_lifecycle() -> void:
	var actor = actor_for("beacon_jellyfish")
	var material = actor.sprite.material
	check(material is ShaderMaterial and material.shader.resource_path == "res://shaders/jellyfish_idle.gdshader","Authored jellyfish idle binds the dedicated tentacle shader")
	if not material is ShaderMaterial:
		actor.free()
		return
	var root_before: Transform2D = actor.transform
	var target_before: Rect2 = actor.target_bounds
	var source_texture: Texture2D = actor.pipeline_frames.idle[0].texture
	check(is_zero_approx(tentacle_strength(actor)),"New idle starts without a deformation jump")
	advance(actor,0.2)
	var partial := tentacle_strength(actor)
	check(partial > 0.0 and partial < 1.0,"Tentacle motion eases into the existing idle transition")
	var time_before := float(material.get_shader_parameter("motion_time"))
	advance(actor,0.4)
	check(is_equal_approx(tentacle_strength(actor),1.0) and float(material.get_shader_parameter("motion_time")) > time_before,"Tentacles reach full motion and keep advancing")
	check(actor.transform == root_before and actor.target_bounds == target_before,"Tentacles do not move the actor or target bounds")
	actor.set_mipmap_sampling(false)
	check(actor.sprite.texture == source_texture and actor.sprite.material == material,"Tentacles retain the authored image through texture sampling refresh")
	actor.face_toward(actor.position+Vector2(100,0))
	check(actor.sprite.material == material and tentacle_strength(actor) > 0.0,"Changing facing retains the active material")
	for requested in ["pierce","damaged","move","missing_action"]:
		actor.set_pose(requested)
		check(is_zero_approx(tentacle_strength(actor)),"Tentacles stop immediately for action: "+requested)
		advance(actor,0.5)
		check(is_zero_approx(tentacle_strength(actor)),"Action playback does not resume tentacles: "+requested)
		actor.set_pose("idle")
		check(is_zero_approx(tentacle_strength(actor)),"Returning from action starts smoothly: "+requested)
		advance(actor,0.5)
		check(tentacle_strength(actor) > 0.0,"Tentacles resume on idle: "+requested)
	actor.hide()
	advance(actor,0.1)
	check(is_zero_approx(tentacle_strength(actor)),"Hidden actors stop tentacle motion")
	actor.show()
	advance(actor,0.5)
	actor.modulate.a = 0.4
	advance(actor,0.1)
	check(is_zero_approx(tentacle_strength(actor)),"Return reveal does not deform a partly transparent actor")
	actor.modulate.a = 1.0
	advance(actor,0.5)
	check(tentacle_strength(actor) > 0.0,"Full visibility restores tentacle motion")
	actor.alive = false
	check(is_zero_approx(tentacle_strength(actor)),"Death stops tentacles immediately")
	advance(actor,0.5)
	check(is_zero_approx(tentacle_strength(actor)),"Dead actor remains still")
	actor.free()

func check_material_isolation() -> void:
	var first = actor_for("beacon_jellyfish",Vector2(980,350))
	var second = actor_for("beacon_jellyfish",Vector2(980,550))
	check(first.sprite.material != second.sprite.material,"Each jellyfish owns its own material parameters")
	advance(first,0.5)
	check(tentacle_strength(first) > 0.0 and is_zero_approx(tentacle_strength(second)),"Advancing one jellyfish does not animate another")
	var idle_frames: Array = first.pipeline_frames.idle.duplicate()
	first.pipeline_frames.idle = [idle_frames[0],idle_frames[0]]
	first.set_pose("idle")
	advance(first,0.6)
	check(is_zero_approx(tentacle_strength(first)),"Authored multi-frame idle bypasses procedural tentacles")
	var replacement := Runtime.Frame.new()
	replacement.texture = ImageTexture.create_from_image(idle_frames[0].texture.get_image())
	replacement.transform = idle_frames[0].transform
	replacement.duration = 100.0
	first.pipeline_frames.idle = [replacement]
	first.set_pose("idle")
	advance(first,0.6)
	check(is_zero_approx(tentacle_strength(first)),"Replacement artwork does not inherit masks calibrated for the original illustration")
	first.free()
	second.free()
	for id in ["fish","robot","pruning_hound","dancer_black"]:
		var other = actor_for(id)
		var before = other.sprite.material
		advance(other,0.7)
		check(other.sprite.material == before and is_zero_approx(tentacle_strength(other)),"Other enemy material is unchanged: "+id)
		other.free()
	var player := Actor.new()
	add_child(player)
	player.setup_player(Vector2(400,450),1)
	player.set_process(false)
	var before = player.sprite.material
	advance(player,0.7)
	check(player.sprite.material == before and is_zero_approx(tentacle_strength(player)),"Player material is unchanged")
	player.free()

func _ready() -> void:
	if not OS.get_user_data_dir().to_lower().contains("qa"):
		push_error("Jellyfish idle tests require an isolated QA user directory")
		get_tree().quit(2)
		return
	Game.save_enabled = false
	Game.save_path = "user://jellyfish_idle_unused.json"
	Game.meta_path = "user://jellyfish_idle_meta_unused.json"
	var before: Dictionary = Game.state.duplicate(true)
	check_jellyfish_lifecycle()
	check_material_isolation()
	check(Game.state == before,"Tentacle animation leaves game state unchanged")
	var output := OS.get_environment("QA_OUT_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false,"gpu":false},"\t"))
	print("JELLYFISH IDLE: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
