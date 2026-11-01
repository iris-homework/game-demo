extends Node
## Real status-event dispatch and cosmetic lifecycle. No saves or pointer input.
class StageProbe extends "res://scripts/combat/test_stage.gd":
	var buff_targets: Array[Node2D] = []
	func present_enemy_buff(actor: Node2D) -> Node2D:
		buff_targets.append(actor)
		return super.present_enemy_buff(actor)

class BattleProbe extends "res://scripts/battle.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func refresh_enemy_hud() -> void: pass
	func refresh_player_plate() -> void: pass
	func refresh_hp() -> void: pass
	func impact(_pos: Vector2, _text: String, _color: Color, _text_scale: float = 1.0) -> void: pass

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func enemy(id: String, intent: Dictionary) -> Dictionary:
	return {"id":id,"displayName":id,"maxHp":100,"intentSequence":[intent]}

func fixture(definitions: Array) -> BattleProbe:
	var view := BattleProbe.new()
	view.model = CombatModel.new()
	view.model.initialize("enemy_buff_fx",100,100,{"ruleset":"noren_v1","deck":[],"handSize":0},definitions)
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.shown_player_buffs = view.model.buff_state.duplicate(true)
	view.shown_player_hp = view.model.player_hp
	add_child(view)
	var stage := StageProbe.new()
	view.stage = stage
	view.add_child(stage)
	var resolver := EnemyVisualResolver.new()
	var visuals: Array[EnemyVisualResolver.Visual] = []
	for _definition in definitions:
		visuals.append(resolver.resolve({"combatVisualId":"robot"},{}))
	stage.setup(577.0,visuals)
	return view

func destroy(view: BattleProbe) -> void:
	view.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_model_events() -> void:
	var view := fixture([
		enemy("charged",{"type":"charge","amount":5}),
		enemy("suited",{"type":"energy_suit"}),
		enemy("guard",{"type":"fortify","amount":5,"strength":1}),
		enemy("support",{"type":"strength_allies","amount":2,"targetIds":["charged","suited"]})
	])
	var stage: StageProbe = view.stage
	var result := view.model.end_turn()
	var committed := view.model.snapshot()
	var apply_events: Array = result.turnEvents.filter(func(event): return event.type == "status_apply")
	check(apply_events.size() == 6,"Real charge, suit, fortify and ally actions emit six gain events")
	var expected_targets: Array[int] = [0,1,2,2,0,1]
	var expected_buffs: Array[String] = ["electric_charge","energy_suit","block","strength","strength","strength"]
	for i in apply_events.size():
		var event: Dictionary = apply_events[i]
		if i < expected_targets.size():
			check(event.target == expected_targets[i] and event.buffId == expected_buffs[i],"Authoritative event keeps its intended buff and recipient")
		var before := stage.buff_targets.size()
		await view.present_status_event(event)
		check(stage.buff_targets.size() == before+1,"Each real positive enemy gain dispatches one reinforcement cue")
		if stage.buff_targets.size() > before:
			check(stage.buff_targets.back() == stage.enemies[int(event.target)],"Cue follows the event recipient, including ally buffs from a different source")
		check(view.model.snapshot() == committed,"Status playback does not modify the resolved combat snapshot")
	check(view.shown_enemies[0].buffs.strength == 2 and view.shown_enemies[1].buffs.strength == 2,"Ally strength remains visible on both intended recipients")
	check(view.shown_enemies[2].block == 5 and view.shown_enemies[2].buffs.strength == 1,"Self fortify preserves both displayed block and strength")
	await destroy(view)
	check(get_tree().get_nodes_in_group("enemy_buff_fx").is_empty(),"Battle teardown leaves no reinforcement cues")

