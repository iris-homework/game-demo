class_name CombatModel
extends RefCounted
const CYBERWARE_LIMIT := 6
var buffs := preload("res://scripts/combat/effects/buff_library.gd").new()
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
# IDs on cooldown for this player turn; retained under the legacy save key.
var used_cyberware: Array = []
var next_attack_bonus := 0
var energy := 0
var block := 0
var stance := "melee"
var ammo := 0
var parry := 0
var exhaust_pile: Array = []
var powers: Array = []
var turn_damage_bonus := 0
var turn_discount := 0
var stance_discount := false
var pressure_used := false
var dissection_used := false
var opening_draw_done := false
# Only new definitions without legacy fields use this optional state.
var buff_state: Dictionary = {}

func is_noren() -> bool:
	return profile.get("ruleset", "") == "noren_v1"


func cyberware_cards() -> Array:
	# Older snapshots retain eight definitions for validating earned bonuses,
	# but only the first six are available in the current battle interface.
	return profile.get("cyberware", {}).get("cards", []).slice(0, CYBERWARE_LIMIT)

func available_cyberware_count() -> int:
	var available := 0
	for definition in cyberware_cards():
		if not definition.id in used_cyberware: available += 1
	return available

func activate_cyberware(id: String) -> bool:
	if not outcome.is_empty() or player_hp <= 0 or id in used_cyberware: return false
	for definition in cyberware_cards():
		if definition.id != id: continue
		var bonus := int(definition.get("nextAttackBonus", 0))
		if bonus <= 0: return false
		used_cyberware.append(id)
		buffs.apply(self, "technology", bonus)
		log_lines.append("%s 已激活，下次攻击伤害 +%d。" % [definition.name, next_attack_bonus])
		return true
	return false

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
	if is_noren():
		energy = int(profile.get("energyPerTurn", 3))
		stance = profile.get("initialStance", "melee")
		ammo = int(profile.get("initialAmmo", 2))
		if profile.get("shuffleInitialDeck", true): draw_pile.shuffle()
	for definition in enemy_defs:
		var enemy: Dictionary = definition.duplicate(true)
		enemy.maxHp = int(profile.enemyMaxHp) if enemy.get("maxHp") == null else int(enemy.maxHp)
		enemy.hp = enemy.maxHp
		if is_noren():
			enemy.block = int(enemy.get("block", 0))
			enemy.bleed = 0
			enemy.weak = 0
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

func draw_cards(amount: int = -1) -> Array:
	var drawn: Array = []
	if not outcome.is_empty(): return drawn
	opening_draw_done = true
	var desired := int(profile.get("handSize", 3)) if amount < 0 else hand.size() + amount
	while hand.size() < desired:
		if draw_pile.is_empty():
			if discard_pile.is_empty() or not profile.get("recycleDiscardWhenEmpty", true): break
			draw_pile = discard_pile.duplicate()
			discard_pile.clear()
			draw_pile.shuffle()
		var uid = draw_pile.pop_back()
		hand.append(uid)
		drawn.append(uid)
	return drawn

func play_card(uid: String, target_index: int = -1, discard_uid: String = "", extra_ammo: int = 0) -> Dictionary:
	if is_noren(): return play_noren_card(uid, target_index, discard_uid, extra_ammo)
	return play_legacy_card(uid, target_index)

func play_legacy_card(uid: String, target_index: int) -> Dictionary:
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
	var hits: Array = []
	# Apply once to the first damage effect of a valid attack, never per hit.
	var bonus := next_attack_bonus if definition.get("type", "") == "attack" else 0
	for effect in effects:
		var amount := mini(int(effect.amount) + bonus, int(enemies[target_index].hp))
		enemies[target_index].hp -= amount
		damage += amount
		hits.append({"damage":amount,"blocked":0,"hpAfter":enemies[target_index].hp,"killed":enemies[target_index].hp == 0})
		if bonus > 0:
			buffs.clear(self, "technology")
			bonus = 0
	hand.erase(uid)
	discard_pile.append(uid)
	log_lines.append("%s → %s，造成 %d 点伤害。" % [definition.name, enemies[target_index].displayName, damage])
	var alive := false
	for enemy in enemies:
		if enemy.hp > 0: alive = true
	if not alive: outcome = "win"
	return {"uid":uid, "target":target_index, "damage":damage, "hits":hits, "outcome":outcome}

