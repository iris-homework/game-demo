extends Control
## Clipped presentation world. No model, saves, card data or HUD are mutated here.
signal phase_changed(phase: String)
const Actor = preload("res://scripts/combat/pose_actor.gd")
const ReturnGhost = preload("res://scripts/combat/return_ghost_fx.gd")
const NeonSlash = preload("res://scripts/combat/prismatic_slash_fx.gd")
const NorenSlash = preload("res://scripts/combat/noren_slash_fx.gd")
const DancerStrike = preload("res://scripts/combat/dancer_strike_fx.gd")
const GunBurst = preload("res://scripts/combat/gun_burst_fx.gd")
const PalmLaser = preload("res://scripts/combat/palm_laser_fx.gd")
const BiteHit = preload("res://scripts/combat/bite_hit_fx.gd")
const PollutionSpit = preload("res://scripts/combat/pollution_spit_fx.gd")
const FishDeathBurst = preload("res://scripts/combat/fish_death_burst_fx.gd")
const CardGainFX = preload("res://scripts/combat/card_gain_fx.gd")
const AuthoredAttack := preload("res://scripts/combat/authored_attack.gd")
const PipelineCatalogScript := preload("res://enemy_asset_pipeline/runtime/pipeline_catalog.gd")
const ACTOR_SCALE := 1.2544
const ATTACK_ZOOM_FACTOR := 0.9
const RANGED_RETREAT_DISTANCE := 280.0
const RANGED_HIT_STOP := 0.12
const RANGED_BLOCK_STOP := 0.09
const GROUND_CLEARANCE := Vector2(70,45)*ACTOR_SCALE
var world := Node2D.new()
var actors_root := Node2D.new()
var player: Node2D
var enemies: Array[Node2D] = []
var floor_y := 307.0
var zoom := 1.0
var focus_x := 720.0
var focus_y := 272.0
var active_attacker: Node2D
var active_defender: Node2D
var active_attack_config: Dictionary = {}
var shake := Vector2.ZERO
var phase := "idle"
var shake_time := 0.0
var shake_duration := 0.0
var shake_strength := 0.0
var shake_direction := 1.0
var impact_zoom := 1.0
var last_hit_stop := 0.0
var camera_tween: Tween
var sound := AudioStreamPlayer.new()
var audio_rate := 22050
var combat_audio := preload("res://scripts/combat/combat_audio.gd").new()
var scenery: TextureRect
var scenery_base_rect := Rect2()
var dancer_duet := false
var dancer_lights: Node2D

func set_dancer_duet(enemy_visuals: Array[EnemyVisualResolver.Visual]) -> void:
	# Called behind the blackout after the model has committed its second phase.
	dancer_duet = true
	for actor in enemies:
		actors_root.remove_child(actor)
		actor.queue_free()
	enemies.clear()
	player.home = Vector2(720, floor_y-30)
	player.position = player.home
	player.facing = 1.0
	player.set_pose("idle")
	# Spread both dancers along the player's horizontal foot line.
	var black_home: Vector2 = player.home + Vector2(420, 0)
	var white_home := Vector2(2.0 * player.home.x - black_home.x, black_home.y)
	for i in enemy_visuals.size():
		var actor := Actor.new()
		actors_root.add_child(actor)
		actor.setup_enemy(enemy_visuals[i], black_home if i == 0 else white_home, -1.0 if i == 0 else 1.0)
		enemies.append(actor)
	if not is_instance_valid(dancer_lights):
		dancer_lights = preload("res://scripts/combat/dancer_spotlights.gd").new()
		dancer_lights.name = "DancerSpotlights"
		dancer_lights.z_index = -1
		world.add_child(dancer_lights)
	dancer_lights.actors.assign([enemies[1], player, enemies[0]])
	zoom = 1.0
	focus_x = 720
	focus_y = floor_y-35
	update_depth()
	_update_camera()

