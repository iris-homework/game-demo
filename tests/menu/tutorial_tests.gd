extends "res://tests/combat/cards/noren_cards_visual.gd"
## Run only in a copied project with a tutorial-settings-qa user directory.
var capture := false
var sentinel := "tutorial QA: preserve existing checkpoint bytes"

func _ready() -> void:
	if not OS.get_user_data_dir().contains("tutorial-settings-qa"):
		push_error("Tutorial QA requires an isolated copied project")
		get_tree().quit(2)
		return
	output = OS.get_environment("QA_OUT_DIR") + "/"
	DirAccess.make_dir_recursive_absolute(output)
	capture = DisplayServer.get_name() != "headless"
	if capture:
		DisplayServer.window_move_to_foreground()
		await get_tree().create_timer(0.2).timeout
	Game.save_path = "user://tutorial_checkpoint.json"
	Game.meta_path = "user://tutorial_meta.json"
	Game.save_enabled = true
	for path in [Game.save_path, Game.meta_path]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(sentinel)
	var original_enemies := Game.enemy_catalog.duplicate(true)
	var original_battles := Game.battles.duplicate(true)
	# No in-memory run and an unreadable disk checkpoint must still allow learning.
	Game.state = {}
	Game.start_tutorial()
	check(Game.tutorial_mode and Game.training_mode and Game.page == "battle", "Tutorial starts without reading an invalid disk checkpoint")
	check_tutorial_setup()
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	model.draw_cards()
	check(model.hand.map(func(uid): return model.card(uid).id) == Game.TUTORIAL_DECK.slice(0, 5), "Opening hand has all teaching examples in a deterministic order")
	check(model.energy == 3 and model.ammo == 2 and model.stance == "melee", "Tutorial uses normal Noren resource rules")
	var before_step := model.snapshot()
	var guard: String = model.hand[1]
	model.play_card(guard, -1)
	check(model.energy == 2 and model.block == 5 and guard in model.discard_pile, "Playing guard spends one energy and enters discard")
	Game.commit_combat(model)
	Game.menu()
	check(Game.state.is_empty() and not Game.tutorial_mode and not Game.training_mode, "Exiting restores an empty in-memory run")
	check(Game.battles == original_battles and Game.enemy_catalog == original_enemies, "Tutorial removes its encounter without altering formal fish or battles")
	# Existing progress, deck, technology and an unfinished combat remain exact.
	var saved := Game.initial_state()
	saved.currentHp = 17
	saved.credits = 987
	saved.deck = ["noren_36", "noren_36"]
	saved.ownedCyberwareIds = ["swift_chip"]
	saved.equippedCyberwareIds = ["swift_chip"]
	saved.combat = before_step
	saved.battleStart = before_step.duplicate(true)
	saved.currentScene = "battle"
	saved.battleId = "B11"
	for outcome in ["win", "lose", "exit"]:
		Game.state = saved.duplicate(true)
		Game.start_tutorial()
		check_tutorial_setup()
		check(Game.state.deck.is_empty() and Game.equipped_cyberware_ids().is_empty(), "Tutorial does not inherit the adventure deck or technology: " + outcome)
		if outcome == "exit": Game.menu()
		else: check(Game.battle_exit(outcome, Game.revision), "Tutorial result uses normal training exit: " + outcome)
		check(Game.state == saved and Game.page == "menu", "Adventure is restored byte-for-byte in memory: " + outcome)
		check(not Game.battles.has(Game.TUTORIAL_BATTLE_ID) and not Game.tutorial_mode, "Temporary encounter and tutorial flag are cleared: " + outcome)
	for locked in ["transition", "busy", "save", "page"]:
		Game.transition_locked = locked == "transition"
		Game.battle_busy = locked == "busy"
		Game.pending_save_kind = "test" if locked == "save" else ""
		Game.page = "map" if locked == "page" else "menu"
		Game.start_tutorial()
		check(not Game.training_mode and not Game.battles.has(Game.TUTORIAL_BATTLE_ID), "Blocked tutorial start leaves no temporary definitions: " + locked)
	Game.transition_locked = false
	Game.battle_busy = false
	Game.pending_save_kind = ""
	Game.page = "menu"
	Game.state = saved.duplicate(true)
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await idle()
	check(is_instance_valid(app.view.tutorial_button) and not app.view.tutorial_button.disabled, "Menu provides an enabled dedicated tutorial entry")
	await get_tree().create_timer(0.5).timeout
	await capture_frame("menu")
	app.view._set_training_open(true)
	check(app.view.tutorial_button.disabled, "Training chooser disables the tutorial entry behind it")
	app.view._set_training_open(false)
	app.view.open_settings()
	check(app.view.tutorial_button.disabled, "Settings disables tutorial entry behind it")
	app.view.close_settings()
	await get_tree().process_frame
	await get_tree().process_frame
	await click_control(app.view.tutorial_button)
	await idle()
	check(Game.tutorial_mode and app.shown_page == "battle" and app.view.initialized, "A viewport click on tutorial opens the playable teaching battle")
	if not Game.tutorial_mode:
		print("ENTRY DIAGNOSTIC ", {"page":Game.page,"shown":app.shown_page,"busy":Game.battle_busy,"locked":Game.transition_locked,"pending":Game.pending_save_kind,"disabled":app.view.tutorial_button.disabled,"hovered":get_viewport().gui_get_hovered_control(),"rect":app.view.tutorial_button.get_global_rect()})
		await capture_frame("entry-failed")
		await finish_qa()
		return
	await exercise_guide()
	await win_tutorial()
	check(Game.page == "menu" and not Game.tutorial_mode and Game.state == saved, "Winning through real combat returns to menu and restores the original adventure")
	Game.start_tutorial()
	await idle()
	var battle_before: Dictionary = app.view.model.snapshot()
	await click_control(app.view.get_node("menu_button"))
	check(is_instance_valid(app.exit_dialog), "Tutorial exit button opens the standard confirmation")
	await click_control(app.exit_cancel)
	check(Game.tutorial_mode and app.view.model.snapshot() == battle_before, "Canceling exit preserves the ongoing lesson and combat")
	await click_control(app.view.get_node("menu_button"))
	await click_control(app.exit_ok)
	await idle()
	check(Game.state == saved and not Game.tutorial_mode, "Confirming tutorial exit restores the original adventure")
	# Existing seven encounter training remains unmodified and has no tutorial HUD.
	Game.start_enemy_training("fish")
	await idle()
	check(Game.training_mode and not Game.tutorial_mode and app.view.model.enemies.size() == 2, "Ordinary fish training still has both enemies")
	check(not is_instance_valid(app.view.tutorial_guide), "Ordinary training does not display the guide")
	Game.menu()
	await idle()
	check(Game.state == saved and Game.battles == original_battles, "Normal training still restores progress and removes its encounter")
	await finish_qa()

