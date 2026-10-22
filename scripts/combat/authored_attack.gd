extends RefCounted
## The same authored sequence drives previews and production. Never resolves damage.
const Effect := preload("res://scripts/combat/authored_attack_fx.gd")

static func play(stage, attacker, defender, style: String, config: Dictionary, hits: Array, on_hit: Callable) -> void:
	if not attacker.alive or not defender.alive:
		return
	stage.active_attacker = attacker
	stage.active_defender = defender
	stage.active_attack_config = config
	attacker.face_toward(defender.position)
	defender.face_toward(attacker.position)
	var direction: float = 1.0 if defender.position.x >= attacker.position.x else -1.0
	var destination: Vector2 = attacker.position
	var ranged: bool = config.type in ["shoot", "laser"]
	if config.movement == "approach":
		destination = stage.attack_destination(attacker, defender, stage._motion_value(attacker, "reach", 92.0))
		if config.muzzle != Vector2.ZERO:
			# Optional weapon/mouth anchor sets the horizontal contact distance.
			# Keep the feet on the target's depth lane, rather than lifting the actor.
			attacker.set_pose(config.strikePose)
			var offset: Vector2 = stage.world.to_local(attacker.sprite.to_global(config.muzzle)) - attacker.position
			destination.x = contact_point(stage, defender, config).x - offset.x
		stage.frame_attack(attacker, defender, destination)
		stage.set_phase("approach")
		attacker.set_pose("move")
		await stage.approach(attacker, defender, destination)
	else:
		await stage.wide()
		if config.movement == "retreat":
			stage.set_phase("retreat")
			attacker.set_pose("retreat" if attacker.poses.has("retreat") else "move")
			destination.x = clampf(destination.x - direction * stage.RANGED_RETREAT_DISTANCE, 100, 1310)
			await stage.move_actor(attacker, destination, stage.travel_duration(attacker, attacker.position.distance_to(destination)))
	if stage.camera_tween != null and stage.camera_tween.is_running():
		await stage.camera_tween.finished
	for i in hits.size():
		var hit: Dictionary = hits[i]
		var blocked := int(hit.get("blocked", 0)) > 0
		var damage := int(hit.get("damage", 0))
		stage.set_phase("bite_open" if config.type == "bite" else "windup")
		attacker.set_pose(config.windupPose)
		await _wait(stage, config.windup)
		attacker.set_pose(config.strikePose)
		stage.set_phase("bite_close" if config.type == "bite" else ("fire" if ranged else "strike"))
		if style in ["slash", "pierce"]:
			stage.combat_audio.play_cue("slash")
		await _wait(stage, config.impactDelay)
		var point: Vector2 = contact_point(stage, defender, config)
		if ranged:
			var origin := source_point(stage, attacker, config)
			_spawn(stage, origin, "muzzle", config.muzzleTexture, 0.16, attacker)
			stage.set_phase("projectile_flight" if config.type == "shoot" else "laser_grow")
			var flight: float = float(config.flightTime)
			if config.type == "shoot" and flight > 0:
				var projectile = _spawn(stage, origin, "projectile", config.projectileTexture, flight + 0.04, attacker)
				projectile.rotation = (point - origin).angle()
				await stage.create_tween().tween_property(projectile, "position", point, flight).finished
				projectile.queue_free()
			elif config.type == "laser":
				var beam = _spawn(stage, origin, "laser", null, maxf(0.12, flight + 0.12), attacker)
				# Beam coordinates are in the world; avoid scaling the endpoint twice.
				beam.scale = Vector2.ONE
				beam.end = point - origin
				beam.beam_width = maxf(2, attacker.laser_palm_width * absf(attacker.sprite.scale.y) * absf(attacker.scale.y))
				await _wait(stage, flight)
		else:
			# A short release supports single-pose artwork without stretching the PNG.
			await stage.move_actor(attacker, destination + Vector2(direction * 8, 0), 0.035)
		stage.set_phase("impact")
		if config.impactTexture != null:
			_spawn(stage, point, "hit", config.impactTexture, 0.27, defender, attacker)
		elif config.type == "bite":
			_spawn(stage, point, "bite", null, 0.27, defender, attacker)
		elif style in ["slash", "pierce"]:
			stage.show_strike(point, direction, style, blocked)
		else:
			var effect = _spawn(stage, point, "hit", null, 0.24, defender, attacker)
			effect.blocked = blocked
		stage.play_hit_sound(blocked)
		defender.set_pose("block" if blocked else "damaged")
		defender.sprite.modulate = Color(1.6, 1.2, 1.4)
		stage.last_hit_stop = stage._hit_stop(attacker, 0.095)
		stage._pipeline_camera(attacker, direction, 8.0 if damage > 0 else 4.0)
		# The supplied hit is already authoritative. This callback only reveals it.
		on_hit.call(hit, i)
		await _wait(stage, stage.last_hit_stop)
		defender.sprite.modulate = Color.WHITE
		if blocked and damage > 0:
			defender.set_pose("damaged")
		await stage._await_pipeline_pose(attacker)
		stage.set_phase("recover")
		attacker.set_pose(config.recoveryPose)
		if not ranged:
			await stage.move_actor(attacker, destination, maxf(0.001, config.recovery))
		else:
			await _wait(stage, config.recovery)
		await stage._await_pipeline_pose(attacker)
		if bool(hit.get("killed", false)):
			await stage.retire_actor(defender)
			break
		defender.set_pose("idle")
	attacker.set_pose("idle")
	stage.set_phase("idle")

static func source_point(stage, attacker, config: Dictionary) -> Vector2:
	return stage.world.to_local(attacker.sprite.to_global(config.muzzle)) + stage._effect_offset(attacker) * stage.depth_scale(attacker.position)

static func contact_point(stage, defender, config: Dictionary) -> Vector2:
	var point: Vector2 = stage.world.to_local(defender.to_global(config.contact))
	if is_instance_valid(stage.active_attacker):
		point += stage._effect_offset(stage.active_attacker) * stage.depth_scale(defender.position)
	return point

static func _spawn(stage, point: Vector2, mode: String, texture: Texture2D, duration: float, depth_actor, effect_actor = null):
	var effect := Effect.new()
	effect.position = point
	effect.mode = mode
	effect.texture = texture
	effect.duration = duration
	effect.scale = Vector2.ONE * stage.depth_scale(depth_actor.position) * stage._effect_scale(effect_actor if effect_actor != null else depth_actor)
	stage.world.add_child(effect)
	return effect

static func _wait(stage, seconds: float) -> void:
	if seconds > 0:
		await stage.get_tree().create_timer(seconds).timeout
