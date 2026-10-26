extends Node
## Real main/console callbacks, headless + Dummy. No screenshots or physical input.
const Cleanup = preload("res://scripts/combat/audio_cleanup.gd")
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var app: Control
var output := "user://console-page-refresh-qa"

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message, "passed":ok})
	if not ok:
		failures.append(message)
		push_error("CONSOLE PAGE REFRESH: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func idle() -> void:
	await settle()
	var deadline := Time.get_ticks_msec() + 20000
	while Game.transition_locked or Game.battle_busy:
		if Time.get_ticks_msec() >= deadline:
			check(false, "Scene presentation finishes within twenty seconds")
			get_tree().quit(2)
			return
		await get_tree().process_frame
	await settle()

func remove_app() -> void:
	if not is_instance_valid(app): return
	if is_instance_valid(app.audio_hooks): app.audio_hooks.attach(null)
	await Cleanup.release(app, get_tree())
	app.queue_free()
	await settle()
	app = null

func fresh() -> void:
	await remove_app()
	Game.save_enabled = false
	Game.save_path = output.path_join("checkpoint.json")
	Game.meta_path = output.path_join("meta.json")
	Game.pending_save_kind = ""
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.config.developmentMode = true
	Game.state = Game.initial_state()
	Game.page = Game.state.currentScene

func mount() -> void:
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await idle()

func dialogue(node_id: String = "intro_01") -> void:
	await fresh()
	Game.state.activeEventId = "E01"
	Game.state.currentPlaceId = "bar"
	Game.enter_node(node_id)
	await mount()

func add_and_close(label: String) -> void:
	var before: int = Game.state.deck.count("noren_23")
	var revision: int = Game.revision
	app.open_card_console()
	check(is_instance_valid(app.card_console), label + " opens the real card console")
	check(Game.console_command("addcard 23").begins_with("已添加"), label + " adds through the real command")
	check(Game.revision == revision + 1 and Game.state.deck.count("noren_23") == before + 1, label + " commits one card and one revision")
	check(is_instance_valid(app.card_console), label + " addition keeps the console open")
	app.close_card_console()
	await idle()
	check(not is_instance_valid(app.card_console), label + " closes the console")

func test_dialogue_actions() -> void:
	await dialogue()
	await add_and_close("Dialogue Continue")
	check(app.view.expected_revision == Game.revision, "Continue view uses the post-console revision")
	app.view.text_label.visible_characters = -1
	app.view.advance()
	await settle()
	check(Game.state.activeNodeId == "intro_02", "Continue actually advances the authored dialogue after adding a card")
	await dialogue("contract")
	await add_and_close("Dialogue choice")
	app.view.select(0)
	await settle()
	check(Game.state.activeNodeId == "chosen_01" and "money_chip" in Game.state.ownedCyberwareIds, "Choice actually advances and grants the selected support chip")
	await dialogue()
	await add_and_close("Dialogue Skip")
	app.view.skip()
	await settle()
	check(Game.state.activeNodeId == "contract" and Game.state.currentScene == "dialogue", "Skip actually advances to the authored choice boundary")

func test_task_briefing() -> void:
	await fresh()
	Game.state.currentScene = "map"
	Game.page = "map"
	Game.state.completedEventIds = ["E01"]
	Game.state.refreshedEventIds = ["E02"]
	Game.visit("junkyard")
	await mount()
	app.view._process(10.0)
	await add_and_close("Task briefing")
	# A reconstructed briefing may start its typewriter again.
	app.view._process(10.0)
	var start: Button = app.view.find_child("event_E02", true, false)
	check(start != null and not start.disabled, "Current briefing enables its authored task button")
	if start != null:
		start.pressed.emit()
		await settle()
		check(Game.page == "dialogue" and Game.state.activeEventId == "E02" and Game.state.activeNodeId == Game.events.E02.startNodeId, "Task button actually starts E02 after console close")

func test_ordinary_result() -> void:
	await fresh()
	Game.state.activeEventId = "E01"
	Game.state.currentPlaceId = "bar"
	Game.enter_node("finish")
	await mount()
	check(Game.page == "result" and not Game.has_battle_reward(), "E01 fixture uses ordinary event settlement")
	await add_and_close("Ordinary settlement")
	var action: Button
	for node in app.view.find_children("*", "Button", true, false):
		if node.text.begins_with("返回城市地图"):
			action = node
			break
	check(action != null, "Ordinary settlement exposes its real return button")
	if action != null:
		action.pressed.emit()
		await settle()
		check(Game.page == "map" and Game.state.currentScene == "map", "Ordinary E01 settlement really returns to the map after adding a card")

func reward_fixture() -> void:
	await fresh()
	Game.state.activeEventId = "E02"
	Game.state.activeNodeId = "finish"
	Game.state.currentPlaceId = "junkyard"
	Game.state.battleId = "B02"
	Game.state.currentScene = "result"
	Game.state.currentDay = 2
	Game.state.result = "win"
	Game.state.completedEventIds = ["E01", "E02"]
	Game.state.battleHistory = [{"battleId":"B02", "result":"win"}]
	Game.prepare_battle_reward()
	Game.page = "result"
	Game.revision += 1
	check(Game.has_battle_reward() and Game.state.battleReward.options.size() == 3, "Reward fixture generates three real current candidates")
	await mount()

func test_battle_rewards() -> void:
	await reward_fixture()
	var result_view: Control = app.view
	var reward: Control = result_view.reward_view
	var receipt: Dictionary = Game.state.battleReward.duplicate(true)
	await add_and_close("Battle reward")
	check(app.view == result_view and app.view.reward_view == reward, "Console close refreshes the same result and reward nodes in place")
	check(Game.state.battleReward == receipt and reward.expected_revision == Game.revision, "Console addition keeps the frozen reward and updates its action revision")
	var before: int = Game.state.credits
	var amount: int = Game.reward_credit_amount()
	reward.credits_reward_button.pressed.emit()
	await settle()
	check(Game.state.credits == before + amount and Game.reward_credits_status() == "claimed", "Credit action actually claims the frozen amount after adding a card")
	check(app.view == result_view and app.view.reward_view == reward, "Credit claim keeps the same reward view")
	# Repeat the console round trip after credits, exercising an already updated receipt.
	await add_and_close("Partially claimed reward")
	check(app.view == result_view and app.view.reward_view == reward, "Partially claimed reward also refreshes in place")
	reward.card_reward_button.pressed.emit()
	await settle()
	check(is_instance_valid(reward.picker), "Card picker actually opens after console close")
	if is_instance_valid(reward.picker):
		var selected: String = Game.state.battleReward.options[0]
		var copies: int = Game.state.deck.count(selected)
		reward.picker.option_buttons[0].pressed.emit()
		await settle()
		check(Game.state.battleReward.status == "claimed" and Game.state.deck.count(selected) == copies + 1, "Picker actually grants its generated candidate exactly once")
		check(app.view == result_view and app.view.reward_view == reward, "Card claim keeps the same reward view")
	await add_and_close("Fully claimed reward")
	reward.exit_button.pressed.emit()
	await settle()
	check(Game.page == "map" and Game.state.credits == before + amount, "Reward Leave actually returns to map and retains paid credits")

func test_unchanged_commands_and_continuous_additions() -> void:
	await dialogue()
	var view: Control = app.view
	var revision: int = Game.revision
	var state: Dictionary = Game.state.duplicate(true)
	app.open_card_console()
	for command in ["help", "cards", "owned", "addcard missing", "addcard 23 0", "unknown"]:
		Game.console_command(command)
	check(Game.revision == revision and Game.state == state, "Queries and rejected commands do not change revision or state")
	app.close_card_console()
	await settle()
	check(app.view == view and view.expected_revision == Game.revision, "Closing an unchanged console preserves the current page instance")
	app.open_card_console()
	var console: Control = app.card_console
	var before: int = Game.state.deck.count("noren_23")
	for index in 2:
		check(Game.console_command("addcard 23").begins_with("已添加"), "Continuous addition %d succeeds" % index)
		check(app.card_console == console and app.view == view, "Continuous addition %d keeps console and underlying page alive" % index)
	check(Game.state.deck.count("noren_23") == before + 2, "Both continuous additions persist in the in-memory deck")
	app.close_card_console()
	await settle()
	check(app.view.expected_revision == Game.revision, "Closing after continuous additions refreshes to the final revision")

func test_external_page_change_with_open_console() -> void:
	await dialogue()
	var original_id: int = app.view.get_instance_id()
	var created: Array[int] = []
	app.child_entered_tree.connect(func(node: Node):
		var script = node.get_script()
		if script != null and script.resource_path == "res://scripts/dialogue.gd": created.append(node.get_instance_id()))
	app.open_card_console()
	Game.console_command("addcard 23")
	check(is_instance_valid(app.card_console), "External-change fixture has a changed, still-open console")
	Game.enter_node("intro_02")
	await settle()
	check(not is_instance_valid(app.card_console), "External changed signal closes the console during page replacement")
	check(created.size() == 1 and app.view.get_instance_id() != original_id, "External replacement creates exactly one dialogue view without recursive refresh")
	check(Game.state.activeNodeId == "intro_02" and app.view.expected_revision == Game.revision, "The one replacement view shows the externally selected current node")
	var live_views := 0
	for child in app.get_children():
		var script = child.get_script()
		if script != null and script.resource_path == "res://scripts/dialogue.gd": live_views += 1
	check(live_views == 1, "Only one dialogue page remains attached after external replacement")

func test_battle_restore() -> void:
	await fresh()
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.enter_node("battle")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	model.draw_cards()
	model.turn = 3
	model.player_hp = 48
	model.energy = 1
	model.block = 7
	Game.commit_combat(model)
	await mount()
	var view: Control = app.view
	var live_model = view.model
	var before: Dictionary = view.model.snapshot()
	await add_and_close("Ongoing battle")
	check(app.view == view and view.model == live_model, "Battle console retains the current view and model object")
	check(view.model.snapshot() == Game.state.combat and view.expected_revision == Game.revision, "Battle-specific restore synchronizes the current snapshot and revision")
	check(view.model.turn == before.turn and view.model.player_hp == before.playerHp and view.model.energy == before.norenState.energy and view.model.block == before.norenState.block, "Battle addition preserves turn, damage, spent energy and block instead of restarting")
	check(view.model.hand == before.hand and view.model.instances.size() == before.instances.size() + 1 and view.model.draw_pile.size() == before.drawPile.size() + 1, "Battle addition retains the current hand and adds one draw-pile instance")
	check(view.shown_draw_count == view.model.draw_pile.size(), "Battle restore updates the draw-pile badge")

func _ready() -> void:
	if OS.get_user_data_dir().ends_with("/MidnightCommissionDemo"):
		push_error("Run console page refresh QA only in an isolated copied project/user directory")
		get_tree().quit(2)
		return
	get_tree().create_timer(90).timeout.connect(func(): push_error("CONSOLE PAGE REFRESH timeout"); get_tree().quit(2))
	var configured := OS.get_environment("QA_OUT_DIR")
	if not configured.is_empty(): output = configured
	DirAccess.make_dir_recursive_absolute(output)
	await test_dialogue_actions()
	await test_task_briefing()
	await test_ordinary_result()
	await test_battle_rewards()
	await test_unchanged_commands_and_continuous_additions()
	await test_external_page_change_with_open_console()
	await test_battle_restore()
	await remove_app()
	var file := FileAccess.open(output.path_join("console-page-refresh-results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures, "records":records,
		"scope":"real main/console/page callbacks; headless + Dummy; no GPU pixels or physical input"}, "\t"))
	file.close()
	print("CONSOLE PAGE REFRESH TESTS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
