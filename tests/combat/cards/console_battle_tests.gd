extends Node
## Run in an isolated project/user directory. No screenshots or physical input.
var checks := 0
var failures: Array[String] = []
var output := "res://artifacts/qa/console-battle-2026-10-25"
var app: Control

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("CONSOLE BATTLE: " + message)

func fresh() -> void:
	Game.save_enabled = false
	Game.save_path = output.path_join("checkpoint.json")
	Game.meta_path = output.path_join("meta.json")
	Game.training_mode = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.pending_save_kind = ""
	Game.config.developmentMode = true
	Game.state = Game.initial_state()
	Game.page = Game.state.currentScene

func battle() -> void:
	fresh()
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.enter_node("battle")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	model.draw_cards()
	Game.commit_combat(model)

func boss() -> void:
	fresh()
	Game.state.currentScene = "map"
	Game.page = "map"
	Game.state.currentDay = 7
	Game.refresh_event_pool()
	check(Game.start_event("E16"), "Boss event starts")
	Game.skip_dialogue(Game.revision)
	check(Game.state.battleId == "B16", "Boss dialogue reaches battle")

func zones(snapshot: Dictionary, description: String) -> void:
	var seen: Dictionary = {}
	var unique := true
	for uid in snapshot.drawPile + snapshot.hand + snapshot.discardPile + snapshot.norenState.exhaustPile:
		unique = unique and snapshot.instances.has(uid) and not seen.has(uid)
		seen[uid] = true
	check(unique and seen.size() == snapshot.instances.size(), description + " preserves all instances exactly once")
	check(Game.valid_combat(snapshot), description + " validates")

func test_add() -> void:
	battle()
	var before: Dictionary = Game.state.combat.duplicate(true)
	var opening: Dictionary = Game.state.battleStart.duplicate(true)
	check(Game.console_command("addcard 36 2").begins_with("已添加"), "Number command succeeds")
	check(Game.console_command("addcard 深度伤口").begins_with("已添加"), "Chinese-name command succeeds")
	check(Game.console_command("addcard noren_36").begins_with("已添加"), "ID command succeeds")
	var current: Dictionary = Game.state.combat
	check(Game.state.deck.count("noren_36") == 4, "Four added copies enter permanent ownership")
	check(current.drawPile.slice(0, before.drawPile.size()) == before.drawPile, "Adding cards keeps existing draw order")
	check(current.drawPile.size() == before.drawPile.size() + 4, "Added copies enter live draw pile")
	check(current.hand == before.hand and current.discardPile == before.discardPile and current.norenState == before.norenState, "Addition preserves hand, discard and resources")
	var added: Array = current.drawPile.slice(before.drawPile.size())
	check(added.all(func(uid): return current.instances[uid] == "noren_36"), "Every new UID resolves to requested card")
	check(Game.state.battleStart.drawPile.slice(opening.drawPile.size()) == added, "Restart point contains the same added UIDs")
	check(Game.valid_battle_start(Game.state) and Game.valid_save(Game.state), "Live and restart snapshots remain mutually valid")
	zones(current, "Repeated additions")
	var model := CombatModel.new()
	model.restore(current)
	var drawn := model.draw_cards(4)
	check(drawn.size() == 4 and drawn.all(func(uid): return uid in added), "Added cards can be drawn immediately in the same battle")
	check(model.play_card(drawn[0], -1).get("exhausted", false) and "persistent_bleed" in model.powers, "An added card executes its real effect in the current battle")
	var frozen := Game.state.duplicate(true)
	for command in ["addcard missing", "addcard 36 0", "addcard 36 1.5", "addcard 36 100", "addcard 36 1 extra"]:
		Game.console_command(command)
		check(Game.state == frozen, "Invalid addition stays atomic: " + command)
	Game.save_enabled = true
	check(Game.save_game(), "Added battle saves to dedicated checkpoint")
	Game.state = {}
	check(Game.load_game(), "Added battle checkpoint reloads")
	check(Game.state.combat.instances == frozen.combat.instances and Game.state.combat.hand.is_empty(), "Reload restarts battle with every added copy")
	check(Game.valid_save(Game.state), "Reloaded added battle validates")
	Game.save_enabled = false
	var snapshot := Game.state.duplicate(true)
	Game.save_enabled = true
	Game.save_path = output.path_join("missing-directory/checkpoint.json")
	check(Game.console_command("addcard 23").contains("失败") and Game.state == snapshot, "Save failure rolls back ownership, live battle and restart snapshot together")
	Game.save_enabled = false

