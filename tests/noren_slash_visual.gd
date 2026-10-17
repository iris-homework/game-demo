extends Node
## Actual stage attacks; isolated presentation, no saves and no physical input.
const Stage = preload("res://scripts/combat/test_stage.gd")
const Slash = preload("res://scripts/combat/noren_slash_fx.gd")
const Neon = preload("res://scripts/combat/prismatic_slash_fx.gd")
var stage: Control
var checks := 0
var failures := 0
var output := "res://artifacts/qa/noren-slash-2026-10-18/"
var case_name := ""
var expected_new := true
var expected_direction := 1.0
var callbacks: Array = []
var impacts: Array = []
var all_impacts: Array = []
var created_ids: Array[int] = []
var caption: Label

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(case_name+": "+title)

func effects(script: Script) -> Array:
	return stage.world.get_children().filter(func(node): return node.get_script() == script)

func on_hit(hit: Dictionary, index: int) -> void:
	callbacks.append({"index":index,"hit":hit.duplicate(true)})

func on_phase(value: String) -> void:
	if value != "impact": return
	var authored := effects(Slash)
	var legacy := effects(Neon)
	check(authored.size() == (1 if expected_new else 0),"Only Noren player slash uses authored effect")
	check(legacy.size() == (0 if expected_new else 1),"Other attacks retain legacy effect")
	var found: Array = authored if expected_new else legacy
	if found.size() != 1: return
	var fx = found[0]
	check(not created_ids.has(fx.get_instance_id()),"Each hit creates a fresh effect")
	created_ids.append(fx.get_instance_id())
	check(is_equal_approx(fx.direction,expected_direction),"Effect mirrors to actual attack direction")
	check(stage.active_attacker.pose in ["slash","pierce"],"Impact retains attacking pose")
	var hit: Dictionary = callbacks[-1].hit
	check(fx.blocked == (int(hit.get("blocked",0)) > 0),"Blocked presentation follows supplied hit")
	check(stage.active_defender.pose == ("block" if fx.blocked else "damaged"),"Impact retains matching defender pose")
	if expected_new:
		check(fx.scale.is_equal_approx(Vector2.ONE*stage.depth_scale(stage.active_defender.position)),"Authored effect follows defender depth scale")
		check(is_equal_approx(fx.duration,0.24 if fx.blocked else 0.30),"Slash lifetime preserves block timing")
	var record := {"case":case_name,"index":callbacks[-1].index,"direction":fx.direction,"scaleX":fx.scale.x,"attackerPose":stage.active_attacker.pose,"defenderPose":stage.active_defender.pose,"authored":expected_new,"blocked":fx.blocked}
	impacts.append(record)
	all_impacts.append(record)
	if DisplayServer.get_name() == "headless": return
	# Capture the actual contact positions and poses at a reproducible peak.
	# Restore automatic time immediately afterwards so lifetime is still exercised.
	var previous_progress: float = fx.progress
	fx.manual = true
	fx.set_progress(0.25)
	caption.text = "%s | hit %d | direction %+.0f | depth %.3f" % [case_name,callbacks.size(),expected_direction,stage.depth_scale(stage.active_defender.position)]
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output+"%s-hit-%02d.png" % [case_name,callbacks.size()])
	check(error == OK,"Peak screenshot saved")
	if is_instance_valid(fx):
		fx.set_progress(previous_progress)
		fx.manual = false

func run_case(label: String, style: String, supplied_hits: Array, direction: float, feet: float, enemy_attack: bool = false, new_effect: bool = true) -> void:
	case_name = label
	expected_new = new_effect
	expected_direction = direction
	callbacks.clear()
	impacts.clear()
	var attacker = stage.enemies[0] if enemy_attack else stage.player
	var defender = stage.player if enemy_attack else stage.enemies[0]
	attacker.position = Vector2(420 if direction > 0 else 1020,feet)
	defender.position = Vector2(900 if direction > 0 else 540,feet)
	attacker.set_pose("idle")
	defender.set_pose("idle")
	var original_hits := supplied_hits.duplicate(true)
	await stage.attack(attacker,defender,style,supplied_hits,on_hit)
	check(callbacks.size() == supplied_hits.size(),"Exactly one callback per supplied hit")
	check(impacts.size() == supplied_hits.size(),"Every hit produces an impact effect")
	for i in callbacks.size():
		check(callbacks[i].index == i and callbacks[i].hit == supplied_hits[i],"Callback preserves hit data and ordering")
	check(supplied_hits == original_hits,"Presentation leaves supplied results unchanged")
	await get_tree().create_timer(0.4).timeout
	check(effects(Slash).is_empty() and effects(Neon).is_empty(),"All transient attack effects release automatically")
	check(stage.phase == "idle","Attack returns to idle")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://noren_slash_qa_unused.json"
	Game.meta_path = "user://noren_slash_qa_meta_unused.json"
	output += "headless/" if DisplayServer.get_name() == "headless" else "render/"
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	var background := ColorRect.new()
	background.color = Color("11141c")
	background.size = Vector2(1440,900)
	add_child(background)
	caption = Label.new()
	caption.position = Vector2(72,180)
	caption.add_theme_font_size_override("font_size",24)
	add_child(caption)
	stage = Stage.new()
	add_child(stage)
	var resolver := EnemyVisualResolver.new()
	var visuals: Array[EnemyVisualResolver.Visual] = [resolver.resolve({"id":"qa_finn","combatVisualId":"finn"},{})]
	stage.setup(577,visuals)
	stage.phase_changed.connect(on_phase)
	await get_tree().process_frame
	check(stage.player.kind == "noren","Stage uses the real Noren player")
	check(Slash.TEXTURE.resource_path == "res://assets/combat_fx/noren_slash.png","Authored source texture is used")
	var hit := {"damage":6,"blocked":0,"hpAfter":94,"killed":false}
	await run_case("right-far-single","slash",[hit],1.0,stage.floor_y-105)
	await run_case("right-near-multi","slash",[hit,{"damage":0,"blocked":6,"hpAfter":94,"killed":false},{"damage":3,"blocked":3,"hpAfter":91,"killed":false}],1.0,stage.floor_y+45)
	await run_case("left-single","slash",[hit],-1.0,stage.floor_y-30)
	await run_case("enemy-slash","slash",[hit],-1.0,stage.floor_y-30,true,false)
	await run_case("player-pierce","pierce",[hit],1.0,stage.floor_y-30,false,false)
	# Verify the kind guard as well as the player-identity guard.
	stage.player.kind = "qa_other_character"
	await run_case("other-player-slash","slash",[hit],1.0,stage.floor_y-30,false,false)
	stage.player.kind = "noren"
	var manual = Slash.new()
	manual.manual = true
	stage.world.add_child(manual)
	manual.set_progress(0.25)
	await get_tree().create_timer(0.35).timeout
	check(is_instance_valid(manual) and is_equal_approx(manual.progress,0.25),"Manual preview holds its selected frame")
	manual.manual = false
	await get_tree().create_timer(0.4).timeout
	check(not is_instance_valid(manual),"Manual preview releases when automatic playback resumes")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"impacts":all_impacts,"physicalInput":false,"scope":"isolated real stage attacks; supplied hit results; no model or card input"},"\t"))
	print("NOREN SLASH: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
