extends Node
## Real attack playback and transient ownership; no models, saves or pointer input.
const Stage = preload("res://scripts/combat/test_stage.gd")
const Strike = preload("res://scripts/combat/dancer_strike_fx.gd")
const NorenSlash = preload("res://scripts/combat/noren_slash_fx.gd")
const NeonSlash = preload("res://scripts/combat/prismatic_slash_fx.gd")
const Palette = preload("res://shaders/dancer_strike_palette.gdshader")
const AudioCleanup = preload("res://scripts/combat/audio_cleanup.gd")
var stage: Control
var effects: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fixture(duet: bool) -> void:
	stage = Stage.new()
	add_child(stage)
	var resolver := EnemyVisualResolver.new()
	var visuals: Array[EnemyVisualResolver.Visual] = [resolver.resolve({"combatVisualId":"dancer_black"},{})]
	if duet: visuals.append(resolver.resolve({"combatVisualId":"dancer_white"},{}))
	stage.setup(577.0,visuals)
	if duet: stage.set_dancer_duet(visuals)
	effects.clear()
	contacts.clear()
	stage.world.child_entered_tree.connect(record_effect)

func record_effect(node: Node) -> void:
	if node.get_script() not in [Strike,NorenSlash,NeonSlash]: return
	effects.append({"script":node.get_script(),"mode":node.mode,"direction":node.direction,
		"blocked":node.blocked,"position":node.position,"scale":node.scale,
		"frame":Engine.get_process_frames(),"ref":weakref(node)})

func record_hit(hit: Dictionary, index: int) -> void:
	contacts.append({"hit":hit.duplicate(true),"index":index,"pose":stage.active_attacker.pose})
	check(effects.size() == index+1,"Each real segment produces exactly one strike before its callback")
	if effects.size() <= index: return
	var fx: Dictionary = effects[index]
	var expected_mode := "pierce" if stage.active_attacker.kind == "dancer_black" else "slash"
	var expected_pose := "slash_alt" if expected_mode == "slash" and index % 2 == 1 else expected_mode
	check(stage.active_attacker.pose == expected_pose,"Contact uses the correct pose: white slash / return slash / slash; black retains pierce")
	var expected_direction := 1.0 if stage.active_defender.position.x > stage.active_attacker.position.x else -1.0
	var depth: float = stage.depth_scale(stage.active_defender.position)
	var point: Vector2 = stage.active_defender.position + Vector2(-expected_direction*13,-62)*depth
	point += stage._effect_offset(stage.active_attacker)*depth
	check(fx.script == Strike and fx.mode == expected_mode,"Dancer action dispatches to its dedicated black thrust or white slash")
	check(fx.frame == Engine.get_process_frames(),"Dedicated strike and existing hit callback share the contact frame")
	check(fx.direction == expected_direction and fx.position.is_equal_approx(point),"Strike follows attack direction and target contact")
	var vertical_direction := -1.0 if expected_pose == "slash_alt" else 1.0
	check(fx.scale.is_equal_approx(Vector2(1.0,vertical_direction)*depth*stage._effect_scale(stage.active_attacker)),"Strike follows the upward return cut while preserving target depth and authored effect scale")
	check(fx.blocked == (int(hit.get("blocked",0)) > 0),"Strike receives full and partial block state")
	var live = fx.ref.get_ref()
	check(live != null and live.material is ShaderMaterial and live.material.shader == Palette,"Dancer hit uses its independent black and white palette material")
	if live != null and live.material is ShaderMaterial:
		check(bool(live.material.get_shader_parameter("piercing")) == (expected_mode == "pierce"),"Actual attack selects the matching black thrust or white slash palette")
		if expected_mode == "slash":
			check(is_instance_valid(live.impact_flash) and live.impact_flash.texture == NorenSlash.TEXTURE,"White slash preserves Noren's separate crescent and contact burst artwork")
		else:
			check(live.material.get_shader_parameter("opacity_reference") == NorenSlash.PIERCE_OPACITY_REFERENCE,"Black thrust preserves the existing airy interior opacity reference")

func destroy_stage() -> void:
	check(await AudioCleanup.release(stage,get_tree()),"Attack audio references drain before stage disposal")
	stage.queue_free()
	await get_tree().process_frame
	stage = null

