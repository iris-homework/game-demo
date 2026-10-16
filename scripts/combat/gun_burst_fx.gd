extends Node2D
## Local ink-like flashes at the barrel / contact. No projectile or connecting beam.
var mode := "muzzle"
var blocked := false
var variation := 0
var elapsed := 0.0
var duration := 0.24
var hold_remaining := 0.0

func _ready() -> void:
	z_index = 9
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	queue_redraw()

func _process(delta: float) -> void:
	# Local hit-stop: leave the scene, HUD, input lock and camera clock running.
	var held := minf(delta,hold_remaining)
	hold_remaining -= held
	delta -= held
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	queue_redraw()

func noise(index: int) -> float:
	return fposmod(sin(float(index * 127 + variation * 53 + 19)) * 43758.5453, 1.0)

func shard(start: Vector2, end: Vector2, width: float, alpha: float) -> void:
	var axis := (end-start).normalized()
	var normal := Vector2(-axis.y,axis.x)
	var middle := start.lerp(end,0.22)
	var points := PackedVector2Array([start,middle+normal*width,end,middle-normal*width*0.55])
	draw_colored_polygon(points,Color(0.93,0.97,1.0,alpha))
	draw_line(start,end,Color(1,1,1,alpha*0.7),0.7,true)

func broken_arc(center: Vector2, radii: Vector2, start: float, sweep: float, alpha: float, seed_index: int) -> void:
	var points := PackedVector2Array()
	for j in 26:
		var angle := start+sweep*float(j)/25.0
		var ripple := 1.0+(noise(seed_index+j)-0.5)*0.13
		points.append(center+Vector2(cos(angle),sin(angle))*radii*ripple)
	draw_polyline(points,Color(0.81,0.87,0.91,alpha),0.9,true)

func _draw() -> void:
	var t := clampf(elapsed/duration,0,1)
	var fade := pow(1-t,1.4)
	var flash := pow(maxf(0,1-elapsed/0.10),0.8)
	var spread := 0.74+0.50*(1-pow(1-t,3))
	var muzzle := mode=="muzzle"
	var accent := Color("abcfff") if blocked else Color("ff416b")
	# A tight luminous core keeps the dense white strokes readable on dark costumes.
	for radius in [19.0,12.0,7.0]:
		draw_circle(Vector2.ZERO,radius*spread*(0.72 if muzzle else 1.0),Color(accent,flash*0.055))
	var count := 27 if muzzle else 44
	for i in count:
		var angle := (noise(i*3)-0.5)*2.45 if muzzle else float(i)*2.39996+noise(i*3)*0.45
		var ray := Vector2(cos(angle),sin(angle))
		var length := lerpf(21,65,noise(i*3+1)) if muzzle else lerpf(19,57,noise(i*3+1))
		if i%7==0: length *= 1.23
		var inner := lerpf(1,11,noise(i*3+2))+t*13
		var start := ray*inner*spread
		var end := ray*length*spread
		var alpha := fade*lerpf(0.35,0.95,noise(i+90))
		shard(start,end,lerpf(0.4,1.7,noise(i+140))*(1-t*0.65),alpha)
		if i%3==0:
			var bend := ray.rotated(0.21 if i%2==0 else -0.23)
			var points := PackedVector2Array([start,ray*length*0.42*spread,bend*length*0.69*spread,ray*length*0.82*spread])
			draw_polyline(points,Color(0.9,0.95,1,alpha*0.65),0.8,true)
	# Uneven shock loops and smoke curls, confined to each end of the shot.
	if muzzle:
		broken_arc(Vector2(9+t*11,-2),Vector2(8+t*5,25+t*14),-1.9,4.8,fade*0.75,31)
		broken_arc(Vector2(18+t*13,-13-t*16),Vector2(13,25+t*12),-2.7,4.0,fade*0.40,72)
		broken_arc(Vector2(12,-21-t*21),Vector2(8+t*8,19),-2.5,3.7,fade*0.27,106)
	else:
		broken_arc(Vector2(-2,0),Vector2(24,32)*spread,0.3,2.35,fade*0.61,31)
		broken_arc(Vector2(2,-3),Vector2(31,22)*spread,3.0,2.5,fade*0.49,72)
		# Thin colored fragments frame the white burst; block uses cool blue.
		for i in 12:
			var ray := Vector2.from_angle(float(i)*2.39996+0.5)
			var point := ray*(18+t*42+noise(i+210)*10)
			draw_line(point,point+ray*(4+noise(i+240)*10)*(1-t),Color(accent,fade*0.75),1.2,true)
	for i in (5 if muzzle else 7):
		var angle := (noise(i+300)-0.5)*3.0 if muzzle else float(i)*2.39996
		var ray := Vector2.from_angle(angle)
		var point := ray*(17+noise(i+330)*28+t*27)
		var radius := (0.6+noise(i+360)*1.1)*fade
		draw_line(point-Vector2(radius*1.8,0),point+Vector2(radius*1.8,0),Color(1,1,1,fade*0.7),0.8,true)
		draw_line(point-Vector2(0,radius*2.5),point+Vector2(0,radius*2.5),Color(1,1,1,fade*0.7),0.8,true)
	# Jagged central flash, short enough to expose the contact pose between rounds.
	for i in (9 if muzzle else 13):
		var angle := float(i)*TAU/(9.0 if muzzle else 13.0)
		var ray := Vector2.from_angle(angle)
		shard(-ray*2,ray*(8+noise(i+400)*13)*flash,2.1*flash,flash)
