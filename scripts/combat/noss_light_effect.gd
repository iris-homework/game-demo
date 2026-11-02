extends Node2D
## Pure gold/ivory launch, sampled flight trail and twinkling motes; presentation only.
var mode := "muzzle"
var duration := 0.24
var elapsed := 0.0
var axis := Vector2.LEFT
var visual_scale := 1.0
var projectile: Node2D
var tail_offset := Vector2.ZERO
var samples: Array[Vector2] = []
var sparkles: Array[Dictionary] = []
var sparkle_serial := 0
var shatter := false
var fragments: Array[Dictionary] = []
const MAX_SPARKLES := 64
const GOLD := Color("ffe66a")
const IVORY := Color("fffeed")

func _ready() -> void:
	z_index = 14 if mode == "trail" else 16
	add_to_group("noss_sword_vfx")
	add_to_group("noss_sword_"+mode)
	if mode != "trail":
		for i in (14 if mode == "impact" else 9):
			var ray := Vector2.from_angle(axis.angle()+float(i)*TAU/(14.0 if mode == "impact" else 9.0))
			_emit_sparkle(ray*5.0*visual_scale,ray*(95.0 if mode == "impact" else 65.0)*visual_scale)
	if mode == "impact" and shatter:
		# Deterministic glasslike light shards; no combat RNG or model writes.
		for i in 14:
			var ray := Vector2.from_angle(float(i)*2.39996)
			var variation := 0.5+0.5*sin(float(i)*7.137)
			fragments.append({"velocity":ray*(240.0+variation*320.0)*visual_scale+Vector2.UP*80.0*visual_scale,
				"length":18.0+variation*18.0,"width":2.8+variation*2.6,
				"rotation":ray.angle(),"spin":(-1.0 if i%2 == 0 else 1.0)*(3.0+variation*5.0)})
	_sample_tail()
	queue_redraw()

func _sample_tail() -> void:
	if mode != "trail" or not is_instance_valid(projectile) or projectile.is_queued_for_deletion(): return
	var point: Vector2 = projectile.position+tail_offset
	if samples.is_empty() or samples[-1].distance_to(point) > 0.5:
		var previous := point if samples.is_empty() else samples[-1]
		# Distance-based emission keeps the fast projectile's trail filled at low FPS.
		var steps := clampi(ceili(previous.distance_to(point)/(23.0*visual_scale)),1,24)
		for i in steps:
			var anchor := previous.lerp(point,float(i+1)/float(steps))
			var side := sin(float(sparkle_serial)*2.39996)
			_emit_sparkle(anchor+axis.orthogonal()*side*12.0*visual_scale,
				(-axis*22.0+axis.orthogonal()*side*46.0)*visual_scale)
		samples.append(point)
		while samples.size() > 12: samples.pop_front()

func _emit_sparkle(point: Vector2, velocity: Vector2) -> void:
	var variation := 0.5+0.5*sin(float(sparkle_serial)*12.9898)
	sparkles.append({"point":point,"velocity":velocity,"born":elapsed,
		"life":0.16+variation*0.06,"size":2.0+variation*2.5,
		"phase":float(sparkle_serial)*2.39996,"frequency":9.0+variation*5.0})
	sparkle_serial += 1
	while sparkles.size() > MAX_SPARKLES: sparkles.pop_front()

func sparkle_brightness(particle: Dictionary, time: float) -> float:
	var age: float = time-float(particle.born)
	if age < 0.0 or age >= float(particle.life): return 0.0
	var pulse := 0.22+0.78*pow(0.5+0.5*sin(age*TAU*float(particle.frequency)+float(particle.phase)),2.0)
	return pulse*pow(1.0-age/float(particle.life),0.65)

func _draw_sparkles() -> void:
	for particle in sparkles:
		var alpha := sparkle_brightness(particle,elapsed)
		if alpha <= 0.01: continue
		var age: float = elapsed-float(particle.born)
		var point: Vector2 = particle.point+particle.velocity*age
		var size: float = float(particle.size)*visual_scale*(0.65+0.55*alpha)
		draw_circle(point,size*2.0,Color(GOLD,alpha*0.13))
		draw_colored_polygon(PackedVector2Array([point+Vector2(0,-size*1.5),
			point+Vector2(size*0.55,0),point+Vector2(0,size*1.5),point-Vector2(size*0.55,0)]),Color(IVORY,alpha))
		draw_line(point-Vector2(size*1.2,0),point+Vector2(size*1.2,0),Color(GOLD,alpha),0.8*visual_scale,true)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	_sample_tail()
	for i in range(sparkles.size()-1,-1,-1):
		if elapsed-float(sparkles[i].born) >= float(sparkles[i].life): sparkles.remove_at(i)
	queue_redraw()

