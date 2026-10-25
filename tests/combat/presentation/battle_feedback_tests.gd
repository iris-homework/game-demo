extends "res://tests/combat/cards/noren_cards_visual.gd"
## Headless node/state checks. No screenshots, window changes or system pointer input.
var error_cues := 0

func freeze_battle(view: Control) -> Dictionary:
	return {
		"model": view.model.snapshot(),
		"state": Game.state.duplicate(true),
		"revision": Game.revision,
		"busy": Game.battle_busy,
		"locked": Game.transition_locked,
		"cards": view.cards.keys(),
	}

func check_unchanged(view: Control, before: Dictionary, title: String) -> void:
	check(view.model.snapshot() == before.model, title + ": combat snapshot is unchanged")
	check(Game.state == before.state and Game.revision == before.revision, title + ": no commit or save-state mutation")
	check(Game.battle_busy == before.busy and Game.transition_locked == before.locked, title + ": input remains unlocked")
	check(view.cards.keys() == before.cards and not is_instance_valid(view.pile_overlay), title + ": live hand is retained without an overlay")

func check_mouse_ignored(root: Control, title: String) -> void:
	check(root.mouse_filter == Control.MOUSE_FILTER_IGNORE, title + ": root ignores pointer input")
	for child in root.find_children("*", "Control", true, false):
		check(child.mouse_filter == Control.MOUSE_FILTER_IGNORE, title + ": %s ignores pointer input" % child.name)

func check_label_fits(line: Label, hud: Control, title: String) -> void:
	var font: Font = line.get_theme_font("font")
	var font_size := line.get_theme_font_size("font_size")
	var text_size := font.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	check(line.visible and not line.text.is_empty(), title + ": label is visible and populated")
	check(line.size.x + 1.0 >= text_size.x and line.size.y + 1.0 >= font.get_height(font_size), title + ": complete text fits its label")
	var bounds := hud.get_global_rect().grow(1.0)
	var label_bounds := line.get_global_rect()
	check(bounds.encloses(label_bounds), title + ": label stays inside the HUD")

func check_feedback(view: Control, resource: String, title: String) -> void:
	var feedback = view.resource_feedback
	check(is_instance_valid(feedback) and feedback.visible, title + ": dedicated feedback is visible")
	check(feedback.resource == resource, title + ": feedback identifies the rejected resource")
	check(feedback.title_label.text == ("能量不足" if resource == "energy" else "弹药不足"), title + ": resource title is explicit")
	check(not feedback.detail_label.text.is_empty(), title + ": actionable detail is populated")
	check(not is_instance_valid(app.toast), title + ": no duplicate generic toast")
	check_mouse_ignored(feedback, title)
	check_label_fits(feedback.title_label,feedback,title + " title")
	check_label_fits(feedback.detail_label,feedback,title + " detail")

func clear_training_toast() -> void:
	if is_instance_valid(app.toast): app.toast.queue_free()
	await get_tree().process_frame

