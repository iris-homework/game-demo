extends Control
## Clipped presentation world. No model, saves, card data or HUD are mutated here.
signal phase_changed(phase: String)
const Actor = preload("res://scripts/combat/pose_actor.gd")
const NeonSlash = preload("res://scripts/combat/prismatic_slash_fx.gd")
var world := Node2D.new()
var player: Node2D
var enemies: Array[Node2D] = []
var floor_y := 307.0
var zoom := 1.0
var focus_x := 720.0
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
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-2500,floor_y-20),Vector2(4000,floor_y-20),Vector2(4000,1500),Vector2(-2500,1500)])
	ground.color = Color("13141a")
	world.add_child(ground)
	var horizon := Line2D.new()
	horizon.points = PackedVector2Array([Vector2(-2500,floor_y-20),Vector2(4000,floor_y-20)])
	horizon.width = 1
	horizon.default_color = Color("22232b")
	world.add_child(horizon)
	player = Actor.new()
	world.add_child(player)
	player.setup("noren",Vector2(405,floor_y),1.0)
	for i in count:
		var actor := Actor.new()
		world.add_child(actor)
		actor.setup("finn",Vector2(1021+i*180-(count-1)*100,floor_y),-1.0)
		enemies.append(actor)
	add_child(sound)
	sound.volume_db = -16
	_update_camera()

func _process(delta: float) -> void:
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
	world.position = Vector2(720-focus_x*effective_zoom,floor_y*(1-effective_zoom))+shake

func set_phase(value: String) -> void:
	phase = value
	phase_changed.emit(value)

func camera_to(target_x: float, magnification: float, duration: float) -> Tween:
	if camera_tween and camera_tween.is_running(): camera_tween.kill()
	camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	camera_tween.tween_property(self,"focus_x",target_x,duration)
	camera_tween.tween_property(self,"zoom",magnification,duration)
	return camera_tween

func wide() -> void:
	set_phase("wide")
	await camera_to(720,1.0,0.24).finished
	shake = Vector2.ZERO
	_update_camera()

func contact(actor: Node2D) -> Vector2:
	return actor.global_position+Vector2(0,-62*zoom*impact_zoom)

func target_rect(index: int) -> Rect2:
	var actor := enemies[index]
	return Rect2(actor.global_position+Vector2(-65,-130)*zoom*impact_zoom,Vector2(130,145)*zoom*impact_zoom).intersection(get_global_rect())

func move_actor(actor: Node2D, destination: Vector2, duration: float) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(actor,"position",destination,duration)
	await tween.finished

func attack(attacker: Node2D, defender: Node2D, style: String, hits: Array, on_hit: Callable) -> void:
	if not attacker.alive or not defender.alive: return
	var direction := 1.0 if defender.position.x > attacker.position.x else -1.0
	var enemy_attack := attacker != player
	attacker.face_toward(defender.position)
	defender.face_toward(attacker.position)
	var reach := 105.0 if style == "pierce" else 86.0
	var destination := defender.position-Vector2(direction*reach,0)
	set_phase("prepare")
	camera_to((destination.x+defender.position.x)*0.5,1.65,0.25)
	await move_actor(attacker,attacker.position-Vector2(direction*7,0),0.08)
	if attacker.position.distance_to(destination) > 26:
		set_phase("approach")
		attacker.set_pose("move")
		await move_actor(attacker,destination,0.15)
	else:
		await move_actor(attacker,destination,0.08)
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
		var contact_point: Vector2 = defender.position+Vector2(-direction*13,-62)
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
		neon_fx(actor.position-Vector2(0,30),"vanish")
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
			trail.mode = "return"
			trail.manual = true
			trail.start = actor.position-Vector2(0,48)
			trail.end = actor.home-Vector2(0,48)
			world.add_child(trail)
			trails.append(trail)
			flight.tween_method(trail.set_progress,0.0,1.0,0.18)
		await flight.finished
		for trail in trails: trail.queue_free()
		var reveal := create_tween().set_parallel(true)
		for actor in returning:
			actor.position = actor.home
			neon_fx(actor.home-Vector2(0,30),"arrive")
			actor.facing = 1.0 if actor == player else -1.0
			actor.set_pose("idle")
			reveal.tween_property(actor,"modulate",Color.WHITE,0.10)
		await reveal.finished
	if camera_tween.is_running(): await camera_tween.finished
	set_phase("idle")
