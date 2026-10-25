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
		var credit_amount: int = Game.reward_credit_amount()
		check(credit_amount >= 40 and credit_amount <= 60, "Generated base credits stay within 40–60")
		check(Game.state.credits == int(Game.config.initialCredits) and Game.reward_credit_amount() == credit_amount and Game.reward_credits_status() == "pending" and Game.state.battleReward.options.size() == 3,"Base credits await explicit claim alongside three offers")
		Game.enter_node("finish")
		check(Game.state.credits == int(Game.config.initialCredits) and Game.reward_credits_status() == "pending" and Game.reward_credit_amount() == credit_amount,"Finish reentry cannot automatically claim or reroll credits")
		var options: Array = Game.state.battleReward.options.duplicate()
		check(roundtrip() and Game.state.battleReward.options == options and Game.reward_credit_amount() == credit_amount and Game.reward_credits_status() == "pending" and Game.state.credits == int(Game.config.initialCredits),"Pending reward and unpaid credits persist unchanged")
		rev = Game.revision
		check(not Game.claim_reward_credits(rev - 1), "Stale credit request rejected")
		check(Game.claim_reward_credits(rev) and Game.state.credits == int(Game.config.initialCredits) + credit_amount and Game.reward_credits_status() == "claimed", "Explicit credit claim pays exactly once")
		check(not Game.claim_reward_credits(rev) and not Game.claim_reward_credits(Game.revision), "Repeated credit claim rejected")
		rev = Game.revision
		check(not Game.choose_reward_card("unknown",rev),"Invalid reward rejected")
		check(Game.choose_reward_card(options[1],rev),"Select one offered card")
		check(not Game.choose_reward_card(options[0],rev) and not Game.choose_reward_card(options[2],Game.revision),"Duplicate and second choice rejected")
		check(Game.state.deck == [options[1]] and Game.state.credits == int(Game.config.initialCredits) + credit_amount,"One card added with no repeated credits")
		check(roundtrip() and Game.state.battleReward.status == "claimed" and Game.state.deck == [options[1]],"Claimed reward persists")
		if id == "B16":
			check(Game.page == "result" and not Game.is_week_complete() and Game.can_continue(), "New Boss receipt remains in rewards until explicit exit after reload")
			check(Game.claim_rewards(Game.revision) and Game.is_week_complete(), "Explicit Boss reward exit completes first week")
			check(not Game.claim_rewards(Game.revision), "Completed Boss reward cannot exit a second time")
			check(not Game.choose_reward_card(options[0],Game.revision), "No claiming from week completion")
		else:
			check(Game.claim_rewards(Game.revision) and Game.page == "map","Exit reward to map")
			check(not Game.choose_reward_card(options[0],Game.revision),"No claiming from map")
	# The money chip remains an additional reward, separate from the random base.
	start_battle("B02")
	Game.state.ownedCyberwareIds.append("money_chip")
	Game.state.equippedCyberwareIds = ["money_chip"]
	Game.initialize_combat()
	check(Game.battle_exit("win", Game.revision) and Game.state.credits == int(Game.config.initialCredits), "Money chip waits for reward credit claim")
	finish_dialogue()
	var chip_credit_amount: int = Game.reward_credit_amount()
	check(Game.state.credits == int(Game.config.initialCredits) and Game.state.battleReward.credits >= 40 and Game.state.battleReward.credits <= 60 and chip_credit_amount == int(Game.state.battleReward.credits) + 30, "Random base plus frozen chip 30 remains unpaid")
	check(Game.claim_reward_credits(Game.revision) and Game.state.credits == int(Game.config.initialCredits) + chip_credit_amount, "Explicit claim pays base plus chip together exactly once")
	check(not Game.claim_reward_credits(Game.revision), "Chip-inclusive credit claim cannot repeat")
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
	# Explicit exit skips every unclaimed reward without granting credits.
	start_battle("B02")
	Game.battle_exit("win",Game.revision)
	finish_dialogue()
	Game.claim_rewards(Game.revision)
	check(Game.page == "map" and Game.state.battleReward.status == "skipped" and Game.reward_credits_status() == "skipped" and Game.state.deck.is_empty() and Game.state.credits == int(Game.config.initialCredits),"Exit without claims skips credits and card")
	check(not Game.claim_reward_credits(Game.revision), "Credits cannot be claimed from map after skipping")
	# Historical receipts keep the old amount and never repay on reload/reentry.
	var current := Game.state.duplicate(true)
	for legacy_amount in [50, 1000]:
		for reward_status in ["pending", "claimed", "skipped"]:
			Game.state = current.duplicate(true)
			Game.state.credits = int(Game.config.initialCredits) + legacy_amount
			Game.state.battleReward.credits = legacy_amount
			Game.state.battleReward.erase("creditsStatus")
			Game.state.battleReward.erase("bonusCredits")
			Game.state.battleReward.status = reward_status
			if reward_status == "claimed":
				Game.state.battleReward.selectedCardId = Game.state.battleReward.options[0]
				Game.state.deck.append(Game.state.battleReward.selectedCardId)
			var legacy_options: Array = Game.state.battleReward.options.duplicate()
			check(roundtrip(), "Legacy %d-credit receipt reloads: " % legacy_amount + reward_status)
			Game.enter_node("finish")
			check(Game.state.credits == int(Game.config.initialCredits) + legacy_amount and Game.state.battleReward.credits == legacy_amount and Game.state.battleReward.options == legacy_options and Game.state.battleReward.status == reward_status, "Legacy %d-credit receipt stays paid and frozen: " % legacy_amount + reward_status)
			check(Game.reward_credits_status() == "claimed" and not Game.claim_reward_credits(Game.revision), "Legacy already-paid credits never become claimable: " + reward_status)
	Game.state = current
	for valid_amount in [40, 49, 50, 51, 60]:
		var compatible := Game.state.duplicate(true)
		compatible.battleReward.credits = valid_amount
		check(Game.valid_save(compatible), "Integer reward within inclusive 40–60 range remains loadable: " + str(valid_amount))
	for bad_amount in [-1, 0, 39, 61, 50.5, INF, "50"]:
		var bad := Game.state.duplicate(true)
		bad.battleReward.credits = bad_amount
		check(not Game.valid_save(bad), "Malformed reward amount rejected: " + str(bad_amount))
	# A card can be taken before credits; failed credit saves roll back independently.
	start_battle("B02")
	Game.battle_exit("win", Game.revision)
	finish_dialogue()
	check(Game.choose_reward_card(Game.state.battleReward.options[0], Game.revision) and Game.reward_credits_status() == "pending", "Card-first choice leaves credit claim available")
	check(roundtrip() and Game.reward_credits_status() == "pending" and Game.state.credits == int(Game.config.initialCredits), "Card-first save preserves unpaid credits")
	var retry_credit_amount: int = Game.reward_credit_amount()
	var unpaid := Game.state.duplicate(true)
	var real_path := Game.save_path
	var unpaid_revision := Game.revision
	Game.save_enabled = true
	Game.save_path = real_path.path_join("blocked.json")
	check(not Game.claim_reward_credits(Game.revision) and Game.state == unpaid and Game.revision == unpaid_revision, "Failed credit save restores balance, claim status and revision")
	Game.save_path = real_path
	check(Game.claim_reward_credits(Game.revision) and Game.state.credits == int(Game.config.initialCredits) + retry_credit_amount, "Credit retry succeeds once after card selection")
	check(roundtrip() and Game.state.credits == int(Game.config.initialCredits) + retry_credit_amount and Game.reward_credit_amount() == retry_credit_amount and Game.reward_credits_status() == "claimed" and not Game.claim_reward_credits(Game.revision), "Paid credit save cannot pay twice")
	Game.save_enabled = false
	for bad_status in [null, 1, "unknown"]:
		var bad := Game.state.duplicate(true)
		bad.battleReward.creditsStatus = bad_status
		check(not Game.valid_save(bad), "Malformed credit claim status rejected")
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
