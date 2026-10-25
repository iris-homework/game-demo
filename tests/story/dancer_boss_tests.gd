extends Node
var checks := 0
var failures: Array[String] = []
var output := "res://artifacts/qa/dancer-boss-2026-10-25/rules"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("DANCER BOSS: " + message)

func fresh() -> void:
	Game.save_enabled = false
	Game.save_path = output.path_join("checkpoint.json")
	Game.meta_path = output.path_join("meta.json")
	Game.training_mode = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.page = "map"

func test_dialogue() -> void:
	fresh()
	Game.state.currentDay = 7
	Game.refresh_event_pool()
	check(Game.start_event("E16"), "expanded Boss dialogue starts through formal event entrance")
	var visited: Array[String] = []
	while Game.page == "dialogue" and visited.size() < 20:
		visited.append(Game.state.activeNodeId)
		Game.advance(Game.revision)
	check(visited.size() == 9 and Game.state.battleId == "B16" and Game.page == "battle", "expanded intro continues into existing Boss battle")
	var event: Dictionary = Game.events.E16
	check(event.nodes.values().all(func(n): return n.get("speakerId", "") in ["", "@player", "dancer_black"] and "白舞者" not in n.get("text", "")), "white dancer never appears or speaks in dialogue")
	var asset_id: String = Game.characters.dancer_black.portraitAssetId
	var path := "res://assets/characters/dancer_black_dialogue_v1.png"
	check(Game.assets[asset_id].path == path and not Game.assets[asset_id].whiteKey, "black dancer binds existing transparent dialogue portrait")
	var texture := Game.texture(asset_id)
	check(texture != null and texture.get_size() == Vector2(1024,1536), "original black dancer portrait loads at authored resolution")
	# Stage, player and dancer lines all override stale portraits on resumed saves.
	for node_id in ["intro_01", "intro_02", "intro_03", "win_01", "win_02", "win_03", "lose"]:
		Game.enter_node(node_id)
		Game.state.portraits = {"left":"@player", "right":"bartender"}
		var before: Dictionary = Game.state.duplicate(true)
		var view = load("res://scenes/dialogue.tscn").instantiate()
		add_child(view)
		var portraits: Array = view.find_children("*", "TextureRect", true, false).filter(func(p): return p.texture != null and p.texture.resource_path.begins_with("res://assets/characters/"))
		check(portraits.size() == 1 and portraits[0].texture == texture, node_id + " shows only black dancer portrait, including old checkpoint state")
		if portraits.size() == 1:
			check(portraits[0].material == null and portraits[0].is_visible_in_tree(), node_id + " preserves portrait transparency in actual dialogue view")
		check(Game.state == before, node_id + " presentation does not rewrite saved state")
		view.free()

func start_boss() -> CombatModel:
	fresh()
	Game.state.currentDay = 7
	Game.refresh_event_pool()
	check(Game.start_event("E16"), "day-seven event starts")
	Game.skip_dialogue(Game.revision)
	check(Game.state.currentScene == "battle" and Game.state.battleId == "B16", "intro/skip enters B16")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	return model

func killing_card(model: CombatModel, all_targets: bool = false, damage: int = 999, hits: int = 3) -> String:
	# Test-only transaction: explicit multi-hit/AoE coverage, not an authored card.
	var uid := "qa_dancer_" + str(model.instances.size())
	model.instances[uid] = uid
	model.card_catalog[uid] = {"id":uid, "name":"QA strike", "type":"attack", "cost":0, "target":"all" if all_targets else "enemy", "effects":[{"type":"damage", "amount":damage, "hits":hits}]}
	model.hand.append(uid)
	return uid

func pad_draw_pile(model: CombatModel) -> void:
	# Keep assertions about the old discard separate from legitimate discard recycling.
	for i in 18:
		var uid := "qa_reserve_" + str(i)
		model.instances[uid] = uid
		model.card_catalog[uid] = {"id":uid,"name":"QA reserve","type":"skill","cost":0,"target":"self","effects":[]}
		model.draw_pile.append(uid)