func end_turn() -> Dictionary:
	if is_noren(): return end_noren_turn()
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
			var hits: Array = []
			for hit_index in int(intent.get("hits",1)):
				var loss := mini(player_hp,int(intent.get("amount",0)))
				player_hp = maxi(0,player_hp-loss)
				hits.append({"damage":loss,"blocked":0,"hpAfter":player_hp,"killed":player_hp == 0})
				if player_hp == 0: break
			attacks.append({"id":enemy.id, "damage":damage, "hits":hits})
			log_lines.append("%s 执行意图：攻击 %d。" % [enemy.displayName, damage])
		if player_hp == 0:
			outcome = "lose"
			break
	if outcome.is_empty():
		turn += 1
		used_cyberware.clear()
		for enemy in enemies:
			enemy.intentIndex += 1
			enemy.intent = intent_for(enemy, int(enemy.intentIndex))
	return {"discarded":discarded, "attacks":attacks, "drawn":draw_cards(), "outcome":outcome}

func use_item(_item_id: String, _target_index: int, _inventory: Dictionary, _catalog: Dictionary) -> Dictionary:
	# No item effect contract is approved yet. Fail closed; never invent an effect.
	return {"ok":false, "reason":"道具效果待设计；当前没有可使用道具。"}

func snapshot() -> Dictionary:
	var saved := {"battleId":battle_id,"turn":turn,"playerHp":player_hp,"maxHp":max_hp,"drawPile":draw_pile.duplicate(),"hand":hand.duplicate(),"discardPile":discard_pile.duplicate(),"instances":instances.duplicate(true),"enemies":enemies.duplicate(true),"outcome":outcome,"log":log_lines.slice(-30),"profile":profile.duplicate(true),"cardCatalog":card_catalog.duplicate(true),"usedCyberware":used_cyberware.duplicate(),"nextAttackBonus":next_attack_bonus,"norenState":{"energy":energy,"block":block,"stance":stance,"ammo":ammo,"parry":parry,"exhaustPile":exhaust_pile.duplicate(),"powers":powers.duplicate(),"turnDamageBonus":turn_damage_bonus,"turnDiscount":turn_discount,"stanceDiscount":stance_discount,"pressureUsed":pressure_used,"dissectionUsed":dissection_used},"openingDrawDone":opening_draw_done}
	if not buff_state.is_empty(): saved.buffs = buff_state.duplicate(true)
	return saved

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
	for enemy in enemies:
		if enemy.has("buffs"): enemy.buffs = buffs.restore_extra_state(enemy.buffs)
	outcome = data.outcome
	log_lines = data.log.duplicate()
	profile = data.profile.duplicate(true)
	card_catalog = data.cardCatalog.duplicate(true)
	used_cyberware = data.get("usedCyberware", []).duplicate()
	buff_state = buffs.restore_extra_state(data.get("buffs", {}))
	next_attack_bonus = int(data.get("nextAttackBonus", 0))

	var n: Dictionary = data.get("norenState", {})
	energy = int(n.get("energy", 0))
	block = int(n.get("block", 0))
	stance = n.get("stance", "melee")
	ammo = int(n.get("ammo", 0))
	parry = int(n.get("parry", 0))
	exhaust_pile = n.get("exhaustPile", []).duplicate()
	powers = n.get("powers", []).duplicate()
	turn_damage_bonus = int(n.get("turnDamageBonus", 0))
	turn_discount = int(n.get("turnDiscount", 0))
	stance_discount = n.get("stanceDiscount", false)
	pressure_used = n.get("pressureUsed", false)
	dissection_used = n.get("dissectionUsed", false)
	opening_draw_done = data.get("openingDrawDone", not (hand.is_empty() and turn == 1 and discard_pile.is_empty()))

func card_cost(uid: String) -> int:
	var definition := card(uid)
	var cost := int(definition.get("cost", 0)) if definition.get("cost") != null else 0
	if is_noren() and definition.get("type") == "attack":
		cost -= buffs.attack_discount(self)
	return maxi(0, cost)