func check_tutorial_setup() -> void:
	var snapshot: Dictionary = Game.state.combat
	check(snapshot.enemies.size() == 1 and snapshot.enemies[0].id == "fish" and snapshot.enemies[0].hp == 30, "Tutorial uses one existing 30 HP mutant fish")
	check(Game.state.currentHp == 70 and Game.state.playerCharacterId == "noren", "Tutorial starts with healthy Noren")
	check(Game.state.battleStart.is_empty(), "Tutorial does not create a persistent battle restart checkpoint")

func click_control(control: Control) -> void:
	var presses: Array = []
	control.pressed.connect(func(): presses.append(true), CONNECT_ONE_SHOT)
	await pointer(control.get_global_rect().get_center())
	await pointer(control.get_global_rect().get_center(), 1)
	await pointer(control.get_global_rect().get_center(), 0)
	if presses.is_empty() and is_instance_valid(control):
		print("CLICK DIAGNOSTIC ", {"name":control.name,"point":control.get_global_rect().get_center(),"hover":get_viewport().gui_get_hovered_control(),"focused":get_window().has_focus(),"mouse":get_viewport().get_mouse_position(),"disabled":control.disabled,"visible":control.is_visible_in_tree()})

func pointer(point: Vector2, pressed: int = -1) -> void:
	var event: InputEventMouse
	if pressed < 0:
		event = InputEventMouseMotion.new()
	else:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed == 1
		event = button
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	await get_tree().process_frame