func setup(feet_y: float, enemy_visuals: Array[EnemyVisualResolver.Visual], scenery_texture: Texture2D = null, ground_start: float = 0.5) -> void:
	# This is the new-battle boundary. Refresh before the player is created so
	# Noren and any lazily resolved actors use the just-applied catalog. Existing
	# Visual instances already owned by a running battle are not touched.
	PipelineCatalogScript.refresh()
	var count := enemy_visuals.size()
	# Rear-lane detours need headroom above the old y=270 cut line.
	# Keep the lower edge at 690 so actors/effects stay out of the hand area.
	position = Vector2(0,160)
	size = Vector2(1440,530)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	floor_y = feet_y-position.y
	add_child(world)
	focus_y = floor_y-35
	if scenery_texture != null:
		setup_scenery(scenery_texture,ground_start)
	else:
		var ground := preload("res://scripts/combat/depth_floor.gd").new()
		ground.z_index = -2
		ground.baseline = floor_y
		world.add_child(ground)
	actors_root.y_sort_enabled = true
	world.add_child(actors_root)
	player = Actor.new()
	actors_root.add_child(player)
	player.setup_player(Vector2(405,floor_y-30),1.0)
	for i in count:
		var actor := Actor.new()
		actors_root.add_child(actor)
		actor.setup_enemy(enemy_visuals[i],enemy_home(i,count,enemy_visuals[i].formation_slot),-1.0)
		enemies.append(actor)
		if count > 1:
			var marker := Label.new()
			marker.text = "%02d" % (i+1)
			marker.position = Vector2(20,3)
			marker.add_theme_font_size_override("font_size",13)
			marker.modulate = Color("8babb8")
			actor.add_child(marker)
	update_depth()
	sound.bus = "SFX"
	add_child(sound)
	sound.volume_db = -16
	add_child(combat_audio)
	_update_camera()

func setup_scenery(texture: Texture2D, ground_start: float) -> void:
	# Place the artwork horizon behind the furthest depth lane, preserving aspect ratio.
	var ground_line := position.y+floor_y-155.0
	var ground_uv := clampf(ground_start,0.1,0.9)
	var image_size := texture.get_size()
	var image_scale := maxf(1440.0/image_size.x,maxf(ground_line/(ground_uv*image_size.y),(900.0-ground_line)/((1.0-ground_uv)*image_size.y)))
	var dimensions := image_size*image_scale
	scenery_base_rect = Rect2(Vector2((1440.0-dimensions.x)*0.5,ground_line-ground_uv*dimensions.y),dimensions)
	scenery = TextureRect.new()
	scenery.name = "BattleScenery"
	scenery.texture = texture
	scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scenery.z_index = -2
	# Full canvas sibling avoids seams at the actor stage's clipping boundaries.
	get_parent().add_child(scenery)

func _exit_tree() -> void:
	if is_instance_valid(scenery): scenery.queue_free()

func enemy_home(index: int, count: int, formation_slot: String = "") -> Vector2:
	# Opt-in encounter slots leave every other battle's default depth lanes intact.
	match formation_slot:
		"triangle_left_back": return Vector2(965,floor_y-135)
		"triangle_left_front": return Vector2(965,floor_y+65)
		"triangle_right": return Vector2(1160,floor_y-35)
	if count == 1: return Vector2(1021,floor_y-75)
	if count == 2: return Vector2(1000+index*105,floor_y-105+index*135)
	# Three clear depth lanes; additional columns remain within the stage.
	var lanes := [Vector2(980,-110),Vector2(1140,-30),Vector2(930,45)]
	var slot: Vector2 = lanes[index%3]
	return Vector2(slot.x+float(index/3)*130,floor_y+slot.y)

func depth_scale(point: Vector2) -> float:
	# One foot-anchored scale for poses, targeting, contact, framing and return ghosts.
	return ACTOR_SCALE*clampf(1.0+(point.y-(floor_y-30))*0.00065,0.91,1.08)

func update_depth() -> void:
	for actor in actors_root.get_children():
		actor.scale = Vector2.ONE*depth_scale(actor.position)

func _process(delta: float) -> void:
	update_depth()
	if shake_time < shake_duration:
		shake_time = minf(shake_duration,shake_time+delta)
		var t := shake_time/shake_duration
		var envelope := pow(1-t,2)
		shake = Vector2(-shake_direction*cos(t*TAU*2.5),sin(t*TAU*3.5)*0.40)*shake_strength*envelope
		impact_zoom = 1+0.026*envelope
	else:
		shake = Vector2.ZERO
		impact_zoom = 1.0
	_update_camera()

func kick_camera(direction: float, strength: float, duration: float = 0.20) -> void:
	shake_time = 0.0
	shake_duration = maxf(0.01,duration)
	shake_strength = strength
	shake_direction = direction
	shake = Vector2(-direction*strength,0)
	impact_zoom = 1.026
	_update_camera()