func _draw() -> void:
	_draw_sparkles()
	var t := clampf(elapsed/maxf(0.001,duration),0.0,1.0)
	var fade := pow(1.0-t,1.25)
	var strength := visual_scale
	if mode == "impact" and shatter:
		_draw_shatter(t,fade)
	if mode == "trail":
		for i in range(1,samples.size()):
			var weight := float(i)/float(samples.size()-1)
			var alpha := fade*(0.18+0.65*weight)
			draw_line(samples[i-1],samples[i],Color(GOLD,alpha*0.25),(3.0+8.0*weight)*strength,true)
			draw_line(samples[i-1],samples[i],Color(GOLD,alpha),(1.0+3.2*weight)*strength,true)
			draw_line(samples[i-1],samples[i],Color(IVORY,alpha),maxf(0.6,1.3*weight)*strength,true)
		return
	var impact := mode == "impact"
	var radius := (7.0+32.0*t if impact else 5.0+21.0*t)*strength
	draw_circle(Vector2.ZERO,radius*0.68,Color(GOLD,fade*0.17))
	draw_arc(Vector2.ZERO,radius,0,TAU,36,Color(GOLD,fade*0.85),1.8*strength,true)
	var flash := sin(PI*clampf(t*1.8,0.0,1.0)) if impact else (1.0-t)
	draw_circle(Vector2.ZERO,(3.0+6.0*flash)*strength,Color(IVORY,fade))
	var rays := 8 if impact else 6
	for i in rays:
		var angle := axis.angle()+float(i)*TAU/float(rays)
		var ray := Vector2.from_angle(angle)
		var start := ray*radius*0.55
		var end := ray*(radius+(15.0 if impact else 11.0)*fade*strength)
		draw_line(start,end,Color(GOLD,fade),2.6*strength,true)
		draw_line(start,end,Color(IVORY,fade),0.9*strength,true)
	if impact:
		# A small directional cross at contact remains readable through guard flash.
		var normal := axis.orthogonal()
		draw_line(-normal*radius*0.55,normal*radius*0.55,Color(IVORY,fade),1.2*strength,true)

func _draw_shatter(t: float, fade: float) -> void:
	var flash := pow(1.0-clampf(t*3.0,0.0,1.0),2.0)
	draw_circle(Vector2.ZERO,(40.0+100.0*t)*visual_scale,Color(GOLD,flash*0.30))
	draw_circle(Vector2.ZERO,(17.0+20.0*t)*visual_scale,Color(IVORY,flash))
	draw_arc(Vector2.ZERO,(18.0+145.0*t)*visual_scale,0,TAU,48,Color(GOLD,fade*0.8),3.2*visual_scale,true)
	draw_arc(Vector2.ZERO,(10.0+110.0*t)*visual_scale,0,TAU,48,Color(IVORY,fade*0.5),1.2*visual_scale,true)
	for ray in [Vector2.DOWN,Vector2.RIGHT]:
		var reach: float = (95.0 if ray == Vector2.DOWN else 70.0)*visual_scale*(1.0+t)
		draw_line(-ray*reach,ray*reach,Color(GOLD,flash*0.5),9.0*visual_scale,true)
		draw_line(-ray*reach,ray*reach,Color(IVORY,flash),2.5*visual_scale,true)
	for fragment in fragments:
		var point: Vector2 = fragment.velocity*elapsed+Vector2.DOWN*180.0*visual_scale*elapsed*elapsed
		var ray := Vector2.from_angle(float(fragment.rotation)+float(fragment.spin)*elapsed)
		var side := ray.orthogonal()
		var length: float = fragment.length*visual_scale*(1.0-t*0.65)
		var width: float = fragment.width*visual_scale
		var shard := PackedVector2Array([point-ray*length*0.55,point+side*width,
			point+ray*length*0.65,point-side*width*0.55])
		draw_circle(point,width*2.0,Color(GOLD,fade*0.13))
		draw_colored_polygon(shard,Color(GOLD,fade*0.9))
		draw_line(point-ray*length*0.40,point+ray*length*0.52,Color(IVORY,fade),1.3*visual_scale,true)
