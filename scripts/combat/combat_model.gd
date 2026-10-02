class_name CombatModel
extends RefCounted
## Pure, serializable combat rules. Animation and scene navigation never live here.
var battle_id := ""
var turn := 1
var player_hp := 100
var max_hp := 100
var draw_pile: Array = []
var hand: Array = []
var discard_pile: Array = []
var instances: Dictionary = {}
var enemies: Array = []
var outcome := ""
var profile: Dictionary = {}
var card_catalog: Dictionary = {}
var log_lines: Array = []

func initialize(id: String, hp: int, maximum: int, rules: Dictionary, enemy_defs: Array, cards: Dictionary = {}) -> void:
	battle_id = id
	player_hp = hp
	max_hp = maximum
	profile = rules.duplicate(true)
	card_catalog = cards.duplicate(true)
	card_catalog.merge(profile.get("cards", {}), false)
	for i in profile.get("deck", []).size():
		var uid := "card_%03d" % i
		instances[uid] = profile.deck[i]
		draw_pile.append(uid)
	for definition in enemy_defs:
		var enemy: Dictionary = definition.duplicate(true)
		enemy.maxHp = int(profile.enemyMaxHp) if enemy.get("maxHp") == null else int(enemy.maxHp)
		enemy.hp = enemy.maxHp
		enemy.intentIndex = 0
		enemy.intent = intent_for(enemy, 0)
		enemies.append(enemy)
	if player_hp <= 0: outcome = "lose"
	log_lines.append("战斗连接已建立。")

func intent_for(enemy: Dictionary, index: int) -> Dictionary:
	var sequence: Array = enemy.get("intentSequence", [])
	return (profile.intent if sequence.is_empty() else sequence[index % sequence.size()]).duplicate(true)

func card(uid: String) -> Dictionary:
	return card_catalog.get(instances.get(uid, ""), {})

func draw_cards() -> Array:
	var drawn: Array = []
	if not outcome.is_empty(): return drawn
	while hand.size() < int(profile.get("handSize", 3)):
		if draw_pile.is_empty():
			if discard_pile.is_empty() or not profile.get("recycleDiscardWhenEmpty", true): break
			draw_pile = discard_pile.duplicate()
			discard_pile.clear()
			draw_pile.shuffle()
		var uid = draw_pile.pop_back()
		hand.append(uid)
		drawn.append(uid)
	return drawn

func play_card(uid: String, target_index: int) -> Dictionary:
	if not outcome.is_empty() or not uid in hand or target_index < 0 or target_index >= enemies.size(): return {}
	if enemies[target_index].hp <= 0: return {}
	var definition := card(uid)
	if definition.is_empty(): return {}
	var effects: Array = definition.get("effects", [])
	# Validate every effect before moving the card or changing HP.
	for effect in effects:
		if effect.get("type", "") != "damage" or not effect.get("amount") is float and not effect.get("amount") is int: return {}
		if effect.amount < 0: return {}
	var damage := 0
	for effect in effects:
		var amount := mini(int(effect.amount), int(enemies[target_index].hp))
		enemies[target_index].hp -= amount
		damage += amount
	hand.erase(uid)
	discard_pile.append(uid)
	log_lines.append("%s → %s，造成 %d 点伤害。" % [definition.name, enemies[target_index].displayName, damage])
	var alive := false
	for enemy in enemies:
		if enemy.hp > 0: alive = true
	if not alive: outcome = "win"
	return {"uid":uid, "target":target_index, "damage":damage, "outcome":outcome}

func end_turn() -> Dictionary:
	if not outcome.is_empty(): return {}
	var discarded := hand.duplicate()
	if profile.get("discardHandAtTurnEnd", true):
		discard_pile.append_array(hand)
		hand.clear()
	var attacks: Array = []
	for enemy in enemies:
		if enemy.hp <= 0: continue
		var intent: Dictionary = enemy.intent
		if intent.get("type", "") == "attack":
			var damage := int(intent.get("amount", 0)) * int(intent.get("hits", 1))
			player_hp = maxi(0, player_hp - damage)
			attacks.append({"id":enemy.id, "damage":damage})
			log_lines.append("%s 执行意图：攻击 %d。" % [enemy.displayName, damage])
		if player_hp == 0:
			outcome = "lose"
			break
	if outcome.is_empty():
		turn += 1
		for enemy in enemies:
			enemy.intentIndex += 1
			enemy.intent = intent_for(enemy, int(enemy.intentIndex))
	return {"discarded":discarded, "attacks":attacks, "drawn":draw_cards(), "outcome":outcome}

func use_item(_item_id: String, _target_index: int, _inventory: Dictionary, _catalog: Dictionary) -> Dictionary:
	# No item effect contract is approved yet. Fail closed; never invent an effect.
	return {"ok":false, "reason":"道具效果待设计；当前没有可使用道具。"}

func snapshot() -> Dictionary:
	return {"battleId":battle_id,"turn":turn,"playerHp":player_hp,"maxHp":max_hp,"drawPile":draw_pile.duplicate(),"hand":hand.duplicate(),"discardPile":discard_pile.duplicate(),"instances":instances.duplicate(true),"enemies":enemies.duplicate(true),"outcome":outcome,"log":log_lines.slice(-30),"profile":profile.duplicate(true),"cardCatalog":card_catalog.duplicate(true)}

func restore(data: Dictionary) -> void:
	battle_id = data.battleId
	turn = int(data.turn)
	player_hp = int(data.playerHp)
	max_hp = int(data.maxHp)
	draw_pile = data.drawPile.duplicate()
	hand = data.hand.duplicate()
	discard_pile = data.discardPile.duplicate()
	instances = data.instances.duplicate(true)
	enemies = data.enemies.duplicate(true)
	outcome = data.outcome
	log_lines = data.log.duplicate()
	profile = data.profile.duplicate(true)
	card_catalog = data.cardCatalog.duplicate(true)