func _update_camera() -> void:
	var effective_zoom := zoom*impact_zoom
	world.scale = Vector2.ONE*effective_zoom
	world.position = Vector2(720-focus_x*effective_zoom,floor_y-35-focus_y*effective_zoom)+shake
	if is_instance_valid(scenery):
		var dimensions := scenery_base_rect.size*effective_zoom
		var origin := position+world.position+(scenery_base_rect.position-position)*effective_zoom
		# The illustration ends at its edges; constrain only its framing, never actors.
		origin.x = clampf(origin.x,1440.0-dimensions.x,0.0)
		origin.y = clampf(origin.y,900.0-dimensions.y,0.0)
		scenery.position = origin
		scenery.size = dimensions

func set_phase(value: String) -> void:
	phase = value
	phase_changed.emit(value)

func camera_to(target_x: float, magnification: float, duration: float, target_y: float = NAN) -> Tween:
	if camera_tween and camera_tween.is_running(): camera_tween.kill()
	camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	camera_tween.tween_property(self,"focus_x",target_x,duration)
	camera_tween.tween_property(self,"focus_y",floor_y-35 if is_nan(target_y) else target_y,duration)
	camera_tween.tween_property(self,"zoom",magnification,duration)
	return camera_tween

func wide() -> void:
	set_phase("wide")
	await camera_to(720,1.0,0.24).finished
	shake = Vector2.ZERO
	_update_camera()

func contact(actor: Node2D) -> Vector2:
	return actor.to_global(Vector2(0,-62))

func present_card_gain(kind: String, amount: int) -> Node2D:
	if amount <= 0 or not is_instance_valid(player): return null
	var fx := CardGainFX.new()
	fx.kind = kind
	fx.amount = amount
	fx.position = player.target_bounds.get_center()
	player.add_child(fx)
	return fx

func target_rect(index: int) -> Rect2:
	var actor := enemies[index]
	return Rect2(actor.to_global(actor.target_bounds.position),actor.target_bounds.size*actor.global_scale).intersection(get_global_rect())

func move_actor(actor: Node2D, destination: Vector2, duration: float) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(actor,"position",destination,duration)
	await tween.finished

func attack_destination(attacker: Node2D, defender: Node2D, reach: float) -> Vector2:
	var direction := 1.0 if defender.position.x >= attacker.position.x else -1.0
	var preferred: Vector2 = defender.position-Vector2(direction*reach*depth_scale(defender.position),0)
	for offset in [Vector2.ZERO,Vector2(0,-42),Vector2(0,42),Vector2(-direction*35,0),Vector2(direction*reach*2,0)]:
		var candidate: Vector2 = preferred+offset
		var clear := true
		for other in actors_root.get_children():
			if other == attacker or other == defender or not other.alive: continue
			if ((candidate-other.position)/GROUND_CLEARANCE).length() < 1.0:
				clear = false
				break
		if clear: return candidate
	return preferred

func path_clear(points: Array[Vector2], attacker: Node2D, defender: Node2D) -> bool:
	for other in actors_root.get_children():
		if other == attacker or other == defender or not other.alive: continue
		for i in points.size()-1:
			var foot: Vector2 = other.position/GROUND_CLEARANCE
			var nearest := Geometry2D.get_closest_point_to_segment(foot,points[i]/GROUND_CLEARANCE,points[i+1]/GROUND_CLEARANCE)
			if foot.distance_to(nearest) < 1.0: return false
	return true

func approach_path(attacker: Node2D, defender: Node2D, destination: Vector2) -> Array[Vector2]:
	var direct: Array[Vector2] = [attacker.position,destination]
	if path_clear(direct,attacker,defender): return direct
	var best := direct
	var best_length := INF
	# Short detours on the ground plane, not a navigation or collision simulation.
	for lane in [floor_y-165,floor_y-65,floor_y+100]:
		var candidate: Array[Vector2] = [attacker.position,Vector2(attacker.position.x,lane),Vector2(destination.x,lane),destination]
		if not path_clear(candidate,attacker,defender): continue
		var distance := 0.0
		for i in candidate.size()-1: distance += candidate[i].distance_to(candidate[i+1])
		if distance < best_length:
			best_length = distance
			best = candidate
	return best

func approach(attacker: Node2D, defender: Node2D, destination: Vector2) -> void:
	var points := approach_path(attacker,defender,destination)
	var total := 0.0
	for i in points.size()-1: total += points[i].distance_to(points[i+1])
	var duration := travel_duration(attacker,total)
	for i in points.size()-1:
		await move_actor(attacker,points[i+1],maxf(0.01,duration*points[i].distance_to(points[i+1])/maxf(total,1)))

