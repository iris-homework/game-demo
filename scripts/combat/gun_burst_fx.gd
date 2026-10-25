extends Node2D
## Layered local gunfire: hot muzzle petals, shock rings and contact sparks.
## Presentation only; no projectile, gameplay RNG or connecting beam.
const IVORY := Color("fff3d5")
const GOLD := Color("ffbd63")
const EMBER := Color("ff653c")
const CYAN := Color("64e9ff")
const PINK := Color("ff4f91")

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
	# Keep the existing local hit-stop, without freezing the camera or HUD.
	var held := minf(delta, hold_remaining)
	hold_remaining -= held
	delta -= held
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	queue_redraw()

func noise(index: int) -> float:
	return fposmod(sin(float(index * 127 + variation * 53 + 19)) * 43758.5453, 1.0)

func shard(start: Vector2, end: Vector2, width: float, tint: Color, alpha: float) -> void:
	if alpha <= 0.001 or width <= 0.001 or start.distance_squared_to(end) < 0.01: return
	var axis := (end-start).normalized()
	var normal := Vector2(-axis.y, axis.x)
	var middle := start.lerp(end, 0.28)
	var points := PackedVector2Array([start, middle+normal*width, end, middle-normal*width*0.65])
	draw_colored_polygon(points, Color(tint, alpha))
	draw_line(start, end, Color(IVORY, alpha*0.65), 0.7, true)

func glow(center: Vector2, radius: float, tint: Color, alpha: float) -> void:
	# Soft stepped falloff, also supported by the Compatibility renderer.
	for layer in range(5, 0, -1):
		draw_circle(center, radius*float(layer)/5.0, Color(tint, alpha*0.06))

func arc(center: Vector2, radii: Vector2, start: float, sweep: float, tint: Color, alpha: float, width: float = 1.0) -> void:
	if alpha <= 0.001: return
	var points := PackedVector2Array()
	for j in 33:
		var angle := start+sweep*float(j)/32.0
		points.append(center+Vector2(cos(angle), sin(angle))*radii)
	draw_polyline(points, Color(tint, alpha*0.12), width+3.0, true)
	draw_polyline(points, Color(tint, alpha), width, true)

func _draw() -> void:
	var t := clampf(elapsed/duration, 0.0, 1.0)
	var fade := pow(1.0-t, 1.5)
	var flash := pow(maxf(0.0, 1.0-t/0.62), 1.6)
	var expansion := 1.0-pow(1.0-t, 3.0)
	if mode == "muzzle":
		_draw_muzzle(t, fade, flash, expansion)
	else:
		_draw_impact(t, fade, flash, expansion)

func _draw_muzzle(t: float, fade: float, flash: float, expansion: float) -> void:
	glow(Vector2(20, 0), 50.0+expansion*12.0, EMBER, flash*0.8)
	glow(Vector2(8, 0), 24.0, GOLD, flash)
	# Broad outer flame, golden inner petals, then a sharp ivory core.
	for i in 9:
		var angle := lerpf(-1.05, 1.05, float(i)/8.0)+(noise(i)-0.5)*0.16
		var ray := Vector2.from_angle(angle)
		var reach := lerpf(40.0, 88.0, noise(i+30))*(1.0-t*0.55)
		shard(Vector2(-3, 0), ray*reach, lerpf(5.0, 11.0, noise(i+60))*flash, EMBER, flash*0.65)
		shard(Vector2.ZERO, ray*reach*0.82, lerpf(2.8, 6.0, noise(i+60))*flash, GOLD, flash*0.9)
		shard(Vector2.ZERO, ray*reach*0.56, 2.6*flash, IVORY, flash)
	shard(Vector2(-5, 0), Vector2(105.0*(1.0-t*0.65), 0), 7.5*flash, IVORY, flash)
	# Two expanding, incomplete pressure rings perpendicular to the barrel.
	for i in 2:
		var ring := float(i)
		var center := Vector2(15.0+ring*23.0+expansion*31.0, 0)
		var radii := Vector2(8.0+expansion*8.0, 23.0+ring*7.0+expansion*20.0)
		arc(center, radii, -1.33, 2.66, CYAN if i == 1 else GOLD, fade*(0.68-ring*0.18), 1.2)
		arc(center, radii, 1.95, 2.35, IVORY, fade*0.4, 0.8)
	_draw_sparks(true, t, fade, expansion)
	# Small hot curls lift away after the initial flash instead of a static star.
	for i in 3:
		var index := float(i)
		arc(Vector2(11+index*12+expansion*13, -13-index*10-t*25), Vector2(7+expansion*11, 12+expansion*9), -2.6+t, 2.4, GOLD, fade*(0.18+0.15*t), 0.8)
	_draw_core(flash, GOLD)