func check_card_zones(model: CombatModel, label: String) -> void:
	var seen: Dictionary = {}
	var total := 0
	var unique_known := true
	for zone in [model.draw_pile, model.hand, model.discard_pile, model.exhaust_pile]:
		for uid in zone:
			total += 1
			unique_known = unique_known and model.instances.has(uid) and not seen.has(uid)
			seen[uid] = true
	check(unique_known, label + " every UID is known and occurs in exactly one zone")
	check(total == model.instances.size(), label + " no card lost between zones")

func test_new_phase_player_turn() -> void:
	for kind in ["single", "multi", "aoe", "legacy"]:
		var model := start_boss()
		model.draw_cards()
		pad_draw_pile(model)
		var old_hand: Array = model.hand.duplicate()
		var old_turn: int = model.turn
		model.energy = 0
		if kind == "legacy": model.profile.erase("ruleset")
		var uid := killing_card(model, kind == "aoe", 99, 1 if kind == "single" else 3)
		var result: Dictionary = model.play_card(uid, -1 if kind == "aoe" else 0)
		check(result.phaseChanged and model.turn == old_turn + 1, kind + " lethal opens exactly one new player turn")
		check(model.energy == int(model.profile.energyPerTurn), kind + " new turn restores configured energy")
		check(model.hand.size() == 5 and result.drawn == model.hand, kind + " returns exactly five new-turn cards")
		check(result.discarded == old_hand and old_hand.all(func(card_uid): return card_uid in model.discard_pile), kind + " remaining old hand is discarded")
		check(result.hits.size() == 1 and model.enemies.all(func(e): return e.hp == 90 and e.intentIndex == 0), kind + " complete card cannot hit or advance new dancers")
		check_card_zones(model, kind)
		var snapshot := model.snapshot()
		var restored := CombatModel.new()
		restored.restore(JSON.parse_string(JSON.stringify(snapshot)))
		check(JSON.parse_string(JSON.stringify(restored.snapshot())) == JSON.parse_string(JSON.stringify(snapshot)), kind + " new-turn state roundtrips")

func test_phase_turn_state_and_draws() -> void:
	var model := start_boss()
	model.profile.cyberware = {"cards":[
		{"id":"qa_swift","name":"QA swift","type":"passive","effect":"opening_draw","amount":2},
		{"id":"qa_long","name":"QA long","effect":"next_attack_bonus","nextAttackBonus":3,"cooldownTurns":3},
		{"id":"qa_short","name":"QA short","effect":"gain_energy","amount":1,"cooldownTurns":1}
	]}
	model.opening_draw_done = false
	pad_draw_pile(model)
	model.draw_cards()
	check(model.hand.size() == 7, "swift gives two extra cards only on opening")
	var old_hand: Array = model.hand.duplicate()
	check(model.activate_cyberware("qa_long") and model.activate_cyberware("qa_short"), "setup active cooldowns through real activations")
	model.stance = "ranged"
	model.ammo = 4
	model.parry = 2
	model.stance_discount = true
	model.powers = ["high_pressure", "dissection", "ranged_mastery", "persistent_bleed"]
	model.pressure_used = true
	model.dissection_used = true
	model.block = 1
	model.buffs.apply(model, "next_damage", 7)
	model.buffs.apply(model, "next_discount", 2)
	model.buffs.apply(model, "next_hit_damage", 6)
	model.buffs.apply(model, "strength", 3)
	model.buffs.apply(model, "pollution", 3)
	model.buffs.apply(model, "vulnerable", 2)
	var hp_before: int = model.player_hp
	var intermediate: Array = [model.draw_pile[-1], model.draw_pile[-2]]
	var uid := killing_card(model)
	# A damage skill leaves attack-only bonuses untouched, then draws before turn closure.
	model.card_catalog[uid].type = "skill"
	model.card_catalog[uid].effects = [{"type":"damage","amount":99},{"type":"draw","amount":2}]
	var result: Dictionary = model.play_card(uid, 0)
	check(result.phaseChanged and model.turn == 2 and model.energy == 3, "lethal skill completes effects then starts player turn")
	check(result.discarded.size() == old_hand.size() + 2 and old_hand.all(func(card_uid): return card_uid in result.discarded), "old and mid-card hand are returned as discarded")
	check(intermediate.all(func(card_uid): return card_uid in result.discarded and not card_uid in result.drawn), "mid-card draws are not reported as fresh-turn draws")
	check(result.drawn == model.hand and model.hand.size() == 5 and model.opening_draw_done, "new hand is five; swift does not reapply")
	check(model.player_hp == hp_before - 2 and model.block == 0, "old block absorbs pollution once before new-turn block reset")
	check(model.buffs.count(model, "pollution") == 2 and model.buffs.count(model, "vulnerable") == 1, "old player pollution and vulnerable decay once")
	check(result.phaseTurnEvents.filter(func(e): return e.get("buffId") == "pollution").size() == 1 and result.phaseTurnEvents.filter(func(e): return e.get("buffId") == "vulnerable").size() == 1, "phase exposes one event per old-player status settlement")
	check(model.turn_damage_bonus == 0 and model.turn_discount == 0 and model.buffs.count(model, "next_hit_damage") == 0, "temporary turn attack bonuses and discount clear")
	check(not model.pressure_used and not model.dissection_used, "new-turn ability markers reset")
	check(model.stance == "ranged" and model.ammo == 4 and model.parry == 2 and model.stance_discount, "stance ammo parry and pending stance discount survive")
	check(model.powers.size() == 4 and model.buffs.count(model, "strength") == 3 and model.next_attack_bonus == 3, "battle powers strength and unspent technology bonus survive")
	check(model.cyberware_cooldown("qa_long") == 2 and model.cyberware_cooldown("qa_short") == 0, "each technology cooldown advances exactly once")
	check_card_zones(model, "phase state")