func test_real_attacks(duet: bool) -> void:
	fixture(duet)
	var attacker: Node2D = stage.enemies[1 if duet else 0]
	if duet:
		check(attacker.poses.has("slash_alt"),"White dancer resolves its additional slash from the actual visual catalog")
		if attacker.poses.has("slash_alt"):
			check(attacker.poses.slash_alt != attacker.poses.slash,"Alternate slash uses a distinct texture")
	var hits := [{"damage":6,"blocked":0,"hpAfter":64,"killed":false},
		{"damage":0,"blocked":6,"hpAfter":64,"killed":false},
		{"damage":3,"blocked":3,"hpAfter":61,"killed":false}]
	var before := hits.duplicate(true)
	# Enemy intents use their authored style override, as in the actual Boss turn.
	await stage.attack(attacker,stage.player,"hit",hits,record_hit)
	check(effects.size() == 3 and contacts.size() == 3,"Three supplied hit segments keep exactly three visual effects and callbacks")
	check(hits == before,"Attack effects never alter supplied combat results")
	for i in contacts.size():
		check(contacts[i].hit == before[i] and contacts[i].index == i,"Callbacks retain the supplied hit data and order")
	check(attacker.pose == "idle","Attack completion restores the idle pose")
	if duet:
		effects.clear()
		contacts.clear()
		await stage.attack(attacker,stage.player,"hit",hits,record_hit)
		check(contacts.size() == 3 and contacts[0].pose == "slash" and contacts[1].pose == "slash_alt" and contacts[2].pose == "slash","A repeated triple attack restarts the slash / return slash / slash sequence")
	await stage.return_home()
	check(attacker.position.is_equal_approx(attacker.home),"Dancer returns to its original home after dedicated attack effects")
	await get_tree().create_timer(0.45).timeout
	for fx in effects:
		check(fx.ref.get_ref() == null,"Dedicated attack effects naturally release after playback")
	await destroy_stage()

func test_dispatch_and_anchors() -> void:
	fixture(true)
	stage.active_defender = stage.player
	var refs: Array[WeakRef] = []
	for i in 2:
		stage.active_attacker = stage.enemies[i]
		stage.active_attacker.pipeline_effects = {"scale":1.2,"offset":[3,-4]}
		for direction in [-1.0,1.0]:
			stage.player.position.y = stage.floor_y + (-90.0 if direction < 0 else 60.0)
			var point := Vector2(720,210)
			stage.show_strike(point,direction,"pierce" if i == 0 else "slash",true)
			var fx: Dictionary = effects[-1]
			var depth: float = stage.depth_scale(stage.player.position)
			check(fx.script == Strike and fx.direction == direction,"Dedicated effect supports both facing directions")
			check(fx.position.is_equal_approx(point+Vector2(3,-4)*depth),"Effect offset is applied once at either target depth")
			check(fx.scale.is_equal_approx(Vector2.ONE*depth*1.2),"Both colored effects follow authored scale at either target depth")
			refs.append(fx.ref)
	stage.active_attacker = stage.enemies[1]
	stage.active_attacker.set_pose("slash_alt")
	for direction in [-1.0,1.0]:
		var point := Vector2(720,210)
		var depth: float = stage.depth_scale(stage.player.position)
		stage.show_strike(point,direction,"slash",false)
		var fx: Dictionary = effects[-1]
		check(fx.direction == direction and fx.scale.is_equal_approx(Vector2(1,-1)*depth*1.2),"Return slash flips vertically with either horizontal facing")
		check(fx.position.is_equal_approx(point+Vector2(3,-4)*depth),"Return slash reflection keeps the same target contact and authored offset")
		refs.append(fx.ref)
	stage.active_attacker = stage.player
	stage.active_defender = stage.enemies[0]
	stage.show_strike(Vector2(720,210),1.0,"slash",false)
	check(effects[-1].script == NorenSlash,"Player retains the existing red slash artwork")
	stage.active_attacker = stage.enemies[0]
	stage.active_defender = stage.player
	stage.show_strike(Vector2(720,210),-1.0,"slash",false)
	check(effects[-1].script == NeonSlash,"Dedicated black effect is scoped to the black dancer's thrust")
	await destroy_stage()
	for ref in refs:
		check(ref.get_ref() == null,"Stage disposal also releases active dedicated effects")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://dancer_strike_unused.json"
	Game.meta_path = "user://dancer_strike_meta_unused.json"
	var before: Dictionary = Game.state.duplicate(true)
	var revision: int = Game.revision
	check(Strike.TEXTURE == NorenSlash.TEXTURE and Strike.PIERCE_TEXTURE == NorenSlash.PIERCE_TEXTURE,"Dancers reuse Noren's exact slash and thrust silhouettes")
	check(Strike.DRAW_SIZE.x > NorenSlash.DRAW_SIZE.x and Strike.DRAW_SIZE.y > NorenSlash.DRAW_SIZE.y,"White slash is broader and taller than Noren's reference slash")
	check(Strike.PIERCE_DRAW_SIZE.x > NorenSlash.PIERCE_DRAW_SIZE.x and Strike.PIERCE_DRAW_SIZE.y > NorenSlash.PIERCE_DRAW_SIZE.y,"Black thrust is longer and thicker than Noren's reference thrust")
	get_tree().create_timer(40.0).timeout.connect(func():
		push_error("Dancer strike tests timed out")
		get_tree().quit(2))
	await test_real_attacks(false)
	await test_real_attacks(true)
	await test_dispatch_and_anchors()
	check(Game.state == before and Game.revision == revision,"Effects preserve adventure state and revision")
	print("DANCER STRIKE TESTS: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
