extends Node
## Isolated, headless metadata/flow checks; no reward balance changes.
const OUTPUT := "res://artifacts/qa/battle-types-2026-10-23/"
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func begin_battle(id: String = "B04") -> void:
	Game.save_enabled = false
	Game.training_mode = false
	Game.training_backup.clear()
	Game.transition_locked = false
	Game.battle_busy = false
	Game.state = Game.initial_state()
	Game.state.targetId = "richard"
	Game.state.activeEventId = Game.battles[id].eventId
	Game.state.currentPlaceId = Game.battles[id].placeId
	seed(20261023)
	Game.enter_node("battle")

func roundtrip() -> void:
	check(Game.save_game(), "Write isolated checkpoint")
	Game.state = {}
	check(Game.load_game(), "Reload isolated checkpoint")

func finish_battle() -> void:
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	for enemy in model.enemies: enemy.hp = 0
	model.resolve_outcome()
	Game.commit_combat(model)
	check(Game.battle_exit("win", Game.revision), "Victory follows normal story route")
	var steps := 0
	while Game.state.currentScene == "dialogue" and steps < 100:
		if Game.node_data().has("next"): Game.advance(Game.revision)
		else: Game.choose(0, Game.revision)
		steps += 1
	check(steps < 100 and Game.has_battle_reward(), "Story reaches reward page")

func labels_under(node: Node) -> Array[String]:
	var texts: Array[String] = []
	if node is Label: texts.append(node.text)
	for child in node.get_children(): texts.append_array(labels_under(child))
	return texts

func check_battle_view(kind: String) -> void:
	var view: Control = load("res://scripts/battle.gd").new()
	add_child(view)
	var texts := labels_under(view)
	check(Game.display_name(Game.PLAYER_REFERENCE) + " / " + Game.battle_type_label(kind) in texts, "Battle header displays " + kind)
	check(not "MIDNIGHT / W01" in texts, "Typed battle preserves footer-free layout")
	view.free() # Before deferred opening animation: this checks the UI structure only.
	Game.battle_busy = false

func check_reward_view(kind: String) -> void:
	var view: Control = load("res://scripts/reward.gd").new()
	add_child(view)
	var expected: String = Game.event_data().title + "  /  " + Game.battle_type_label(kind) + "  /  战利品"
	check(expected in labels_under(view), "Reward subtitle displays frozen " + kind)
	view.free()

func test_types() -> void:
	var base: Dictionary = {}
	for kind in ["normal", "elite", "boss"]:
		Game.battles.B04.battleType = kind
		begin_battle()
		check(Game.battle_type() == kind and Game.state.battleStart.profile.battleType == kind, "New combat and opening capture " + kind)
		check(Game.valid_save(Game.state), "New typed battle validates")
		var comparable: Dictionary = Game.state.combat.duplicate(true)
		comparable.profile.erase("battleType")
		if base.is_empty(): base = comparable
		else: check(same(base, comparable), "Changing type preserves enemies, cards and rules")
		check_battle_view(kind)
		var other: String = "boss" if kind != "boss" else "normal"
		Game.battles.B04.battleType = other
		check(Game.battle_type() == kind and Game.configured_battle_type("B04") == other, "Config edits cannot reclassify current battle")
		check(Game.battle_type("B02") == "normal", "Other encounter lookup uses its own config")
		var model := CombatModel.new()
		model.restore(Game.state.combat)
		check(model.snapshot().profile.battleType == kind, "Model restore preserves frozen type")
		roundtrip()
		Game.resume()
		check(Game.battle_type() == kind, "Disk reload and opening restart preserve type")
		finish_battle()
		check(Game.state.battleReward.battleType == kind, "Reward captures finished battle type")
		check(Game.state.credits == int(Game.config.initialCredits) and Game.reward_credit_amount() == 50 and Game.reward_credits_status() == "pending" and Game.state.battleReward.options.size() == 3, "Type does not change unpaid reward amounts")
		var offers: Array = Game.state.battleReward.options
		check(offers[0] != offers[1] and offers[0] != offers[2] and offers[1] != offers[2], "Reward options remain distinct")
		check(offers.all(func(id): return Game.card_catalog[id].rarity != "C"), "Reward still uses non-C pool")
		check_reward_view(kind)
		roundtrip()
		check(Game.state.battleReward.battleType == kind, "Pending reward retains type after reload")
		check(Game.claim_reward_credits(Game.revision) and Game.state.credits == int(Game.config.initialCredits) + 50, "Typed credit reward requires explicit claim")
		check(Game.choose_reward_card(offers[0], Game.revision), "Typed reward can be claimed")
		var credits: int = Game.state.credits
		Game.enter_node("finish")
		check(Game.state.credits == credits, "Typed reward cannot be granted twice")
		var adventure: Dictionary = Game.state.duplicate(true)
		Game.start_training("B04")
		check(Game.training_mode and Game.battle_type() == other and Game.state.battleStart.is_empty(), "Training reads new config without formal opening")
		Game.finish_training("win")
		check(same(Game.state, adventure), "Training restores adventure including reward type")

