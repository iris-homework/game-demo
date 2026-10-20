extends Node
var checks := 0
var failed := 0
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(title)

func fresh(hp: int = 100) -> CombatModel:
	var model := CombatModel.new()
	model.initialize("test",hp,100,Game.prototype_rules,[{"id":"target","displayName":"target","maxHp":20,"intentSequence":[]}])
	model.draw_cards()
	return model

func _ready() -> void:
	Game.save_enabled = false
	var model := fresh()
	var uid: String = model.hand[0]
	model.card_catalog[model.instances[uid]].effects = [{"type":"damage","amount":1},{"type":"damage","amount":2}]
	model.next_attack_bonus = 2
	var result := model.play_card(uid,0)
	check(result.damage == 5 and result.hits.size() == 2,"Multi-hit total and event count")
	check(result.hits[0].damage == 3 and result.hits[0].hpAfter == 17 and result.hits[1].damage == 2 and result.hits[1].hpAfter == 15,"Bonus applies once; intermediate HP preserved")
	check(model.hand.size() == 4 and model.discard_pile == [uid] and model.next_attack_bonus == 0,"One card consumed")
	check(model.play_card(uid,0).is_empty(),"Replayed UID rejected")
	var snapshot := model.snapshot()
	var restored := CombatModel.new()
	restored.restore(snapshot)
	check(restored.snapshot() == snapshot,"Transient events do not require save migration")
	model = fresh(4)
	model.enemies[0].intent = {"type":"attack","amount":2,"hits":3}
	result = model.end_turn()
	check(result.attacks[0].hits.size() == 2,"Enemy multi-hit stops on lethal contact")
	check(result.attacks[0].hits[0].hpAfter == 2 and result.attacks[0].hits[1].hpAfter == 0 and result.attacks[0].hits[1].killed,"Enemy event HP and lethal flag")
	check(model.outcome == "lose" and model.player_hp == 0 and model.turn == 1,"No extra turn after lethal")
	model = fresh()
	model.enemies[0].intent = {"type":"attack","amount":0,"hits":1}
	result = model.end_turn()
	check(result.attacks[0].hits[0].damage == 0 and result.attacks[0].hits[0].blocked == 0,"Zero damage is not a successful block")
	model = fresh()
	uid = model.hand[0]
	model.enemies[0].hp = 1
	model.next_attack_bonus = 5
	result = model.play_card(uid,0)
	check(result.hits[0].damage == 1 and result.hits[0].killed and result.outcome == "win","Overkill displays actual HP loss")
	print("COMBAT HIT EVENTS: %d checks, %d failures" % [checks,failed])
	get_tree().quit(0 if failed == 0 else 1)
