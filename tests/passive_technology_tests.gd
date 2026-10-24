extends Node
const OUTPUT := "res://artifacts/qa/passive-technology-2026-10-24"
const PASSIVES := ["money_chip", "healing_chip", "swift_chip"]
var checks := 0
var failures: Array[String] = []
var save_file := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("PASSIVE TECHNOLOGY: " + message)

func same(left, right) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func reset(ids: Array = [], hp: int = 70) -> void:
	Game.save_enabled = false
	Game.save_path = save_file
	Game.meta_path = OUTPUT.path_join("meta-test.json")
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.training_backup.clear()
	Game.state = Game.initial_state()
	Game.state.ownedCyberwareIds.append_array(PASSIVES)
	Game.state.equippedCyberwareIds = ids.duplicate()
	Game.state.currentHp = hp
	Game.state.activeEventId = "E02"
	Game.state.currentPlaceId = "junkyard"
	Game.enter_node("battle")

func model() -> CombatModel:
	var value := CombatModel.new()
	value.restore(Game.state.combat)
	return value

func win_model() -> void:
	var combat := model()
	combat.draw_cards()
	for enemy in combat.enemies: enemy.hp = 0
	combat.outcome = "win"
	Game.commit_combat(combat)

func finish_story() -> void:
	var count := 0
	while Game.state.currentScene == "dialogue" and count < 100:
		if Game.node_data().has("next"): Game.advance(Game.revision)
		else: Game.choose(0,Game.revision)
		count += 1
	check(count < 100, "post-battle story terminates")

func test_definitions() -> void:
	check(Game.initial_state().ownedCyberwareIds == ["dimensional_pocket","accelerated_clock","backup_energy"], "new adventure still owns only original three active technologies")
	check(Game.initial_state().equippedCyberwareIds == Game.initial_state().ownedCyberwareIds, "default equipped technologies unchanged")
	check(Game.technology_shop_offers().size() == 6 and Game.technology_shop_offers().all(func(o): return o.price == 150), "six offers all cost 150")
	for id in PASSIVES:
		var definition := Game.cyberware_definition(id)
		check(CombatModel.is_passive_cyberware(definition) and CombatModel.valid_cyberware_definition(definition) and not definition.has("cooldownTurns"), "passive has valid effect and no cooldown: " + id)
		for changed in [{"type":"unknown"},{"type":null},{"effect":"gain_energy"},{"amount":0},{"amount":-1},{"amount":0.5},{"amount":"5"},{"cooldownTurns":1},{"nextAttackBonus":1}]:
			var invalid := definition.duplicate(true)
			invalid.merge(changed,true)
			check(not CombatModel.valid_cyberware_definition(invalid), "invalid passive definition rejected: " + id + str(changed))
	var active := Game.cyberware_definition("backup_energy").duplicate(true)
	check(not CombatModel.is_passive_cyberware(active) and CombatModel.valid_cyberware_definition(active), "old missing-type active definition remains accepted")
	active.type = "active"
	check(CombatModel.valid_cyberware_definition(active), "explicit active type accepted")
	active.type = "passive"
	check(not CombatModel.valid_cyberware_definition(active), "active effect cannot masquerade as passive")

