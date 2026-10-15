extends "res://tests/combat_stage_visual.gd"
## Rendered real battle, with isolated demo enemies. Pointer coverage is opt-in.
var pointer_mode := false
var impact_count := 0
var approach_samples: Array[Vector2] = []
var active_view: Control

func _process(_delta: float) -> void:
	if is_instance_valid(active_view) and is_instance_valid(active_view.stage):
		if active_view.stage.phase == "approach": approach_samples.append(active_view.stage.player.position)

func on_phase(value: String) -> void:
	phases.append(value)
	if value == "impact":
		impact_count += 1
		for actor in [active_view.stage.active_attacker,active_view.stage.active_defender]:
			verify(active_view.stage.get_global_rect().has_point(actor.to_global(Vector2(0,-120))),"Active actor head stays inside stage")
		shot("impact_%02d" % impact_count)
	if value == "light_flight":
		await settle(0.06)
		shot("return_light")

func _ready() -> void:
	pointer_mode = "--pointer" in OS.get_cmdline_user_args()
	output = "res://artifacts/qa/combat-depth-2026-10-13/%d-%s/" % [DisplayServer.window_get_size().x,"pointer" if pointer_mode else "render"]
	DirAccess.make_dir_recursive_absolute(output)
	var demo: Node = load("res://scenes/combat_stage_demo.tscn").instantiate()
	add_child(demo)
	await settle(0.5)
	app = demo.get_child(0)
	while not is_instance_valid(app.view) or app.shown_page != "battle" or app.view.model.enemies.size() != 3:
		await get_tree().process_frame
	await idle()
	var view = app.view
	active_view = view
	var stage = view.stage
	stage.phase_changed.connect(on_phase)
	verify(not Game.save_enabled and view.model.enemies.size() == 3,"Demo uses three isolated opponents with saving disabled")
	verify(stage.enemies[0].position.y < stage.enemies[1].position.y and stage.enemies[1].position.y < stage.enemies[2].position.y,"Enemy feet occupy three depth lanes")
	verify(stage.enemies[0].scale.y < stage.enemies[2].scale.y and stage.actors_root.y_sort_enabled,"Depth changes scale and uses foot Y sorting")
	var ui: Rect2 = view.end_button.get_global_rect()
	await shot("01-three-depth-lanes")
	for i in 3:
		verify(view.target_at_point(stage.contact(stage.enemies[i])) == i,"Wide view selects the intended depth lane")
	# Frontmost target wins even if its model index is earlier.
	var saved: Vector2 = stage.enemies[0].position
	stage.enemies[0].position = stage.enemies[2].position+Vector2(0,18)
	stage.update_depth()
	view.update_target_rects()
	verify(view.target_at_point(stage.contact(stage.enemies[2])) == 0,"Overlapping hit areas select by frontmost foot, not model order")
	stage.enemies[0].position = saved
	stage.update_depth()
	view.update_target_rects()
	# Deliberately obstruct the direct route and check a non-intersecting detour.
	var obstruction: Vector2 = stage.enemies[1].position
	stage.enemies[1].position = Vector2(650,stage.player.position.y)
	var endpoint := Vector2(850,stage.player.position.y)
	var route: Array[Vector2] = stage.approach_path(stage.player,stage.enemies[0],endpoint)
	verify(route.size() > 2 and stage.path_clear(route,stage.player,stage.enemies[0]),"Approach detours around a bystander's ground footprint")
	stage.enemies[1].position = obstruction
	if pointer_mode:
		await click(card_point(view.cards[view.model.hand[0]]))
		await click(stage.contact(stage.enemies[0]),MOUSE_BUTTON_RIGHT)
		verify(view.selected_uid.is_empty() and view.model.enemies[0].hp == 20,"Cancel on back lane consumes no card")
	for index in [0,2,1]:
		var uid: String = view.model.hand[0]
		var previous_y: float = stage.player.position.y
		approach_samples.clear()
		if pointer_mode:
			await click(card_point(view.cards[uid]))
			await motion(stage.contact(stage.enemies[index]))
			verify(view.hovered_target == index and view.aim.locked,"Pointer locks intended target after camera movement")
			await click(stage.contact(stage.enemies[index]))
			await idle()
		else:
			view.select_card(uid)
			await view.play_selected(index)
		verify(view.model.enemies[index].hp == 19,"Attack damages only the selected enemy once")
		verify(absf(stage.player.position.y-previous_y) > 40,"Switching target traverses the Y axis")
		verify(approach_samples.size() > 1,"Approach animates through ground positions")
		verify(not is_equal_approx(stage.focus_y,stage.floor_y-35) and stage.zoom >= 1.0 and stage.zoom <= 1.485,"Near camera tracks Y and adapts zoom to preserve depth targets")
		verify(view.target_at_point(stage.contact(stage.enemies[index])) == index,"Near view hit area matches projected enemy")
		for enemy in stage.enemies:
			verify(stage.get_global_rect().has_point(stage.contact(enemy)),"Every live depth target stays available in near view")
		verify(view.end_button.get_global_rect() == ui,"Camera does not move fixed UI")
		await shot("02-near-target-%d" % index)
	# Consecutive same-target hit should remain beside the target.
	phases.clear()
	view.select_card(view.model.hand[0])
	await view.play_selected(1)
	verify(not phases.has("approach"),"Same target does not trigger another long approach")
	var before_hits := impact_count
	await view.end_turn_pressed()
	verify(impact_count == before_hits+3 and view.model.player_hp == 97,"All three distinct enemies attack exactly once")
	verify(view.model.turn == 2 and view.model.hand.size() == 5,"All enemy actions finish before next hand")
	for actor in stage.actors_root.get_children():
		verify(actor.position == actor.home and actor.modulate == Color.WHITE,"Survivor returns to its own XY home")
	verify(is_equal_approx(stage.focus_y,stage.floor_y-35) and is_equal_approx(stage.zoom,1),"Wide camera restores both axes")
	await shot("03-returned")
	# A dead enemy remains dead/invisible while the rest complete another round.
	view.model.enemies[2].hp = 1
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.select_card(view.model.hand[0])
	await view.play_selected(2)
	verify(not stage.enemies[2].alive and stage.enemies[2].modulate.a == 0,"Lethal hit fades only the selected depth target")
	await view.end_turn_pressed()
	verify(view.model.player_hp == 95 and not stage.enemies[2].alive and stage.enemies[2].modulate.a == 0,"Dead enemy neither attacks nor reappears on return")
	var snapshot: Dictionary = view.model.snapshot()
	app.swap_view()
	await idle()
	active_view = app.view
	verify(app.view.model.snapshot() == snapshot and app.view.stage.enemies[0].position == app.view.stage.enemies[0].home,"Restore preserves model and rebuilds depth homes without extra damage")
	await shot("04-restored")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"syntheticPointer":pointer_mode,"physicalInput":false},"\t"))
	print("COMBAT DEPTH: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
