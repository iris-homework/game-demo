extends Node
## Headless completion-flow regression. Persistence requires an explicit QA directory.
var checks := 0
var failures: Array[String] = []
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("WEEK END: " + message)

func same(left, right) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func fresh() -> void:
	Game.save_enabled = false
	Game.save_path = output.path_join("checkpoint.json")
	Game.meta_path = output.path_join("meta.json")
	Game.pending_save_kind = ""
	Game.training_mode = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.page = "map"

func victory_dialogue() -> Dictionary:
	fresh()
	Game.state.currentDay = 7
	Game.refresh_event_pool()
	check(Game.start_event("E16"), "day-seven Boss entrance starts")
	Game.skip_dialogue(Game.revision)
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	model.enemy_damage(0, 999)
	model.resolve_outcome()
	check(model.advance_encounter_phase(), "formal Boss reaches second phase")
	for index in model.enemies.size(): model.enemy_damage(index, 999)
	model.resolve_outcome()
	check(model.encounter_phase == 2 and model.outcome == "win", "both second-phase dancers defeated")
	check(Game.commit_combat(model), "real victorious model commits")
	check(Game.battle_exit("win", Game.revision), "victory enters authored post-battle dialogue")
	check(Game.page == "dialogue" and Game.state.activeNodeId == "win_01", "victory retains first post-battle line")
	check(not Game.is_week_complete() and not Game.is_run_over(), "victory alone does not end the week")
	return Game.state.duplicate(true)

func reward_state(skip: bool = true) -> Dictionary:
	victory_dialogue()
	var credits: int = Game.state.credits
	if skip:
		Game.skip_dialogue(Game.revision)
	else:
		var visited: Array[String] = []
		while Game.page == "dialogue" and visited.size() < 10:
			visited.append(Game.state.activeNodeId)
			Game.advance(Game.revision)
		check(visited == ["win_01", "win_02", "win_03", "win_04", "win_05"], "all five post-battle lines precede rewards")
	check(Game.page == "result" and Game.state.currentScene == "result", "dialogue reaches original result page")
	check(Game.has_battle_reward() and Game.state.battleReward.get("battleType") == "boss", "Boss card reward available")
	check(Game.state.battleReward.get("status") == "pending" and Game.state.credits == credits + 50, "credits paid once and choice remains pending")
	check(not Game.is_week_complete() and not Game.is_run_over() and Game.can_continue(), "pending reward remains resumable before completion")
	return Game.state.duplicate(true)

func completed_state() -> Dictionary:
	reward_state(false)
	var selected: String = Game.state.battleReward.options[0]
	var count_before: int = Game.state.deck.count(selected)
	check(Game.choose_reward_card(selected, Game.revision), "choose one Boss reward card")
	check(Game.state.deck.count(selected) == count_before + 1 and Game.state.battleReward.status == "claimed", "chosen card committed exactly once")
	check(not Game.is_week_complete() and Game.can_continue(), "choosing a card still waits for reward exit")
	check(Game.claim_rewards(Game.revision), "reward exit ends first week")
	check(Game.page == "result" and Game.state.currentScene == "result", "completion retains result route")
	check(Game.is_week_complete() and Game.is_run_over() and not Game.is_run_failed(), "completion is terminal victory, never defeat")
	check(Game.state.flags.get("week1Complete", false) and not Game.can_continue(), "completion flag disables continue")
	check(Game.state.result == "win" and Game.state.currentDay == 7 and "E16" in Game.state.completedEventIds, "victory identity and day-seven completion remain")
	check(Game.state.battleReward.status == "claimed" and Game.state.deck.count(selected) == count_before + 1, "completion preserves claimed card")
	check(Game.valid_save(Game.state), "completed checkpoint validates")
	return Game.state.duplicate(true)

func test_pending_roundtrip() -> void:
	var pending := reward_state()
	check(Game.save_game(), "pending reward saves only to QA checkpoint")
	Game.state = {}
	check(Game.load_game(), "pending reward reloads")
	check(same(Game.state, pending), "pending reward roundtrip preserves offer and credits")
	check(not Game.is_week_complete() and Game.can_continue() and Game.has_battle_reward(), "reloaded pending reward remains selectable and resumable")
	var selected: String = Game.state.battleReward.options[0]
	check(Game.choose_reward_card(selected, Game.revision), "pending reward can be claimed after reload")
	check(not Game.is_week_complete() and Game.state.battleReward.status == "claimed", "reload choice waits for explicit exit")
	var credits: int = Game.state.credits
	check(Game.claim_rewards(Game.revision) and Game.is_week_complete(), "exit after reload reaches completion")
	check(Game.state.credits == credits and selected in Game.state.deck, "reward exit does not repay credits or revoke card")
	var after := Game.state.duplicate(true)
	check(not Game.claim_rewards(Game.revision) and same(Game.state, after), "completed reward exit rejects duplicates")

