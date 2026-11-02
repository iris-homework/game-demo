extends Node
## Sample actual Stage tweens; geometry checks independently measure companion clearance.
const Stage := preload("res://scripts/combat/test_stage.gd")
const Resolver := preload("res://scripts/combat/enemy_visual_resolver.gd")
var checks := 0
var failures: Array[String] = []
var output := ""
var capture := false
var stage
var observing := false
var samples: Array[Dictionary] = []
var reports: Array[Dictionary] = []
var pictures: Array[Image] = []
var picture_times: Array[float] = []
var elapsed := 0.0
var next_capture := 0.0
var moving_target := false
var target_moved := false

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func length_of(points: Array[Vector2]) -> float:
	var total := 0.0
	for i in points.size()-1: total += points[i].distance_to(points[i+1])
	return total

func clearance(points: Array[Vector2], attacker, defender) -> float:
	var result := INF
	for other in stage.actors_root.get_children():
		if other == attacker or other == defender or not other.alive: continue
		var foot: Vector2 = other.position/Stage.GROUND_CLEARANCE
		for i in points.size()-1:
			var nearest := Geometry2D.get_closest_point_to_segment(foot,points[i]/Stage.GROUND_CLEARANCE,points[i+1]/Stage.GROUND_CLEARANCE)
			result = minf(result,nearest.distance_to(foot))
	return result

func path_location(point: Vector2, points: Array[Vector2]) -> Vector2:
	var distance := INF
	var progress := 0.0
	var accumulated := 0.0
	for i in points.size()-1:
		var nearest := Geometry2D.get_closest_point_to_segment(point,points[i],points[i+1])
		if point.distance_to(nearest) < distance:
			distance = point.distance_to(nearest)
			progress = accumulated+points[i].distance_to(nearest)
		accumulated += points[i].distance_to(points[i+1])
	return Vector2(distance,progress)

func sample() -> void:
	var attacker = stage.enemies[0]
	var defender = stage.player
	var direction := 1.0 if defender.position.x >= attacker.position.x else -1.0
	var facing: bool = attacker.facing == direction and defender.facing == -direction
	facing = facing and signf(attacker.sprite.transform.x.x) == direction*attacker.source_facing and signf(defender.sprite.transform.x.x) == -direction*defender.source_facing
	samples.append({"time":elapsed,"point":attacker.position,"visible":attacker.is_visible_in_tree() and attacker.sprite.is_visible_in_tree(),"alpha":attacker.modulate.a*attacker.self_modulate.a*attacker.sprite.modulate.a*attacker.sprite.self_modulate.a,"facing":facing,"target":defender.position})

func _process(delta: float) -> void:
	if not observing: return
	elapsed += delta
	# A moving target exercises facing updates during travel, including a side change.
	if moving_target and elapsed >= 0.10 and not target_moved:
		stage.player.position.x = 1320.0
		target_moved = true
		return # The next Tween step must react before we observe its facing.
	sample()
	if capture and elapsed >= next_capture:
		RenderingServer.force_draw(false)
		pictures.append(get_viewport().get_texture().get_image())
		picture_times.append(elapsed)
		next_capture = elapsed+1.0/24.0

