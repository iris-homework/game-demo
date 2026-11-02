extends Node2D
## Target-centred ritual and light detonation. Only reveals supplied model hits.
const CHARGE_TIME := 0.62
const BURST_TIME := 0.72
const ExplosionShader := preload("res://shaders/noss_halo_explosion.gdshader")
const GOLD := Color("ffe66a")
const IVORY := Color("fffeed")
var bursting := false
var elapsed := 0.0
var visual_scale := 1.0
var burst_glow: ColorRect

func _ready() -> void:
	z_index = 18
	add_to_group("noss_heavy_vfx")
	add_to_group("noss_halo_burst" if bursting else "noss_halo_charge")
	if bursting:
		burst_glow = ColorRect.new()
		burst_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		burst_glow.size = Vector2(820,820)*visual_scale
		burst_glow.position = -burst_glow.size*0.5
		var glow_material := ShaderMaterial.new()
		glow_material.shader = ExplosionShader
		glow_material.set_shader_parameter("lifetime",BURST_TIME)
		burst_glow.material = glow_material
		add_child(burst_glow)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if is_instance_valid(burst_glow): burst_glow.material.set_shader_parameter("blast_age",elapsed)
	if elapsed >= (BURST_TIME if bursting else CHARGE_TIME):
		queue_free()
		return
	queue_redraw()

func ring(radius: float, color: Color, width: float, angle: float = 0.0) -> void:
	draw_arc(Vector2.ZERO,radius*visual_scale,angle,angle+TAU,96,color,width*visual_scale,true)

func _draw() -> void:
	if bursting:
		draw_burst()
	else:
		draw_charge()

func draw_charge() -> void:
	var t := clampf(elapsed/CHARGE_TIME,0.0,1.0)
	var appear := clampf(t*5.0,0.0,1.0)
	var radius := lerpf(112.0,83.0,t)
	var glow := (0.55+0.45*t)*appear
	draw_circle(Vector2.ZERO,radius*visual_scale,Color(GOLD,0.035*glow))
	ring(radius,Color(GOLD,glow*0.15),9.0)
	ring(radius,Color(GOLD,glow),2.6)
	ring(radius-9.0,Color(IVORY,glow*0.80),1.0)
	# Orbiting marks close around the target, then converge before detonation.
	for i in 12:
		var angle := float(i)*TAU/12.0+elapsed*0.45
		var axis := Vector2.from_angle(angle)
		var normal := axis.orthogonal()
		var center := axis*(radius+7.0)*visual_scale
		var length := (7.0+7.0*t)*visual_scale
		draw_line(center-axis*length,center+axis*length,Color(IVORY,glow),1.5*visual_scale,true)
		draw_line(center-normal*4.0*visual_scale,center+normal*4.0*visual_scale,Color(GOLD,glow),1.4*visual_scale,true)
	for i in 8:
		var axis := Vector2.from_angle(float(i)*TAU/8.0-elapsed*0.8)
		var point := axis*lerpf(138.0,40.0,t)*visual_scale
		var pulse := (0.4+0.6*pow(sin(elapsed*15.0+float(i)),2.0))*appear
		draw_circle(point,2.2*visual_scale,Color(IVORY,pulse))
	# A final inner ring signals the blast rather than obscuring the target.
	if t > 0.65:
		ring(lerpf(60.0,17.0,(t-0.65)/0.35),Color(IVORY,(t-0.65)*2.0),1.5)

func draw_burst() -> void:
	var t := clampf(elapsed/BURST_TIME,0.0,1.0)
	var fade := pow(1.0-t,1.6)
	var travel := 1.0-pow(1.0-t,2.5)
	# Uneven tapered shards replace the old evenly spaced wheel of thin lines.
	for i in 20:
		var axis := Vector2.from_angle(float(i)*2.39996+0.12)
		var normal := axis.orthogonal()
		var radius := 30.0+(190.0+float(i%5)*23.0)*travel
		var length := (20.0+float(i%4)*13.0)*fade
		var start := axis*radius*visual_scale
		var end := axis*(radius+length)*visual_scale
		var width := (2.0+float(i%3))*fade*visual_scale
		draw_line(start,end,Color(GOLD,fade*0.22),width*5.0,true)
		# Subpixel shards eventually collapse; skip them before triangulation.
		if width > 0.3*visual_scale and length > 0.75:
			draw_colored_polygon(PackedVector2Array([start-normal*width,end,start+normal*width]),Color(IVORY,fade))
	for i in 72:
		var axis := Vector2.from_angle(float(i)*2.39996)
		var point := axis*(22.0+(125.0+float(i%7)*27.0)*travel)*visual_scale
		var pulse := fade*(0.25+0.75*pow(sin(elapsed*36.0+float(i)),2.0))
		var size := (2.0+float(i%3))*visual_scale
		draw_line(point-Vector2(size*1.6,0),point+Vector2(size*1.6,0),Color(GOLD,pulse),1.2*visual_scale,true)
		draw_line(point-Vector2(0,size*2.0),point+Vector2(0,size*2.0),Color(IVORY,pulse),1.0*visual_scale,true)

static func play(stage, attacker, defender, hits: Array, on_hit: Callable) -> void:
	if not attacker.alive or not defender.alive: return
	stage.active_attacker = attacker
	stage.active_defender = defender
	attacker.face_toward(defender.position)
	defender.face_toward(attacker.position)
	await stage.wide()
	for index in hits.size():
		var hit: Dictionary = hits[index]
		attacker.set_pose("shoot")
		var target: Vector2 = stage.world.to_local(defender.to_global(defender.target_bounds.get_center()))
		var depth: float = stage.depth_scale(defender.position)
		var charge = load("res://scripts/combat/noss_halo_strike.gd").new()
		charge.position = target
		charge.visual_scale = depth
		stage.world.add_child(charge)
		stage.set_phase("halo_charge")
		await stage.get_tree().create_timer(CHARGE_TIME).timeout
		if is_instance_valid(charge): charge.queue_free()
		var burst = load("res://scripts/combat/noss_halo_strike.gd").new()
		burst.bursting = true
		burst.position = target
		burst.visual_scale = depth
		stage.world.add_child(burst)
		var damage := int(hit.get("damage",0))
		stage.play_hit_sound(int(hit.get("blocked",0)) > 0)
		defender.set_pose("damaged" if damage > 0 else "block")
		defender.sprite.modulate = Color(1.5,1.45,1.2)
		stage.last_hit_stop = stage._hit_stop(attacker,0.16)
		stage.kick_camera(signf(target.x-attacker.position.x),20.0 if damage > 0 else 10.0,0.28)
		stage.set_phase("halo_burst")
		on_hit.call(hit,index)
		await stage.get_tree().create_timer(stage.last_hit_stop).timeout
		defender.sprite.modulate = Color.WHITE
		stage.set_phase("recover")
		await stage.get_tree().create_timer(0.42).timeout
		if bool(hit.get("killed",false)):
			await stage.retire_actor(defender)
			break
		defender.set_pose("idle")
	attacker.set_pose("idle")
	stage.set_phase("idle")