func test_guards() -> void:
	battle()
	for command in ["addcard 23", "kill"]:
		for guard in ["busy", "transition", "pending", "development"]:
			var before := Game.state.duplicate(true)
			Game.battle_busy = guard == "busy"
			Game.transition_locked = guard == "transition"
			Game.pending_save_kind = "combat" if guard == "pending" else ""
			Game.config.developmentMode = guard != "development"
			Game.console_command(command)
			check(Game.state == before, command + " blocked by " + guard)
		Game.battle_busy = false
		Game.transition_locked = false
		Game.pending_save_kind = ""
		Game.config.developmentMode = true
	var before := Game.state.duplicate(true)
	Game.console_command("kill extra")
	check(Game.state == before, "Kill rejects unexpected arguments")
	fresh()
	before = Game.state.duplicate(true)
	Game.console_command("kill")
	check(Game.state == before, "Kill outside battle cannot mutate adventure")
	Game.state = {}
	Game.console_command("kill")
	check(Game.state.is_empty(), "Kill without adventure is safe")

func test_kill() -> void:
	battle()
	for enemy in Game.state.combat.enemies: enemy.block = 999
	var before: Dictionary = Game.state.combat.duplicate(true)
	Game.console_command("kill")
	check(Game.state.combat.enemies.all(func(enemy): return enemy.hp == 0), "Kill clears all three enemies despite block")
	check(Game.state.combat.outcome == "win" and Game.state.currentHp == before.playerHp, "Kill wins without changing player HP")
	check(Game.valid_combat(Game.state.combat), "Killed snapshot validates")
	var frozen := Game.state.duplicate(true)
	Game.console_command("kill")
	check(Game.state == frozen, "Repeated kill on finished battle is inert")
	Game.console_command("addcard 23")
	check(Game.state == frozen, "Finished battle cannot receive more cards")
	battle()
	frozen = Game.state.duplicate(true)
	Game.save_enabled = true
	Game.save_path = output.path_join("missing-directory/checkpoint.json")
	Game.console_command("kill")
	check(Game.state == frozen, "Failed kill save rolls back combat and outcome")
	Game.save_enabled = false
	boss()
	Game.console_command("addcard 36 2")
	Game.console_command("kill")
	check(Game.state.combat.encounterPhase == 2 and Game.state.combat.outcome.is_empty(), "First Boss kill advances to second phase")
	check(Game.state.combat.enemies.all(func(enemy): return enemy.hp == 80), "First kill leaves newly spawned phase alive at authored eighty HP")
	check(Game.valid_battle_start(Game.state) and Game.valid_save(Game.state), "Boss phase with console additions remains loadable")
	zones(Game.state.combat, "Boss phase transition")
	Game.console_command("addcard 23")
	check(Game.valid_battle_start(Game.state), "Second-phase addition also updates opening card set")
	Game.console_command("kill")
	check(Game.state.combat.outcome == "win" and Game.state.combat.enemies.all(func(enemy): return enemy.hp == 0), "Second Boss kill wins against both dancers")
	check(Game.valid_combat(Game.state.combat), "Boss final killed snapshot validates")

