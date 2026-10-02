extends Node2D
## Vector environment accents, independent of place backgrounds and character art.
func _draw() -> void:
	for center in [Vector2(408,543),Vector2(1020,546)]:
		for ring in range(3):
			var points := PackedVector2Array()
			for i in 81:
				var angle := float(i)/80.0*TAU
				points.append(center+Vector2(cos(angle)*(171+ring*12),sin(angle)*(13+ring*4)))
			draw_polyline(points,Color(0.2,0.8,0.91,0.18-ring*0.035),1.2,true)
		draw_line(center+Vector2(-204,5),center+Vector2(-185,5),Color("509bac"),2,true)
		draw_line(center+Vector2(185,5),center+Vector2(204,5),Color("509bac"),2,true)
	for x in [44,1389]:
		draw_line(Vector2(x,398),Vector2(x,480),Color("345569"),1,true)
		for j in 5: draw_line(Vector2(x,399+j*16),Vector2(x+9,399+j*16),Color("345569"),1,true)
