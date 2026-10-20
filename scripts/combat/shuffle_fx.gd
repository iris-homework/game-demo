extends Node2D
## Card backs only. Never touches the shuffled order, live cards or global RNG.
signal transferred(amount: int)
signal landed
const FLIGHT_TIME := 0.64
const STAGGER := 0.035
var outline := PackedVector2Array([
	Vector2(-23,-29),Vector2(16,-29),Vector2(23,-22),
	Vector2(23,23),Vector2(17,29),Vector2(-23,29),Vector2(-23,-29)])
const CYAN := Color("#64ffe1")
const PINK := Color("#ff3158")
var origin := Vector2.ZERO
var destination := Vector2.ZERO
var elapsed := 0.0
var total_duration := 0.0
var visual_count := 0
var card_count := 0
var arrived := 0

func start(source: Vector2, target: Vector2, amount: int) -> void:
	origin = source
	destination = target
	card_count = amount
	visual_count = mini(amount,12)
	total_duration = FLIGHT_TIME+STAGGER*(visual_count-1)
	z_index = 45
	var tween := create_tween()
	tween.tween_method(update_flight,0.0,total_duration,total_duration)
	tween.tween_callback(func(): landed.emit(); queue_free())

func update_flight(time: float) -> void:
	elapsed = time
	while arrived < visual_count and elapsed+0.0001 >= FLIGHT_TIME+STAGGER*arrived:
		# A large pile uses representative cards, with exact aggregate counts.
		var before := floori(float(arrived)*card_count/visual_count)
		arrived += 1
		transferred.emit(floori(float(arrived)*card_count/visual_count)-before)
	queue_redraw()

func path_at(t: float, index: int) -> Vector2:
	var height := 190.0+float(index%4)*25.0
	var u := smoothstep(0.0,1.0,t)
	return origin.bezier_interpolate(origin+Vector2(-290,-height),
		destination+Vector2(290,-height),destination,u)

func angle_at(t: float, index: int) -> float:
	# The long edge follows the flight tangent: landscape at the arc's crest.
	# Reverse the tangent before taking its angle to avoid the ±PI wrap.
	var tangent := path_at(minf(1.0,t+0.002),index)-path_at(maxf(0.0,t-0.002),index)
	var along_arc := (-tangent).angle()-PI/2.0
	var turn_in := smoothstep(0.0,0.16,t)
	var turn_out := 1.0-smoothstep(0.84,1.0,t)
	return along_arc*turn_in*turn_out

func trail_ribbon(t: float, index: int, width: float, color: Color, offset: float = 0.0) -> void:
	# One continuous, tapered ribbon with interpolated vertex alpha. Shared
	# edges avoid the bright joints left by many overlapping line segments.
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var shades := PackedColorArray()
	var centers := PackedVector2Array()
	var start := maxf(0.0,t-0.15)
	var visibility := smoothstep(0.0,0.12,t)*(1.0-smoothstep(0.78,1.0,t))
	for sample_index in 25:
		var q := float(sample_index)/24.0
		var sample_t := lerpf(start,t,q)
		var tangent := (path_at(minf(1.0,sample_t+0.002),index)-path_at(maxf(0.0,sample_t-0.002),index)).normalized()
		var normal := Vector2(-tangent.y,tangent.x)
		var center := path_at(sample_t,index)+normal*offset
		centers.append(center)
		var half_width := width*lerpf(0.025,1.0,pow(q,0.75))
		left.append(center+normal*half_width)
		right.append(center-normal*half_width)
		shades.append(Color(color,color.a*pow(q,1.65)*visibility))
	if width < 1.0:
		draw_polyline_colors(centers,shades,width*2.0,true)
		return
	# Draw joined quads directly: very short, thin launch ribbons must not
	# depend on polygon triangulation tolerances.
	for i in range(left.size()-1):
		draw_primitive(
			PackedVector2Array([left[i],left[i+1],right[i+1],right[i]]),
			PackedColorArray([shades[i],shades[i+1],shades[i+1],shades[i]]),
			PackedVector2Array())

func draw_trail(t: float, index: int) -> void:
	trail_ribbon(t,index,9.0,Color(CYAN,0.035))
	trail_ribbon(t,index,5.0,Color(CYAN,0.075))
	trail_ribbon(t,index,2.2,Color(CYAN,0.20))
	trail_ribbon(t,index,0.7,Color(Color("#bbfff1"),0.72))
	trail_ribbon(t,index,0.65,Color(PINK,0.32),4.0)
	# Sparse glints follow the same tangent and fade into the wake.
	if index%2 != 0: return
	for spark in 3:
		var lag := 0.04+float(spark)*0.035
		if t <= lag: continue
		var sample_t := t-lag
		var tangent := (path_at(sample_t+0.002,index)-path_at(sample_t-0.002,index)).normalized()
		var normal := Vector2(-tangent.y,tangent.x)
		var drift := sin(index*2.1+spark*3.0)*float(spark+1)*2.5
		var speck := path_at(sample_t,index)+normal*drift
		var opacity := sin(t*PI)*(0.65-float(spark)*0.16)
		draw_line(speck-tangent*4.0,speck+tangent*1.5,Color(CYAN,opacity*0.5),1.0,true)
		draw_circle(speck,1.1,Color(Color("#d9fff8"),opacity),true,-1,true)

func _draw() -> void:
	# Render the complete wake first so no later card's trail paints over a
	# previously drawn card back when the swarm overlaps.
	for index in visual_count:
		var t := (elapsed-index*STAGGER)/FLIGHT_TIME
		if t > 0.0 and t < 1.0: draw_trail(t,index)
	for index in visual_count:
		var t := (elapsed-index*STAGGER)/FLIGHT_TIME
		if t < 0.0 or t >= 1.0: continue
		var accent := CYAN.lerp(PINK,float(index%3)*0.30)
		var pos := path_at(t,index)
		var size_factor := 0.82*(1.0+sin(t*PI)*0.22)
		draw_set_transform(pos+Vector2(3,5),angle_at(t,index),Vector2.ONE*size_factor)
		draw_colored_polygon(outline,Color(0,0,0,0.40))
		draw_set_transform(pos,angle_at(t,index),Vector2.ONE*size_factor)
		draw_colored_polygon(outline,Color("#111b2c"))
		draw_polyline(outline,Color(accent,0.9),1.6,true)
		draw_rect(Rect2(-17,-23,34,46),Color(accent,0.24),false,1.0)
		var diamond := PackedVector2Array([Vector2(0,-12),Vector2(9,0),
			Vector2(0,12),Vector2(-9,0),Vector2(0,-12)])
		draw_polyline(diamond,accent,1.5,true)
		draw_line(Vector2(-12,-18),Vector2(4,-18),Color(accent,0.65),1.0,true)
		draw_line(Vector2(-4,18),Vector2(12,18),Color(accent,0.65),1.0,true)
		draw_set_transform(Vector2.ZERO)
	# A brief landing pulse ties the swarm back to the draw-pile icon.
	if elapsed >= FLIGHT_TIME:
		var pulse := clampf((elapsed-FLIGHT_TIME)/maxf(0.15,total_duration-FLIGHT_TIME),0,1)
		draw_arc(destination,25+pulse*16,-PI,PI,32,Color(CYAN,(1-pulse)*0.55),2,true)
