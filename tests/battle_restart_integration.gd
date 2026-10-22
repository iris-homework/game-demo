extends Node
## Headless application callbacks plus two separate processes; no real player saves.
const OUTPUT := "res://artifacts/qa/battle-restart-2026-10-22/integration/"
var app: Control
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func wait_for_battle() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if Game.page == "battle" and is_instance_valid(app.view) and app.view.get("initialized") == true and not Game.battle_busy and not Game.transition_locked:
			return
		await get_tree().process_frame
	check(false, "Battle view becomes ready")

func _ready() -> void:
	get_tree().create_timer(45).timeout.connect(func(): push_error("Integration timeout"); get_tree().quit(2))
	seed(20261022)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	Game.save_path = OUTPUT + "checkpoint.json"
	Game.meta_path = OUTPUT + "meta.json"
	Game.save_enabled = true
	var mode := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "read"
	if mode == "write":
		Game.state = Game.initial_state()
		Game.state.currentHp = 73
		Game.state.activeEventId = "E04"
		Game.state.currentPlaceId = "alley"
		Game.enter_node("battle")
	else:
		Game.state = {}
		Game.page = "menu"
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	if mode != "write": Game.resume()
	await wait_for_battle()
	if failures > 0:
		get_tree().quit(1)
		return
	if mode == "write":
		var expected := {"combat":app.view.model.snapshot(), "firstHand":app.view.model.hand.duplicate()}
		var file := FileAccess.open(OUTPUT + "expected-opening.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(expected))
		file.close()
		check(app.view.model.player_hp == 73 and app.view.model.turn == 1, "Actual battle opens with adventure HP")
		app.view.show_cyberware()
		app.view.activate_cyberware("test_cyberware_01")
		app.view.close_pile()
		check(app.view.model.used_cyberware.size() == 1, "Actual technology callback commits")
		var uid: String = app.view.model.hand[0]
		app.view.selected_uid = uid
		var target := 0 if app.view.model.card_target(uid) == "enemy" else -1
		await app.view.play_selected(target)
		check(app.view.model.energy < 3, "Actual card callback spends energy")
		await app.view.end_turn_pressed()
		check(app.view.model.turn == 2 and app.view.model.player_hp < 73, "Actual enemy turn commits damage")
		var disk = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
		check(disk.combat.turn == 1 and disk.currentHp == 73 and disk.combat.hand.is_empty(), "Disk contains opening while live view is turn two")
		# Quit the first process directly with a progressed live battle.
	else:
		var expected = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT + "expected-opening.json"))
		check(JSON.parse_string(JSON.stringify(app.view.model.snapshot())) == expected.combat, "Fresh process restores exact opening including HP, hands, statuses and enemies")
		check(app.view.model.hand == expected.firstHand, "Fresh process keeps initial shuffled hand")
		var uid: String = app.view.model.hand[0]
		app.view.selected_uid = uid
		await app.view.play_selected(0 if app.view.model.card_target(uid) == "enemy" else -1)
		check(app.view.model.energy < 3, "Resumed battle remains playable")
		Game.menu()
		while Game.transition_locked: await get_tree().process_frame
		check(Game.page == "menu", "Return to actual menu")
		app.view.continue_button.pressed.emit()
		await wait_for_battle()
		check(JSON.parse_string(JSON.stringify(app.view.model.snapshot())) == expected.combat, "Continue button restarts exact opening without duplicate draw")
	# Let presentation-only timers settle before tearing down the test harness.
	await get_tree().create_timer(0.5).timeout
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("BATTLE RESTART INTEGRATION %s: %d checks, %d failures" % [mode, checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