func frame_attack(attacker: Node2D, defender: Node2D, destination: Vector2) -> void:
	var magnification := 1.65*ATTACK_ZOOM_FACTOR
	var target_x := (destination.x+defender.position.x)*0.5
	var target_y := (destination.y+defender.position.y)*0.5
	if enemies.size() > 1:
		# Keep all living opponents available for the next card while closing in.
		var left := INF
		var right := -INF
		var top := INF
		var bottom := -INF
		for actor in actors_root.get_children():
			if not actor.alive: continue
			# Frame the complete approach, including rear-lane detours, rather
			# than only the final contact point while the attacker is moving.
			var feet: Array[Vector2] = [actor.position]
			if actor == attacker: feet = approach_path(attacker,defender,destination)
			for foot in feet:
				left = minf(left,foot.x+actor.target_bounds.position.x*depth_scale(foot))
				right = maxf(right,foot.x+actor.target_bounds.end.x*depth_scale(foot))
				top = minf(top,foot.y+minf(-135,actor.target_bounds.position.y)*depth_scale(foot))
				bottom = maxf(bottom,foot.y+maxf(20,actor.target_bounds.end.y)*depth_scale(foot))
		magnification = maxf(1.0,minf(magnification,ATTACK_ZOOM_FACTOR*(size.y-48)/(bottom-top)))
		magnification = maxf(1.0,minf(magnification,ATTACK_ZOOM_FACTOR*(size.x-128)/(right-left)))
		# An attack-centered close-up can clip the opposite flanking dancer.
		# Leave room for the hit-stop zoom, camera shake and defender recoil.
		var half_width := (size.x*0.5-64)/magnification
		target_x = clampf(target_x,right-half_width,left+half_width)
		target_y = (top+bottom)*0.5+(floor_y-35-size.y*0.5)/magnification
	camera_to(target_x,magnification,0.25,target_y)

func attack(attacker: Node2D, defender: Node2D, style: String, hits: Array, on_hit: Callable) -> void:
	# Visual profiles select presentation only; supplied model hits remain authoritative.
	# An explicitly selected authored action wins. The profile override is the
	# default for intents without their own animation, not a lock on all attacks.
	if not attacker.pipeline_attacks.has(style) and not attacker.attack_style_override.is_empty():
		style = attacker.attack_style_override
	active_attack_config = {}
	if attacker.pipeline_attacks.has(style):
		await AuthoredAttack.play(self, attacker, defender, style, attacker.pipeline_attacks[style], hits, on_hit)
		return
	if style == "laser":
		await laser_attack(attacker, defender, hits, on_hit)
		return
	if style == "shoot":
		await ranged_attack(attacker, defender, hits, on_hit)
		return
	if not attacker.alive or not defender.alive: return
	active_attacker = attacker
	active_defender = defender
	var direction := 1.0 if defender.position.x > attacker.position.x else -1.0
	var enemy_attack := attacker != player
	attacker.face_toward(defender.position)
	defender.face_toward(attacker.position)
	var reach := 105.0 if style == "pierce" else 86.0
	if style == "bite": reach = 92.0
	reach = _motion_value(attacker,"reach",reach)
	var destination := attack_destination(attacker,defender,reach)
	direction = 1.0 if defender.position.x >= destination.x else -1.0
	set_phase("prepare")
	frame_attack(attacker,defender,destination)
	await move_actor(attacker,attacker.position-Vector2(direction*7,0),0.08)
	if attacker.position.distance_to(destination) > 26:
		set_phase("approach")
		attacker.set_pose("move")
		await approach(attacker,defender,destination)
	else:
		await move_actor(attacker,destination,0.08)
	attacker.face_toward(defender.position)
	defender.face_toward(attacker.position)
	if camera_tween.is_running(): await camera_tween.finished
	for i in hits.size():
		var hit: Dictionary = hits[i]
		var blocked := int(hit.get("blocked",0)) > 0
		var damage := int(hit.get("damage",0))
		set_phase("windup")
		# The existing raised guard also serves as the slash anticipation pose.
		attacker.set_pose("bite" if style == "bite" else ("block" if style != "pierce" else "move"))
		if blocked: defender.set_pose("block")
		# Telegraph, compress, then release quickly for both sides (enemy gets a clearer tell).
		await move_actor(attacker,destination-Vector2(direction*10,0),0.10 if enemy_attack else 0.075)
		var default_windup := 0.12 if style == "bite" else (0.045 if enemy_attack else 0.025)
		await get_tree().create_timer(_motion_value(attacker,"windup",default_windup)).timeout
		var strike_pose := "bite_close" if style == "bite" else style
		# Alternate the white dancer's sword pose within this attack only. Keep
		# the slash style for contact effects, audio and supplied combat results.
		if attacker.kind == "dancer_white" and style == "slash" and i % 2 == 1 and attacker.poses.has("slash_alt"):
			strike_pose = "slash_alt"
		attacker.set_pose(strike_pose)
		if style == "slash" or style == "pierce": combat_audio.play_cue("slash")
		await move_actor(attacker,destination+Vector2(direction*10,0),0.035)
		var contact_point: Vector2 = defender.position+Vector2(-direction*13,-62)*depth_scale(defender.position)
		show_strike(contact_point,direction,style,blocked)
		play_hit_sound(blocked)
		if not blocked and damage > 0: defender.set_pose("damaged")
		on_hit.call(hit,i)
		last_hit_stop = _hit_stop(attacker,0.095 if enemy_attack else (0.075 if style == "pierce" else 0.085))
		_pipeline_camera(attacker,direction,8.0 if damage > 0 else 4.5)
		defender.sprite.modulate = Color(1.65,1.3,1.65,1)
		set_phase("impact")
		# Actor poses and positions hold; camera impulse decays independently of HUD.
		await get_tree().create_timer(last_hit_stop).timeout
		defender.sprite.modulate = Color.WHITE
		if blocked and damage > 0: defender.set_pose("damaged")
		var origin: Vector2 = defender.position
		var recoil := 4.0 if damage == 0 else (17.0 if blocked else 12.0)
		await move_actor(defender,origin+Vector2(direction*recoil,0),0.065)
		set_phase("recover")
		var recovery := _motion_value(attacker,"recovery",0.12)
		var settle := create_tween().set_parallel(true)
		settle.tween_property(defender,"position",origin,recovery)
		settle.tween_property(attacker,"position",destination,recovery)
		await settle.finished
		# The authored attack sequence owns its presentation length. Damage was
		# already applied once by CombatModel; this only stops the next pose
		# from cutting a multi-frame attack short.
		await _await_pipeline_pose(attacker)
		if bool(hit.get("killed",false)):
			await retire_actor(defender)
			break
		defender.set_pose("idle")
	attacker.set_pose("idle")
	set_phase("idle")