func test_legacy_and_invalid() -> void:
	Game.battles.B04.battleType = "elite"
	begin_battle()
	var typed: Dictionary = Game.state.duplicate(true)
	for invalid in [null, 7, [], {}, "", "legendary", "ELITE"]:
		var bad: Dictionary = typed.duplicate(true)
		bad.combat.profile.battleType = invalid
		bad.battleStart.profile.battleType = invalid
		check(not Game.valid_save(bad), "Reject invalid frozen battle type: " + str(invalid))
		Game.battles.B04.battleType = invalid
		check(Game.configured_battle_type("B04") == "normal", "Invalid authoring value safely defaults to normal")
	Game.battles.B04.erase("battleType")
	check(Game.configured_battle_type("B04") == "normal", "Missing config field defaults to normal")
	Game.battles.B04.battleType = "elite"
	Game.state.combat.profile.erase("battleType")
	Game.state.battleStart.profile.erase("battleType")
	check(Game.valid_save(Game.state) and Game.battle_type() == "normal", "Legacy opening and combat remain normal and loadable")
	check_battle_view("normal")
	roundtrip()
	check(Game.battle_type() == "normal", "Legacy reload does not inherit new elite config")
	finish_battle()
	check(Game.state.battleReward.battleType == "normal", "Legacy combat creates normal reward")
	for invalid in [null, 7, [], {}, "", "legendary", "ELITE"]:
		var bad: Dictionary = Game.state.duplicate(true)
		bad.battleReward.battleType = invalid
		check(not Game.valid_save(bad), "Reject invalid reward type: " + str(invalid))
	Game.state.battleReward.erase("battleType")
	check(Game.valid_save(Game.state), "Legacy pending reward remains loadable")
	check_reward_view("normal")
	roundtrip()
	check(Game.choose_reward_card(Game.state.battleReward.options[0], Game.revision), "Legacy reward can still be claimed")

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	Game.save_enabled = false
	Game.save_path = OUTPUT + "checkpoint.json"
	Game.meta_path = OUTPUT + "meta.json"
	var original: Dictionary = Game.battles.duplicate(true)
	for id in Game.battles:
		var expected := "boss" if id == "B16" else "normal"
		check(Game.battles[id].get("battleType") == expected, id + " explicitly declares its type")
		begin_battle(id)
		check(Game.battle_type() == expected and Game.valid_save(Game.state), id + " initializes a valid typed battle")
	test_types()
	test_legacy_and_invalid()
	Game.battles = original
	Game.save_enabled = false
	var file := FileAccess.open(OUTPUT + "battle-type-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures, "scope":"headless metadata, flow, save compatibility and UI structure; no visual or physical-input acceptance"}, "\t"))
	file.close()
	print("BATTLE TYPE TESTS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
