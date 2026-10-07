extends Node2D
## Owns only a detached visual card. Never touches combat state or input locks.
signal landed
const CYAN := Color("64ffe1")
const PINK := Color("ff3158")
var outline := PackedVector2Array([Vector2(-90,-103),Vector2(-78,-115),Vector2(74,-115),Vector2(90,-99),Vector2(90,101),Vector2(76,115),Vector2(-90,115),Vector2(-90,-103)])
var card: CombatCard
var origin := Vector2.ZERO
var destination := Vector2.ZERO
var control := Vector2.ZERO
var start_scale := Vector2.ONE
var start_angle := 0.0
var progress := 0.0
var arrival := -1.0
var strength := 1.0

func start(view: CombatCard, target: Vector2, duration: float, delay: float, intensity: float) -> void:
	card = view
	origin = view.position + view.pivot_offset
	destination = target
	control = origin.lerp(target,0.5) + Vector2(65,-155)
	start_scale = view.scale
	start_angle = view.rotation
	strength = intensity
	z_index = 39
	# Node2D has no mouse surface; all card controls also ignore input.
	view.reparent(self)
	view.z_index = 1
	var tween := create_tween()
	if delay > 0.0: tween.tween_interval(delay)
	tween.tween_method(update_flight,0.0,1.0,duration)
	tween.tween_callback(func(): card.visible = false; landed.emit())
	tween.tween_method(update_arrival,0.0,1.0,0.24)
	tween.tween_callback(queue_free)

func path_at(t: float) -> Vector2:
	var u := t * t * (2.0-t)
	return origin.bezier_interpolate(control, destination+Vector2(-12,-90),destination,u)

func scale_at(t: float) -> Vector2:
	var shrink := start_scale.lerp(Vector2(0.055,0.055),pow(t,1.5))
	return shrink * Vector2(1.0-0.3*sin(t*PI),1.0)

func angle_at(t: float) -> float:
	return start_angle + t*t*3.5

func update_flight(t: float) -> void:
	progress = t
	card.position = path_at(t)-card.pivot_offset
	card.scale = scale_at(t)
	card.rotation = angle_at(t)
	card.modulate = Color(1.0,1.0,1.0,1.0-smoothstep(0.86,1.0,t))
	queue_redraw()

func update_arrival(t: float) -> void:
	arrival = t
	queue_redraw()

func _draw() -> void:
	if progress > 0.0:
		var fade := 1.0 if arrival < 0.0 else 1.0-arrival
		# Layered ribbons and offset silhouettes suggest chromatic afterimages.
		for i in range(18):
			var t := maxf(0.0,progress-float(i)*0.013)
			var previous := maxf(0.0,t-0.018)
			var alpha := (1.0-float(i)/18.0)*0.7*fade*strength
			var a := path_at(t)
			var b := path_at(previous)
			draw_line(a,b,Color(CYAN,alpha*0.12),17.0,true)
			draw_line(a,b,Color(CYAN,alpha),2.5,true)
			draw_line(a+Vector2(8,-5),b+Vector2(8,-5),Color(PINK,alpha*0.8),1.5,true)
		for i in range(4,0,-1):
			var t := maxf(0.0,progress-float(i)*0.048)
			draw_set_transform(path_at(t),angle_at(t),scale_at(t))
			draw_polyline(outline,Color(CYAN if i%2 == 0 else PINK,0.20*fade*strength),2.0,true)
		draw_set_transform(Vector2.ZERO)
	if arrival < 0.0:
		# A small receiver forms as the card approaches the upright pile.
		var charge := smoothstep(0.48,1.0,progress)
		draw_arc(destination,40.0-15.0*charge,-PI*0.85,PI*0.65,32,Color(CYAN,charge*0.75*strength),2.0,true)
	else:
		var fade := (1.0-arrival)*strength
		var radius := 19.0+arrival*52.0
		draw_arc(destination,radius,0,TAU,48,Color(CYAN,fade*0.8),2.0,true)
		draw_arc(destination,radius*0.68,-PI*0.7,PI*0.7,30,Color(PINK,fade),3.0,true)
		draw_circle(destination,15.0*(1.0-arrival),Color(CYAN,fade*0.3))
		for i in range(10):
			var direction := Vector2.from_angle(float(i)*TAU/10.0+0.3)
			var point := destination+direction*(22.0+arrival*(48.0+float(i%3)*9.0))
			draw_line(point,point+direction*(8.0-5.0*arrival),Color(PINK if i%2 else CYAN,fade),2.0,true)
