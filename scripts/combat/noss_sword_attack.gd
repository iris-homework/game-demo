extends RefCounted
## Calibrated left-facing sword PNG. Presentation consumes already-resolved hits.
const Images := preload("res://enemy_asset_pipeline/runtime/pipeline_image.gd")
const TEXTURE := "res://assets/combat_test/noss_boss/noss_vfx_projectile.png"
const MUZZLES := {"noss":Vector2(145,275), "noss_phase2":Vector2(245,435)}
const FLIGHT_TIME := 0.16
const LightEffect := preload("res://scripts/combat/noss_light_effect.gd")

static func effect(stage, mode: String, point: Vector2, direction: Vector2, depth: float, duration: float):
	var fx := LightEffect.new()
	fx.mode = mode
	fx.position = point
	fx.axis = direction
	fx.visual_scale = depth
	fx.duration = duration
	stage.world.add_child(fx)
	return fx

static func play(stage, attacker, defender, hits: Array, on_hit: Callable) -> void:
	if not attacker.alive or not defender.alive: return
	stage.active_attacker = attacker
	stage.active_defender = defender
	attacker.face_toward(defender.position)
	defender.face_toward(attacker.position)
	await stage.wide()
	var texture := Images.load_texture(TEXTURE)
	for index in hits.size():
		var hit: Dictionary = hits[index]
		stage.set_phase("windup")
		attacker.set_pose("shoot")
		await stage.get_tree().create_timer(0.24).timeout
		var origin: Vector2 = stage.world.to_local(attacker.sprite.to_global(MUZZLES.get(attacker.kind, Vector2.ZERO)))
		var target: Vector2 = stage.world.to_local(defender.to_global(defender.target_bounds.get_center()))
		var direction := (target-origin).normalized()
		var depth: float = stage.depth_scale(attacker.position)
		var projectile := Sprite2D.new()
		projectile.name = "NossLightSword"
		projectile.add_to_group("noss_light_sword")
		projectile.texture = texture
		projectile.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		projectile.z_index = 15
		# The selected PNG points LEFT. Its rotation must remove PI, rather than
		# use the usual right-facing projectile convention and fly hilt-first.
		projectile.rotation = direction.angle()-PI
		var half_length := 83.0*depth
		var texture_width := float(texture.get_width()) if texture != null else 2172.0
		projectile.scale = Vector2.ONE*(180.0/maxf(1.0,texture_width))*depth
		projectile.position = origin+direction*half_length
		stage.world.add_child(projectile)
		effect(stage,"muzzle",origin,direction,depth,0.24)
		var trail := LightEffect.new()
		trail.mode = "trail"
		trail.duration = FLIGHT_TIME+0.24
		trail.projectile = projectile
		trail.axis = direction
		trail.tail_offset = -direction*half_length
		trail.visual_scale = depth
		stage.world.add_child(trail)
		stage.set_phase("projectile_flight")
		await stage.create_tween().tween_property(projectile,"position",target-direction*half_length,FLIGHT_TIME).finished
		projectile.queue_free()
		effect(stage,"impact",target,direction,stage.depth_scale(defender.position),0.30)
		stage.set_phase("impact")
		var blocked := int(hit.get("blocked",0)) > 0
		var damage := int(hit.get("damage",0))
		stage.play_hit_sound(blocked)
		defender.set_pose("damaged" if damage > 0 else "block")
		defender.sprite.modulate = Color(1.5,1.4,1.1)
		stage.last_hit_stop = stage._hit_stop(attacker,0.10)
		stage._pipeline_camera(attacker,-1.0 if direction.x < 0 else 1.0,7.0 if damage > 0 else 4.0)
		# Reveal the model's result once at contact; never apply damage here.
		on_hit.call(hit,index)
		await stage.get_tree().create_timer(stage.last_hit_stop).timeout
		defender.sprite.modulate = Color.WHITE
		stage.set_phase("recover")
		await stage.get_tree().create_timer(0.16).timeout
		if bool(hit.get("killed",false)):
			await stage.retire_actor(defender)
			break
		defender.set_pose("idle")
	attacker.set_pose("idle")
	stage.set_phase("idle")
