extends Node
var count := 0
var failures: Array[String] = []
func check(ok: bool, title: String) -> void:
	count += 1
	if not ok:
		failures.append(title)
		push_error(title)

func model_for(id: String, hp: int = 100) -> CombatModel:
	var m := CombatModel.new()
	var definitions: Array = []
	for enemy_id in Game.battles[id].enemyIds: definitions.append(Game.enemy_catalog[enemy_id])
	m.initialize(id,hp,100,Game.prototype_rules,definitions)
	return m

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://r1_combat_test.json"
	Game.meta_path = "user://r1_meta_test.json"
	for id in Game.battles:
		var m := model_for(id)
		check(m.enemies[0].hp == 3,id+" HP 3")
		check(m.enemies[0].intent.type == "attack" and m.enemies[0].intent.amount == 1,id+" intention attack 1")
		check(m.draw_cards().size() == 5,id+" draw 5 cards")
		for hit in 3:
			var uid: String = m.hand[0]
			check(m.play_card(uid,0).damage == 1,id+" damage exactly 1")
			check(m.play_card(uid,0).is_empty(),id+" cannot replay discarded card")
			check(m.enemies[0].hp == 2-hit,id+" HP after hit")
		check(m.outcome == "win",id+" 3 cards win")
		check(m.hand.size() == 2 and m.discard_pile.size() == 3,id+" pile accounting")
		check(m.end_turn().is_empty(),id+" finished battle rejects end turn")
	var model := model_for("B04")
	model.draw_cards()
	var old_hand := model.hand.duplicate()
	var snapshot := model.snapshot()
	check(model.play_card(model.hand[0],8).is_empty(),"Invalid target rejected")
	check(model.snapshot() == snapshot,"Invalid target does not mutate")
	var turn_result := model.end_turn()
	check(turn_result.attacks[0].damage == 1 and model.player_hp == 99,"Enemy applies telegraphed damage")
	check(model.turn == 2 and model.hand.size() == 5,"New turn draws hand")
	check(model.hand.all(func(uid): return uid in old_hand),"Discard reshuffle conserves card identities")
	check(model.enemies[0].intent.amount == 1,"Next intent refreshes")
	var near_death := model_for("B04",1)
	near_death.draw_cards()
	near_death.end_turn()
	check(near_death.player_hp == 0 and near_death.outcome == "lose","Natural HP defeat")
	check(near_death.draw_cards().is_empty(),"No draw after defeat")
	var dead := model_for("B04",0)
	check(dead.outcome == "lose","Reenter at zero HP cannot bypass defeat")
	Game.state = Game.initial_state()
	check(Game.state.currentHp == 100 and Game.state.maxHp == 100 and Game.state.currentDay == 1,"Initial HP and date")
	Game.state.completedEventIds = ["E01"]
	Game.state.currentScene = "map"
	for place in ["hospital","clinic"]:
		for hp in [50,90]:
			Game.state.currentHp = hp
			check(Game.heal_at(place),place+" service")
			check(Game.state.currentHp == (80 if hp == 50 else 100),place+" heal30% capped")
			check(Game.state.currentDay == 1,place+" no automatic time cost")
	Game.state.currentHp = 50
	check(not Game.heal_at("bar"),"No healing at non-service location")
	Game.apply_actions([{"op":"advanceDay","days":2}])
	check(Game.state.currentDay == 3,"Explicit day advance")
	Game.apply_actions([{"op":"advanceDay","days":20}])
	check(Game.state.currentDay == 7 and Game.state.currentWeek == 1,"Date capped without advancing week")
	check(not Game.apply_actions([{"op":"healHpPercent","percent":1.3}]),"Invalid healing action rejected")
	# Save a damaged, partially played battle; restore piles, HP and intent exactly.
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.enter_node("battle")
	model = model_for("B04",50)
	model.draw_cards()
	model.play_card(model.hand[0],0)
	Game.commit_combat(model)
	var expected := Game.state.duplicate(true)
	check(Game.save_game(),"Save mid-battle")
	Game.state = {}
	check(Game.load_game(),"Load mid-battle")
	check(JSON.parse_string(JSON.stringify(Game.state)) == JSON.parse_string(JSON.stringify(expected)),"Mid-battle exact roundtrip")
	var restored := CombatModel.new()
	restored.restore(Game.state.combat)
	check(restored.hand.size() == 4 and restored.discard_pile.size() == 1 and restored.enemies[0].hp == 2,"No reset/exploit on resume")
	check(restored.player_hp == 50 and Game.state.currentDay == 7,"HP/date persisted")
	check(not restored.use_item("missing",0,{},Game.item_catalog).ok,"Empty items cannot create effect")
	check(Game.read_data("cards/cards.json").is_empty() and Game.item_catalog.is_empty(),"Formal card/item pools stay empty")
	var original := Game.state.duplicate(true)
	Game.start_training("B12")
	check(Game.training_mode and Game.state.currentHp == 100,"Practice isolated")
	Game.battle_exit("win",Game.revision)
	check(not Game.training_mode and Game.state == original,"Practice restores exact adventure")
	var legacy := Game.initial_state()
	legacy.schemaVersion = 1
	for key in ["currentHp","maxHp","currentDay","combat","inventory"]: legacy.erase(key)
	legacy.credits = 123
	legacy.flags = {"alleyClue":true}
	legacy.targetId = "lumina"
	var migrated = Game.migrate_save(legacy)
	check(Game.valid_save(migrated),"Version 1 migration accepted")
	check(migrated.credits == 123 and migrated.flags.alleyClue and migrated.targetId == "lumina","Migration preserves story")
	check(migrated.currentHp == 100 and migrated.currentDay == 1,"Migration defaults new fields")
	Game.meta_profile = {"schemaVersion":1,"cyberwareState":{"test_marker":true}}
	check(Game.save_meta(),"Independent meta save")
	Game.new_game()
	check(Game.meta_profile.cyberwareState.test_marker,"New adventure preserves meta")
	Game.meta_profile = {"schemaVersion":1,"cyberwareState":{}}
	check(Game.load_meta() and Game.meta_profile.cyberwareState.test_marker,"Meta roundtrip")
	for path in [Game.save_path,Game.save_path+".bak",Game.save_path+".tmp",Game.meta_path,Game.meta_path+".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("COMBAT TESTS: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
