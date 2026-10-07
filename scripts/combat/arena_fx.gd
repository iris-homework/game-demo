extends Node2D
## A street plane and contact shadows anchor the portraits to the environment.
## Presentation only; no target or combat state is owned here.
var paint_ground := true
var contact_points: Array[Vector2] = []

func ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 64:
		var angle := float(i)/64.0*TAU
		points.append(center+Vector2(cos(angle)*radii.x,sin(angle)*radii.y))
	draw_colored_polygon(points,color)

func _draw() -> void:
	if paint_ground:
		# Blend the distant edge into the location art instead of adding a raised stage.
		for y in range(448,705):
			var depth := clampf((y-448.0)/65.0,0.0,1.0)
			var tone := Color("181822").lerp(Color("10121a"),(y-448.0)/257.0)
			tone.a = smoothstep(0.0,1.0,depth)*0.98
			draw_rect(Rect2(0,y,1440,1),tone)
		# Paving joints share a vanishing point; subdued reflections stay on the floor.
		var vanishing := Vector2(720,368)
		for x in [-1400,-600,0,480,960,1440,2040,2840]:
			var end := Vector2(x,705)
			var start := vanishing.lerp(end,(493.0-368.0)/(705.0-368.0))
			draw_line(start,end,Color("35313c70"),1.0,true)
		for y in [506,548,607,687]:
			draw_line(Vector2(0,y),Vector2(1440,y),Color("34313d70"),1.0,true)
		ellipse(Vector2(1085,535),Vector2(215,17),Color("447f8e08"))
	for center in contact_points:
		# Broad faint penumbra, then a tight dark contact patch under the soles.
		for layer in range(12,0,-1):
			ellipse(center+Vector2(-12,2),Vector2(38+layer*3.5,3+layer*0.85),Color(0.01,0.01,0.018,0.035))
		ellipse(center,Vector2(36,4),Color(0.008,0.008,0.014,0.42))