func _draw_impact(t: float, fade: float, flash: float, expansion: float) -> void:
	var accent := CYAN if blocked else PINK
	glow(Vector2.ZERO, 47.0+expansion*24.0, accent, flash*0.85)
	# Broken concentric corona leaves the central contact and body readable.
	for i in 3:
		var start := float(i)*TAU/3.0+0.25+t*0.45
		arc(Vector2.ZERO, Vector2(32, 40)*(0.8+expansion*1.15), start, 1.48, accent, fade*0.75, 1.7)
		arc(Vector2.ZERO, Vector2(22, 28)*(0.9+expansion*1.0), start+0.15, 1.05, IVORY, flash*0.65, 0.9)
	for i in 20:
		var angle := float(i)*2.39996+(noise(i+100)-0.5)*0.36
		var ray := Vector2.from_angle(angle)
		var inner := 6.0+expansion*24.0
		var reach := lerpf(33.0, 70.0, noise(i+140))+expansion*19.0
		shard(ray*inner, ray*reach, lerpf(1.0, 3.2, noise(i+180))*(1.0-t*0.7), accent, fade*0.75)
		if i%2 == 0:
			shard(ray*inner, ray*reach*0.82, 1.4*(1.0-t), IVORY, fade)
	if blocked:
		# A curved frontal shield and detached chips distinguish blocked contact.
		arc(Vector2(8, 0), Vector2(26, 46)*(1.0+expansion*0.25), 1.85, 2.58, CYAN, fade, 2.4)
		for i in 5:
			var angle := 2.0+float(i)*0.53
			var center := Vector2(8, 0)+Vector2.from_angle(angle)*Vector2(33, 51)*(1+expansion*0.65)
			var axis := Vector2.from_angle(angle+PI/2.0)
			shard(center-axis*4, center+axis*5, 2.2*fade, CYAN, fade*0.85)
	else:
		# A short oblique flare punctuates damage without spanning the battlefield.
		var ray := Vector2(0.82, -0.57)
		shard(-ray*29*flash, ray*60*flash, 4.0*flash, PINK, flash*0.6)
		shard(-ray*19*flash, ray*43*flash, 1.5*flash, IVORY, flash)
	_draw_sparks(false, t, fade, expansion)
	_draw_core(flash, accent)

func _draw_sparks(muzzle: bool, t: float, fade: float, expansion: float) -> void:
	for i in (19 if muzzle else 25):
		var angle := (noise(i+220)-0.5)*2.65 if muzzle else float(i)*2.39996
		var ray := Vector2.from_angle(angle)
		var speed := lerpf(25.0, 64.0, noise(i+260))
		var point := ray*(12.0+noise(i+290)*15.0+expansion*speed)
		point.y += t*t*23.0
		var tail := point-ray*lerpf(4.0, 15.0, noise(i+320))*(1.0-t)
		var tint := GOLD if muzzle else (CYAN if blocked or i%3 == 0 else PINK)
		draw_line(tail, point, Color(tint, fade*0.12), 3.4, true)
		draw_line(tail, point, Color(tint, fade*0.85), 1.0, true)
		if i%4 == 0:
			var radius := lerpf(1.0, 2.1, noise(i+350))*fade
			draw_line(point-Vector2(radius*2, 0), point+Vector2(radius*2, 0), Color(IVORY, fade), 0.8, true)
			draw_line(point-Vector2(0, radius*2), point+Vector2(0, radius*2), Color(IVORY, fade), 0.8, true)

func _draw_core(flash: float, tint: Color) -> void:
	if flash <= 0.001: return
	glow(Vector2.ZERO, 18.0*flash, tint, flash)
	shard(Vector2(-10, 0)*flash, Vector2(22, 0)*flash, 3.8*flash, IVORY, flash)
	shard(Vector2(0, -18)*flash, Vector2(0, 18)*flash, 2.2*flash, IVORY, flash*0.85)