func test_phase_end_turn_status_once() -> void:
	for source in ["counter", "enemy_pollution"]:
		var model := start_boss()
		model.draw_cards()
		pad_draw_pile(model)
		model.enemies[0].hp = 1
		model.buffs.apply(model, "pollution", 3)
		model.buffs.apply(model, "vulnerable", 2)
		model.used_cyberware = ["qa_long"]
		model.cyberware_cooldowns = {"qa_long":3}
		if source == "counter": model.parry = 1
		else: model.buffs.apply(model, "pollution", 1, 0)
		var hp_before: int = model.player_hp
		var old_hand: Array = model.hand.duplicate()
		var result: Dictionary = model.end_turn()
		check(result.phaseChanged and model.turn == 2 and model.energy == 3, source + " opens one new turn")
		check(model.player_hp == hp_before - 26 and result.attacks.size() == 1, source + " one pollution tick then one vulnerable attack, no new dancer action")
		check(model.buffs.count(model, "pollution") == 2 and model.buffs.count(model, "vulnerable") == 1, source + " player statuses do not decay twice")
		check(result.turnEvents.filter(func(e): return e.get("target") == -1 and e.get("buffId") == "pollution").size() == 1, source + " only one player pollution event")
		check(model.cyberware_cooldown("qa_long") == 2, source + " cooldown advances once")
		check(result.discarded == old_hand and result.drawn == model.hand and model.hand.size() == 5, source + " discard and draw happen once")
		check(model.enemies.all(func(e): return e.hp == 90 and e.intentIndex == 0), source + " new dancers remain untouched at initial intent")
		check_card_zones(model, source)
	var model := start_boss()
	model.draw_cards()
	model.player_hp = 1
	model.buffs.apply(model, "pollution", 2)
	model.buffs.apply(model, "vulnerable", 2)
	model.used_cyberware = ["qa_long"]
	model.cyberware_cooldowns = {"qa_long":3}
	var uid := killing_card(model)
	var result: Dictionary = model.play_card(uid, 0)
	check(not result.phaseChanged and model.encounter_phase == 1 and model.outcome == "lose", "lethal old-turn pollution defeats player before reveal")
	check(model.turn == 1 and model.cyberware_cooldown("qa_long") == 3 and model.hand.is_empty() and result.drawn.is_empty(), "fatal closure never starts or draws new player turn")
	check(result.phaseTurnEvents.any(func(e): return e.get("buffId") == "pollution" and e.get("killed", false)), "fatal closure still returns player pollution event")
	check_card_zones(model, "fatal closure")

