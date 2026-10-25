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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Game.save_path.get_base_dir()))
	Game.meta_path = "res://artifacts/qa/reward-2026-10-09/test_meta.json"
	for id in Game.battles:
		start_battle(id)
		if id == "B16":
			# Formal Boss victories require a valid defeated second-phase snapshot.
			var boss := CombatModel.new()
			boss.restore(Game.state.combat)
			boss.enemy_damage(0, 999)
			boss.resolve_outcome()
			check(boss.advance_encounter_phase(), "Boss reward fixture reaches real second phase")
			for index in boss.enemies.size(): boss.enemy_damage(index, 999)
			boss.resolve_outcome()
			check(boss.encounter_phase == 2 and boss.outcome == "win" and Game.valid_combat(boss.snapshot()), "Boss reward fixture defeats both second-phase dancers")
			check(Game.commit_combat(boss), "Boss reward fixture commits actual victory")
		var rev := Game.revision
		check(Game.battle_exit("win",rev),id + " accepts victory")
		check(not Game.battle_exit("win",rev),"Duplicate result rejected")
		check(Game.page == "dialogue" and Game.state.credits == int(Game.config.initialCredits) and Game.state.battleReward.is_empty(),"No rewards before dialogue ends")
		if id == "B02": check(roundtrip(),"Resume post-battle dialogue from disk")
		finish_dialogue()
		check(Game.page == "result" and Game.has_battle_reward(),id + " opens victory reward after dialogue")
		check(Game.state.credits == int(Game.config.initialCredits) + 50 and Game.state.battleReward.options.size() == 3,"Exactly 50 credits and three offers")
		Game.enter_node("finish")
		check(Game.state.credits == int(Game.config.initialCredits) + 50,"Finish reentry cannot duplicate credits")
		var options: Array = Game.state.battleReward.options.duplicate()
		check(roundtrip() and Game.state.battleReward.options == options,"Pending reward persists unchanged")
		rev = Game.revision
		check(not Game.choose_reward_card("unknown",rev),"Invalid reward rejected")
		check(Game.choose_reward_card(options[1],rev),"Select one offered card")
		check(not Game.choose_reward_card(options[0],rev) and not Game.choose_reward_card(options[2],Game.revision),"Duplicate and second choice rejected")
		check(Game.state.deck == [options[1]] and Game.state.credits == int(Game.config.initialCredits) + 50,"One card added with no repeated credits")
		check(roundtrip() and Game.state.battleReward.status == "claimed" and Game.state.deck == [options[1]],"Claimed reward persists")
		if id == "B16":
			check(Game.page == "result" and Game.is_week_complete() and not Game.can_continue(), "Claimed Boss receipt reloads into first-week completion")
			check(not Game.claim_rewards(Game.revision), "Completed Boss reward cannot exit a second time")
			check(not Game.choose_reward_card(options[0],Game.revision), "No claiming from week completion")
		else:
			check(Game.claim_rewards(Game.revision) and Game.page == "map","Exit reward to map")
			check(not Game.choose_reward_card(options[0],Game.revision),"No claiming from map")
	# The money chip remains an additional reward, separate from the base 50.
	start_battle("B02")
	Game.state.ownedCyberwareIds.append("money_chip")
	Game.state.equippedCyberwareIds = ["money_chip"]
	Game.initialize_combat()
	check(Game.battle_exit("win", Game.revision) and Game.state.credits == int(Game.config.initialCredits) + 30, "Money chip still pays 30 before the base reward")
	finish_dialogue()
	check(Game.state.credits == int(Game.config.initialCredits) + 80 and Game.state.battleReward.credits == 50, "Base 50 plus money chip 30 pays exactly 80")
	# Nonvictories end the run without a reward.
	for outcome in ["lose"]:
		start_battle("B02")
		Game.battle_exit(outcome,Game.revision)
		finish_dialogue()
		check(Game.page == "defeat" and not Game.can_continue() and Game.state.credits == int(Game.config.initialCredits) and Game.state.deck.is_empty() and Game.state.battleReward.is_empty(),outcome + " never rewards")
	Game.new_game()
	finish_dialogue()
	check(Game.page == "result" and not Game.has_battle_reward() and Game.state.credits == int(Game.config.initialCredits),"Nonbattle event retains normal result")
	# Acquired cards augment the next adventure battle and survive a combat save.
	start_battle("B02")
	Game.battle_exit("win",Game.revision)
	finish_dialogue()
	var earned: String = Game.state.battleReward.options[0]
	Game.choose_reward_card(earned,Game.revision)
	Game.claim_rewards(Game.revision)
	Game.state.activeEventId = "E11"
	Game.state.currentPlaceId = Game.battles.B11.placeId
	Game.state.battleReward = {}
	Game.enter_node("battle")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	check(model.instances.size() == 11 and model.instances.values().count(earned) == 1,"Next battle contains earned card plus base deck")
	model.draw_cards(11)
	var uid: String = model.instances.find_key(earned)
	var candidates := model.discard_candidates(uid)
	check(model.card(uid).id == earned and not model.play_card(uid,0,candidates[0]).is_empty(),"Earned card is playable")
	Game.commit_combat(model)
	check(roundtrip() and Game.state.combat.instances.size() == 11,"Expanded battle snapshot restores")
	# Training never consumes the pending reward or changes adventure ownership.
	var saved := Game.state.duplicate(true)
	Game.start_training("B02")
	check(Game.state.combat.instances.size() == 11,"Training copies currently owned deck")
	Game.battle_exit("win",Game.revision)
	check(Game.page == "menu" and Game.state == saved,"Training victory restores adventure without rewards")
	# Explicit exit skips just the unchosen card, retaining credits.
	start_battle("B02")
	Game.battle_exit("win",Game.revision)
	finish_dialogue()
	Game.claim_rewards(Game.revision)
	check(Game.page == "map" and Game.state.battleReward.status == "skipped" and Game.state.deck.is_empty() and Game.state.credits == int(Game.config.initialCredits) + 50,"Exit without card preserves credits")
	# Historical receipts keep the old amount and never repay on reload/reentry.
	var current := Game.state.duplicate(true)
	for reward_status in ["pending", "claimed", "skipped"]:
		Game.state = current.duplicate(true)
		Game.state.credits = int(Game.config.initialCredits) + 1000
		Game.state.battleReward.credits = 1000
		Game.state.battleReward.status = reward_status
		if reward_status == "claimed":
			Game.state.battleReward.selectedCardId = Game.state.battleReward.options[0]
			Game.state.deck.append(Game.state.battleReward.selectedCardId)
		var legacy_options: Array = Game.state.battleReward.options.duplicate()
		check(roundtrip(), "Legacy 1000-credit receipt reloads: " + reward_status)
		Game.enter_node("finish")
		check(Game.state.credits == int(Game.config.initialCredits) + 1000 and Game.state.battleReward.credits == 1000 and Game.state.battleReward.options == legacy_options and Game.state.battleReward.status == reward_status, "Legacy receipt stays paid and frozen: " + reward_status)
	Game.state = current
	for bad_amount in [-1, 0, 49, 51, 50.5, INF, "50"]:
		var bad := Game.state.duplicate(true)
		bad.battleReward.credits = bad_amount
		check(not Game.valid_save(bad), "Malformed reward amount rejected: " + str(bad_amount))
	# Schema 1/2 compatibility and rejection of malformed reward claims.
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
	check(not Game.valid_save(invalid),"Claim outside the original offer rejected")
	invalid = Game.state.duplicate(true)
	invalid.deck = "bad"
	check(not Game.valid_save(invalid),"Malformed deck rejected")
	print("REWARD TESTS: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
