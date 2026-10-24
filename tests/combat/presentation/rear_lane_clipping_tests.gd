extends Node
## Geometry and actual movement only; headless, no physical input or saves.
const Stage = preload("res://scripts/combat/test_stage.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func body_visible(stage, actor) -> bool:
	var body: Rect2 = actor.get_global_transform() * actor.target_bounds
	return stage.get_global_rect().encloses(body)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://rear_lane_unused.json"
	Game.meta_path = "user://rear_lane_meta_unused.json"
	var resolver := EnemyVisualResolver.new()
	var visuals: Array[EnemyVisualResolver.Visual] = []
	for i in 3:
		var visual := resolver.resolve({"id":"qa_henchman", "combatVisualId":"gang_henchman"},{})
		# Keep this clipping regression's original body geometry independent of the art fixture.
		visual.target_bounds = Rect2(-58,-130,116,145)
		visuals.append(visual)
	for feet_y in [557.0, 577.0, 637.0]:
		var stage = Stage.new()
		add_child(stage)
		stage.setup(feet_y, visuals)
		stage.set_process(false)
		var attacker = stage.enemies[0]
		attacker.position = Vector2(1000, stage.floor_y-30)
		stage.enemies[1].position = Vector2(750, stage.floor_y-30)
		stage.enemies[2].position = Vector2(750, stage.floor_y+100)
		var destination: Vector2 = stage.attack_destination(attacker, stage.player, 92)
		var path: Array[Vector2] = stage.approach_path(attacker, stage.player, destination)
		check(path.size() == 4 and is_equal_approx(path[1].y,stage.floor_y-165), "Fixture forces a rear-lane detour")
		var old_clip := Rect2(0,270,1440,420)
		attacker.position = path[1]
		stage.update_depth()
		stage._update_camera()
		var body: Rect2 = attacker.get_global_transform() * attacker.target_bounds
		check(old_clip.encloses(body) == (feet_y == 637.0), "Old clip reproduces clipping at high lanes; low lane is the control")
		check(body_visible(stage,attacker), "Wide view contains rear-lane body")
		attacker.position = path[0]
		stage.frame_attack(attacker,stage.player,destination)
		var all_visible := true
		# Move along the actual Tween path while the attack camera also interpolates.
		stage.approach(attacker,stage.player,destination)
		var elapsed := 0.0
		while elapsed < 1.5:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			stage.update_depth()
			stage._update_camera()
			all_visible = all_visible and body_visible(stage,attacker) and body_visible(stage,stage.player)
		check(all_visible, "Attacker and defender remain inside clip throughout approach")
		check(attacker.position.is_equal_approx(destination), "Approach reaches contact")
		check(is_equal_approx(stage.get_global_rect().end.y,690), "Lower clip keeps hand area protected")
		check(stage.actors_root.y_sort_enabled, "Characters retain foot-based occlusion")
		check(stage.player.to_global(Vector2.ZERO).y < 690, "Player remains in battle region")
		stage.queue_free()
		await get_tree().process_frame
	print("REAR LANE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
