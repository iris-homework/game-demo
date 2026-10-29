extends Node
## Presentation-only idle checks. Run in an isolated QA project/user directory.
const Actor = preload("res://scripts/combat/pose_actor.gd")
const Pipeline = preload("res://enemy_asset_pipeline/runtime/pipeline_catalog.gd")
const Runtime = preload("res://enemy_asset_pipeline/runtime/pipeline_runtime_profile.gd")
var checks := 0
var failures := 0

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func actor_for(id: String, origin := Vector2(980,460)):
	var visual := Game.enemy_combat_visual({"id":"preview_"+id,"combatVisualId":id})
	var actor := Actor.new()
	add_child(actor)
	actor.setup_enemy(visual,origin,-1)
	actor.set_process(false)
	return actor

func advance(actor, seconds: float) -> void:
	for i in int(ceil(seconds*60.0)):
		actor._process(1.0/60.0)

func check_catalog() -> void:
	var ids: Array = Game.enemy_visuals.catalog.keys()
	for id in Pipeline.get_profiles():
		if not ids.has(id): ids.append(id)
	for id in ids:
		var actor = actor_for(id)
		var rest: Transform2D = actor.sprite.transform
		var root_before: Transform2D = actor.transform
		var bounds_before: Rect2 = actor.target_bounds
		var material_before = actor.sprite.material
		var texture_before = actor.sprite.texture
		var anchor: Vector2 = rest.affine_inverse()*Vector2.ZERO
		advance(actor,0.9)
		var first: Transform2D = actor.sprite.transform
		advance(actor,0.8)
		check(not actor.sprite.transform.is_equal_approx(first),"Idle visibly changes over time: "+id)
		check(actor.transform == root_before and actor.home == root_before.origin and actor.target_bounds == bounds_before,"Idle preserves position, home and targeting: "+id)
		check(actor.sprite.material == material_before and actor.sprite.texture == texture_before,"Idle retains authored material and texture: "+id)
		if id not in ["beacon_jellyfish","rogue_drone"]:
			check((actor.sprite.transform*anchor).length() < 0.02,"Grounded idle keeps calibrated soles planted: "+id)
		else:
			check((actor.sprite.transform*anchor).length() < 8.0,"Hover displacement stays close to original position: "+id)
		if id == "robot":
			var local_motion: Transform2D = actor.sprite.transform*rest.affine_inverse()
			check(is_equal_approx(local_motion.x.x,1.0) and is_equal_approx(local_motion.y.y,1.0),"Robot does not stretch like a soft body")
		actor.face_toward(actor.position+Vector2(100,0))
		advance(actor,0.5)
		check(actor.facing == 1 and actor.sprite.transform.determinant()*rest.determinant() < 0,"Idle preserves a requested facing change: "+id)
		for requested in ["damaged","pierce","move","missing_action"]:
			actor.set_pose(requested)
			var action_rest: Transform2D = actor.sprite.transform
			advance(actor,0.1)
			check(actor._idle_motion_transform.is_equal_approx(Transform2D.IDENTITY),"No idle overlay during requested action, including fallback: "+id+"/"+requested)
			if actor.pipeline_frames.get(actor.pose,[]).size() <= 1:
				check(actor.sprite.transform.is_equal_approx(action_rest),"Single-frame action remains calibrated: "+id+"/"+requested)
		actor.set_pose("idle")
		advance(actor,0.8)
		check(not actor._idle_motion_transform.is_equal_approx(Transform2D.IDENTITY),"Idle resumes after action: "+id)
		actor.alive = false
		advance(actor,0.2)
		check(actor._idle_motion_transform.is_equal_approx(Transform2D.IDENTITY),"Dead enemies have no idle motion: "+id)
		actor.free()

func check_independence() -> void:
	var first = actor_for("gang_henchman",Vector2(980,350))
	var second = actor_for("gang_henchman",Vector2(980,550))
	advance(first,1.2)
	advance(second,1.2)
	check(not first.sprite.transform.is_equal_approx(second.sprite.transform),"Same-type enemies at different slots do not breathe in lockstep")
	first.free()
	second.free()
	var player := Actor.new()
	add_child(player)
	player.setup_player(Vector2(400,450),1)
	player.set_process(false)
	var before := player.sprite.transform
	advance(player,2.0)
	check(player.sprite.transform.is_equal_approx(before),"Player idle is unchanged")
	player.free()
	seed(10529)
	var expected := randi()
	seed(10529)
	var actor = actor_for("fish")
	advance(actor,4.0)
	check(randi() == expected,"Idle setup and updates never consume combat random numbers")
	actor.free()

func check_authored_frames_and_attachments() -> void:
	var actor = actor_for("gang_henchman")
	var rest: Transform2D = actor.sprite.transform
	var frame := Runtime.Frame.new()
	frame.texture = actor.sprite.texture
	# The actor faces right in source space; frame transform is before mirroring.
	frame.transform = Transform2D(Vector2(-1,0),Vector2(0,1),Vector2.ZERO)*rest
	frame.duration = 100.0
	frame.loop = true
	var attachment := Runtime.Attachment.new()
	attachment.texture = actor.sprite.texture
	attachment.offset = Vector2(12,-20)
	attachment.visual_scale = Vector2(0.2,0.2)
	frame.attachments = [attachment]
	actor.pipeline_frames.idle = [frame]
	actor.set_pose("idle")
	var attached: Node2D = actor.attachment_above.get_child(0)
	var relative_before: Transform2D = actor.sprite.global_transform.affine_inverse()*attached.global_transform
	advance(actor,1.1)
	var relative_after: Transform2D = actor.sprite.global_transform.affine_inverse()*attached.global_transform
	check(relative_before.is_equal_approx(relative_after),"Authored attachment follows idle deformation without sliding")
	actor.set_mipmap_sampling(false)
	attached = actor.attachment_above.get_child(0)
	check((actor.sprite.global_transform.affine_inverse()*attached.global_transform).is_equal_approx(relative_before),"Texture sampling refresh does not double-apply motion to attachments")
	actor.face_toward(actor.position+Vector2(100,0))
	advance(actor,0.4)
	attached = actor.attachment_above.get_child(0)
	check((actor.sprite.global_transform.affine_inverse()*attached.global_transform).is_equal_approx(relative_before),"Attachment remains aligned after facing change")
	var second_frame := Runtime.Frame.new()
	second_frame.texture = frame.texture
	second_frame.transform = frame.transform
	second_frame.duration = 100.0
	second_frame.loop = true
	actor.pipeline_frames.idle = [frame,second_frame]
	actor.set_pose("idle")
	var animated_rest: Transform2D = actor.sprite.transform
	advance(actor,2.0)
	check(actor.sprite.transform.is_equal_approx(animated_rest) and actor._idle_motion_transform.is_equal_approx(Transform2D.IDENTITY),"Authored multi-frame idle is not deformed a second time")
	actor.free()

func _ready() -> void:
	if not OS.get_user_data_dir().to_lower().contains("qa"):
		push_error("Enemy idle tests require an isolated QA user directory")
		get_tree().quit(2)
		return
	Game.save_enabled = false
	Game.save_path = "user://idle_unused.json"
	Game.meta_path = "user://idle_meta_unused.json"
	var before: Dictionary = Game.state.duplicate(true)
	check_catalog()
	check_independence()
	check_authored_frames_and_attachments()
	check(Game.state == before,"Actor animation leaves the game state unchanged")
	var output := OS.get_environment("QA_OUT_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false,"gpu":false},"\t"))
	print("ENEMY IDLE: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
