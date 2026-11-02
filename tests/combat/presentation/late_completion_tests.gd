extends Node
## Headless deterministic scheduler injection; no physical input or rendering.
const Stage = preload("res://scripts/combat/test_stage.gd")
const Ghost = preload("res://scripts/combat/return_ghost_fx.gd")
const Cleanup = preload("res://scripts/combat/audio_cleanup.gd")
var checks := 0
var failures: Array[String] = []
var records: Array = []
var output := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	records.append({"check":label,"passed":ok})
	if not ok:
		failures.append(label)
		push_error("LATE COMPLETION: " + label)

func complete_reveal_early(tween: Tween, trace: Dictionary, stage: Control) -> void:
	trace.injected = true
	# Advance only this presentation tween while return_home still awaits its timer.
	tween.custom_step(1.0)
	trace.finishedBeforeResume = not tween.is_running() and stage.phase == "home_glitch"

func drive_return(stage: Control, trace: Dictionary) -> void:
	Game.battle_busy = true
	await stage.return_home()
	Game.battle_busy = false
	trace.returned = true

func run_case(early: bool) -> void:
	var label := "early completion" if early else "normal completion"
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	var model := CombatModel.new()
	model.initialize("B02", 70, 70, rules, [Game.enemy_catalog.robot], Game.card_catalog)
	model.draw_cards()
	var model_before := model.snapshot()
	var game_before: Dictionary = Game.state.duplicate(true)
	var visuals: Array[EnemyVisualResolver.Visual] = [Game.enemy_combat_visual(model.enemies[0])]
	var stage := Stage.new()
	add_child(stage)
	stage.setup(533, visuals)
	stage.player.position += Vector2(70, 15)
	stage.enemies[0].position -= Vector2(35, 12)
	var trace := {"returned":false,"injected":false,"finishedBeforeResume":false}
	if early:
		stage.phase_changed.connect(func(phase: String):
			if phase != "home_glitch" or trace.injected: return
			# ReturnGhost.setup creates no tweens; the last one is the new reveal.
			var reveal: Tween = get_tree().get_processed_tweens().back()
			complete_reveal_early.call_deferred(reveal, trace, stage))
	drive_return(stage, trace)
	var watchdog := get_tree().create_timer(2.0)
	while not trace.returned and watchdog.time_left > 0:
		await get_tree().process_frame
	records.append({"case":label,"phaseAtWatchdog":stage.phase,"trace":trace.duplicate(),"busyAtWatchdog":Game.battle_busy})
	check(not early or trace.injected and trace.finishedBeforeResume, label + ": injection finishes reveal while the earlier timer is pending")
	check(trace.returned, label + ": return_home completes before watchdog")
	check(not Game.battle_busy, label + ": owner releases battle busy after return_home")
	check(stage.phase == "idle", label + ": stage reaches idle")
	check(model.snapshot() == model_before and Game.state == game_before, label + ": model and adventure state remain unchanged")
	await get_tree().process_frame
	var ghosts := 0
	for node in stage.world.get_children():
		if node.get_script() == Ghost: ghosts += 1
	check(ghosts == 0, label + ": every return ghost is cleaned up")
	var actors: Array = [stage.player]
	actors.append_array(stage.enemies)
	for actor in actors:
		check(actor.position.is_equal_approx(actor.home), label + ": actor returns to home " + actor.kind)
		check(is_equal_approx(actor.modulate.a, 1.0), label + ": actor is fully visible " + actor.kind)
	check(await Cleanup.release(stage, get_tree()), label + ": stage audio references drain before disposal")
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Game.battle_busy = false

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("LATE COMPLETION: isolated QA user directory and absolute QA_OUT_DIR required")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	Game.state = Game.initial_state()
	await run_case(false)
	await run_case(true)
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"scope":"Headless deterministic early-completion injection; no GPU, physical input, damage, or save writes"}, "\t"))
	file.close()
	print("LATE COMPLETION: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