func test_event_gate() -> void:
	fresh()
	for day in range(1, 7):
		Game.state.currentDay = day
		Game.refresh_event_pool()
		check(not "E16" in Game.state.refreshedEventIds, "boss absent day " + str(day))
		check(not Game.start_event("E16"), "boss entrance rejects day " + str(day))
	Game.state.currentDay = 7
	Game.state.refreshedEventIds = ["E01", "E02", "E04"]
	check(not Game.start_event("E02"), "stale pool cannot bypass seventh-day removal")
	Game.refresh_event_pool()
	check(Game.state.refreshedEventIds == ["E16"], "boss replaces full ordinary pool")
	check(Game.state.flags.get("dancerBossAppeared", false), "appearance persists")
	check(Game.available_events("hive").size() == 1 and Game.map_event_type("E16") == "boss", "boss place and map classification")
	var before := JSON.stringify(Game.state)
	for place in Game.places: Game.available_events(place.id)
	check(JSON.stringify(Game.state) == before, "queries remain read only")
	Game.events.QA_PERMANENT = Game.events.E01.duplicate(true)
	Game.events.QA_PERMANENT.id = "QA_PERMANENT"
	Game.events.QA_PERMANENT.permanent = true
	Game.refresh_event_pool()
	check(Game.state.refreshedEventIds.has("QA_PERMANENT") and Game.state.refreshedEventIds.has("E16"), "explicit permanent event survives")
	Game.events.erase("QA_PERMANENT")
	Game.state.completedEventIds.append("E16")
	Game.refresh_event_pool()
	check(Game.state.refreshedEventIds.is_empty(), "ordinary events do not return after boss completion")
	Game.state.currentDay = 6
	Game.refresh_event_pool()
	check(Game.state.refreshedEventIds.is_empty(), "persisted appearance survives clock rewind")
	fresh()
	Game.state.currentDay = 7
	Game.state.refreshedEventIds = ["E02", "E04", "E11"]
	var migrated: Dictionary = Game.migrate_save(Game.state.duplicate(true))
	check(migrated.refreshedEventIds == ["E16"] and Game.valid_save(migrated), "old day-seven map migrates to boss pool")
	Game.state = migrated
	check(Game.available_events("hive").size() == 1 and Game.available_events("block5").is_empty(), "migrated boss map marker uses hive, not block five")
	check(Game.start_event("E16") and Game.state.currentPlaceId == "hive", "migrated boss entrance moves to hive")
	check(Game.battles.B16.placeId == "hive", "formal and training battle scenery uses hive")
	for place_id in ["market", "mall", "clinic"]:
		check(not Game.place_data(place_id).is_empty(), "resident place retained " + place_id)

