extends Control
## Clipped presentation world. No model, saves, card data or HUD are mutated here.
signal phase_changed(phase: String)
const Actor = preload("res://scripts/combat/pose_actor.gd")
const ReturnGhost = preload("res://scripts/combat/return_ghost_fx.gd")
const NeonSlash = preload("res://scripts/combat/prismatic_slash_fx.gd")
const GunBurst = preload("res://scripts/combat/gun_burst_fx.gd")
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

func setup(count: int, feet_y: float) -> void:
	position = Vector2(0,270)
	size = Vector2(1440,420)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	floor_y = feet_y-position.y
	add_child(world)
	focus_y = floor_y-35
	var ground := preload("res://scripts/combat/depth_floor.gd").new()
	ground.baseline = floor_y
	world.add_child(ground)
	actors_root.y_sort_enabled = true
	world.add_child(actors_root)
	player = Actor.new()
	actors_root.add_child(player)
	player.setup("noren",Vector2(405,floor_y-30),1.0)
	for i in count:
		var actor := Actor.new()
		actors_root.add_child(actor)
		actor.setup("finn",enemy_home(i,count),-1.0)
		enemies.append(actor)
		if count > 1:
			var marker := Label.new()
			marker.text = "%02d" % (i+1)
			marker.position = Vector2(20,3)
			marker.add_theme_font_size_override("font_size",13)
			marker.modulate = Color("8babb8")
			actor.add_child(marker)
	update_depth()
	add_child(sound)
	sound.volume_db = -16
	_update_camera()

func enemy_home(index: int, count: int) -> Vector2:
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

func kick_camera(direction: float, strength: float) -> void:
	shake_time = 0.0
	shake_duration = 0.20
	shake_strength = strength
	shake_direction = direction
	shake = Vector2(-direction*strength,0)
	impact_zoom = 1.026
	_update_camera()

func _update_camera() -> void:
	var effective_zoom := zoom*impact_zoom
	world.scale = Vector2.ONE*effective_zoom
	world.position = Vector2(720-focus_x*effective_zoom,floor_y-35-focus_y*effective_zoom)+shake

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

func target_rect(index: int) -> Rect2:
	var actor := enemies[index]
	return Rect2(actor.to_global(Vector2(-58,-130)),Vector2(116,145)*actor.global_scale).intersection(get_global_rect())

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
	var duration := clampf(total/2300.0,0.15,0.34)
	for i in points.size()-1:
		await move_actor(attacker,points[i+1],maxf(0.01,duration*points[i].distance_to(points[i+1])/maxf(total,1)))

func frame_attack(attacker: Node2D, defender: Node2D, destination: Vector2) -> void:
	var magnification := 1.65*ATTACK_ZOOM_FACTOR
	var target_y := (destination.y+defender.position.y)*0.5
	if enemies.size() > 1:
		# Keep all living opponents available for the next card while closing in.
		var top := INF
		var bottom := -INF
		for actor in actors_root.get_children():
			if not actor.alive: continue
			var foot: Vector2 = destination if actor == attacker else actor.position
			top = minf(top,foot.y-135*depth_scale(foot))
			bottom = maxf(bottom,foot.y+20*depth_scale(foot))
		magnification = maxf(1.0,minf(magnification,ATTACK_ZOOM_FACTOR*(size.y-48)/(bottom-top)))
		target_y = (top+bottom)*0.5+(floor_y-35-size.y*0.5)/magnification
	camera_to((destination.x+defender.position.x)*0.5,magnification,0.25,target_y)

func attack(attacker: Node2D, defender: Node2D, style: String, hits: Array, on_hit: Callable) -> void:
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
		attacker.set_pose("block" if style != "pierce" else "move")
		if blocked: defender.set_pose("block")
		# Telegraph, compress, then release quickly for both sides (enemy gets a clearer tell).
		await move_actor(attacker,destination-Vector2(direction*10,0),0.10 if enemy_attack else 0.075)
		await get_tree().create_timer(0.045 if enemy_attack else 0.025).timeout
		attacker.set_pose(style)
		await move_actor(attacker,destination+Vector2(direction*10,0),0.035)
		var contact_point: Vector2 = defender.position+Vector2(-direction*13,-62)*depth_scale(defender.position)
		show_strike(contact_point,direction,style,blocked)
		play_hit_sound(blocked)
		if not blocked and damage > 0: defender.set_pose("damaged")
		on_hit.call(hit,i)
		last_hit_stop = 0.095 if enemy_attack else (0.075 if style == "pierce" else 0.085)
		kick_camera(direction,8.0 if damage > 0 else 4.5)
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
		var settle := create_tween().set_parallel(true)
		settle.tween_property(defender,"position",origin,0.12)
		settle.tween_property(attacker,"position",destination,0.12)
		await settle.finished
		if bool(hit.get("killed",false)):
			defender.alive = false
			await create_tween().tween_property(defender,"modulate:a",0.0,0.16).finished
			break
		defender.set_pose("idle")
	attacker.set_pose("idle")
	set_phase("idle")