func capture_frame(file_name: String) -> void:
	if capture: await shot(file_name)

func exercise_guide() -> void:
	var view: Control = app.view
	check(is_instance_valid(view.tutorial_guide), "Tutorial guide is attached to the battle")
	await capture_frame("tutorial-opening")
	var guide: Control = view.tutorial_guide
	var before: Dictionary = view.model.snapshot()
	for index in 7:
		guide.set_step(index)
		await get_tree().process_frame
		check_guidance_geometry(guide, index)
		check(guide.body_label.position.y + guide.body_label.size.y <= guide.task_panel.position.y, "Lesson body fits above task: %d" % index)
		check(guide.task_label.position.y + guide.task_label.size.y <= guide.previous_button.position.y, "Lesson task fits above buttons: %d" % index)
		await capture_frame("lesson-%d" % index)
	check(guide.completed.is_empty() and view.model.snapshot() == before, "Reading all lessons does not mark practice complete or mutate combat")
	check_guidance_follow(view, guide)
	guide.set_step(0)
	var guard: String = view.model.hand[1]
	view.select_card(guard, false)
	guide._update_highlights()
	check(guide.guidance_targets.any(func(target): return target.kind == "play_area"), "Selecting the teaching skill redirects its leader to the real release area")
	await capture_frame("selected-card-target")
	await click_control(guide.next_button)
	check(guide.step_index == 1 and view.model.snapshot() == before and view.selected_uid.is_empty(), "Guide click navigates instead of accidentally playing a selected self card")
	await click_control(guide.previous_button)
	check(guide.step_index == 0, "Previous lesson button works")
	await click_control(guide.collapse_button)
	check(guide.collapsed and not guide.panel_view.visible, "Guide can collapse without ending battle")
	check(guide.guidance_targets.is_empty() and guide.leader_paths.is_empty() and guide.highlights.is_empty(), "Collapsing immediately removes all target outlines and leader lines")
	await click_control(guide.expand_button)
	check(not guide.collapsed and guide.panel_view.visible, "Guide can reopen at the same lesson")
	check_guidance_geometry(guide, 0)
	# Actual card UI dispatch and rule resolution, with no fixture replacements.
	view.select_card(guard, false)
	view.play_selected(-1)
	await idle()
	check(guide.completed.get(0, false) and view.model.energy == 2 and view.model.block == 5, "Actual guard play completes the energy practice")
	guide.set_step(1)
	var power := ""
	for uid in view.model.hand:
		if view.model.card(uid).id == "noren_40": power = uid
	view.select_card(power, false)
	view.play_selected(-1)
	await idle()
	check(guide.completed.get(1, false) and power in view.model.exhaust_pile, "Actual ability play completes card type practice and exhausts its card")
	guide._update_highlights()
	check(guide.guidance_targets.any(func(target): return target.get("kind", "") == "exhaust"), "After the ability is played its guidance moves to the real exhaust control")
	check(target_contains_control(guide, view.exhaust_button), "Ability follow-up points at the actual exhaust button bounds")
	await capture_frame("guide-exhaust-target")
	guide.set_step(5)
	check(not view.player_plate.badges.is_empty(), "Ability creates a real status badge to inspect")
	await pointer(view.player_plate.badges[0].get_global_rect().get_center())
	await get_tree().create_timer(0.9).timeout
	check(guide.completed.get(5, false), "Hovering a real status badge completes buff inspection")
	await capture_frame("buff-tooltip")
	guide.set_step(4)
	await pointer(view.enemy_intents[0].get_global_rect().get_center())
	check(guide.mouse_filter == Control.MOUSE_FILTER_IGNORE and get_viewport().gui_get_hovered_control() == view.enemy_intents[0], "Drawn leaders let real viewport hover reach the intended enemy control")
	await get_tree().create_timer(0.9).timeout
	check(guide.completed.get(4, false), "Hovering the real fish intent completes enemy inspection")
	check(view.enemy_intents[0].tooltip_text.contains("追加 2 层污染") and view.enemy_intents[0].tooltip_text.contains("死亡"), "Fish tooltip exposes its attack and death mechanics")
	await capture_frame("enemy-tooltip")
	guide.set_step(2)
	guide._update_highlights()
	check(guide.guidance_targets.size() == 1 and target_contains_control(guide, view.draw_count), "Pile guidance initially points only to the draw pile")
	for title in ["抽牌堆", "弃牌堆"]:
		view.show_pile(title, view.model.draw_pile if title == "抽牌堆" else view.model.discard_pile)
		await get_tree().process_frame
		await get_tree().process_frame
		check(not guide.visible and is_instance_valid(view.pile_overlay), "Pile overlay takes precedence over guide: " + title)
		check(guide.guidance_targets.is_empty() and guide.leader_paths.is_empty() and guide.highlights.is_empty(), "A pile overlay clears guidance geometry: " + title)
		await capture_frame("draw-pile" if title == "抽牌堆" else "discard-pile")
		view.close_pile()
		await get_tree().process_frame
		await get_tree().process_frame
		guide._update_highlights()
		if title == "抽牌堆":
			check(guide.guidance_targets.size() == 1 and target_contains_control(guide, view.discard_count) and not target_contains_control(guide, view.draw_count), "After reading the draw pile the leader switches to the unread discard pile")
			await capture_frame("guide-discard-target")
		else:
			check(guide.guidance_targets.size() == 2 and target_contains_control(guide, view.draw_count) and target_contains_control(guide, view.discard_count), "After both inspections guidance shows both real pile positions")
	check(guide.completed.get(2, false) and guide.visible, "Both real pile views complete the pile lesson and restore the guide")
	guide.set_step(3)
	var ranged := ""
	for uid in view.model.hand:
		if view.model.card(uid).id == "noren_04": ranged = uid
	view.select_card(ranged, false)
	view.play_selected(-1)
	await idle()
	check(view.model.stance == "ranged" and guide.completed.get(3, false), "Changing stance through a real card completes protagonist practice")
	check(view.model.energy == 0 and view.model.stance_discount, "Stance card uses last energy and grants ranged attack discount")
	await capture_frame("ranged")
	guide.set_step(6)
	await click_control(view.end_button)
	await idle()
	check(view.model.turn == 2 and view.model.energy == 3 and view.model.hand.size() == 5 and guide.completed.get(6, false), "Real end-turn input runs fish action, refills energy and deals five cards")
	check(guide.completed.size() == 7, "All seven practice goals were completed by their actual actions")
	await capture_frame("next-turn")
	await click_control(guide.next_button)
	check(guide.collapsed, "Final lesson allows continuing free practice")