func test_opening() -> void:
	reset(["swift_chip"])
	var opening: Dictionary = Game.state.battleStart.duplicate(true)
	check(not opening.openingDrawDone and opening.hand.is_empty(), "swift battleStart captured before first draw")
	var combat := model()
	check(combat.draw_cards().size() == 7 and combat.hand.size() == 7, "equipped swift raises opening five to seven")
	check(combat.draw_cards().is_empty() and combat.hand.size() == 7, "repeated first-turn default draw cannot reapply swift")
	for enemy in combat.enemies: enemy.intent = {"type":"attack","amount":0,"hits":1}
	combat.end_turn()
	check(combat.turn == 2 and combat.hand.size() == 5, "second turn draws normal five")
	var saved := combat.snapshot()
	var restored := CombatModel.new()
	restored.restore(saved)
	check(restored.draw_cards().is_empty() and restored.hand.size() == 5, "snapshot restore never repeats opening bonus")
	reset(["swift_chip"])
	Game.save_enabled = true
	combat = model()
	combat.draw_cards()
	Game.commit_combat(combat)
	check(Game.load_game() and not Game.state.combat.openingDrawDone, "unfinished combat reload restores first-draw checkpoint")
	combat = model()
	check(combat.draw_cards().size() == 7 and combat.hand.size() == 7, "restart consistently draws seven once")
	reset([])
	combat = model()
	check(combat.draw_cards().size() == 5, "owned but unequipped swift gives no extra draw")
	Game.state.equippedCyberwareIds = ["swift_chip"]
	combat = model()
	check(combat.draw_cards().size() == 5, "changing adventure equipment cannot alter existing battle snapshot")
	reset(["swift_chip"])
	var definitions: Dictionary = Game.prototype_rules.cyberware.duplicate(true)
	Game.cyberware_definition("swift_chip").amount = 9
	Game.state.equippedCyberwareIds = []
	combat = model()
	check(combat.draw_cards().size() == 7, "frozen swift amount survives later catalog and equipment changes")
	Game.prototype_rules.cyberware = definitions
	var old := combat.snapshot()
	old.erase("openingDrawDone")
	restored.restore(old)
	check(restored.draw_cards().is_empty() and restored.hand.size() == 7, "legacy snapshot with existing hand does not replay first draw")

func test_activation_and_snapshot() -> void:
	reset(PASSIVES + ["backup_energy"])
	var combat := model()
	combat.draw_cards()
	check(combat.available_cyberware_count() == 1, "only equipped active technology counts as available")
	for id in PASSIVES:
		var before := combat.snapshot()
		check(not combat.cyberware_available(id) and not combat.activate_cyberware(id) and combat.snapshot() == before, "passive cannot be activated through any model caller: " + id)
		var invalid := before.duplicate(true)
		invalid.usedCyberware = [id]
		check(not Game.valid_combat(invalid), "passive cannot appear in old used-only snapshot: " + id)
		invalid.cyberwareCooldowns = {id:1}
		check(not Game.valid_combat(invalid), "passive cannot appear in cooldown snapshot: " + id)
	check(combat.activate_cyberware("backup_energy") and combat.energy == 4, "old active technology still activates normally")
	check(Game.valid_combat(combat.snapshot()), "mixed active/passive snapshot remains valid")
	var snapshot := combat.snapshot()
	snapshot.profile.cyberware.cards.append(Game.cyberware_definition("test_cyberware_01").duplicate(true))
	snapshot.profile.playerCyberwareIds.append("test_cyberware_01")
	var legacy := CombatModel.new()
	legacy.restore(snapshot)
	check(legacy.cyberware_cards().size() == 4 and not legacy.activate_cyberware("test_cyberware_01"), "fifth frozen technology remains outside four usable slots")
	reset([])
	combat = model()
	for id in ["test_cyberware_01","test_cyberware_02","test_cyberware_03","test_cyberware_04","swift_chip"]:
		combat.profile.cyberware.cards.append(Game.cyberware_definition(id).duplicate(true))
	check(combat.draw_cards().size() == 5, "fifth frozen swift cannot grant opening cards")