func neon_fx(point: Vector2, kind: String, direction: float = 1.0) -> Node2D:
	var fx := NeonSlash.new()
	fx.position = point
	fx.z_index = 1
	fx.mode = kind
	fx.direction = direction
	world.add_child(fx)
	return fx

func show_strike(point: Vector2, direction: float, style: String, blocked: bool) -> void:
	var fx := neon_fx(point,style,direction)
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
		if not actor.alive or actor.position.distance_to(actor.home) < 1: continue
		returning.append(actor)
		neon_fx(actor.position-Vector2(0,30)*depth_scale(actor.position),"vanish")
		actor.modulate = Color(2,1.4,1.8,1)
		fade.tween_property(actor,"modulate:a",0.0,0.06)
	if returning.is_empty():
		fade.kill()
	else:
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
			actor.facing = 1.0 if actor == player else -1.0
			actor.set_pose("idle")
			var ghost := ReturnGhost.new()
			ghost.position = actor.home
			ghost.scale = Vector2.ONE*depth_scale(actor.home)
			ghost.z_index = 1
			world.add_child(ghost)
			ghost.setup(actor.sprite)
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
		await move_actor(attacker, origin.lerp(destination, 0.5) - Vector2(0,30), 0.12)
		await move_actor(attacker, destination, 0.14)
	for i in hits.size():
		var hit: Dictionary = hits[i]
		set_phase("aim")
		attacker.set_pose("idle")
		await get_tree().create_timer(0.10).timeout
		attacker.set_pose("shoot")
		last_hit_stop = RANGED_HIT_STOP if int(hit.damage)>0 else RANGED_BLOCK_STOP
		show_gun_bursts(attacker,defender,direction,int(hit.blocked)>0,i)
		defender.set_pose("block" if hit.blocked > 0 else "damaged")
		defender.sprite.modulate = Color(1.55,1.8,2.1) if int(hit.damage)==0 else Color(2.1,0.38,0.55)
		play_hit_sound(hit.blocked > 0)
		kick_camera(direction,9.0 if int(hit.damage)>0 else 6.0)
		on_hit.call(hit,i)
		set_phase("shoot")
		# Hold both contact poses and local flashes; the camera impulse keeps decaying.
		await get_tree().create_timer(last_hit_stop).timeout
		if int(hit.blocked)>0 and int(hit.damage)>0: defender.set_pose("damaged")
		await create_tween().tween_property(defender.sprite,"modulate",Color.WHITE,0.12).finished
		if hit.killed:
			defender.alive = false
			await create_tween().tween_property(defender,"modulate:a",0.0,0.16).finished
			break
		defender.set_pose("idle")
	attacker.set_pose("idle")
	set_phase("idle")

func show_gun_bursts(attacker: Node2D, defender: Node2D, direction: float, blocked: bool, round_index: int) -> void:
	var muzzle := GunBurst.new()
	muzzle.mode = "muzzle"
	muzzle.duration = 0.19
	muzzle.hold_remaining = last_hit_stop
	muzzle.variation = round_index
	# Barrel opening in the authored shooting texture, through its calibrated mirror/scale.
	muzzle.position = world.to_local(attacker.sprite.to_global(Vector2(270,325))) if attacker.kind=="noren" else attacker.position+Vector2(direction*75,-65)*depth_scale(attacker.position)
	muzzle.scale = Vector2(direction,1)*depth_scale(attacker.position)
	world.add_child(muzzle)
	var impact := GunBurst.new()
	impact.mode = "impact"
	impact.hold_remaining = last_hit_stop
	impact.blocked = blocked
	impact.variation = round_index
	impact.position = defender.position+Vector2(-direction*8,-62)*depth_scale(defender.position)
	impact.scale = Vector2(direction,1)*depth_scale(defender.position)
	world.add_child(impact)