func card_target(uid: String) -> String:
	var target: String = card(uid).get("target", "enemy")
	return ("enemy" if stance == "ranged" else "self") if target == "stance" else target

func discard_candidates(uid: String) -> Array:
	return hand.filter(func(other): return other != uid and card(other).get("type") == "attack")

func extra_ammo_limit(uid: String) -> int:
	return mini(maxi(0, ammo - 1), int(card(uid).get("extraAmmoMax", 0))) if stance == "ranged" else 0

func play_error(uid: String) -> String:
	if not outcome.is_empty() or not uid in hand: return "卡牌不在可用手牌中。"
	var definition := card(uid)
	if definition.is_empty(): return "卡牌定义无效。"
	if not is_noren(): return ""
	if energy < card_cost(uid): return "能量不足。"
	if definition.type == "attack" and stance == "ranged" and ammo < 1: return "弹药不足；先补弹或切回近战。"
	for effect in definition.get("effects", []):
		if effect.type == "discard_attack" and discard_candidates(uid).is_empty(): return "手中没有可弃置的攻击牌。"
	return ""

func change_stance(value: String) -> Array:
	if value == "toggle": value = "ranged" if stance == "melee" else "melee"
	if value == stance: return []
	stance = value
	if stance == "melee": return draw_cards(1)
	buffs.apply(self, "stance_discount")
	return []

func gain_ammo(amount: int) -> void:
	ammo = mini(int(profile.get("ammoCap", 6)), ammo + amount)

func enemy_damage(index: int, amount: int, bypass: bool = false) -> Dictionary:
	var enemy: Dictionary = enemies[index]
	var absorbed := 0 if bypass else mini(amount, int(enemy.get("block", 0)))
	enemy.block = int(enemy.get("block", 0)) - absorbed
	var loss := mini(maxi(0, amount - absorbed), int(enemy.hp))
	enemy.hp -= loss
	return {"target":index,"damage":loss,"blocked":absorbed,"hpAfter":enemy.hp,"blockAfter":enemy.block,"killed":enemy.hp == 0}

func apply_bleed(index: int, amount: int, card_stance: String, single: bool) -> void:
	buffs.apply(self, "bleed", amount, index, {"source":"card", "stance":card_stance, "single":single})

func resolve_outcome() -> void:
	if player_hp <= 0: outcome = "lose"
	elif enemies.all(func(enemy): return enemy.hp <= 0): outcome = "win"