func test_skip_choice() -> void:
	reward_state()
	var deck: Array = Game.state.deck.duplicate()
	check(Game.claim_rewards(Game.revision), "unselected card may be explicitly abandoned at week exit")
	check(Game.is_week_complete() and Game.state.battleReward.status == "skipped" and Game.state.deck == deck, "abandoning card consumes offer and ends week without adding a card")

func test_completion_save_retry() -> void:
	reward_state()
	var credits: int = Game.state.credits
	var blocker_path := output.path_join("write-blocker")
	var blocker := FileAccess.open(blocker_path, FileAccess.WRITE)
	blocker.store_string("QA-only regular file prevents creating a child checkpoint")
	blocker.close()
	Game.save_path = blocker_path.path_join("checkpoint.json")
	Game.save_enabled = true
	check(not Game.claim_rewards(Game.revision), "failed completion checkpoint reports failure")
	check(Game.pending_save_kind == "scene" and Game.is_week_complete() and Game.state.battleReward.status == "skipped", "completion resolves once while awaiting save retry")
	var waiting := Game.state.duplicate(true)
	Game.go_map()
	check(not Game.claim_rewards(Game.revision) and same(Game.state, waiting), "pending completion save blocks further progress")
	Game.save_path = output.path_join("checkpoint.json")
	check(Game.retry_pending_save() and Game.pending_save_kind.is_empty(), "recovered storage persists completion through retry")
	check(same(Game.state, waiting) and Game.state.credits == credits and Game.is_week_complete(), "retry preserves completion without duplicate income")
	Game.save_enabled = false

func test_navigation_and_roundtrip(done: Dictionary) -> void:
	Game.state = done.duplicate(true)
	Game.page = "result"
	var revision: int = Game.revision
	Game.go_map()
	Game.visit("market")
	check(not Game.start_event("E16"), "completed adventure cannot start events")
	Game.enter_node("intro_01")
	check(not Game.claim_rewards(Game.revision), "completed adventure cannot claim rewards again")
	check(not Game.choose_reward_card(Game.state.battleReward.options[1], Game.revision), "completed adventure cannot choose another card")
	check(same(Game.state, done) and Game.revision == revision and Game.page == "result", "map/place/dialogue/reward routes preserve terminal checkpoint")
	Game.menu()
	check(Game.page == "menu" and same(Game.state, done) and not Game.is_run_failed(), "menu preserves completed victory")
	Game.resume()
	check(Game.page != "map" and Game.state.currentScene == "result" and not Game.is_run_failed(), "direct resume cannot revive adventure or create defeat")
	check(Game.save_game(), "completed victory saves")
	var disk = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	check(disk.currentScene == "result" and disk.result == "win" and disk.flags.get("week1Complete", false), "save projection never converts completion into defeat")
	Game.state = {}
	check(not Game.can_continue(), "disk-only completed save disables continue")
	check(Game.load_game() and Game.is_week_complete() and not Game.is_run_failed(), "completed save reloads as victory")
	check(same(Game.state, done), "completed save preserves card, credits and history")