func retire_actor(actor: Node2D) -> void:
	if not actor.alive: return
	actor.alive = false
	if actor.kind == "fish" and not actor.is_player:
		var fx := FishDeathBurst.new()
		fx.position = actor.position
		fx.scale = actor.scale
		world.add_child(fx)
		fx.setup_sprite(actor.sprite)
		actor.modulate.a = 0.0
		set_phase("fish_death_burst")
		await fx.finished
	else:
		await create_tween().tween_property(actor,"modulate:a",0.0,0.16).finished
	face_duet_survivor()

func face_duet_survivor() -> void:
	# Only the split-side Boss formation needs a new idle target after a death.
	if not dancer_duet or not player.alive: return
	var survivors: Array[Node2D] = []
	for enemy in enemies:
		if enemy.alive: survivors.append(enemy)
	if survivors.size() != 1: return
	var survivor := survivors[0]
	player.face_toward(survivor.position)
	survivor.face_toward(player.position)

func spawn_pollution_spit(attacker: Node2D, defender: Node2D, instant: bool = false) -> Node2D:
	if not attacker.alive or attacker.kind != "fish": return null
	var fx := PollutionSpit.new()
	# Fish artwork mouth, transformed with the current pose, facing and foot scale.
	fx.start = world.to_local(attacker.sprite.to_global(Vector2(150,610)))
	fx.end = world.to_local(defender.to_global(Vector2(0,-62)))
	fx.target_actor = defender
	fx.size_factor = depth_scale(defender.position)
	fx.flight_time = 0.0 if instant else 0.30
	world.add_child(fx)
	return fx

func present_pollution_spit(attacker: Node2D, defender: Node2D, on_contact: Callable) -> void:
	if not attacker.alive or not defender.alive or attacker.kind != "fish":
		on_contact.call()
		await get_tree().create_timer(0.35).timeout
		return
	active_attacker = attacker
	active_defender = defender
	attacker.face_toward(defender.position)
	defender.face_toward(attacker.position)
	set_phase("spit_prepare")
	frame_attack(attacker,defender,attacker.position)
	if camera_tween.is_running(): await camera_tween.finished
	attacker.set_pose("bite")
	await get_tree().create_timer(0.14).timeout
	var fx := spawn_pollution_spit(attacker,defender)
	fx.impacted.connect(func():
		defender.set_pose("damaged")
		on_contact.call()
		set_phase("spit_impact"))
	set_phase("spit_flight")
	await fx.finished
	attacker.set_pose("idle")
	defender.set_pose("idle")
	set_phase("idle")