func play_noren_card(uid: String, target_index: int, discard_uid: String, extra_ammo: int) -> Dictionary:
	if not play_error(uid).is_empty(): return {}
	var definition := card(uid)
	var target_kind := card_target(uid)
	if target_kind == "enemy" and (target_index < 0 or target_index >= enemies.size() or enemies[target_index].hp <= 0): return {}
	if extra_ammo < 0 or extra_ammo > extra_ammo_limit(uid): return {}
	var effects: Array = definition.get("effects", [])
	# Validate the complete transaction before spending resources or moving any card.
	var allowed := ["damage","ammo","draw","stance","discard_attack"]
	for effect in effects:
		if not effect is Dictionary: return {}
		if not effect.get("type", "") in allowed and not buffs.valid_card_effect(effect): return {}
		if effect.has("amount") and (not (effect.amount is int or effect.amount is float) or effect.amount < 0): return {}
		if effect.type == "discard_attack" and not discard_uid in discard_candidates(uid): return {}
	var at_start := stance
	var ammo_before := ammo
	var before := enemies.duplicate(true)
	var attack: bool = definition.type == "attack"
	var targets_to_hit: Array = []
	if target_kind == "all":
		for i in enemies.size():
			if enemies[i].hp > 0: targets_to_hit.append(i)
	elif target_kind == "enemy": targets_to_hit.append(target_index)
	var bonus := 0
	energy -= card_cost(uid)
	if attack:
		bonus = buffs.begin_attack(self, at_start)
		if at_start == "melee": gain_ammo(1)
		else: ammo -= 1 + extra_ammo
	hand.erase(uid)
	# Hold the resolving card outside all draw piles until its effects finish.
	var drawn: Array = []
	var discarded: Array = []
	var hits: Array = []
	var damage := 0
	for effect in effects:
		if effect.get("when", at_start) != at_start: continue
		if effect.has("requiresBleed") and (target_index < 0 or int(before[target_index].get("bleed", 0)) < int(effect.requiresBleed)): continue
		var amount := int(effect.get("amount", 0))
		match effect.type:
			"damage":
				for index in targets_to_hit:
					var count := int(effect.get("hits", 1))
					if at_start == "ranged" and effect.has("bleedExtraHit") and int(before[index].get("bleed", 0)) >= int(effect.bleedExtraHit): count += 1
					for segment in count:
						if enemies[index].hp <= 0: break
						var base := amount + (bonus if segment == 0 else 0)
						if at_start == "ranged":
							base += extra_ammo * int(definition.get("extraAmmoBonus", 0))
							if ammo_before == 1: base += int(effect.get("lastAmmoBonus", 0))
							if int(before[index].hp) * 2 <= int(before[index].maxHp): base += int(effect.get("executeBonus", 0))
						var hit := enemy_damage(index, roundi(base * (1.5 if at_start == "ranged" else 1.0)), at_start == "ranged" and effect.get("rangedIgnoreBlock", false))
						buffs.after_attack_hit(self, index, at_start, hit)
						damage += hit.damage
						hits.append(hit)
				bonus = 0
			"ammo": gain_ammo(amount)
			"draw": drawn.append_array(draw_cards(amount))
			"stance": drawn.append_array(change_stance(effect.value))
			"discard_attack":
				hand.erase(discard_uid)
				discard_pile.append(discard_uid)
				discarded.append(discard_uid)
			_:
				buffs.apply_card_effect(self, effect, targets_to_hit, {"stance":at_start, "before":before, "single":target_kind == "enemy"})
	var exhausted: bool = definition.get("exhaust", false) or definition.type == "power"
	if exhausted: exhaust_pile.append(uid)
	else: discard_pile.append(uid)
	resolve_outcome()
	log_lines.append("%s · %s · 伤害 %d" % [definition.name, "近战" if at_start == "melee" else "远程", damage])
	return {"uid":uid,"target":target_index,"damage":damage,"hits":hits,"drawn":drawn,"discarded":discarded,"exhausted":exhausted,"stance":at_start,"outcome":outcome}

func end_noren_turn() -> Dictionary:
	if not outcome.is_empty(): return {}
	var discarded := hand.duplicate()
	discard_pile.append_array(hand)
	hand.clear()
	buffs.player_turn_end(self)
	var attacks: Array = []
	for index in enemies.size():
		var enemy: Dictionary = enemies[index]
		if enemy.hp <= 0: continue
		buffs.own_turn_start(self, index)
		var intent: Dictionary = enemy.intent
		if intent.get("type", "") != "attack":
			buffs.own_turn_end(self, index)
			continue
		var per_hit := buffs.enemy_attack_damage(enemy, int(intent.get("amount", 0)))
		var total := per_hit * int(intent.get("hits", 1))
		var hits: Array = []
		var damage := 0
		for segment in int(intent.get("hits", 1)):
			var absorbed := mini(block, per_hit)
			block -= absorbed
			var loss := mini(player_hp, per_hit - absorbed)
			player_hp -= loss
			damage += loss
			hits.append({"damage":loss,"blocked":absorbed,"hpAfter":player_hp,"killed":player_hp == 0})
			if player_hp == 0: break
		var counters: Array = buffs.after_enemy_attack(self, index, total)
		attacks.append({"id":enemy.id,"damage":damage,"hits":hits,"counters":counters})
		buffs.own_turn_end(self, index)
		resolve_outcome()
		if not outcome.is_empty(): break
	if outcome.is_empty():
		turn += 1
		buffs.own_turn_start(self)
		energy = int(profile.get("energyPerTurn", 3))
		used_cyberware.clear()
		for enemy in enemies:
			enemy.intentIndex += 1
			enemy.intent = intent_for(enemy, int(enemy.intentIndex))
	return {"discarded":discarded,"attacks":attacks,"drawn":draw_cards(),"outcome":outcome}
