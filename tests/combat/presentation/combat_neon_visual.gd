extends "res://tests/combat/presentation/combat_stage_visual.gd"
## Shared combat-flow regression plus sampled impulse and effect-lifetime checks.
var sampled_hits := 0
var shake_min := 0.0
var shake_max := 0.0
var observing := false

func _process(_delta: float) -> void:
	if observing and is_instance_valid(app) and app.shown_page == "battle":
		shake_min = minf(shake_min,app.view.stage.shake.x)
		shake_max = maxf(shake_max,app.view.stage.shake.x)


func motion(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_viewport().get_final_transform()*pos
	event.global_position = event.position
	event.button_mask = mouse_mask
	# Let the OS warp's own motion finish before queuing the synthetic motion.
	Input.warp_mouse(event.position)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame

func verify(ok: bool, message: String) -> void:
	super.verify(ok,message)
	if not ok and is_instance_valid(app) and app.shown_page == "battle":
		print("NEON FAILURE STATE ",message," ",JSON.stringify({"pointer":str(app.view.get_global_mouse_position()),"selected":app.view.selected_uid,"held":app.view.held_card_uid,"target":app.view.target_at_pointer(),"phase":app.view.stage.phase,"busy":Game.battle_busy}))

func _ready() -> void:
	evidence = "res://artifacts/qa/combat-neon-2026-10-13"
	await super._ready()

func on_phase(value: String) -> void:
	super.on_phase(value)
	if value == "impact":
		sampled_hits += 1
		observing = true
		shake_min = minf(0,app.view.stage.shake.x)
		shake_max = maxf(0,app.view.stage.shake.x)
		var view = app.view
		var stage = view.stage
		var a: Vector2 = stage.player.position
		var b: Vector2 = stage.enemies[0].position
		var ui: Rect2 = view.end_button.get_global_rect()
		var initial_shake: Vector2 = stage.shake
		verify(stage.last_hit_stop >= 0.075 and initial_shake.length() >= 4.5,"Both sides trigger a real hit-stop and camera impulse")
		await settle(0.035)
		verify(stage.player.position == a and stage.enemies[0].position == b,"Actor movement holds during contact")
		verify(view.end_button.get_global_rect() == ui and stage.shake.length() < initial_shake.length(),"Camera impulse decays while UI stays still")
		await shot("neon_contact_%02d" % sampled_hits)
	elif value == "idle":
		if observing:
			verify(shake_min < -0.1 and shake_max > 0.1,"Camera impulse travels in both directions")
			observing = false
		verify(app.view.stage.shake == Vector2.ZERO and is_equal_approx(app.view.stage.impact_zoom,1),"Camera impulse clears without drift")
	elif value == "light_flight":
		await settle(0.08)
		await shot("neon_return_%02d" % sampled_hits)
