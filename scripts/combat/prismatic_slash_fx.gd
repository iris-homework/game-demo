extends Node2D
## Procedural additive ribbons, shared by hits and teleport returns. Presentation only.
var mode := "slash"
var direction := 1.0
var progress := 0.0
var duration := 0.30
var manual := false
var blocked := false
var start := Vector2.ZERO
var end := Vector2.ZERO
const PALETTE := [Color("58fff1"),Color("589cff"),Color("b877ff"),Color("ff55be"),Color("ffc6ef")]

func _ready() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	z_index = 8

func _process(delta: float) -> void:
	if not manual:
		progress = minf(1.0,progress+delta/duration)
		if progress >= 1.0:
			queue_free()
			return
	queue_redraw()

func set_progress(value: float) -> void:
	progress = value
	queue_redraw()

func rainbow(t: float, alpha: float) -> Color:
	var part := clampf(t,0,0.999)*4
	var index := int(part)
	var color: Color = PALETTE[index].lerp(PALETTE[index+1],part-index)
	color.a = alpha
	return color

func ribbon_shape(points: PackedVector2Array, width: float, opacity: float, core: bool = false) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var colors := PackedColorArray()
	for i in points.size():
		var t := i/float(points.size()-1)
		var tangent := (points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]).normalized()
		var normal := Vector2(-tangent.y,tangent.x)
		var taper := pow(sin(PI*clampf(t,0.003,0.997)),0.7)
		left.append(points[i]+normal*width*taper*0.5)
		right.append(points[i]-normal*width*taper*0.5)
		colors.append(Color(1,0.95,1,opacity) if core else rainbow(t,opacity))
	# Explicit triangles stay valid even when a short return bends more tightly than its glow width.
	for i in range(points.size()-1):
		draw_primitive(PackedVector2Array([left[i],right[i],left[i+1]]),PackedColorArray([colors[i],colors[i],colors[i+1]]),PackedVector2Array())
		draw_primitive(PackedVector2Array([right[i],right[i+1],left[i+1]]),PackedColorArray([colors[i],colors[i+1],colors[i+1]]),PackedVector2Array())

func ribbon(points: PackedVector2Array, width: float, opacity: float) -> void:
	if points.size() < 2 or points[0].distance_to(points[-1]) < 0.1: return
	# Continuous tapered strips avoid the bright dotted joints of overlapping line segments.
	for layer in [4.0,2.3,1.45]: ribbon_shape(points,width*layer,opacity*0.055)
	ribbon_shape(points,width,opacity*0.72)
	ribbon_shape(points,width*0.20,opacity*0.88,true)
	var cyan_edge := PackedVector2Array()
	var pink_edge := PackedVector2Array()
	for point in points:
		cyan_edge.append(point+Vector2(0,-3))
		pink_edge.append(point+Vector2(0,3))
	draw_polyline(cyan_edge,Color("58ffef",opacity*0.30),1.0,true)
	draw_polyline(pink_edge,Color("ff48bb",opacity*0.30),1.0,true)

func blade_point(t: float) -> Vector2:
	if mode == "pierce":
		return Vector2(lerpf(-108,35,t)*direction,sin(t*PI)*-6)
	return Vector2((-72*(1-t)*(1-t)+110*2*(1-t)*t-25*t*t)*direction,lerpf(-73,58,t))

func return_point(t: float) -> Vector2:
	return start.lerp(end,t)-Vector2(0,sin(t*PI)*30)

func star(point: Vector2, radius: float, alpha: float) -> void:
	if radius <= 0.01 or alpha <= 0.001: return
	# Keep the inner corners inside the tips as the return spark shrinks.
	# Fixed 3px corners self-intersected near the end of the fade.
	var inset := minf(3.0, radius * 0.25)
	var outline := PackedVector2Array([point+Vector2(-radius,0),point+Vector2(-inset,-inset),point+Vector2(0,-radius*0.65),point+Vector2(inset,-inset),point+Vector2(radius,0),point+Vector2(inset,inset),point+Vector2(0,radius*0.65),point+Vector2(-inset,inset)])
	draw_colored_polygon(outline,Color(0.85,1,1,alpha))
	for r in [radius*0.8,radius*0.45]: draw_circle(point,r,Color(0.55,0.35,1,alpha*0.05))

func _draw() -> void:
	if mode == "return":
		var head := clampf(progress,0,1)
		var tail := maxf(0,head-0.46)
		var points := PackedVector2Array()
		for i in 30: points.append(return_point(lerpf(tail,head,i/29.0)))
		ribbon(points,14.0,0.86)
		var echo := PackedVector2Array()
		for p in points: echo.append(p+Vector2(0,7))
		ribbon(echo,2.0,0.34)
		star(return_point(head),19,0.9)
		return
	var fade := pow(1.0-progress,1.25)
	if mode == "vanish" or mode == "arrive":
		var points := PackedVector2Array()
		for i in 26:
			var t := i/25.0
			points.append(Vector2(lerpf(-55,55,t),sin(t*PI)*-22-18)+Vector2(0,-progress*22))
		ribbon(points,7,fade)
		star(Vector2(0,-28),24*(1-progress),fade)
	else:
		var head := minf(1,0.62+progress*2.5)
		var tail := maxf(0,(progress-0.22)*0.95)
		var points := PackedVector2Array()
		for i in 34: points.append(blade_point(lerpf(tail,head,i/33.0)))
		ribbon(points,11 if mode == "pierce" else 16,fade)
		star(Vector2.ZERO,30*(1-progress),fade)
	# Deterministic short shards travel away from the contact point.
	for i in 11:
		var angle := i*2.39996+0.25
		var ray := Vector2(cos(angle),sin(angle))
		var distance := 8+progress*(40+(i%3)*16)
		var point := ray*distance
		var tangent := Vector2(-ray.y,ray.x)
		var shard := PackedVector2Array([point+ray*(10*(1-progress)+2),point+tangent*1.7,point-ray*4,point-tangent*1.7])
		draw_colored_polygon(shard,rainbow(i/11.0,fade*0.7))
