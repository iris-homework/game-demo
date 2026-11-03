extends Node
## Real published two-lurker stage; presentation only, no model/RNG or input calls.
const Stage := preload("res://scripts/combat/test_stage.gd")
const Resolver := preload("res://scripts/combat/enemy_visual_resolver.gd")
const AudioCleanup := preload("res://scripts/combat/audio_cleanup.gd")
var checks := 0
var failures: Array[String] = []
var reports: Array[Dictionary] = []
var output := ""
var stage
var observing := false
var samples: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
var phases: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func snapshot() -> Dictionary:
	var attacker = stage.enemies[0]
	var defender = stage.player
	var direction := 1.0 if defender.position.x >= attacker.position.x else -1.0
	return {"phase":stage.phase,"frame":Engine.get_process_frames(),
		"x":attacker.position.x,"y":attacker.position.y,"targetX":defender.position.x,
		"direction":direction,"facing":attacker.facing,"targetFacing":defender.facing,
		"mirror":signf(attacker.sprite.transform.x.x),
		"targetMirror":signf(defender.sprite.transform.x.x),
		"pose":attacker.pose,"shakeDirection":stage.shake_direction}

func _process(_delta: float) -> void:
	if observing and stage.phase in ["bite_open","bite_close","impact","recover"]:
		samples.append(snapshot())

func record_phase(value: String) -> void:
	if observing and value in ["bite_open","bite_close","impact","recover"]:
		phases.append(snapshot())

func record_hit(hit: Dictionary, index: int) -> void:
	var entry := snapshot()
	entry["hit"] = hit.duplicate(true)
	entry["index"] = index
	contacts.append(entry)

func faces_target(entry: Dictionary) -> bool:
	return entry.facing == entry.direction and entry.targetFacing == -entry.direction \
		and entry.mirror == entry.direction*stage.enemies[0].source_facing \
		and entry.targetMirror == -entry.direction*stage.player.source_facing