func exercise_energy_rejection() -> void:
	await install_hand([1,26,5,2], "melee")
	await clear_training_toast()
	var view = app.view
	var feedback = view.resource_feedback
	check(not feedback.visible, "New battle starts with no resource feedback")
	view.model.energy = 0
	view.refresh_resources()
	var before := freeze_battle(view)
	var cues_before := error_cues
	view.select_card("card_000")
	check(error_cues == cues_before+1,"Resource rejection plays exactly one existing error cue")
	check_feedback(view, "energy", "Zero-energy select rejection")
	check(view.selected_uid.is_empty(), "Rejected card never enters aim")
	check(feedback.detail_label.text.contains(str(view.model.card_cost("card_000"))) and feedback.detail_label.text.contains("0"), "Energy detail includes required cost and current zero")
	check_unchanged(view, before, "Zero-energy select rejection")
	# A different, affordable card can still be selected while the hint is visible.
	view.select_card("card_002")
	check(view.selected_uid == "card_002" and not feedback.visible, "Selecting an affordable zero-cost card clears the feedback without blocking input")
	view.cancel_selection()
	view.model.energy = 1
	view.refresh_resources()
	before = freeze_battle(view)
	check(view.model.card_cost("card_001") > view.model.energy, "Positive-energy fixture is still below the expensive card's cost")
	view.select_card("card_001")
	check_feedback(view, "energy", "Positive but insufficient energy")
	check(feedback.detail_label.text.contains(str(view.model.card_cost("card_001"))) and feedback.detail_label.text.contains("1"), "Energy detail includes expensive cost and positive current value")
	check_unchanged(view, before, "Positive but insufficient energy")
	# Cover the second guard: resource may change after aim began.
	view.model.energy = 3
	view.refresh_resources()
	view.select_card("card_001")
	check(view.selected_uid == "card_001", "Expensive card selects when enough energy is available")
	view.model.energy = 0
	view.refresh_resources()
	before = freeze_battle(view)
	view.play_selected(0)
	check_feedback(view, "energy", "Energy lost after selection")
	check_unchanged(view, before, "Energy lost after selection")
	view.cancel_selection()

func exercise_ammo_and_feedback_lifetime() -> void:
	await install_hand([1,26,5,2], "ranged")
	await clear_training_toast()
	var view = app.view
	var feedback = view.resource_feedback
	view.model.energy = 3
	view.model.ammo = 0
	view.refresh_resources()
	var before := freeze_battle(view)
	view.select_card("card_000")
	check_feedback(view, "ammo", "Zero-ammo select rejection")
	check(feedback.detail_label.text.contains("补弹") and feedback.detail_label.text.contains("切回近战"), "Ammo detail explains both recovery options")
	check_unchanged(view, before, "Zero-ammo select rejection")
	var original_id: int = feedback.get_instance_id()
	for i in 6:
		view.select_card("card_000")
	check(view.resource_feedback.get_instance_id() == original_id, "Rapid repeated rejection reuses one feedback instance")
	check_unchanged(view, before, "Rapid repeated ammo rejection")
	await get_tree().create_timer(1.1).timeout
	view.select_card("card_000")
	await get_tree().create_timer(0.8).timeout
	check(feedback.visible, "A repeated rejection restarts the hint lifetime")
	check_unchanged(view, before, "Hint animation and restart")
	await get_tree().create_timer(1.2).timeout
	check(not feedback.visible, "Resource hint automatically hides after the renewed lifetime")
	check_unchanged(view, before, "Hint timeout")
	# Replace the resource type while the previous hint still has time remaining.
	view.select_card("card_000")
	await get_tree().create_timer(1.1).timeout
	view.model.energy = 0
	view.refresh_resources()
	before = freeze_battle(view)
	view.select_card("card_000")
	check_feedback(view, "energy", "Ammo-to-energy hint replacement")
	check(view.resource_feedback.get_instance_id() == original_id, "Changing resource type reuses the same feedback instance")
	await get_tree().create_timer(0.8).timeout
	check(feedback.visible and feedback.resource == "energy", "The previous resource timeout cannot hide its replacement early")
	check_unchanged(view, before, "Resource hint replacement")
	# Cover play_selected's ammo guard after a valid aim began.
	view.model.energy = 3
	view.model.ammo = 1
	view.refresh_resources()
	view.select_card("card_000")
	check(view.selected_uid == "card_000", "Ranged card selects with available ammo")
	view.model.ammo = 0
	view.refresh_resources()
	before = freeze_battle(view)
	view.play_selected(0)
	check_feedback(view, "ammo", "Ammo lost after selection")
	check_unchanged(view, before, "Ammo lost after selection")
	view.cancel_selection()
	# A successful selection clears the hint, and a recovery action still works.
	view.select_card("card_002")
	check(view.selected_uid == "card_002" and not feedback.visible, "Recovery-card selection clears the hint without blocking input")
	view.play_selected(-1)
	check(not feedback.visible, "Beginning an action keeps old resource feedback hidden")
	await idle()
	check(view.model.ammo == 2 and not "card_002" in view.model.hand, "Actual zero-cost reload resolves after resource rejection")
	# Leave a live hint behind, then destroy its battle view and pending timers.
	view.model.ammo = 0
	view.refresh_resources()
	view.select_card("card_000")
	check(feedback.visible, "Cleanup fixture has an active hint")
	await install_hand([1,2], "melee")
	await clear_training_toast()
	check(not is_instance_valid(feedback), "Replacing the battle frees feedback and its pending animation")
	check(not app.view.resource_feedback.visible, "Replacement battle has no stale resource hint")
	before = freeze_battle(app.view)
	await get_tree().create_timer(2.0).timeout
	check(not app.view.resource_feedback.visible, "Old feedback timers cannot affect the replacement battle")
	check_unchanged(app.view, before, "Old battle hint cleanup")

