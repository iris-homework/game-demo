extends Node

const CHIPS := ["money_chip", "healing_chip", "swift_chip"]
var checks := 0
var failures: Array[String] = []
var output := "res://artifacts/qa/opening-support-2026-10-24"
var save_file := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("OPENING SUPPORT: " + message)

func same(left, right) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func fresh() -> void:
	Game.save_enabled = false
	Game.save_path = save_file
	Game.meta_path = output.path_join("meta-test.json")
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.new_game()
	Game.skip_dialogue(Game.revision)
	check(Game.state.activeNodeId == "contract", "opening stops at support choice")

func texts(node: Node) -> String:
	var value := ""
	if node is Label or node is Button or node is RichTextLabel: value += str(node.text) + "\n"
	for child in node.get_children(): value += texts(child)
	return value

func test_catalog_and_branches() -> void:
	var opening: Dictionary = Game.events.E01
	var authored := JSON.stringify(opening)
	for removed in ["理查德", "卢米娜", "失联的欠债人", "货运联络人", "setTarget"]:
		check(not removed in authored, "opening removes old target content: " + removed)
	check("三个委托" in authored, "opening states three-commission return objective")
	check(opening.nodes.contract.choices.map(func(c): return c.id) == CHIPS, "three choices use the three existing chips")
	for index in CHIPS.size():
		fresh()
		var id: String = CHIPS[index]
		var original_owned: Array = Game.state.ownedCyberwareIds.duplicate()
		var original_equipped: Array = Game.state.equippedCyberwareIds.duplicate()
		var credits: int = Game.state.credits
		var rev := Game.revision
		check(Game.choose(index, rev), "chip choice succeeds: " + id)
		check(Game.state.ownedCyberwareIds == original_owned + [id], "only selected chip is acquired: " + id)
		check(Game.state.equippedCyberwareIds == original_equipped + [id], "selected chip fills fourth slot: " + id)
		check(Game.state.flags.get("openingSupportChipId") == id and Game.state.choiceHistory.get("E01:contract") == id, "choice and support receipt agree: " + id)
		check(Game.state.targetId.is_empty() and Game.state.credits == credits, "support assigns no target and spends no credits")
		var chosen := Game.state.duplicate(true)
		check(not Game.choose(index, rev) and Game.state == chosen, "duplicate stale click cannot grant again")
		check(Game.save_game(), "selected support checkpoint saves")
		Game.state = {}
		check(Game.load_game() and same(Game.state, chosen), "selected support roundtrips without duplication")
		Game.skip_dialogue(Game.revision)
		check(Game.state.currentScene == "result" and Game.state.currentDay == 1 and Game.state.completedEventIds == ["E01"], "support finishes without spending a day")
		check(Game.claim_rewards(Game.revision), "support settlement returns to city")
		var settled := Game.state.duplicate(true)
		check(not Game.start_event("E01") and Game.state == settled, "opening cannot be replayed after completion")
		check(Game.save_game() and Game.load_game() and same(Game.state, settled), "settled support persists exactly once")

func test_grant_atomicity_and_full_slots() -> void:
	fresh()
	Game.state.ownedCyberwareIds.append("money_chip")
	Game.state.equippedCyberwareIds.append("money_chip")
	var equipped: Array = Game.state.equippedCyberwareIds.duplicate()
	check(Game.choose(1, Game.revision), "full loadout still accepts support")
	check("healing_chip" in Game.state.ownedCyberwareIds and Game.state.equippedCyberwareIds == equipped, "full slots preserve equipment and store support as owned")
	fresh()
	check(Game.apply_actions([{"op":"grantTechnology", "id":"swift_chip", "equip":true}]), "grant action accepts existing chip")
	var granted := Game.state.duplicate(true)
	check(Game.apply_actions([{"op":"grantTechnology", "id":"swift_chip", "equip":true}]) and Game.state == granted, "duplicate grant neither duplicates ownership nor equipment")
	fresh()
	check(Game.apply_actions([{"op":"grantTechnology", "id":"healing_chip", "equip":false}]), "owned-only grant accepted")
	check("healing_chip" in Game.state.ownedCyberwareIds and not "healing_chip" in Game.state.equippedCyberwareIds, "owned-only action respects equip false")
	for invalid in ["missing_chip", "test_cyberware_01", "", null, 7]:
		fresh()
		var before := Game.state.duplicate(true)
		check(not Game.apply_actions([{"op":"setFlag", "key":"mustRollback"}, {"op":"grantTechnology", "id":invalid, "equip":true}]), "invalid or placeholder grant rejected: " + str(invalid))
		check(Game.state == before, "invalid grant rolls back earlier effects")
	fresh()
	var before := Game.state.duplicate(true)
	check(not Game.apply_actions([{"op":"grantTechnology", "id":"money_chip", "equip":true}, {"op":"spendCredits", "amount":999999}]), "later invalid payment rejects valid grant batch")
	check(Game.state == before, "rejected batch leaves no chip or equipment behind")