func test_phases() -> void:
	var model := start_boss()
	check(model.encounter_phase == 1 and model.enemies.size() == 1 and model.enemies[0].hp == 99, "opening black alone at 99 HP")
	var opening := model.snapshot()
	check(Game.valid_combat(opening), "opening snapshot validates")
	for scene in ["dialogue", "battle", "result"]:
		var legacy: Dictionary = Game.state.duplicate(true)
		legacy.currentScene = scene
		legacy.currentPlaceId = "block5"
		check(Game.migrate_save(legacy).currentPlaceId == "hive" and legacy.currentPlaceId == "block5", "old boss context relocates without mutating source " + scene)
	var map_visit: Dictionary = Game.state.duplicate(true)
	map_visit.currentScene = "map"
	map_visit.currentPlaceId = "block5"
	check(Game.migrate_save(map_visit).currentPlaceId == "block5", "later map visit is not relocated")

	check(not Game.battle_exit("win", Game.revision), "first phase cannot submit victory or grant rewards")
	var result := model.play_card(killing_card(model, true), -1)
	check(result.get("phaseChanged", false) and model.encounter_phase == 2 and model.outcome == "", "AoE transitions without victory")
	check(result.hits.size() == 1 and result.hits[0].hpAfter == 0, "old-stage multi-hit stops at death")
	check(model.enemies.size() == 2 and model.enemies[0].hp == 90 and model.enemies[1].hp == 90, "no hit spills into second phase")
	check(model.enemies[0].id == "dancer_black" and model.enemies[1].id == "dancer_white", "second-phase identities and order")
	check(model.enemies[0].intent.amount == 15 and model.enemies[1].intent.type == "weak" and model.enemies[1].intent.amount == 2, "second phase opens black attack15 and white weak2")
	result = model.play_card(killing_card(model), 0)
	check(not result.phaseChanged and model.outcome == "" and model.enemies[1].hp == 90, "one surviving dancer prevents victory")
	result = model.play_card(killing_card(model), 1)
	check(not result.phaseChanged and model.outcome == "win" and model.encounter_phase == 2, "both defeated yields final victory")
	check(model.play_card(killing_card(model), 0).is_empty(), "final victory locks further plays")
	# Direct damage, bleed and counters all go through the same outcome boundary.
	model = start_boss()
	model.enemies[0].hp = 1
	model.buffs.apply(model, "bleed", 2, 0)
	model.stance = "ranged"
	result = model.play_card(killing_card(model, false, 0, 1), 0)
	check(result.phaseChanged and model.enemies.all(func(e): return e.hp == 90), "bleed-only lethal card advances phase cleanly")
	model = start_boss()
	model.enemies[0].hp = 1
	model.parry = 1
	var hp_before := model.player_hp
	result = model.end_turn()
	check(result.phaseChanged and result.attacks.size() == 1, "counter lethal produces one old-stage attack")
	check(model.encounter_phase == 2 and model.enemies.all(func(e): return e.hp == 90), "counter opens fresh second phase")
	check(model.player_hp == hp_before - 15 and model.turn == 2 and model.energy == 3, "new dancers do not attack in old round")
	check(model.enemies.all(func(e): return e.intentIndex == 0), "new phase starts at first intent")
	model = start_boss()
	model.enemies[0].hp = 1
	model.buffs.apply(model, "pollution", 1, 0)
	result = model.end_turn()
	check(result.phaseChanged and model.encounter_phase == 2, "enemy pollution lethal advances at round boundary")
	model = start_boss()
	model.player_hp = 1
	model.enemies[0].hp = 1
	model.parry = 1
	result = model.end_turn()
	check(model.outcome == "lose" and model.encounter_phase == 1 and not result.phaseChanged, "player death wins tie over phase transition")