func test_excluded_events() -> void:
	var view := fixture([enemy("target",{"type":"charge","amount":1})])
	var stage: StageProbe = view.stage
	var committed := view.model.snapshot()
	var excluded: Array[Dictionary] = [
		{"type":"status_apply","source":0,"target":0,"buffId":"weak","amount":2,"stacksAfter":2},
		{"type":"status_apply","source":0,"target":0,"buffId":"bleed","amount":2,"stacksAfter":2},
		{"type":"status_apply","source":0,"target":-1,"buffId":"block","amount":5,"stacksAfter":5},
		{"type":"status_apply","source":0,"target":0,"buffId":"strength","amount":0,"stacksAfter":0},
		{"type":"status_apply","source":0,"target":0,"buffId":"strength","amount":-1,"stacksAfter":0},
		{"type":"status_decay","source":0,"target":0,"buffId":"strength","amount":1,"stacksAfter":0},
		{"type":"heal","source":0,"target":0,"amount":5,"hpAfter":100}
	]
	for event in excluded:
		await view.present_status_event(event)
		check(stage.buff_targets.is_empty(),"Negative, player, nonpositive, decay and heal events do not dispatch reinforcement")
		check(get_tree().get_nodes_in_group("enemy_buff_fx").is_empty(),"Excluded event creates no reinforcement node")
	check(view.model.snapshot() == committed,"Excluded-event presentation also preserves the combat model")
	stage.enemies[0].alive = false
	await view.present_status_event({"type":"status_apply","source":0,"target":0,"buffId":"strength","amount":1,"stacksAfter":1})
	check(get_tree().get_nodes_in_group("enemy_buff_fx").is_empty(),"Positive status playback cannot attach a cue to a dead actor")
	await destroy(view)

func test_effect_lifecycle() -> void:
	var view := fixture([enemy("first",{"type":"charge","amount":1}),enemy("second",{"type":"charge","amount":1})])
	var stage: StageProbe = view.stage
	var committed := view.model.snapshot()
	check(stage.present_enemy_buff(stage.player) == null,"Player actor is excluded from enemy reinforcement")
	stage.enemies[1].alive = false
	check(stage.present_enemy_buff(stage.enemies[1]) == null,"Dead enemies are excluded from reinforcement")
	stage.enemies[1].alive = true
	var first: Node2D = stage.present_enemy_buff(stage.enemies[0])
	check(is_instance_valid(first),"Live enemy creates a reinforcement cue")
	if not is_instance_valid(first):
		await destroy(view)
		return
	check(first.get_parent() == stage.enemies[0] and first.name == "EnemyBuffFX" and first.is_in_group("enemy_buff_fx"),"Cue is owned and named beneath its recipient")
	check(is_equal_approx(first.duration,0.9) and first.body_bounds.size.x > 0 and first.body_bounds.size.y > 0,"Cue has the intended duration and valid actor body bounds")
	await get_tree().create_timer(0.15).timeout
	check(first.progress > 0.0,"Cue advances over presentation frames")
	var original_id := first.get_instance_id()
	var restarted: Node2D = stage.present_enemy_buff(stage.enemies[0])
	check(restarted.get_instance_id() == original_id and is_zero_approx(restarted.progress),"Repeated gain reuses one cue and restarts its progress")
	check(get_tree().get_nodes_in_group("enemy_buff_fx").size() == 1,"Stacked gains do not create duplicate nodes on one actor")
	var before_position := first.global_position
	stage.enemies[0].position.x += 25.0
	check(is_equal_approx(first.global_position.x-before_position.x,25.0*stage.enemies[0].get_parent().global_scale.x),"Attached cue follows recipient motion")
	var second: Node2D = stage.present_enemy_buff(stage.enemies[1])
	check(second != first and second.get_parent() == stage.enemies[1],"Different recipients own independent reinforcement cues")
	var first_ref: WeakRef = weakref(first)
	var second_ref: WeakRef = weakref(second)
	await get_tree().create_timer(1.05).timeout
	check(first_ref.get_ref() == null and second_ref.get_ref() == null and get_tree().get_nodes_in_group("enemy_buff_fx").is_empty(),"Completed cues free themselves and leave no group entries")
	var live_ref: WeakRef = weakref(stage.present_enemy_buff(stage.enemies[0]))
	check(live_ref.get_ref() != null,"Teardown begins with an active reinforcement cue")
	check(view.model.snapshot() == committed,"Cue creation, restart and completion preserve the authoritative snapshot")
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(live_ref.get_ref() == null and get_tree().get_nodes_in_group("enemy_buff_fx").is_empty(),"Stage destruction frees active reinforcement cues")
	await destroy(view)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://enemy_buff_fx_unused.json"
	Game.meta_path = "user://enemy_buff_fx_meta_unused.json"
	if not "qa" in ProjectSettings.globalize_path("user://").to_lower():
		push_error("Enemy buff FX checks require an isolated QA user directory")
		get_tree().quit(2)
		return
	await test_model_events()
	await test_excluded_events()
	await test_effect_lifecycle()
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path),"Reinforcement checks never write save or meta files")
	var result := {"checks":checks,"failures":failures,"limitations":["Node and event checks only; no rendered-image review or physical input"]}
	var output := OS.get_environment("QA_OUT_DIR")
	if output.is_absolute_path():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t"))
		file.close()
	print("ENEMY BUFF FX: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