func wait_pollution_spits() -> void:
	# Passive hit splashes finish before a counterattack, death exit or return starts.
	for child in world.get_children():
		if child.get_script() == PollutionSpit and not child.is_queued_for_deletion():
			await child.finished

func neon_fx(point: Vector2, kind: String, direction: float = 1.0) -> Node2D:
	var fx := NeonSlash.new()
	fx.position = point
	fx.z_index = 1
	fx.mode = kind
	fx.direction = direction
	world.add_child(fx)
	return fx

func show_strike(point: Vector2, direction: float, style: String, blocked: bool, apply_effect_offset: bool = true) -> void:
	var effect_scale := _effect_scale(active_attacker)
	if apply_effect_offset:
		point += _effect_offset(active_attacker)*depth_scale(active_defender.position)
	if (active_attacker.kind == "dancer_black" and style == "pierce") or (active_attacker.kind == "dancer_white" and style == "slash"):
		var strike := DancerStrike.new()
		strike.mode = style
		strike.position = point
		strike.direction = direction
		strike.blocked = blocked
		strike.scale = Vector2.ONE * depth_scale(active_defender.position) * effect_scale
		# Reflect both slash layers around their contact point for the upward return cut.
		if active_attacker.kind == "dancer_white" and active_attacker.pose == "slash_alt":
			strike.scale.y *= -1.0
		world.add_child(strike)
		return
	if style in ["slash", "pierce"] and active_attacker == player and player.kind == "noren":
		var slash := NorenSlash.new()
		slash.mode = style
		slash.position = point
		slash.direction = direction
		slash.blocked = blocked
		slash.scale = Vector2.ONE * depth_scale(active_defender.position) * effect_scale
		if blocked: slash.duration = 0.28
		world.add_child(slash)
		return
	if style == "bite":
		var bite := BiteHit.new()
		bite.texture = active_attacker.hit_effect_texture
		bite.position = point
		bite.scale = Vector2(-direction,1)*depth_scale(active_defender.position)*effect_scale
		bite.blocked = blocked
		world.add_child(bite)
		return
	var fx := neon_fx(point,style,direction)
	if effect_scale != 1.0:
		fx.scale *= effect_scale
	fx.blocked = blocked
	if blocked: fx.duration = 0.24