func run_case(title: String, mirrored: bool, switch_side: bool) -> void:
	var enemies: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies/enemies.json"))
	var resolver := Resolver.new()
	var visuals: Array[Resolver.Visual] = []
	for id in ["luggage_lurker","luggage_lurker_second"]:
		check(enemies.has(id),title+": formal enemy definition exists: "+id)
		var visual := resolver.resolve(enemies.get(id,{}),enemies)
		check(visual.id == "luggage_lurker" and visual.diagnostics.is_empty(),title+": formal enemy resolves published luggage visual: "+id)
		visuals.append(visual)
	stage = Stage.new()
	add_child(stage)
	stage.setup(577.0,visuals)
	await get_tree().process_frame
	var attacker = stage.enemies[0]
	var defender = stage.player
	var companion = stage.enemies[1]
	check(stage.enemies.size() == 2,title+": exactly the real two-enemy formation, no synthetic blockers")
	check(attacker.pipeline_attacks.has("bite") and attacker.attack_style_override == "bite",title+": authored bite is selected by the real profile override")
	if not attacker.pipeline_attacks.has("bite"):
		await destroy_stage()
		return
	var config: Dictionary = attacker.pipeline_attacks.bite
	check(config.type == "bite" and config.movement == "approach" and config.muzzle == Vector2.ZERO,title+": unmodified published bite uses normal stage contact selection")
	var baseline: float = stage.floor_y-30.0
	defender.position = Vector2(720.0,baseline)
	attacker.position = Vector2(1140.0,baseline)
	var reach: float = attacker.pipeline_motion.get("reach",92.0)
	# One real companion covers all four preferred-side candidates: its sole
	# ellipse radii are 87.808 x 56.448, larger than the 35/42 offsets.
	var preferred: Vector2 = defender.position+Vector2(reach*stage.depth_scale(defender.position),0)
	companion.position = preferred if switch_side else Vector2(1000.0,baseline+180.0)
	if mirrored:
		for actor in stage.actors_root.get_children(): actor.position.x = 1440.0-actor.position.x
		preferred.x = 1440.0-preferred.x
	stage.update_depth()
	var initial_direction := 1.0 if defender.position.x >= attacker.position.x else -1.0
	var candidates: Array[Vector2] = []
	for offset in [Vector2.ZERO,Vector2(0,-42),Vector2(0,42),Vector2(-initial_direction*35,0),Vector2(initial_direction*reach*2,0)]:
		candidates.append(preferred+offset)
	var candidate_clearances: Array[float] = []
	for candidate in candidates:
		candidate_clearances.append(((candidate-companion.position)/Stage.GROUND_CLEARANCE).length())
	if switch_side:
		for i in 4: check(candidate_clearances[i] < 1.0,title+": real companion blocks preferred-side candidate %d" % i)
		check(candidate_clearances[4] >= 1.0,title+": opposite-side fifth candidate is clear")
	else:
		check(candidate_clearances[0] >= 1.0,title+": ordinary preferred contact is unobstructed")
	var destination: Vector2 = stage.attack_destination(attacker,defender,reach)
	check(destination.distance_to(candidates[4] if switch_side else candidates[0]) < 0.001,title+": real destination selector chooses the expected candidate")
	var contact_direction := 1.0 if defender.position.x >= destination.x else -1.0
	check(contact_direction == (-initial_direction if switch_side else initial_direction),title+": contact side changes exactly when the companion blocks it")
	var route: Array[Vector2] = stage.approach_motion_points(attacker,defender,destination)
	check(stage.path_clear(route,attacker,defender),title+": real approach route clears the companion")
	check(route.size() > 2 if switch_side else route.size() == 2,title+": blocked fixture really detours; ordinary control travels directly")
	var before: Dictionary = Game.state.duplicate(true)
	var revision: int = Game.revision
	var hits := [{"damage":5,"blocked":0,"hpAfter":95,"killed":false},
		{"damage":0,"blocked":7,"hpAfter":95,"killed":false}]
	var original_hits := hits.duplicate(true)
	samples.clear()
	contacts.clear()
	phases.clear()
	stage.phase_changed.connect(record_phase)
	observing = true
	# Formal intent requests pierce; production routing must select published bite.
	await stage.attack(attacker,defender,"pierce",hits,record_hit)
	observing = false
	check(contacts.size() == 2,title+": full authored attack reveals exactly two contacts")
	check(hits == original_hits,title+": supplied authoritative results remain unchanged")
	check(not samples.is_empty(),title+": actual attack Tween/poses were sampled")
	var all_facing := true
	var open_samples := 0
	var close_samples := 0
	for entry in samples:
		all_facing = all_facing and faces_target(entry)
		if entry.phase == "bite_open":
			open_samples += 1
			check(entry.pose == config.windupPose,title+": sampled windup uses the real bite-open pose")
		if entry.phase == "bite_close":
			close_samples += 1
			check(entry.pose == config.strikePose,title+": sampled release uses the real bite-close pose")
	check(all_facing,title+": every sampled windup, release, impact and recovery faces the current target with matching sprite mirrors")
	check(open_samples > 0 and close_samples > 0,title+": both bite-open and bite-close actually ran")
	for phase_name in ["bite_open","bite_close","impact","recover"]:
		var matching: Array = phases.filter(func(entry): return entry.phase == phase_name)
		check(matching.size() == 2,title+": each segment enters %s exactly once" % phase_name)
		if phase_name == "bite_open":
			for entry in matching:
				check(Vector2(entry.x,entry.y).distance_to(destination) < 0.001,title+": each windup begins at the selected contact point")
	for i in contacts.size():
		var entry := contacts[i]
		check(i < hits.size() and entry.index == i and entry.hit == original_hits[i],title+": segment %d calls back once in authoritative order" % i)
		check(entry.phase == "impact" and entry.pose == config.strikePose,title+": segment %d callback occurs in bite impact pose" % i)
		check(faces_target(entry) and entry.direction == contact_direction,title+": segment %d faces the actual post-approach side" % i)
		check(absf(entry.x-(destination.x+contact_direction*8.0)) < 0.001 and absf(entry.y-destination.y) < 0.001,title+": segment %d release moves exactly eight pixels toward the target" % i)
		check(absf(defender.position.x-entry.x) < absf(defender.position.x-destination.x),title+": segment %d release closes the target distance" % i)
		check(entry.shakeDirection == contact_direction,title+": segment %d camera shake follows the actual strike side" % i)
	check(attacker.position.distance_to(destination) < 0.001 and attacker.pose == "idle" and stage.phase == "idle",title+": both segments recover to the exact contact point and idle")
	check(companion.position.distance_to(candidates[0] if switch_side else Vector2(440.0 if mirrored else 1000.0,baseline+180.0)) < 0.001,title+": companion remains stationary")
	check(Game.state == before and Game.revision == revision and not Game.save_enabled,title+": complete presentation preserves Game state/revision with saving disabled")
	reports.append({"case":title,"initialDirection":initial_direction,"contactDirection":contact_direction,
		"destination":{"x":destination.x,"y":destination.y},"candidateClearances":candidate_clearances,
		"routePoints":route.size(),"samples":samples.duplicate(true),"phases":phases.duplicate(true),"contacts":contacts.duplicate(true)})
	await destroy_stage()

func destroy_stage() -> void:
	check(await AudioCleanup.release(stage,get_tree()),"stage audio references drained before cleanup")
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	stage = null

func write_result() -> void:
	var result := {"checks":checks,"failures":failures,"cases":reports,
		"userDirectory":OS.get_user_data_dir(),"displayServer":DisplayServer.get_name(),
		"physicalInput":false,"scope":"Headless real-stage published authored bite direction and callbacks; no visual or listening acceptance."}
	var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	if file == null:
		push_error("Cannot write authored attack direction evidence")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(result,"\t"))

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://authored_attack_direction_qa_unused.json"
	Game.meta_path = "user://authored_attack_direction_qa_meta_unused.json"
	output = OS.get_environment("QA_OUT_DIR")
	if DisplayServer.get_name() != "headless" or not "qa" in OS.get_user_data_dir().to_lower() or not output.is_absolute_path():
		push_error("Requires --headless, a dedicated user directory containing qa, and absolute QA_OUT_DIR")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create authored attack direction evidence directory")
		get_tree().quit(2)
		return
	get_tree().create_timer(60.0).timeout.connect(func():
		failures.append("Authored attack direction tests timed out")
		write_result()
		push_error("Authored attack direction tests timed out")
		get_tree().quit(2))
	var original_state: Dictionary = Game.state.duplicate(true)
	var original_revision: int = Game.revision
	await run_case("blocked-preferred-left-to-right",false,true)
	await run_case("blocked-preferred-right-to-left",true,true)
	await run_case("ordinary-from-right",false,false)
	await run_case("ordinary-from-left",true,false)
	check(Game.state == original_state and Game.revision == original_revision,"All four complete authored attacks leave adventure state and revision unchanged")
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path),"No QA save/meta files were created")
	write_result()
	print("AUTHORED_ATTACK_DIRECTION checks=%d failures=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
