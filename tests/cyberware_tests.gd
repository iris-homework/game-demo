extends "res://tests/combat_tests.gd"

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://cyberware_test_checkpoint.json"
	Game.meta_path = "user://cyberware_test_meta.json"
	var m := model_for("B04")
	m.enemies[0].hp = 30
	m.enemies[0].maxHp = 30
	m.draw_cards()
	check(m.cyberware_cards().size() == 6,"Exactly six prototype cyberware cards")
	var before := m.snapshot()
	check(not m.activate_cyberware("missing"),"Unknown cyberware rejected")
	check(m.snapshot() == before,"Invalid activation leaves all state intact")
	var first: String = m.cyberware_cards()[0].id
	var second: String = m.cyberware_cards()[1].id
	check(m.activate_cyberware(first),"Activate first card")
	check(m.next_attack_bonus == 1,"Activation grants pending +1")
	check(m.hand == before.hand and m.draw_pile == before.drawPile and m.discard_pile == before.discardPile,"Activation never touches combat piles")
	check(not m.activate_cyberware(first) and m.next_attack_bonus == 1,"Repeated activation cannot duplicate bonus")
	check(m.activate_cyberware(second) and m.next_attack_bonus == 2,"Distinct activations stack")
	check(m.play_card(m.hand[0],99).is_empty() and m.next_attack_bonus == 2,"Invalid target preserves pending bonus")
	m.card_catalog.test_attack.effects = [{"type":"unimplemented","amount":1}]
	check(m.play_card(m.hand[0],0).is_empty() and m.next_attack_bonus == 2,"Invalid effect preserves pending bonus")
	m.card_catalog.test_attack.effects = [{"type":"damage","amount":1}]
	m.end_turn()
	check(m.next_attack_bonus == 2 and m.player_hp == 99,"Enemy turn does not consume pending player bonus")
	check(m.used_cyberware.is_empty() and Game.valid_combat(m.snapshot()),"Next player turn clears cooldown but keeps a valid pending buff")
	check(m.play_card(m.hand[0],0).damage == 3 and m.next_attack_bonus == 0,"Next attack applies +2 exactly once")
	check(m.play_card(m.hand[0],0).damage == 1,"Following attack returns to base damage")
	m.activate_cyberware(m.cyberware_cards()[2].id)
	m.card_catalog.test_attack.effects = [{"type":"damage","amount":1},{"type":"damage","amount":1}]
	check(m.play_card(m.hand[0],0).damage == 3,"Multi-effect attack receives bonus once, not per hit")
	m.end_turn()
	m.activate_cyberware(m.cyberware_cards()[3].id)
	m.card_catalog.test_attack.effects = []
	m.play_card(m.hand[0],0)
	check(m.next_attack_bonus == 1,"Empty effect card does not consume attack buff")
	m.card_catalog.test_attack.type = "skill"
	m.card_catalog.test_attack.effects = [{"type":"damage","amount":1}]
	check(m.play_card(m.hand[0],0).damage == 1 and m.next_attack_bonus == 1,"Non-attack card does not consume attack buff")
	m.card_catalog.test_attack.type = "attack"
	# Persist with a dedicated test save, then reconstruct the pure model.
	Game.state = Game.initial_state()
	Game.state.currentScene = "battle"
	Game.state.currentPlaceId = "alley"
	Game.state.activeEventId = "E04"
	Game.state.activeNodeId = "battle"
	Game.state.battleId = "B04"
	Game.commit_combat(m)
	check(Game.valid_save(Game.state),"Cyberware snapshot passes validation")
	check(Game.save_game(),"Dedicated battle save written")
	Game.state = {}
	check(Game.load_game(),"Battle with cyberware loads")
	var restored := CombatModel.new()
	restored.restore(Game.state.combat)
	check(restored.used_cyberware == m.used_cyberware and restored.next_attack_bonus == 1,"Used cards and pending effect survive disk roundtrip")
	check(not restored.activate_cyberware(m.cyberware_cards()[3].id),"Reload cannot bypass current-turn cooldown")
	check(restored.play_card(restored.hand[0],0).damage == 2 and restored.next_attack_bonus == 0,"Restored pending effect resolves once")
	var legacy := Game.state.duplicate(true)
	legacy.combat.erase("usedCyberware")
	legacy.combat.erase("nextAttackBonus")
	legacy.combat.profile.erase("cyberware")
	var migrated = Game.migrate_save(legacy)
	check(Game.valid_save(migrated),"Legacy schema-2 battle remains loadable")
	restored.restore(migrated.combat)
	check(restored.cyberware_cards().size() == 6 and restored.next_attack_bonus == 0 and restored.used_cyberware.is_empty(),"Legacy battle gains six unused cards, no free buff")
	check(not legacy.combat.profile.has("cyberware"),"Migration does not mutate input")
	for bad_bonus in [-1,0.5,"1",999]:
		var corrupt := m.snapshot()
		corrupt.nextAttackBonus = bad_bonus
		check(not Game.valid_combat(corrupt),"Reject invalid pending bonus: %s" % bad_bonus)
	for bad_used in [[first,first],["missing"],"bad"]:
		var corrupt := m.snapshot()
		corrupt.usedCyberware = bad_used
		check(not Game.valid_combat(corrupt),"Reject invalid used-card state")
	var all := model_for("B04")
	all.enemies[0].hp = 30
	all.enemies[0].maxHp = 30
	for definition in all.cyberware_cards(): check(all.activate_cyberware(definition.id),"Each of six cards activates once")
	check(all.next_attack_bonus == 6 and Game.valid_combat(all.snapshot()),"All six stacked activations are valid")
	all.draw_cards()
	check(all.play_card(all.hand[0],0).damage == 7,"Six bonuses apply to one attack")
	all.outcome = "win"
	check(not all.activate_cyberware(first),"Finished battle rejects activation")
	check(not model_for("B04",0).activate_cyberware(first),"Defeated player cannot activate")
	var fresh := model_for("B04")
	check(fresh.next_attack_bonus == 0 and fresh.used_cyberware.is_empty(),"New battle resets all activations")
	# Previous saves may have eight definitions and cooldowns for removed IDs.
	var old_eight := fresh.snapshot()
	for index in [7,8]:
		old_eight.profile.cyberware.cards.append({"id":"test_cyberware_%02d" % index,"name":"Legacy %d" % index,"nextAttackBonus":1})
	old_eight.usedCyberware = ["test_cyberware_07","test_cyberware_08"]
	old_eight.nextAttackBonus = 2
	check(Game.valid_combat(old_eight),"Old eight-card snapshot and earned bonus remain valid")
	var old_model := CombatModel.new()
	old_model.restore(old_eight)
	check(old_model.cyberware_cards().size() == 6 and old_model.available_cyberware_count() == 6,"Hidden legacy cooldowns do not reduce six available cards")
	check(not old_model.activate_cyberware("test_cyberware_07") and not old_model.activate_cyberware("test_cyberware_08"),"Removed cards cannot be activated from old saves")
	check(old_model.next_attack_bonus == 2 and Game.valid_combat(old_model.snapshot()),"Previously earned bonus survives six-card upgrade")
	for definition in old_model.cyberware_cards(): old_model.activate_cyberware(definition.id)
	check(old_model.available_cyberware_count() == 0,"Old save never displays a negative available count")
	var cooling := model_for("B04")
	cooling.draw_cards()
	check(cooling.activate_cyberware(first),"Cooldown fixture activates")
	check(not cooling.activate_cyberware(first),"Cannot reuse in activation turn")
	cooling.play_card(cooling.hand[0],0)
	check(not cooling.activate_cyberware(first),"Consuming damage buff does not end cooldown")
	cooling.end_turn()
	check(cooling.turn == 2 and cooling.activate_cyberware(first),"Same cyberware is available on the immediately following turn")
	check(not cooling.activate_cyberware(first),"Reactivation starts a fresh current-turn cooldown")
	# Saving after the turn boundary must retain a carried buff and ready cards.
	cooling.end_turn()
	Game.commit_combat(cooling)
	check(Game.valid_save(Game.state) and Game.save_game(),"Save after cooldown expires with an unspent buff")
	Game.state = {}
	check(Game.load_game(),"Load pending buff with no cooling cards")
	restored.restore(Game.state.combat)
	check(restored.used_cyberware.is_empty() and restored.next_attack_bonus == 1,"Ready state and pending buff survive reload")
	check(restored.activate_cyberware(first) and restored.next_attack_bonus == 2,"Reactivated buff stacks after reload")
	var carry := model_for("B04")
	for definition in carry.cyberware_cards(): carry.activate_cyberware(definition.id)
	carry.end_turn()
	for definition in carry.cyberware_cards(): carry.activate_cyberware(definition.id)
	check(carry.next_attack_bonus == 12 and Game.valid_combat(carry.snapshot()),"Multi-turn bonus exceeding six remains valid")
	var defeated := model_for("B04",1)
	defeated.activate_cyberware(first)
	defeated.end_turn()
	check(defeated.outcome == "lose" and not defeated.activate_cyberware(second),"No new activation after enemy causes defeat")
	for path in [Game.save_path,Game.save_path+".bak",Game.save_path+".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("CYBERWARE TESTS: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
