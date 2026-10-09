extends Node
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func start_battle(id: String) -> void:
	Game.state = Game.initial_state()
	Game.state.targetId = "richard"
	Game.state.activeEventId = Game.battles[id].eventId
	Game.state.currentPlaceId = Game.battles[id].placeId
	Game.enter_node("battle")

func finish_dialogue() -> void:
	var count := 0
	while Game.state.currentScene == "dialogue" and count < 100:
		if Game.node_data().has("next"): Game.advance(Game.revision)
		else: Game.choose(0,Game.revision)
		count += 1
	check(count < 100,"Post-battle dialogue terminates")

func roundtrip() -> bool:
	if not Game.save_game(): return false
	Game.state = {}
	return Game.load_game()

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "res://artifacts/qa/reward-2026-10-09/test_checkpoint.json"
	Game.meta_path = "res://artifacts/qa/reward-2026-10-09/test_meta.json"
	for id in Game.battles:
		start_battle(id)
		var rev := Game.revision
		check(Game.battle_exit("win",rev),id + " accepts victory")
		check(not Game.battle_exit("win",rev),"Duplicate result rejected")
		check(Game.page == "dialogue" and Game.state.credits == 0 and Game.state.battleReward.is_empty(),"No rewards before dialogue ends")
		if id == "B08": check(roundtrip(),"Resume post-battle dialogue from disk")
		finish_dialogue()
		check(Game.page == "result" and Game.has_battle_reward(),id + " opens victory reward after dialogue")
		check(Game.state.credits == 1000 and Game.state.battleReward.options.size() == 3,"Exactly 1000 credits and three offers")
		Game.enter_node("finish")
		check(Game.state.credits == 1000,"Finish reentry cannot duplicate credits")
		var options: Array = Game.state.battleReward.options.duplicate()
		check(roundtrip() and Game.state.battleReward.options == options,"Pending reward persists unchanged")
		rev = Game.revision
		check(not Game.choose_reward_card("unknown",rev),"Invalid reward rejected")
		check(Game.choose_reward_card(options[1],rev),"Select one offered card")
		check(not Game.choose_reward_card(options[0],rev) and not Game.choose_reward_card(options[2],Game.revision),"Duplicate and second choice rejected")
		check(Game.state.deck == [options[1]] and Game.state.credits == 1000,"One card added with no repeated credits")
		check(roundtrip() and Game.state.battleReward.status == "claimed" and Game.state.deck == [options[1]],"Claimed reward persists")
		check(Game.claim_rewards(Game.revision) and Game.page == "map","Exit reward to map")
		check(not Game.choose_reward_card(options[0],Game.revision),"No claiming from map")
	# Nonvictories return through their original story nodes, with no reward.
	for outcome in ["lose","surrender"]:
		start_battle("B08")
		Game.battle_exit(outcome,Game.revision)
		finish_dialogue()
		check(Game.page == "map" and Game.state.credits == 0 and Game.state.deck.is_empty() and Game.state.battleReward.is_empty(),outcome + " never rewards")
	Game.new_game()
	finish_dialogue()
	check(Game.page == "result" and not Game.has_battle_reward() and Game.state.credits == 0,"Nonbattle event retains normal result")
	# Acquired cards augment the next adventure battle and survive a combat save.
	start_battle("B08")
	Game.battle_exit("win",Game.revision)
	finish_dialogue()
	Game.choose_reward_card("test_reward_01",Game.revision)
	Game.claim_rewards(Game.revision)
	Game.state.activeEventId = "E11"
	Game.state.currentPlaceId = Game.battles.B11.placeId
	Game.state.battleReward = {}
	Game.enter_node("battle")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	check(model.instances.size() == 6 and model.instances.values().count("test_reward_01") == 1,"Next battle contains earned card plus base deck")
	model.draw_cards()
	var uid: String = model.hand[0]
	check(model.card(uid).id == "test_reward_01" and model.play_card(uid,0).damage == 1,"Earned card is playable")
	Game.commit_combat(model)
	check(roundtrip() and Game.state.combat.instances.size() == 6,"Expanded battle snapshot restores")
	# Training never consumes the pending reward or changes adventure ownership.
	var saved := Game.state.duplicate(true)
	Game.start_training("B12")
	check(Game.state.combat.instances.size() == 5,"Training uses only original test deck")
	Game.battle_exit("win",Game.revision)
	check(Game.page == "menu" and Game.state == saved,"Training victory restores adventure without rewards")
	# Explicit exit skips just the unchosen card, retaining credits.
	start_battle("B08")
	Game.battle_exit("win",Game.revision)
	finish_dialogue()
	Game.claim_rewards(Game.revision)
	check(Game.page == "map" and Game.state.battleReward.status == "skipped" and Game.state.deck.is_empty() and Game.state.credits == 1000,"Exit without card preserves credits")
	# Schema 1/2 compatibility and rejection of malformed reward ownership.
	var old := Game.initial_state()
	old.erase("battleReward")
	check(Game.valid_save(Game.migrate_save(old)),"Old schema 2 accepts additive reward migration")
	old.schemaVersion = 1
	check(Game.valid_save(Game.migrate_save(old)),"Schema 1 still migrates")
	var invalid := Game.state.duplicate(true)
	invalid.battleReward.options[0] = "bogus"
	check(not Game.valid_save(invalid),"Unknown offer rejected")
	invalid = Game.state.duplicate(true)
	invalid.battleReward.status = "claimed"
	invalid.battleReward.selectedCardId = "test_reward_01"
	check(not Game.valid_save(invalid),"Claim without owned card rejected")
	invalid = Game.state.duplicate(true)
	invalid.deck = "bad"
	check(not Game.valid_save(invalid),"Malformed deck rejected")
	print("REWARD TESTS: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