func test_victory() -> void:
	for hp in [70,98,100]:
		reset(["money_chip","healing_chip"],hp)
		var credits: int = Game.state.credits
		Game.state.equippedCyberwareIds = []
		var definitions: Dictionary = Game.prototype_rules.cyberware.duplicate(true)
		Game.cyberware_definition("money_chip").amount = 999
		win_model()
		check(Game.battle_exit("win",Game.revision), "victory settles frozen equipped chips")
		Game.prototype_rules.cyberware = definitions
		var heal := mini(5,100-hp)
		check(Game.state.credits == credits + 30 and Game.state.currentHp == hp + heal, "victory grants exact 30 and capped healing at HP " + str(hp))
		check(Game.battle_passive_summary() == {"credits":30,"healing":heal}, "summary reports actual chip gains")
		check(Game.state.currentScene == "dialogue" and Game.valid_save(Game.state), "chips are awarded before post-battle dialogue in a valid checkpoint")
		var rev := Game.revision
		check(not Game.battle_exit("win",rev) and Game.state.credits == credits+30, "duplicate end request cannot repeat chip reward")
		finish_story()
		var after: int = Game.state.credits
		check(after == credits+30+int(Game.reward_rules.credits), "normal victory money remains separate from chip money")
		Game.prepare_battle_reward()
		Game.enter_node("finish")
		check(Game.state.credits == after and Game.state.currentHp == hp+heal, "reward preparation and finish reentry never repeat chips")
		check(Game.save_game() and Game.load_game(), "chip receipt roundtrips through isolated disk save")
		check(Game.state.credits == after and Game.battle_passive_summary() == {"credits":30,"healing":heal}, "reload retains chip receipt without new grants")
		# Simulate an old caller replaying victory routing after reload.
		Game.state.currentScene = "battle"
		Game.page = "battle"
		check(Game.battle_exit("win",Game.revision) and Game.state.credits == after and Game.state.currentHp == hp+heal, "independent claim prevents regrant even if victory route is replayed")
		Game.state.activeEventId = "E04"
		Game.state.currentPlaceId = "alley"
		Game.enter_node("battle")
		check(Game.battle_passive_summary() == {"credits":0,"healing":0}, "new battle clears previous chip summary")
	reset([])
	var credits: int = Game.state.credits
	win_model()
	check(Game.battle_exit("win",Game.revision) and Game.state.credits == credits and Game.state.currentHp == 70, "owned but unequipped chips grant no victory benefit")
	check(Game.battle_passive_summary() == {"credits":0,"healing":0} and Game.state.claimedRewardIds.is_empty(), "no equipped victory chip leaves no reward receipt")
	reset([])
	var extra := model()
	for id in ["test_cyberware_01","test_cyberware_02","test_cyberware_03","test_cyberware_04","money_chip"]:
		extra.profile.cyberware.cards.append(Game.cyberware_definition(id).duplicate(true))
	extra.profile.playerCyberwareIds = extra.profile.cyberware.cards.map(func(d): return d.id)
	for enemy in extra.enemies: enemy.hp = 0
	extra.outcome = "win"
	Game.state.battleStart = {}
	Game.commit_combat(extra)
	credits = Game.state.credits
	check(Game.battle_exit("win",Game.revision) and Game.state.credits == credits, "fifth frozen money chip cannot grant victory credits")

