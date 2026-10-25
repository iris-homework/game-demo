extends Node
## Headless presentation regression. No screenshots, synthetic input, models or saves.
const Stage = preload("res://scripts/combat/test_stage.gd")
const GunBurst = preload("res://scripts/combat/gun_burst_fx.gd")
const AudioCleanup = preload("res://scripts/combat/audio_cleanup.gd")
var checks := 0
var failures: Array[String] = []
var stage: Control
var effects: Array[Dictionary] = []
var cues: Array[Dictionary] = []
var contacts: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func fixture() -> void:
	stage = Stage.new()
	add_child(stage)
	var resolver := EnemyVisualResolver.new()
	var visuals: Array[EnemyVisualResolver.Visual] = [resolver.resolve({"id":"gun_burst_target","combatVisualId":"gang_henchman"}, {})]
	stage.setup(577.0, visuals)
	stage.player.set_combat_stance("ranged")
	effects.clear()
	cues.clear()
	contacts.clear()
	stage.world.child_entered_tree.connect(record_effect)
	stage.combat_audio.cue_played.connect(record_cue)

func record_effect(node: Node) -> void:
	if node.get_script() != GunBurst: return
	effects.append({"mode":node.mode,"blocked":node.blocked,"variation":node.variation,
		"duration":node.duration,"hold":node.hold_remaining,"frame":Engine.get_process_frames(),
		"position":node.position,"scale":node.scale,"ref":weakref(node)})

func record_cue(cue: String) -> void:
	cues.append({"cue":cue,"frame":Engine.get_process_frames()})

func record_hit(hit: Dictionary, index: int) -> void:
	contacts.append({"hit":hit.duplicate(true),"index":index,"frame":Engine.get_process_frames()})
	check(effects.size() == (index+1)*2,"Both burst endpoints exist before segment %d callback" % index)
	check(cues.size() == index+1,"Exactly one gunshot precedes segment %d callback" % index)
	if effects.size() >= (index+1)*2 and cues.size() > index:
		var muzzle: Dictionary = effects[index*2]
		var impact: Dictionary = effects[index*2+1]
		var frame := Engine.get_process_frames()
		check(muzzle.mode == "muzzle" and impact.mode == "impact","Segment %d creates the muzzle and impact pair" % index)
		check(muzzle.frame == frame and impact.frame == frame and cues[index].frame == frame,"Segment %d endpoints, gunshot and callback share a frame" % index)
		check(cues[index].cue == "shoot","Segment %d retains its gunshot cue" % index)
		check(muzzle.variation == index and impact.variation == index,"Segment %d supplies matching burst variation" % index)
		check(impact.blocked == (int(hit.blocked)>0),"Segment %d preserves the impact block style" % index)
		check(is_equal_approx(muzzle.duration,0.19) and is_equal_approx(impact.duration,0.24),"Segment %d retains distinct burst lifetimes" % index)
		check(is_equal_approx(muzzle.hold,stage.last_hit_stop) and is_equal_approx(impact.hold,stage.last_hit_stop),"Segment %d holds both endpoints for the contact pause" % index)

func destroy_stage() -> void:
	check(await AudioCleanup.release(stage,get_tree()),"Stage audio playback references drain before disposal")
	stage.queue_free()
	await get_tree().process_frame
	stage = null

func test_local_clock() -> void:
	var fx := GunBurst.new()
	fx.set_process(false)
	fx.hold_remaining = 0.12
	add_child(fx)
	var time_scale := Engine.time_scale
	fx._process(0.03)
	check(is_equal_approx(fx.hold_remaining,0.09) and is_zero_approx(fx.elapsed),"First partial frame consumes only local hold")
	fx._process(0.04)
	check(is_equal_approx(fx.hold_remaining,0.05) and is_zero_approx(fx.elapsed),"Local hold carries across multiple frames")
	fx._process(0.09)
	check(is_zero_approx(fx.hold_remaining) and is_equal_approx(fx.elapsed,0.04),"Frame crossing hold boundary advances by its remaining delta")
	fx._process(0.05)
	check(is_equal_approx(fx.elapsed,0.09),"Following frame advances the normal animation clock")
	check(Engine.time_scale == time_scale and not get_tree().paused,"Contact pause leaves the engine and scene clocks running")
	fx._process(fx.duration)
	check(fx.is_queued_for_deletion(),"Lifetime expiry schedules effect deletion")
	await get_tree().process_frame
	check(not is_instance_valid(fx),"Expired standalone effect is released")

func test_natural_cleanup() -> void:
	var refs: Array[WeakRef] = []
	for mode in ["muzzle","impact"]:
		for blocked in [false,true]:
			var fx := GunBurst.new()
			fx.mode = mode
			fx.blocked = blocked
			fx.duration = 0.19 if mode == "muzzle" else 0.24
			fx.hold_remaining = 0.12
			add_child(fx)
			refs.append(weakref(fx))
	await get_tree().create_timer(0.50).timeout
	for ref in refs:
		check(ref.get_ref() == null,"Natural ticking releases each muzzle/impact and block variant")

