extends Node
## Headless real-view regression. All persistence is under isolated user://.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func same(left, right) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://battle-recovery-checkpoint.json"
	Game.meta_path = "user://battle-recovery-meta.json"
	Game.state = Game.initial_state()
	Game.state.ownedCyberwareIds.append_array(["money_chip", "healing_chip"])
	Game.state.equippedCyberwareIds = ["money_chip", "healing_chip"]
	Game.state.currentHp = 70
	Game.state.activeEventId = "E02"
	Game.state.currentPlaceId = "junkyard"
	Game.enter_node("battle")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	model.draw_cards(10)
	for uid in model.hand.duplicate():
		if model.card(uid).type == "attack":
			model.play_card(uid, 0)
			break
	check(model.outcome == "win", "Reach victory through real card resolution")
	Game.commit_combat(model)
	var before: Dictionary = Game.state.duplicate(true)
	var revision := Game.revision
	# A regular file as parent deterministically rejects writes on every platform.
	var blocker := FileAccess.open("user://battle-recovery-blocker", FileAccess.WRITE)
	blocker.store_string("test write blocker")
	blocker.close()
	Game.save_path = "user://battle-recovery-blocker/checkpoint.json"
	Game.save_enabled = true
	var view = preload("res://scripts/battle.gd").new()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	check(same(Game.state, before) and Game.revision == revision, "Automatic failed terminal exit rolls back all adventure changes")
	check(view.end_button.text == "重试战后结算" and not view.end_button.disabled, "Failed terminal exit exposes enabled retry button even before hand initialization")
	check(Game.page == "battle" and not Game.battle_busy, "Failure leaves battle view responsive")
	view.end_button.pressed.emit()
	check(same(Game.state, before) and Game.revision == revision, "Repeated failing button retry preserves victory and passive rewards atomically")
	check(same(view.model.snapshot(), model.snapshot()), "Retry never replays card, turn or opening draw")
	Game.save_path = "user://battle-recovery-checkpoint.json"
	view.end_button.pressed.emit()
	check(Game.page == "dialogue" and Game.state.currentScene == "dialogue", "Same button retries successfully after storage recovers")
	check(Game.state.credits == before.credits + 30 and Game.state.currentHp == 75, "Recovered exit grants money and healing exactly once")
	check(Game.state.battleHistory.size() == before.battleHistory.size() + 1, "Recovered exit records one victory")
	check(Game.valid_save(Game.state), "Recovered state validates")
	var after: Dictionary = Game.state.duplicate(true)
	view.end_button.pressed.emit()
	check(same(Game.state, after), "Duplicate button event cannot settle or reward victory twice")
	check(Game.load_game() and same(Game.state, after), "Successful retry persists complete victory and rewards")
	Game.save_enabled = false
	view.queue_free()
	await get_tree().process_frame
	print("BATTLE RECOVERY: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