func test_snapshots_and_training() -> void:
	var model := start_boss()
	var opening: Dictionary = Game.state.battleStart.duplicate(true)
	model.enemy_damage(0, 999)
	model.resolve_outcome()
	check(model.advance_encounter_phase(), "explicit boundary advances")
	check(Game.valid_combat(model.snapshot()), "second-phase frozen snapshot validates")
	Game.state.combat = model.snapshot()
	check(Game.valid_battle_start(Game.state) and Game.valid_save(Game.state), "single-enemy opening matches two-enemy live snapshot")
	var active_second_phase: Dictionary = Game.state.duplicate(true)
	var active_revision: int = Game.revision
	check(not Game.battle_exit("win", active_revision), "formal phase two still rejects victory while dancers are alive")
	check(Game.state == active_second_phase and Game.revision == active_revision, "rejected formal result preserves state and revision")
	Game.state.combat.outcome = "win"
	check(not Game.battle_exit("win", Game.revision), "formal victory still validates defeated enemies rather than an outcome label")
	Game.state = active_second_phase
	var restored := CombatModel.new()
	restored.restore(model.snapshot())
	check(restored.encounter_phase == 2 and restored.snapshot() == model.snapshot(), "second-phase snapshot roundtrip")
	Game.enemy_catalog.dancer_white.maxHp = 999
	check(restored.profile.phaseTwoEnemies[1].maxHp == 90, "frozen second-stage definitions ignore live catalog edits")
	Game.enemy_catalog.dancer_white.maxHp = 90
	for variant in ["missing_phase", "invalid_phase", "missing_defs", "bad_hp", "wrong_id", "wrong_count", "early_win"]:
		var broken := model.snapshot()
		match variant:
			"missing_phase": broken.erase("encounterPhase")
			"invalid_phase": broken.encounterPhase = 3
			"missing_defs": broken.profile.erase("phaseTwoEnemies")
			"bad_hp": broken.profile.phaseTwoEnemies[1].maxHp = -1
			"wrong_id": broken.enemies[1].id = "robot"
			"wrong_count": broken.enemies.pop_back()
			"early_win": broken.outcome = "win"
		check(not Game.valid_combat(broken), "reject malformed snapshot " + variant)
	check(Game.save_game(), "second-phase checkpoint projects and saves")
	var disk = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	check(disk.combat.encounterPhase == 1 and disk.combat.enemies.size() == 1, "midbattle disk resumes original opening")
	check(Game.valid_combat(disk.combat) and Game.valid_save(disk), "JSON numeric phase validates after serialization")
	Game.state = {}
	check(Game.load_game() and Game.state.get("combat", {}).get("encounterPhase") == 1, "resume starts phase one")
	check(JSON.parse_string(JSON.stringify(Game.state.get("battleStart", {}))) == JSON.parse_string(JSON.stringify(opening)), "restart preserves original opening draw")
	fresh()
	var adventure: Dictionary = Game.state.duplicate(true)
	Game.page = "menu"
	Game.start_training("B16")
	check(Game.training_mode and Game.state.battleId == "B16", "boss training accessible before day seven")
	model = CombatModel.new()
	model.restore(Game.state.combat)
	check(model.enemies[0].hp == 99 and model.profile.phaseTwoEnemies[1].maxHp == 90, "training keeps requested boss HP")
	var training_state: Dictionary = Game.state.duplicate(true)
	check(not Game.battle_exit("win", Game.revision-1), "training simulation still rejects a stale revision")
	Game.battle_busy = true
	check(not Game.battle_exit("win", Game.revision), "training simulation still rejects busy battle playback")
	Game.battle_busy = false
	Game.transition_locked = true
	check(not Game.battle_exit("win", Game.revision), "training simulation still rejects transition lock")
	Game.transition_locked = false
	check(not Game.battle_exit("surrender", Game.revision) and Game.state == training_state, "training accepts only supported results and preserves rejected attempts")
	check(Game.battle_exit("win", Game.revision), "phase-one Boss training accepts simulated victory")
	check(not Game.training_mode and Game.state == adventure, "training restores entire adventure and event pool")
	# Authored victory follows normal rewards once; no first-phase reward exists.
	model = start_boss()
	model.enemy_damage(0, 999); model.resolve_outcome(); model.advance_encounter_phase()
	model.enemy_damage(0, 999); model.enemy_damage(1, 999); model.resolve_outcome()
	Game.commit_combat(model)
	check(Game.battle_exit("win", Game.revision), "boss final victory reaches authored return")
	Game.skip_dialogue(Game.revision)
	check("E16" in Game.state.completedEventIds and Game.state.battleReward.get("battleType") == "boss", "boss completed with boss reward tier")
	check(Game.state.currentDay == 7 and Game.state.refreshedEventIds.is_empty(), "boss finish stays day seven with no ordinary events")

func _ready() -> void:
	if not OS.get_environment("QA_OUT_DIR").is_empty(): output = OS.get_environment("QA_OUT_DIR")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	test_dialogue()
	test_event_gate()
	test_phases()
	test_new_phase_player_turn()
	test_phase_turn_state_and_draws()
	test_phase_end_turn_status_once()
	test_snapshots_and_training()
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures}, "\t")); file.close()
	print("DANCER BOSS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
