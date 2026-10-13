extends Node2D
## A quiet oblique ground plane, drawn beneath the independently Y-sorted actors.
var baseline := 307.0

func _draw() -> void:
	var horizon := baseline-215.0
	var vanishing := Vector2(610,horizon-310)
	var rows := [horizon,horizon+22,horizon+52,horizon+93,horizon+147,horizon+217,horizon+307,horizon+424,horizon+574,horizon+770,horizon+1030]
	for i in rows.size()-1:
		var tint := Color("151923").lerp(Color("22232d"),minf(float(i)/8.0,1.0))
		draw_rect(Rect2(-4000,rows[i],9400,rows[i+1]-rows[i]),tint)
		draw_line(Vector2(-4000,rows[i]),Vector2(5400,rows[i]),Color(0.38,0.44,0.55,0.13),1.0,true)
	for x in range(-5000,6500,330):
		var near := Vector2(x,horizon+1030)
		var far := vanishing.lerp(near,310.0/1340.0)
		draw_line(far,near,Color(0.40,0.47,0.59,0.12),1.0,true)
	# Offset slab joints and short embedded lights establish scale without a combat grid.
	for row in range(2,8):
		var y: float = rows[row]
		var spread := (y-vanishing.y)/700.0
		for column in range(-5,7):
			var x := 650.0+(column*270.0+(110 if row%2 else 0))*spread
			draw_line(Vector2(x,y+4),Vector2(x+70*spread,y+4),Color(0.02,0.03,0.05,0.5),2,true)
	for segment in [Vector3(210,baseline-95,105),Vector3(1120,baseline+60,135),Vector3(560,baseline+145,160)]:
		draw_line(Vector2(segment.x,segment.y),Vector2(segment.x+segment.z,segment.y),Color(0.20,0.70,0.78,0.065),6,true)
		draw_line(Vector2(segment.x,segment.y),Vector2(segment.x+segment.z,segment.y),Color(0.26,0.66,0.72,0.23),1,true)