func test_failure_training_and_save_failure() -> void:
	reset(PASSIVES)
	var credits: int = Game.state.credits
	var combat := model()
	combat.player_hp = 0
	combat.outcome = "lose"
	Game.commit_combat(combat)
	check(not Game.battle_exit("win",Game.revision), "defeat cannot trigger healing revival")
	check(Game.battle_exit("lose",Game.revision) and Game.state.currentHp == 0 and Game.state.credits == credits, "defeat grants neither healing nor credits")
	check(Game.battle_passive_summary() == {"credits":0,"healing":0}, "defeat has no chip summary")
	for outcome in ["win","lose","exit"]:
		reset(PASSIVES)
		Game.state.currentScene = "map"
		Game.page = "map"
		var adventure := Game.state.duplicate(true)
		Game.start_training("B02")
		check(Game.state.ownedCyberwareIds == adventure.ownedCyberwareIds and Game.state.equippedCyberwareIds == PASSIVES, "training copies actual acquired technology ownership and equipment")
		combat = model()
		check(combat.draw_cards().size() == 7, "training uses swift only inside isolated combat")
		if outcome == "exit": Game.menu()
		else: check(Game.battle_exit(outcome,Game.revision), "training ends with " + outcome)
		check(Game.state == adventure and not Game.training_mode, "training " + outcome + " restores full adventure without chip gains")
	reset(["money_chip","healing_chip"])
	win_model()
	check(Game.save_game(), "pre-transaction winning snapshot saved")
	var original_disk := FileAccess.get_file_as_string(save_file)
	var before := Game.state.duplicate(true)
	var rev := Game.revision
	var page := Game.page
	Game.save_enabled = true
	Game.save_path = OUTPUT.path_join("missing-folder/checkpoint.json")
	var scene_notifications := [0]
	var count_scene := func(): scene_notifications[0] += 1
	Game.changed.connect(count_scene)
	check(not Game.battle_exit("win",rev), "failed write rejects entire victory transaction")
	Game.changed.disconnect(count_scene)
	check(scene_notifications[0] == 0, "failed victory publishes no premature scene change")
	check(Game.state == before and Game.page == page and Game.revision == rev, "failed victory restores money HP claim route and revision")
	check(FileAccess.get_file_as_string(save_file) == original_disk, "failed transaction preserves previously successful disk snapshot")
	Game.save_path = save_file
	check(Game.load_game() and Game.state.get("battlePassiveReward",{}).is_empty(), "reload after failed victory has no false reward claim")
	check(Game.battle_exit("win",Game.revision), "victory retry succeeds after storage recovery")
	check(Game.state.credits == before.credits+30 and Game.state.currentHp == before.currentHp+5, "retry grants each chip exactly once")
	check(Game.load_game() and Game.state.credits == before.credits+30 and Game.state.currentHp == before.currentHp+5, "retry receipt and benefits are atomically persisted")

func test_record_validation() -> void:
	reset(["money_chip","healing_chip"])
	win_model()
	Game.battle_exit("win",Game.revision)
	var saved := Game.state.duplicate(true)
	for bad in [null, [], "bad", {"credits":30}, {"claimId":"bad","eventId":"E02","battleId":"B02","credits":30,"healing":5}]:
		var invalid := saved.duplicate(true)
		invalid.battlePassiveReward = bad
		check(not Game.valid_save(Game.migrate_save(invalid)), "malformed passive receipt rejected: " + str(bad))
	for key in ["credits","healing"]:
		for bad in [-1,0.5,"5"]:
			var invalid := saved.duplicate(true)
			invalid.battlePassiveReward[key] = bad
			check(not Game.valid_save(invalid), "invalid receipt amount rejected")
	Game.state = saved.duplicate(true)
	Game.state.refreshedEventIds = ["E04"]
	Game.state.currentScene = "map"
	Game.page = "map"
	check(Game.start_event("E04") and Game.state.battlePassiveReward.is_empty() and Game.battle_passive_summary() == {"credits":0,"healing":0} and Game.valid_save(Game.state), "starting another event clears old receipt and remains a valid save")
	var legacy := saved.duplicate(true)
	legacy.erase("battlePassiveReward")
	check(Game.valid_save(Game.migrate_save(legacy)), "missing receipt field migrates without retroactive reward")
	reset([])
	var old := Game.state.duplicate(true)
	old.erase("battlePassiveReward")
	var upgraded: Dictionary = Game.migrate_save(old)
	check(upgraded.combat.profile.cyberware.cards.is_empty() and upgraded.battleStart.profile.cyberware.cards.is_empty(), "old frozen battles gain no newly authored passive definitions")

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	save_file = OUTPUT.path_join("checkpoint-test.json")
	test_definitions()
	test_opening()
	test_activation_and_snapshot()
	test_victory()
	test_failure_training_and_save_failure()
	test_record_validation()
	Game.save_enabled = false
	var result := {"checks":checks,"failures":failures,"scope":"headless passive definitions, first draw, activation rejection, frozen snapshots, real victory flow, independent claims, save rollback/roundtrip, training and defeat"}
	var file := FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result,"\t")); file.close()
	print("PASSIVE TECHNOLOGY: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