func test_save_failure() -> void:
	fresh()
	check(Game.save_game(), "pre-choice snapshot saved")
	var disk := FileAccess.get_file_as_string(save_file)
	var before := Game.state.duplicate(true)
	var rev := Game.revision
	var page := Game.page
	var rng_state := Game.event_refresh_rng.state
	# A regular file cannot be used as a directory, so this fails deterministically.
	Game.save_path = save_file.path_join("blocked.json")
	Game.save_enabled = true
	var notifications := [0]
	var count_changed := func(): notifications[0] += 1
	Game.changed.connect(count_changed)
	check(not Game.choose(2, rev), "storage failure rejects support choice")
	Game.changed.disconnect(count_changed)
	check(Game.state == before and Game.revision == rev and Game.page == page, "failed write restores chip, equipment, flag, choice and history")
	check(Game.event_refresh_rng.state == rng_state and notifications[0] == 0, "failed write restores refresh RNG and publishes no scene change")
	check(FileAccess.get_file_as_string(save_file) == disk, "failed write preserves original checkpoint")
	Game.save_path = save_file
	check(Game.choose(2, rev), "same choice can be retried after storage recovery")
	var committed := Game.state.duplicate(true)
	check(Game.load_game() and same(Game.state, committed), "retry stores exactly one support grant")
	Game.save_enabled = false

func test_legacy_choices() -> void:
	for target in ["richard", "lumina"]:
		for node_id in ["chosen_01", "finish"]:
			fresh()
			Game.state.targetId = target
			Game.state.choiceHistory = {"E01:contract":target}
			Game.enter_node(node_id)
			var owned: Array = Game.state.ownedCyberwareIds.duplicate()
			var equipped: Array = Game.state.equippedCyberwareIds.duplicate()
			check(Game.save_game() and Game.load_game(), "legacy selected target checkpoint remains loadable")
			Game.skip_dialogue(Game.revision)
			check(Game.state.ownedCyberwareIds == owned and Game.state.equippedCyberwareIds == equipped and not Game.state.flags.has("openingSupportChipId"), "legacy selected branch receives no retroactive support")
			check(Game.state.targetId == target and Game.state.choiceHistory.get("E01:contract") == target, "legacy choice remains intact")

func test_real_ui() -> void:
	fresh()
	var view: Control = preload("res://scenes/dialogue.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	check(view.choice_buttons.size() == 3 and view.skip_button.disabled, "real dialogue has three enabled chip choices and blocks skip")
	for index in mini(CHIPS.size(), view.choice_buttons.size()):
		var button: Button = view.choice_buttons[index]
		check(not button.disabled and Game.cyberware_definition(CHIPS[index]).name in button.text, "real choice displays existing chip name")
		check(button.position.x >= 0 and button.position.y >= 180 and button.position.x + button.size.x <= 1440 and button.position.y + button.size.y <= 650, "choice fits between HUD and dialogue panel")
		if index > 0:
			check(not button.get_rect().intersects(view.choice_buttons[index-1].get_rect()), "chip buttons do not overlap")
	view.select(2)
	check(Game.state.flags.get("openingSupportChipId") == "swift_chip", "real third-button callback selects swift support")
	view.queue_free()
	await get_tree().process_frame
	Game.skip_dialogue(Game.revision)
	var result: Control = preload("res://scenes/result.tscn").instantiate()
	add_child(result)
	await get_tree().process_frame
	var visible := texts(result)
	check("迅捷芯片" in visible and "不消耗时间" in visible, "real settlement shows granted chip and zero date cost")
	check(not "本次无奖励" in visible, "support settlement does not claim no reward")
	result.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	if not OS.get_environment("QA_OUT_DIR").is_empty(): output = OS.get_environment("QA_OUT_DIR")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	save_file = output.path_join("opening-support-checkpoint.json")
	test_catalog_and_branches()
	test_grant_atomicity_and_full_slots()
	test_save_failure()
	test_legacy_choices()
	await test_real_ui()
	Game.save_enabled = false
	var report := {"checks":checks, "failures":failures, "scope":"headless support acquisition, atomic choices, isolated save roundtrip and failure, legacy compatibility and real dialogue/result node structure; no pixel or physical-input verification"}
	var file := FileAccess.open(output.path_join("opening-support-result.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("OPENING SUPPORT: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