func play_hit_sound(blocked: bool) -> void:
	# Small procedural transient; no new external audio asset dependency.
	var data := PackedByteArray()
	var samples := int(audio_rate*0.09)
	data.resize(samples*2)
	for i in samples:
		var time := float(i)/audio_rate
		var envelope := pow(1.0-float(i)/samples,3)
		var wave := sin(time*TAU*(1900 if blocked else 125))*0.55+sin(time*TAU*3271)*0.18
		data.encode_s16(i*2,int(wave*envelope*24000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = audio_rate
	stream.data = data
	sound.stream = stream
	sound.play()

func return_home() -> void:
	set_phase("return_light")
	camera_to(720,1.0,0.38)
	var returning: Array[Node2D] = []
	var actors: Array[Node2D] = [player]
	actors.append_array(enemies)
	var fade := create_tween().set_parallel(true)
	for actor in actors:
		# A stationary defender can still turn during a hit; every survivor returns.
		if not actor.alive: continue
		returning.append(actor)
		neon_fx(actor.position-Vector2(0,30)*depth_scale(actor.position),"vanish")
		actor.modulate = Color(2,1.4,1.8,1)
		fade.tween_property(actor,"modulate:a",0.0,0.06)
	if returning.is_empty():
		fade.kill()
	else:
		combat_audio.play_cue("snap")
		await fade.finished
		set_phase("light_flight")
		var flight := create_tween().set_parallel(true)
		var trails: Array[Node2D] = []
		for actor in returning:
			var trail := NeonSlash.new()
			trail.z_index = 1
			trail.mode = "return"
			trail.manual = true
			trail.start = actor.position-Vector2(0,48)*depth_scale(actor.position)
			trail.end = actor.home-Vector2(0,48)*depth_scale(actor.home)
			world.add_child(trail)
			trails.append(trail)
			flight.tween_method(trail.set_progress,0.0,1.0,0.18)
		await flight.finished
		for trail in trails: trail.queue_free()
		var ghosts: Array[Node2D] = []
		var reveal := create_tween().set_parallel(true)
		for actor in returning:
			actor.position = actor.home
			actor.facing = 1.0 if actor == player or (dancer_duet and actor.home.x < player.home.x) else -1.0
			actor.set_pose("idle")
		face_duet_survivor()
		for actor in returning:
			var ghost := ReturnGhost.new()
			ghost.position = actor.home
			ghost.scale = Vector2.ONE*depth_scale(actor.home)
			ghost.z_index = 1
			world.add_child(ghost)
			ghost.setup(actor.sprite,actor.white_key_poses.get(actor.pose,false))
			ghosts.append(ghost)
			reveal.tween_method(ghost.set_progress,0.0,1.0,0.50)
			reveal.tween_property(actor,"modulate",Color.WHITE,0.28).set_delay(0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		set_phase("home_glitch")
		await get_tree().create_timer(0.22).timeout
		set_phase("home_reveal")
		await reveal.finished
		for ghost in ghosts: ghost.queue_free()

	if camera_tween.is_running(): await camera_tween.finished
	set_phase("idle")

func ranged_attack(attacker: Node2D, defender: Node2D, hits: Array, on_hit: Callable) -> void:
	if not attacker.alive or not defender.alive: return
	active_attacker = attacker
	active_defender = defender
	var direction := 1.0 if defender.position.x >= attacker.position.x else -1.0
	attacker.face_toward(defender.position)
	defender.face_toward(attacker.position)
	await wide()
	if attacker.position.distance_to(defender.position) < 300 * depth_scale(attacker.position):
		set_phase("retreat")
		attacker.set_pose("retreat")
		var origin: Vector2 = attacker.position
		var destination := origin - Vector2(direction * RANGED_RETREAT_DISTANCE, 0)
		destination.x = clampf(destination.x, 100, 1310)
		# Match the attack approach: switch pose, then glide along the ground in one tween.
		var duration := travel_duration(attacker,origin.distance_to(destination))
		await move_actor(attacker, destination, duration)
	for i in hits.size():
		var hit: Dictionary = hits[i]
		set_phase("aim")
		attacker.set_pose("idle")
		await get_tree().create_timer(0.10).timeout
		attacker.set_pose("shoot")
		combat_audio.play_cue("shoot")
		last_hit_stop = _hit_stop(attacker,RANGED_HIT_STOP if int(hit.damage)>0 else RANGED_BLOCK_STOP)
		show_gun_bursts(attacker,defender,direction,int(hit.blocked)>0,i)
		defender.set_pose("block" if hit.blocked > 0 else "damaged")
		defender.sprite.modulate = Color(1.55,1.8,2.1) if int(hit.damage)==0 else Color(2.1,0.38,0.55)
		play_hit_sound(hit.blocked > 0)
		_pipeline_camera(attacker,direction,16.0 if int(hit.damage)>0 else 10.0)
		on_hit.call(hit,i)
		set_phase("shoot")
		# Hold both contact poses and local flashes; the camera impulse keeps decaying.
		await get_tree().create_timer(last_hit_stop).timeout
		if int(hit.blocked)>0 and int(hit.damage)>0: defender.set_pose("damaged")
		await create_tween().tween_property(defender.sprite,"modulate",Color.WHITE,0.12).finished
		await _await_pipeline_pose(attacker)
		if hit.killed:
			await retire_actor(defender)
			break
		defender.set_pose("idle")
	attacker.set_pose("idle")
	set_phase("idle")

func show_gun_bursts(attacker: Node2D, defender: Node2D, direction: float, blocked: bool, round_index: int) -> void:
	var effect_scale := _effect_scale(attacker)
	var effect_offset := _effect_offset(attacker)
	var muzzle := GunBurst.new()
	muzzle.mode = "muzzle"
	muzzle.duration = 0.19
	muzzle.hold_remaining = last_hit_stop
	muzzle.variation = round_index
	# Barrel opening in the authored shooting texture, through its calibrated mirror/scale.
	muzzle.position = (world.to_local(attacker.sprite.to_global(Vector2(54,385))) if attacker.is_player else attacker.position+Vector2(direction*75,-65)*depth_scale(attacker.position))+effect_offset*depth_scale(attacker.position)
	muzzle.scale = Vector2(direction,1)*depth_scale(attacker.position)*effect_scale
	world.add_child(muzzle)
	var impact := GunBurst.new()
	impact.mode = "impact"
	impact.hold_remaining = last_hit_stop
	impact.blocked = blocked
	impact.variation = round_index
	impact.position = defender.position+Vector2(-direction*8,-62)*depth_scale(defender.position)+effect_offset*depth_scale(defender.position)
	impact.scale = Vector2(direction,1)*depth_scale(defender.position)*effect_scale
	world.add_child(impact)


func laser_attack(attacker: Node2D, defender: Node2D, hits: Array, on_hit: Callable) -> void:
	if not attacker.alive or not defender.alive: return
	active_attacker = attacker
	active_defender = defender
	attacker.face_toward(defender.position)
	defender.face_toward(attacker.position)
	# Keep the full distance visible; firing does not approach or push the robot.
	await wide()
	for i in hits.size():
		var hit: Dictionary = hits[i]
		attacker.set_pose("laser")
		var fx := PalmLaser.new()
		fx.start = world.to_local(attacker.sprite.to_global(attacker.laser_muzzle))
		fx.target = world.to_local(defender.to_global(Vector2(0, -62)))
		fx.start += _effect_offset(attacker)*depth_scale(attacker.position)
		fx.target += _effect_offset(attacker)*depth_scale(defender.position)
		fx.max_width = 0.96 * attacker.laser_palm_width * absf(attacker.sprite.scale.y) * absf(attacker.scale.y) * _effect_scale(attacker)
		fx.blocked = int(hit.get("blocked", 0)) > 0
		world.add_child(fx)
		set_phase("laser_charge")
		await get_tree().create_timer(PalmLaser.CHARGE_TIME).timeout
		set_phase("laser_grow")
		await get_tree().create_timer(PalmLaser.GROW_TIME).timeout
		last_hit_stop = _hit_stop(attacker,0.10)
		defender.set_pose("block" if fx.blocked else "damaged")
		defender.sprite.modulate = Color(1.6, 1.1, 1.6)
		play_hit_sound(fx.blocked)
		_pipeline_camera(attacker,signf(defender.position.x - attacker.position.x), 6.0 if int(hit.get("damage", 0)) > 0 else 3.0)
		on_hit.call(hit, i)
		set_phase("laser_impact")
		await fx.finished
		defender.sprite.modulate = Color.WHITE
		await _await_pipeline_pose(attacker)
		if bool(hit.get("killed", false)):
			await retire_actor(defender)
			break
		defender.set_pose("idle")
	attacker.set_pose("idle")
	set_phase("idle")

func _motion_value(actor: Node2D, key: String, fallback: float) -> float:
	var motion = actor.get("pipeline_motion")
	if motion is Dictionary and motion.has(key):
		var value = motion[key]
		if value is int or value is float:
			return float(value)
	return fallback

func travel_duration(actor: Node2D, distance: float) -> float:
	var motion = actor.get("pipeline_motion")
	if motion is Dictionary and motion.has("speed"):
		return clampf(distance/maxf(1.0,float(motion.speed)),0.03,10.0)
	return clampf(distance/2300.0,0.15,0.34)


func _await_pipeline_pose(actor: Node2D) -> void:
	if actor == null or not actor.has_method("pipeline_pose_remaining"):
		return
	var remaining := maxf(0.0,float(actor.call("pipeline_pose_remaining")))
	if remaining > 0.001:
		await get_tree().create_timer(remaining).timeout

func _effect_scale(actor: Node2D) -> float:
	var effects = actor.get("pipeline_effects")
	if effects is Dictionary and effects.has("scale"):
		var value = effects.scale
		if value is int or value is float:
			return maxf(0.0,float(value))
	return 1.0

func _effect_offset(actor: Node2D) -> Vector2:
	var effects = actor.get("pipeline_effects")
	if effects is Dictionary:
		var value = effects.get("offset")
		if value is Vector2: return value
		if value is Array and value.size() == 2:
			return Vector2(float(value[0]),float(value[1]))
	return Vector2.ZERO

func _hit_stop(actor: Node2D, fallback: float) -> float:
	var effects = actor.get("pipeline_effects")
	if effects is Dictionary and effects.has("hitStop"):
		var value = effects.hitStop
		if value is int or value is float:
			return maxf(0.0,float(value))
	return fallback

func _pipeline_camera(actor: Node2D, direction: float, fallback_strength: float) -> void:
	var effects = actor.get("pipeline_effects")
	if not effects is Dictionary or not effects.has("shake"):
		kick_camera(direction,fallback_strength)
		return
	var shake = effects.shake
	if shake is bool:
		if shake: kick_camera(direction,fallback_strength)
		return
	if shake is int or shake is float:
		kick_camera(direction,maxf(0.0,float(shake)))
		return
	if shake is Dictionary:
		kick_camera(direction,float(shake.get("strength",fallback_strength)),float(shake.get("duration",0.20)))
		return
	kick_camera(direction,fallback_strength)