func test_migration(done: Dictionary) -> void:
	for scene in ["result", "map"]:
		for status in ["claimed", "skipped", "pending"]:
			var old := done.duplicate(true)
			old.flags.erase("week1Complete")
			old.currentScene = scene
			old.battleReward.status = status
			if status != "claimed": old.battleReward.selectedCardId = ""
			var migrated: Dictionary = Game.migrate_save(old)
			var label: String = scene + "/" + status
			check(Game.valid_save(migrated), "legacy Boss checkpoint validates: " + label)
			check(migrated.credits == old.credits and migrated.deck == old.deck and migrated.claimedRewardIds == old.claimedRewardIds, "migration never replays income/card grants: " + label)
			if scene == "result" and status == "pending":
				check(not Game.is_week_complete(migrated) and migrated.battleReward.status == "pending", "legacy pending reward remains claimable")
			else:
				check(Game.is_week_complete(migrated) and migrated.currentScene == "result" and migrated.activeEventId == "E16" and migrated.activeNodeId == "finish", "legacy completed Boss canonicalizes to week result: " + label)
			if status == "claimed": check(migrated.battleReward.selectedCardId == old.battleReward.selectedCardId, "legacy claimed receipt preserved: " + scene)
	var failed := done.duplicate(true)
	Game.mark_run_failed(failed)
	var migrated_failed: Dictionary = Game.migrate_save(failed)
	check(Game.is_run_failed(migrated_failed) and migrated_failed.currentScene == "defeat" and not Game.is_week_complete(migrated_failed), "old failure takes precedence over Boss completion")
	var dialogue := victory_dialogue()
	var migrated_dialogue: Dictionary = Game.migrate_save(dialogue)
	check(migrated_dialogue.currentScene == "dialogue" and migrated_dialogue.activeNodeId == "win_01" and not Game.is_week_complete(migrated_dialogue), "old post-battle dialogue resumes without skipping remaining lines")
	fresh()
	var retired := Game.state.duplicate(true)
	retired.activeEventId = "E12"
	retired.activeNodeId = "finish"
	retired.flags.week1Complete = true
	var migrated_retired: Dictionary = Game.migrate_save(retired)
	check(not migrated_retired.flags.has("week1Complete") and not Game.is_run_over(migrated_retired), "removed E12 finale flag does not create a new completion")

func test_training_and_new_game(done: Dictionary) -> void:
	Game.state = done.duplicate(true)
	Game.page = "menu"
	check(Game.save_game(), "save completed adventure before training")
	var disk := FileAccess.get_file_as_bytes(Game.save_path)
	for outcome in ["win", "lose"]:
		Game.start_training("B16")
		check(Game.training_mode and Game.state.battleId == "B16" and not Game.is_week_complete(), "training starts independently from completed adventure: " + outcome)
		check(Game.battle_exit(outcome, Game.revision), "training accepts supported simulated result: " + outcome)
		check(not Game.training_mode and Game.page == "menu" and same(Game.state, done) and Game.is_week_complete(), "training restores completed adventure: " + outcome)
		check(FileAccess.get_file_as_bytes(Game.save_path) == disk, "training never changes completed disk checkpoint: " + outcome)
	Game.new_game()
	check(not Game.is_run_over() and not Game.is_week_complete() and Game.can_continue(), "new adventure resets completion and enables continue")
	check(Game.state.completedEventIds.is_empty() and not Game.state.flags.has("week1Complete"), "new adventure clears completion history")

func test_view(done: Dictionary) -> void:
	Game.state = done.duplicate(true)
	Game.page = "result"
	var view = preload("res://scenes/result.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var week_end: Control = view.week_end_view
	check(is_instance_valid(week_end) and not is_instance_valid(view.reward_view), "result prioritizes completion over retained reward receipt")
	if is_instance_valid(week_end):
		var buttons := view.find_children("*", "BaseButton", true, false)
		var back := week_end.find_child("return_to_menu", true, false) as Button
		check(buttons.size() == 1 and is_instance_valid(back), "completion exposes exactly one return-to-menu button")
		var title := week_end.find_child("week_end_title", true, false) as Label
		var message := week_end.find_child("week_end_message", true, false) as Label
		check(is_instance_valid(title) and title.text == "第一周结束", "completion title matches requested text")
		check(is_instance_valid(message) and message.text == "后续内容开发中", "completion message matches requested text")
		check(week_end.hp_fill == null and week_end.credits_label == null, "completion omits adventure status controls")
		check(view.handle_escape() and Game.page == "menu" and Game.is_week_complete() and not Game.is_run_failed(), "completion Escape returns to menu without creating defeat")
		Game.page = "result"
		if is_instance_valid(back): back.pressed.emit()
		check(Game.page == "menu" and same(Game.state, done), "only completion button returns to menu without state mutation")
	view.free()
	await get_tree().process_frame

func _ready() -> void:
	Game.save_enabled = false
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty() or not output.is_absolute_path():
		push_error("WEEK END: set QA_OUT_DIR to an isolated absolute test output directory")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	fresh()
	test_pending_roundtrip()
	test_skip_choice()
	test_completion_save_retry()
	var done := completed_state()
	test_navigation_and_roundtrip(done)
	test_migration(done)
	test_training_and_new_game(done)
	await test_view(done)
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures}, "\t"))
	file.close()
	print("WEEK END: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