func check_guidance_geometry(guide: Control, index: int) -> void:
	guide._update_highlights()
	var targets: Array = guide.guidance_targets
	var paths: Array = guide.leader_paths
	check(not targets.is_empty() and targets.size() <= 2, "Lesson has one or two visible operation targets: %d" % index)
	check(paths.size() == targets.size(), "Each lesson target has a matching leader: %d" % index)
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1440, 900))
	for target_index in targets.size():
		var target: Dictionary = targets[target_index]
		var area: Rect2 = target.get("rect", Rect2())
		check(area.has_area() and viewport_rect.intersects(area), "Guidance target has a visible viewport area: %d/%d" % [index, target_index])
		check(not str(target.get("label", "")).is_empty(), "Guidance target has a readable action label: %d/%d" % [index, target_index])
		var tag_rect: Rect2 = guide._target_label_rect(target)
		check(viewport_rect.encloses(tag_rect) and not tag_rect.intersects(Rect2(guide.panel_view.position, guide.panel_view.size)), "Target action label stays on screen and outside the instruction panel: %d/%d" % [index, target_index])
		if target_index >= paths.size(): continue
		var path: PackedVector2Array = paths[target_index]
		check(path.size() >= 2, "Leader includes at least a start and endpoint: %d/%d" % [index, target_index])
		if path.size() < 2: continue
		var length := 0.0
		for point_index in path.size():
			check(path[point_index].is_finite(), "Leader coordinates are finite: %d/%d/%d" % [index, target_index, point_index])
			if point_index > 0: length += path[point_index - 1].distance_to(path[point_index])
		check(length > 1.0 and area.grow(12).has_point(path[path.size() - 1]), "Visible leader terminates beside its operation target: %d/%d" % [index, target_index])