func test_anchors_and_stage_cleanup() -> void:
	fixture()
	var refs: Array[WeakRef] = []
	var near_scale := 0.0
	var far_scale := 0.0
	# Move only presentation actors. Exercise the authored barrel through camera,
	# facing and foot-anchored depth transforms, rather than a screen-space offset.
	stage.player.pipeline_effects = {"scale":1.15,"offset":[3,-4]}
	for direction in [-1.0,1.0]:
		for lane in [-100.0,70.0]:
			stage.player.position = Vector2(720,stage.floor_y+lane)
			stage.enemies[0].position = Vector2(720+direction*450,stage.floor_y-lane)
			stage.player.face_toward(stage.enemies[0].position)
			stage.player.set_pose("shoot")
			stage.update_depth()
			stage.world.position = Vector2(83,-27)
			stage.world.scale = Vector2.ONE*1.17
			stage.last_hit_stop = 0.12
			var barrel: Vector2 = stage.player.sprite.to_global(Vector2(54,385))
			var depth: float = stage.depth_scale(stage.player.position)
			var target_depth: float = stage.depth_scale(stage.enemies[0].position)
			var expected_muzzle: Vector2 = stage.world.to_local(barrel)+Vector2(3,-4)*depth
			var expected_impact: Vector2 = stage.enemies[0].position+Vector2(-direction*8,-62)*target_depth+Vector2(3,-4)*target_depth
			stage.show_gun_bursts(stage.player,stage.enemies[0],direction,true,3)
			var muzzle: Dictionary = effects[-2]
			var impact: Dictionary = effects[-1]
			check(muzzle.position.is_equal_approx(expected_muzzle),"Muzzle remains on the authored barrel for facing %s lane %s" % [direction,lane])
			check(impact.position.is_equal_approx(expected_impact),"Impact follows defender depth for facing %s lane %s" % [direction,lane])
			check(muzzle.scale.is_equal_approx(Vector2(direction,1)*depth*1.15),"Muzzle mirrors horizontally and scales with attacker depth")
			check(impact.scale.is_equal_approx(Vector2(direction,1)*target_depth*1.15),"Impact mirrors horizontally and scales with defender depth")
			if lane < 0: far_scale = absf(muzzle.scale.x)
			else: near_scale = absf(muzzle.scale.x)
			refs.append(muzzle.ref)
			refs.append(impact.ref)
	check(near_scale > far_scale,"Foreground muzzle is larger than rear-lane muzzle")
	check(effects.size() == 8,"Each direct shot adds exactly two transient endpoints")
	for ref in refs:
		check(ref.get_ref() != null,"Stage disposal begins with active burst children")
	await destroy_stage()
	for ref in refs:
		check(ref.get_ref() == null,"Disposing the stage releases its active burst children")

func test_real_shots() -> void:
	fixture()
	var hits := [{"damage":5,"blocked":0,"hpAfter":95,"killed":false},
		{"damage":0,"blocked":8,"hpAfter":95,"killed":false},
		{"damage":3,"blocked":2,"hpAfter":92,"killed":false}]
	var before := hits.duplicate(true)
	await stage.ranged_attack(stage.player,stage.enemies[0],hits,record_hit)
	check(effects.size() == 6 and cues.size() == 3 and contacts.size() == 3,"Real three-segment ranged attack keeps all endpoint, cue and callback counts")
	check(hits == before,"Burst presentation leaves supplied model results unchanged")
	for index in contacts.size():
		check(contacts[index].index == index and contacts[index].hit == before[index],"Contact callback preserves segment order and supplied hit data")
	await get_tree().create_timer(0.40).timeout
	for effect in effects:
		check(effect.ref.get_ref() == null,"Real shot endpoint frees itself after the contact pause and lifetime")
	await destroy_stage()

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://gun_burst_tests/checkpoint_unused.json"
	Game.meta_path = "user://gun_burst_tests/meta_unused.json"
	var original_state: Dictionary = Game.state.duplicate(true)
	var original_revision: int = Game.revision
	get_tree().create_timer(30.0).timeout.connect(func():
		push_error("Gun burst tests timed out")
		get_tree().quit(2))
	await test_local_clock()
	await test_natural_cleanup()
	await test_anchors_and_stage_cleanup()
	await test_real_shots()
	check(Game.state == original_state and Game.revision == original_revision,"Burst tests preserve adventure state and revision")
	for path in [Game.save_path,Game.save_path+".bak",Game.save_path+".tmp",Game.meta_path,Game.meta_path+".tmp"]:
		check(not FileAccess.file_exists(path),"Presentation never creates test save file: "+path)
	print("GUN BURST TESTS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