func run_case(title: String, mirrored: bool, detour: bool, live_target: bool = false) -> void:
	var attacker = stage.enemies[0]
	var defender = stage.player
	var baseline: float = stage.floor_y-30.0
	var positions: Array[Vector2] = [Vector2(1140,baseline),Vector2(850,baseline),Vector2(950,baseline+75)]
	defender.position = Vector2(405,baseline)
	for i in stage.enemies.size():
		stage.enemies[i].position = positions[i]
		stage.enemies[i].alive = not live_target or i == 0
		stage.enemies[i].modulate = Color.WHITE
		if not detour and i > 0: stage.enemies[i].position.y = baseline+180.0
	if mirrored:
		defender.position.x = 1440.0-defender.position.x
		for actor in stage.enemies: actor.position.x = 1440.0-actor.position.x
	attacker.set_pose("move")
	# The real attack caller faces both actors before requesting approach.
	attacker.face_toward(defender.position)
	defender.face_toward(attacker.position)
	var destination: Vector2 = stage.attack_destination(attacker,defender,86.0)
	var start: Vector2 = attacker.position
	var direct: Array[Vector2] = [start,destination]
	var planned: Array[Vector2] = stage.approach_path(attacker,defender,destination)
	var route: Array[Vector2] = stage.approach_motion_points(attacker,defender,destination)
	var distance := length_of(route)
	var duration: float = stage.approach_duration(attacker,route)
	check(not stage.path_clear(direct,attacker,defender) if detour else stage.path_clear(direct,attacker,defender),title+": fixture really requires the claimed route")
	check(planned.size() == 4 if detour else planned.size() == 2,title+": existing planner selects detour or direct")
	check(route[0] == start and route[-1] == destination,title+": exact start/contact retained")
	check(clearance(route,attacker,defender) >= 1.0-0.00001,title+": every route segment clears companions' elliptical soles")
	check(stage.path_clear(route,attacker,defender),title+": formal stage agrees that route is clear")
	check(route.size() > 4 if detour else route == direct,title+": roomy detour has sampled rounded corners; direct stays direct")
	var max_angle := 0.0
	var min_segment := INF
	for i in route.size()-1:
		min_segment = minf(min_segment,route[i].distance_to(route[i+1]))
		if i > 0: max_angle = maxf(max_angle,absf((route[i]-route[i-1]).angle_to(route[i+1]-route[i])))
	check(min_segment > 0.001,title+": no duplicate points or zero-length Tween divisions")
	check(max_angle < deg_to_rad(20.0),title+": adjacent motion segments turn gradually instead of 90 degrees")
	if detour:
		check(duration >= 0.42 and duration+0.0001 >= distance/1350.0,title+": long detour has readable travel time")
		check(distance < length_of(planned),title+": rounding actually cuts the right-angle corners")
	else:
		check(is_equal_approx(duration,stage.travel_duration(attacker,distance)),title+": direct travel keeps authored timing")
	var before: Dictionary = Game.state.duplicate(true)
	samples.clear()
	pictures.clear()
	picture_times.clear()
	elapsed = 0.0
	next_capture = 0.0
	moving_target = live_target
	target_moved = false
	stage.frame_attack(attacker,defender,destination)
	observing = true
	await stage.approach(attacker,defender,destination)
	observing = false
	sample()
	check(samples.size() >= 10,title+": actual Tween sampled throughout travel")
	check(attacker.position.distance_to(destination) < 0.001,title+": actual travel ends at exact contact")
	check(absf(elapsed-duration) < 0.055,title+": actual whole-route duration matches plan")
	var visible := true
	var faces := true
	var monotonic := true
	var max_deviation := 0.0
	var min_clearance := INF
	var max_step := 0.0
	var no_jump := true
	var travelled := 0.0
	var previous := start
	var previous_time := 0.0
	var previous_progress := 0.0
	var max_ease_error := 0.0
	var trajectory: Array = []
	for entry in samples:
		var point: Vector2 = entry.point
		var location := path_location(point,route)
		visible = visible and entry.visible and entry.alpha >= 0.999
		faces = faces and entry.facing
		monotonic = monotonic and location.y+0.01 >= previous_progress
		max_deviation = maxf(max_deviation,location.x)
		var segment: Array[Vector2] = [previous,point]
		min_clearance = minf(min_clearance,clearance(segment,attacker,defender))
		var step := previous.distance_to(point)
		max_step = maxf(max_step,step)
		# A sine ease has maximum speed PI/2 * length/duration. Allow two pixels
		# for process/Tween phase order and floating-point projection at a corner.
		no_jump = no_jump and step <= 1.65*distance/duration*maxf(0.0,entry.time-previous_time)+2.0
		travelled += step
		var expected := distance*(0.5-0.5*cos(PI*clampf(entry.time/duration,0.0,1.0)))
		max_ease_error = maxf(max_ease_error,absf(location.y-expected))
		trajectory.append({"time":entry.time,"x":point.x,"y":point.y,"alpha":entry.alpha,"mutualFacing":entry.facing})
		previous = point
		previous_time = entry.time
		previous_progress = location.y
	check(visible,title+": every actual movement sample remains fully opaque and visible")
	check(faces,title+": both actors face each other along actual movement")
	check(monotonic,title+": whole-route arc progress never reverses")
	check(max_deviation < 0.1,title+": actual movement follows the rounded safe route")
	check(min_clearance >= 0.985,title+": every observed movement segment avoids companions' soles")
	check(no_jump,title+": frame displacement stays within continuous ease speed bound")
	check(max_ease_error < distance/duration*0.04+1.0,title+": a single whole-route ease preserves momentum through corners")
	check(absf(travelled-distance) < 2.0,title+": sampled travel covers the full rounded-route length")
	check(Game.state == before and not Game.save_enabled,title+": presentation leaves game state unchanged and saving disabled")
	if live_target: check(target_moved and defender.position.x > start.x,title+": live target really crossed the attacker's horizontal side")
	var record := {"case":title,"distance":distance,"duration":duration,"elapsed":elapsed,"samples":samples.size(),"maxTurnDegrees":rad_to_deg(max_angle),"maxDeviation":max_deviation,"minCompanionClearance":min_clearance if min_clearance < INF else -1.0,"maxFrameStep":max_step,"maxEaseError":max_ease_error,"trajectory":trajectory}
	if capture:
		var directory := output.path_join(title)
		DirAccess.make_dir_recursive_absolute(directory)
		for i in pictures.size(): pictures[i].save_png(directory.path_join("frame_%04d.png" % i))
		record["captureTimes"] = picture_times.duplicate()
	reports.append(record)
	attacker.set_pose("idle")
	if stage.camera_tween != null and stage.camera_tween.is_running(): await stage.camera_tween.finished

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://approach_motion_qa_unused.json"
	Game.meta_path = "user://approach_motion_qa_meta_unused.json"
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = OS.get_temp_dir().path_join("approach_motion_qa")
	DirAccess.make_dir_recursive_absolute(output)
	if not "qa" in OS.get_user_data_dir().to_lower():
		push_error("Approach tests require a dedicated QA user directory")
		get_tree().quit(2)
		return
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit(2))
	capture = OS.get_environment("QA_CAPTURE") == "1" and DisplayServer.get_name() != "headless"
	var resolver := Resolver.new()
	var visuals: Array[Resolver.Visual] = []
	for i in 3:
		var visual := resolver.resolve({"id":"preview_fish","combatVisualId":"fish"},{})
		check(visual.id == "fish" and visual.diagnostics.is_empty(),"real fish visual resolves for slot %d" % i)
		visuals.append(visual)
	stage = Stage.new()
	add_child(stage)
	stage.setup(577.0,visuals)
	await get_tree().process_frame
	await run_case("rear-detour-left",false,true)
	await run_case("rear-detour-right",true,true)
	check(is_equal_approx(reports[0].distance,reports[1].distance),"left/right mirrored routes preserve distance")
	check(is_equal_approx(reports[0].duration,reports[1].duration),"left/right mirrored routes preserve duration")
	await run_case("direct-left",false,false)
	await run_case("direct-right",true,false)
	await run_case("live-target-side-change",false,false,true)
	check(await preload("res://scripts/combat/audio_cleanup.gd").release(stage,get_tree()),"stage audio references drained before cleanup")
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var result := {"checks":checks,"failures":failures,"cases":reports,"userDirectory":OS.get_user_data_dir(),"capture":capture,"physicalInput":false,"scope":"Real-stage geometry and sampled Tween state; GPU sequences optional, no human visual acceptance."}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("APPROACH_MOTION checks=%d failures=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