func target_contains_control(guide: Control, control: Control) -> bool:
	var center: Vector2 = guide.get_global_transform().affine_inverse() * control.get_global_rect().get_center()
	for target in guide.guidance_targets:
		var area: Rect2 = target.get("rect", Rect2())
		if area.has_point(center): return true
	return false

func check_guidance_follow(view: Control, guide: Control) -> void:
	var before: Dictionary = view.model.snapshot()
	guide.set_step(4)
	guide._update_highlights()
	if guide.guidance_targets.is_empty() or guide.leader_paths.is_empty():
		check(false, "Enemy guidance exists before following its target")
		return
	var original_area: Rect2 = guide.guidance_targets[0].rect
	var original_path: PackedVector2Array = guide.leader_paths[0]
	var intent: Control = view.enemy_intents[0]
	var original_position := intent.position
	# Do not await: normal actor-follow processing must not undo this movement.
	intent.position += Vector2(40, 0)
	guide._update_highlights()
	check(guide.guidance_targets.size() == 1 and guide.leader_paths.size() == 1, "Moving the intended control preserves exactly one target and leader")
	if not guide.guidance_targets.is_empty() and not guide.leader_paths.is_empty():
		var moved_area: Rect2 = guide.guidance_targets[0].rect
		var moved_path: PackedVector2Array = guide.leader_paths[0]
		check((moved_area.position - original_area.position).is_equal_approx(Vector2(40, 0)), "Guidance rectangle follows the actual enemy intent control")
		if original_path.is_empty() or moved_path.is_empty():
			check(false, "A moving target retains a visible leader endpoint")
		else:
			check((moved_path[moved_path.size() - 1] - original_path[original_path.size() - 1]).is_equal_approx(Vector2(40, 0)), "Leader endpoint follows the same control displacement")
	intent.position = original_position
	guide._update_highlights()
	check(view.model.snapshot() == before, "Repositioning guidance and restoring its UI target never mutate combat")

func win_tutorial() -> void:
	# Complete the actual battle with ordinary attack cards and turn transitions.
	for action in 30:
		if Game.page != "battle" or not Game.tutorial_mode: return
		var view: Control = app.view
		var attack := ""
		for uid in view.model.hand:
			if view.model.card(uid).type == "attack" and view.model.play_error(uid).is_empty():
				attack = uid
				break
		if attack.is_empty(): view.end_turn_pressed()
		else:
			view.select_card(attack, false)
			view.play_selected(0)
		await idle()
	check(false, "Actual tutorial combat completes within thirty actions")

func finish_qa() -> void:
	for path in [Game.save_path, Game.meta_path]:
		check(FileAccess.get_file_as_string(path) == sentinel, "Tutorial and training preserve disk bytes: " + path)
	var result := {"checks":checks, "failures":failures, "capture":capture, "userData":OS.get_user_data_dir()}
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	if is_instance_valid(app):
		await preload("res://scripts/combat/audio_cleanup.gd").release(app, get_tree())
		app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("TUTORIAL: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
