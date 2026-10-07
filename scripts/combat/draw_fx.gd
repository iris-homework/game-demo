extends Node2D
## Presentation only: the battle retains ownership of the live hand card.
signal departed
signal landed
const CYAN := Color("64ffe1")
const PINK := Color("ff3158")
var outline := PackedVector2Array([Vector2(-90,-103),Vector2(-78,-115),Vector2(74,-115),Vector2(90,-99),Vector2(90,101),Vector2(76,115),Vector2(-90,115),Vector2(-90,-103)])
var card: CombatCard
var origin := Vector2.ZERO
var destination := Vector2.ZERO
var progress := 0.0
var arrival := -1.0
var active := false
var final_scale := 1.0
var final_angle := 0.0

func start(view: CombatCard, source: Vector2, duration: float, delay: float) -> void:
	card = view
	final_scale = view.home_scale
	final_angle = view.home_rotation
	origin = source
	destination = view.home+view.pivot_offset
	z_index = 9
	view.position = origin-view.pivot_offset
	view.scale = scale_at(0.0)
	view.rotation = angle_at(0.0)
	view.visible = false
	var tween := create_tween()
	if delay > 0.0: tween.tween_interval(delay)
	tween.tween_callback(func(): active = true; card.visible = true; departed.emit())
	tween.tween_method(update_flight,0.0,1.0,duration)
	tween.tween_callback(land)
	tween.tween_method(update_arrival,0.0,1.0,0.18)
	tween.tween_callback(queue_free)

func path_at(t: float) -> Vector2:
	var u := 1.0-pow(1.0-t,2.0)
	return origin.bezier_interpolate(origin+Vector2(125,-180),destination+Vector2(-110,-100),destination,u)

func scale_at(t: float) -> Vector2:
	var unfold := smoothstep(0.0,0.88,t)
	var bounce := sin(smoothstep(0.65,1.0,t)*PI)*0.035
	return Vector2.ONE*(lerpf(0.25,final_scale,unfold)+bounce)

func angle_at(t: float) -> float:
	return lerpf(-1.1,final_angle,1.0-pow(1.0-t,3.0))

func update_flight(t: float) -> void:
	progress = t
	card.position = path_at(t)-card.pivot_offset
	card.scale = scale_at(t)
	card.rotation = angle_at(t)
	queue_redraw()

func land() -> void:
	# Tail effects must never move, free or disable a card after input resumes.
	card.position = card.home
	card.scale = Vector2.ONE*final_scale
	card.rotation = final_angle
	card = null
	landed.emit()

func update_arrival(t: float) -> void:
	arrival = t
	queue_redraw()

func _draw() -> void:
	if not active: return
	var fade := 1.0 if arrival < 0.0 else 1.0-arrival
	for i in range(18):
		var t := maxf(0.0,progress-float(i)*0.013)
		var previous := maxf(0.0,t-0.018)
		var alpha := (1.0-float(i)/18.0)*0.55*fade
		var a := path_at(t)
		var b := path_at(previous)
		draw_line(a,b,Color(CYAN,alpha*0.12),17.0,true)
		draw_line(a,b,Color(CYAN,alpha),2.5,true)
		draw_line(a+Vector2(-5,7),b+Vector2(-5,7),Color(PINK,alpha*0.8),1.5,true)
	for i in range(4,0,-1):
		var t := maxf(0.0,progress-float(i)*0.048)
		draw_set_transform(path_at(t),angle_at(t),scale_at(t))
		draw_polyline(outline,Color(CYAN if i%2 == 0 else PINK,0.18*fade),2.0,true)
	draw_set_transform(Vector2.ZERO)
	# Launch pulse stays around the deck; landing accents frame readable text.
	var launch := clampf(progress*2.5,0.0,1.0)
	draw_arc(origin,20.0+launch*43.0,-PI*0.8,PI*0.8,32,Color(CYAN,(1.0-launch)*0.55),2.0,true)
	if arrival >= 0.0:
		draw_set_transform(destination,final_angle,Vector2.ONE*(final_scale+arrival*0.075))
		draw_polyline(outline,Color(CYAN,fade*0.7),2.0,true)
		draw_set_transform(Vector2.ZERO)
		for side in [-1.0,1.0]:
			var pos := destination+Vector2(side*(94.0+arrival*20.0),90.0)
			draw_line(pos,pos+Vector2(side*8.0,-9.0),Color(PINK,fade*0.6),2.0,true)
