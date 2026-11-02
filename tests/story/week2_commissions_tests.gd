extends Node
## Dedicated copied-project test, including persistence outside the player directory.
const CASES := [
	["E17", "B17", "warden_shield", "camp"],
	["E18", "B18", "chip_broker", "bar"],
	["E19", "B19", "mutant_mouse", "hive"],
	["E20", "B20", "luggage_lurker", "hotel"],
	["E21", "B21", "penitent_ascetic", "church"],
	["E22", "B22", "scavenger_hooker", "junkyard"]]
const OPENING_HP := {"E17":85, "E18":72, "E19":42, "E20":45, "E21":80, "E22":78}
const OPENING_LOSSES := {"E17":[0,14,20], "E18":[0,24,12], "E19":[10,15,27], "E20":[8,18,26], "E21":[0,17,18], "E22":[14,12,0]}
var checks := 0
var failures: Array[String] = []
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("WEEK TWO: " + message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func fresh() -> void:
	Game.save_enabled = false
	Game.pending_save_kind = ""
	Game.training_mode = false
	Game.tutorial_mode = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.save_path = output.path_join("checkpoint.json")
	Game.meta_path = output.path_join("meta.json")
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.page = "map"

func completed_week_one() -> void:
	fresh()
	Game.state.currentDay = 7
	Game.refresh_event_pool()
	check(Game.start_event("E16"), "first-week Boss starts")
	Game.skip_dialogue(Game.revision)
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	model.enemy_damage(0, 999)
	model.resolve_outcome()
	check(model.advance_encounter_phase(), "Boss enters its real second phase")
	for i in model.enemies.size(): model.enemy_damage(i, 999)
	model.resolve_outcome()
	check(Game.commit_combat(model) and Game.battle_exit("win", Game.revision), "real Boss win returns to dialogue")
	Game.skip_dialogue(Game.revision)
	check(Game.claim_reward_credits(Game.revision), "Boss credits collected")
	check(Game.choose_reward_card(Game.state.battleReward.options[0], Game.revision), "Boss card collected")
	check(not Game.start_second_week(Game.revision), "pending Boss reward page cannot skip explicit reward exit")
	check(Game.claim_rewards(Game.revision) and Game.is_week_complete(), "Boss reward exit reaches first-week summary")

func start_week_two() -> void:
	completed_week_one()
	check(Game.start_second_week(Game.revision), "summary opens second week")
	check(Game.state.currentWeek == 2 and Game.state.currentDay == 1 and Game.page == "map", "second week starts at day one on map")

func test_week_gate_and_transition() -> void:
	fresh()
	var before := Game.state.duplicate(true)
	check(not Game.start_second_week(Game.revision) and same(before, Game.state), "new adventure cannot bypass first week")
	for day in [1, 2, 6, 7]:
		Game.state.currentDay = day
		Game.state.refreshedEventIds = []
		Game.refresh_event_pool()
		for c in CASES:
			check(not Game.event_in_refresh_range(Game.events[c[0]]) and not Game.start_event(c[0]), c[0] + " hidden throughout first week")
	completed_week_one()
	var done := Game.state.duplicate(true)
	var revision: int = Game.revision
	check(not Game.start_second_week(revision - 1) and same(done, Game.state), "stale summary callback is rejected")
	Game.transition_locked = true
	check(not Game.start_second_week(revision), "transition lock blocks next week")
	Game.transition_locked = false
	Game.training_mode = true
	check(not Game.start_second_week(revision), "training cannot advance an adventure week")
	Game.training_mode = false
	Game.menu()
	check(Game.can_continue() and not Game.start_second_week(Game.revision), "menu offers continue but cannot bypass summary action")
	Game.resume()
	check(Game.page == "result" and Game.is_week_complete(), "continue reopens settled first-week summary")
	check(Game.start_second_week(Game.revision), "current summary action advances once")
	for field in ["currentHp", "maxHp", "credits", "deck", "ownedCyberwareIds", "equippedCyberwareIds", "difficulty", "playerCharacterId", "completedEventIds", "claimedRewardIds", "battleHistory", "dialogueHistory"]:
		check(same(Game.state[field], done[field]), "week transition retains " + field)
	check(Game.state.flags.week1Complete and not Game.boss_has_appeared(Game.state) and not Game.is_run_over(), "historic first-week flags do not end or suppress second week")
	check(not Game.start_second_week(Game.revision), "double next-week activation is rejected")
	check(Game.state.battleReward.is_empty() and Game.state.combat.is_empty() and Game.state.battleId.is_empty(), "settled battle context cleared without reissuing rewards")
	check(Game.state.blackMarket.week == 2 and Game.state.blackMarket.restockDay == 1, "existing market refreshes for new week")
	check(Game.valid_save(Game.state), "second-week checkpoint validates")
	check(Game.save_game() and Game.load_game() and Game.state.currentWeek == 2 and Game.page == "map", "week two reload is not migrated back to first-week summary")
	for invalid in [0, -1, 1.5, 3, "2"]:
		var bad := Game.state.duplicate(true)
		bad.currentWeek = invalid
		check(not Game.valid_save(bad), "invalid week rejected: " + str(invalid))

func test_pool() -> void:
	start_week_two()
	var seen: Dictionary = {}
	for seed in 32:
		Game.event_refresh_rng.seed = seed
		Game.state.refreshedEventIds = []
		Game.refresh_event_pool()
		check(Game.eligible_events().size() == 6 and Game.state.refreshedEventIds.size() == 3, "six candidates, three slots, seed " + str(seed))
		for id in Game.state.refreshedEventIds: seen[id] = true
	for c in CASES:
		check(seen.has(c[0]) and Game.event_refresh_time_label(Game.events[c[0]]) == "第2周", "natural discovery and week label: " + c[0])
	var kept: Array = Game.state.refreshedEventIds.duplicate()
	for i in 4: Game.refresh_event_pool()
	check(Game.state.refreshedEventIds == kept, "ordinary pool retains existing offers without reroll")
	var hidden := ""
	for c in CASES:
		if not c[0] in kept: hidden = c[0]; break
	check(not hidden.is_empty() and not Game.start_event(hidden), "unrefreshed candidate cannot start directly")
	var before := Game.state.duplicate(true)
	Game.available_events(); Game.map_target_events(); Game.objective()
	check(same(before, Game.state), "pool queries do not mutate adventure")
	Game.state.currentDay = 7
	Game.refresh_event_pool()
	check(Game.state.refreshedEventIds == ["E23"] and Game.boss_has_appeared(Game.state), "second-week day seven offers only Noss, never the first-week Boss")
	Game.state.currentWeek = 3
	check(Game.eligible_events().is_empty(), "these commissions are limited to second week")

func portrait(node: Node, path: String) -> TextureRect:
	if node is TextureRect and node.texture != null and node.texture.resource_path == path: return node
	for child in node.get_children():
		var found := portrait(child, path)
		if found != null: return found
	return null

func test_commission(c: Array) -> void:
	start_week_two()
	var id: String = c[0]
	Game.state.refreshedEventIds = [id]
	Game.refresh_event_pool()
	check(Game.start_event(id), id + " starts from ordinary pool")
	var definition: Dictionary = Game.events[id]
	check(definition.placeId == c[3] and definition.repeatPolicy == "once" and not definition.get("permanent", false), id + " normal one-time encounter at intended place")
	var path: String = Game.assets[Game.characters[c[2]].portraitAssetId].path
	check(Game.assets[Game.characters[c[2]].portraitAssetId].get("whiteKey", true) == false, id + " transparent portrait retains pale details")
	var visited: Array = []
	while Game.page == "dialogue" and visited.size() < 32:
		visited.append(Game.state.activeNodeId)
		var node := Game.node_data()
		check(node.get("choices", []).is_empty() and node.get("speakerId", "") in ["", "@player", c[2]], id + " dialogue contains only player/enemy and no added choices")
		if c[2] == "mutant_mouse": check(node.get("speakerId", "") != "mutant_mouse", "mouse never speaks human language")
		var view := preload("res://scenes/dialogue.tscn").instantiate()
		add_child(view)
		var image := portrait(view, path)
		if not node.get("portraits", {}).get("right", "").is_empty():
			check(image != null and image.material == null and image.size.x > 0, id + " actual dialogue view loads correct transparent portrait")
		view.free()
		Game.advance(Game.revision)
	check(visited.size() >= 6 and visited.size() < 32 and Game.page == "battle" and Game.state.battleId == c[1], id + " pre-battle chain reaches correct combat")
	var enemy_count := 2 if id in ["E19", "E20"] else 1
	check(Game.battle_type() == "normal" and Game.state.combat.enemies.size() == enemy_count, id + " ordinary battle uses intended formation")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	for enemy in model.enemies:
		check(enemy.hp == OPENING_HP[id] and enemy.maxHp == OPENING_HP[id], id + " fresh enemy has designed HP")
		check(Game.enemy_combat_visual(enemy).id == c[2], id + " configured enemy action visual resolves for every unit")
	for turn in 3:
		var hp: int = model.player_hp
		model.end_turn()
		check(model.player_hp == hp - OPENING_LOSSES[id][turn], id + " actual opening turn " + str(turn + 1) + " resolves attacks and status damage")
	check(Game.commit_combat(model), id + " live battle progress commits")
	check(Game.save_game() and Game.load_game() and Game.state.combat.enemies.size() == enemy_count and Game.state.combat.enemies[0].hp == OPENING_HP[id] and Game.state.combat.turn == 1, id + " saved unfinished encounter restarts at frozen opening")
	model.restore(Game.state.combat)
	for i in model.enemies.size(): model.enemy_damage(i, 999)
	model.resolve_outcome()
	check(Game.commit_combat(model) and Game.battle_exit("win", Game.revision), id + " victory reaches authored epilogue")
	check(not id in Game.state.completedEventIds, id + " victory is not complete before epilogue ends")
	var after_battle := 0
	while Game.page == "dialogue" and after_battle < 20:
		check(Game.node_data().get("speakerId", "") in ["", "@player", c[2]], id + " epilogue has no unbound speaker")
		Game.advance(Game.revision)
		after_battle += 1
	check(after_battle >= 3 and after_battle < 20 and Game.page == "result", id + " epilogue reaches reward page")
	check(id in Game.state.completedEventIds and Game.state.currentWeek == 2 and Game.state.currentDay == 2, id + " first completion advances exactly one day")
	check(Game.has_battle_reward() and Game.state.battleReward.battleType == "normal", id + " uses normal reward pipeline")
	var credits: int = Game.state.credits
	check(Game.claim_reward_credits(Game.revision), id + " normal credits claimable")
	check(Game.state.credits >= credits + 40 and Game.state.credits <= credits + 60, id + " ordinary credit range")
	check(Game.claim_rewards(Game.revision) and Game.page == "map" and not Game.is_run_over(), id + " reward exit returns to second-week map")
	check(not Game.start_event(id) and not id in Game.state.refreshedEventIds and Game.state.refreshedEventIds.size() == 3, id + " once-only event leaves pool and another fills vacancy")
	check(Game.valid_save(Game.state) and Game.save_game() and Game.load_game() and Game.state.currentWeek == 2, id + " completed encounter reloads correctly")
	# An actual losing model still enters the common terminal defeat route.
	start_week_two()
	Game.state.refreshedEventIds = [id]
	Game.refresh_event_pool()
	check(Game.start_event(id), id + " fresh failure branch starts")
	Game.skip_dialogue(Game.revision)
	model.restore(Game.state.combat)
	model.player_hp = 1
	for turn in 4:
		if not model.outcome.is_empty(): break
		model.end_turn()
	check(model.outcome == "lose" and Game.commit_combat(model) and Game.battle_exit("lose", Game.revision), id + " real loss accepted")
	check(Game.page == "defeat" and not id in Game.state.completedEventIds and not Game.has_battle_reward(), id + " loss ends run without completion/reward")

func test_transition_save_retry() -> void:
	completed_week_one()
	var blocker := output.path_join("write-blocker")
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("QA-only blocker")
	file.close()
	Game.save_enabled = true
	Game.save_path = blocker.path_join("checkpoint.json")
	check(not Game.start_second_week(Game.revision) and Game.pending_save_kind == "scene", "failed week transition checkpoint requires save retry")
	var waiting := Game.state.duplicate(true)
	check(Game.state.currentWeek == 2 and not Game.start_second_week(Game.revision), "pending checkpoint prevents duplicate transition")
	Game.save_path = output.path_join("checkpoint.json")
	check(Game.retry_pending_save() and Game.page == "map" and same(waiting, Game.state), "save retry preserves same week/pool/progression")
	check(Game.load_game() and Game.state.currentWeek == 2, "retried second-week checkpoint survives reload")
	Game.save_enabled = false

func test_full_second_week() -> void:
	start_week_two()
	var seen: Array = []
	for index in 6:
		check(not Game.state.refreshedEventIds.is_empty(), "remaining second-week work stays discoverable")
		var id: String = Game.state.refreshedEventIds[0]
		check(not id in seen and Game.start_event(id), "each ordinary pooled event starts once")
		seen.append(id)
		Game.skip_dialogue(Game.revision)
		var model := CombatModel.new()
		model.restore(Game.state.combat)
		for i in model.enemies.size(): model.enemy_damage(i, 999)
		model.resolve_outcome()
		check(Game.commit_combat(model) and Game.battle_exit("win", Game.revision), "pooled second-week victory returns")
		Game.skip_dialogue(Game.revision)
		check(Game.claim_rewards(Game.revision), "ordinary reward exit continues the week")
	check(seen.size() == 6 and Game.state.currentDay == 7 and Game.state.currentWeek == 2, "six commissions complete in second-week day seven")
	check(Game.state.refreshedEventIds == ["E23"] and not Game.is_run_over() and Game.page == "map", "six ordinary commissions lead to authored second-week Boss")
	check(Game.save_game() and Game.load_game() and Game.state.currentWeek == 2 and Game.state.currentDay == 7 and Game.page == "map", "fully completed second-week checkpoint reloads on map")
	for c in CASES:
		start_week_two()
		Game.state.difficulty = "advanced"
		Game.state.refreshedEventIds = [c[0]]
		Game.refresh_event_pool()
		check(Game.start_event(c[0]), "advanced second-week event starts")
		Game.skip_dialogue(Game.revision)
		var bonus := 5 if c[0] in ["E19", "E20"] else 10
		for enemy in Game.state.combat.enemies:
			check(enemy.hp == OPENING_HP[c[0]] + bonus and enemy.maxHp == OPENING_HP[c[0]] + bonus and Game.enemy_catalog[enemy.id].maxHp == OPENING_HP[c[0]], c[0] + " advanced formation HP bonus applies once without changing base data")
			check(same(enemy.intent, Game.enemy_catalog[enemy.id].intentSequence[0]), c[0] + " advanced opening intent remains unchanged")

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in output.to_lower() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("WEEK TWO: use isolated copied project and absolute QA_OUT_DIR")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	test_week_gate_and_transition()
	test_pool()
	for c in CASES: test_commission(c)
	test_full_second_week()
	test_transition_save_retry()
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures}, "\t"))
	file.close()
	print("WEEK TWO: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