func test_training() -> void:
	fresh()
	var adventure := Game.state.duplicate(true)
	Game.start_training("B04")
	var deck: Array = Game.state.deck.duplicate()
	var size: int = Game.state.combat.instances.size()
	Game.console_command("addcard 23 2")
	check(Game.state.deck == deck and Game.state.combat.instances.size() == size + 2, "Training addition is available only in this combat")
	check(Game.valid_combat(Game.state.combat), "Training addition snapshot validates")
	Game.console_command("kill")
	check(Game.state.combat.outcome == "win", "Kill also works in training")
	Game.finish_training("win")
	check(Game.state == adventure and not Game.training_mode, "Training restores original adventure after temporary addition and kill")
	Game.start_training("B11")
	var pollution := 0
	for enemy in Game.state.combat.enemies: pollution += int(enemy.get("deathPollution", 0))
	check(pollution > 0, "Fish fixture has authored death effects")
	Game.console_command("kill")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	check(model.buffs.count(model, "pollution") == pollution, "Kill resolves every fish death effect once")
	Game.console_command("kill")
	model.restore(Game.state.combat)
	check(model.buffs.count(model, "pollution") == pollution, "Repeated kill never repeats death effects")
	Game.finish_training("win")

func idle() -> void:
	await get_tree().process_frame
	var start := Time.get_ticks_msec()
	while Game.battle_busy or Game.transition_locked:
		await get_tree().process_frame
		if Time.get_ticks_msec() - start > 20000:
			check(false, "Scene wait timed out")
			get_tree().quit(2)
			return
	await get_tree().process_frame

func test_scene() -> void:
	battle()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await idle()
	var view: Control = app.view
	var before: int = view.model.instances.size()
	app.open_card_console()
	check(is_instance_valid(app.card_console) and view.process_mode == Node.PROCESS_MODE_DISABLED, "Console pauses battle page")
	app.card_console.add_card("noren_23")
	app.close_card_console()
	await idle()
	check(view.model.instances.size() == before + 1 and view.model.snapshot() == Game.state.combat, "Closing console synchronizes live battle model")
	check(view.shown_draw_count == view.model.draw_pile.size(), "Draw-pile badge reflects inserted card")
	check(view.expected_revision == Game.revision, "Console synchronization keeps battle revision current")
	var added_uid: String = view.model.draw_pile.back()
	check(view.model.instances[added_uid] == "noren_23", "New card remains at live draw-pile top")
	app.open_card_console()
	app.card_console.submit("kill")
	await idle()
	check(not is_instance_valid(app.card_console), "Successful kill closes console automatically")
	check(Game.state.currentScene != "battle" and Game.state.result == "win", "Kill leaves real battle through normal victory route")
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	app = null
	boss()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await idle()
	view = app.view
	app.open_card_console()
	app.card_console.submit("kill")
	await idle()
	check(not is_instance_valid(app.card_console) and app.view == view, "Boss first kill closes console and retains battle page")
	check(view.model.encounter_phase == 2 and view.shown_encounter_phase == 2 and view.stage.enemies.size() == 2, "Boss reveal and model both reach second phase")
	check(view.cards.size() == view.model.hand.size() and view.shown_draw_count == view.model.draw_pile.size(), "Boss console transition rebuilds new-round hand and pile display")
	check(view.model.snapshot() == Game.state.combat and not Game.battle_busy, "Boss presentation does not mutate already committed model")
	app.open_card_console()
	app.card_console.submit("kill")
	await idle()
	check(Game.state.currentScene != "battle" and Game.state.result == "win", "Boss second kill exits through formal victory route")
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	app = null

func _ready() -> void:
	if not "qa" in OS.get_user_data_dir().to_lower():
		push_error("CONSOLE BATTLE: isolated QA user directory required")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	test_add()
	test_guards()
	test_kill()
	test_training()
	await test_scene()
	Game.save_enabled = false
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = output.path_join("checkpoint.json") + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	await get_tree().create_timer(0.2).timeout
	print("CONSOLE BATTLE: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