func exercise_turn_hud() -> void:
	var view = app.view
	var hud = view.turn_hud
	check(is_instance_valid(hud) and hud.visible, "Battle contains a visible turn HUD")
	check(view.turn_label == hud.round_label, "Legacy turn_label aliases the HUD round label")
	check_mouse_ignored(hud, "Turn HUD")
	var before := freeze_battle(view)
	var phase_names := {"player":"你的回合", "enemy":"敌方回合", "reveal":"第二幕", "save":"等待保存"}
	for round_number in [1,9,10,99,100,999,1000,9999]:
		for phase in ["player", "enemy", "reveal", "save"]:
			hud.set_state(round_number, phase)
			await get_tree().process_frame
			check(hud.round_number == round_number and hud.phase == phase, "HUD records round %d / %s" % [round_number,phase])
			check(hud.round_label.text.contains(str(round_number)), "Round label contains the full round %d" % round_number)
			check(hud.phase_label.text == phase_names[phase], "Phase %s has a dedicated concise label" % phase)
			check_label_fits(hud.round_label, hud, "Round %d / %s heading" % [round_number,phase])
			check_label_fits(hud.phase_label, hud, "Round %d / %s phase" % [round_number,phase])
	check_unchanged(view, before, "Round and phase display updates")
	hud.set_state(view.model.turn, "player")
	check(hud.phase_label.text == "你的回合", "Player phase is displayed separately from the round number")
	# Observe the real asynchronous turn route rather than only calling set_state.
	var old_round: int = view.model.turn
	view.model.energy = 0
	view.refresh_resources()
	view.select_card("card_000")
	check(view.resource_feedback.visible, "End-turn cleanup fixture has a live rejection hint")
	view.end_turn_pressed()
	check(Game.battle_busy and hud.phase == "enemy" and hud.round_number == old_round, "Real end-turn immediately presents the enemy phase")
	check(not view.resource_feedback.visible, "Real end-turn clears resource feedback when input becomes busy")
	check(hud.phase_label.text.contains("敌方"), "Enemy phase is named in the HUD")
	await idle()
	check(view.model.turn == old_round + 1 and hud.round_number == view.model.turn and hud.phase == "player", "Real end-turn returns to the next player round")
	check(hud.round_label.text.contains(str(view.model.turn)) and hud.phase_label.text == "你的回合", "Next player phase separates the updated round number and phase")
	check_label_fits(hud.round_label, hud, "Actual next-round heading")
	check_label_fits(hud.phase_label, hud, "Actual next-round phase")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://battle_feedback_tests_unused.json"
	Game.meta_path = "user://battle_feedback_tests_meta_unused.json"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	app.audio_player.cue_played.connect(func(cue: String, _path: String):
		if cue == "ui_error": error_cues += 1)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	await exercise_energy_rejection()
	await exercise_ammo_and_feedback_lifetime()
	await exercise_turn_hud()
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "Feedback tests never create save files")
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	print("BATTLE FEEDBACK: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
