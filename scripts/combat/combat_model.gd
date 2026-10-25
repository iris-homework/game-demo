class_name CombatModel
extends RefCounted
## Transient notification only; snapshot and shuffle order remain unchanged.
signal discard_recycled(card_count: int, next_uid: String)
const CYBERWARE_LIMIT := 4
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
var encounter_phase := 1
var profile: Dictionary = {}
var card_catalog: Dictionary = {}
var log_lines: Array = []
# IDs on cooldown; retained under the legacy save key.
var used_cyberware: Array = []
var cyberware_cooldowns: Dictionary = {}
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
	# Older snapshots retain their definitions for validating earned bonuses,
	# but only the first four are available in the current battle interface.
	return profile.get("cyberware", {}).get("cards", []).slice(0, CYBERWARE_LIMIT)

func available_cyberware_count() -> int:
	var available := 0
	for definition in cyberware_cards():
		if cyberware_available(definition.id): available += 1
	return available

static func is_passive_cyberware(definition: Dictionary) -> bool:
	return definition.get("type", "active") == "passive"

func passive_technology_amount(effect: String) -> int:
	var amount := 0
	for definition in cyberware_cards():
		if is_passive_cyberware(definition) and valid_cyberware_definition(definition) and definition.get("effect") == effect:
			amount += int(definition.amount)
	return amount

static func valid_cyberware_definition(definition: Dictionary) -> bool:
	if not definition.get("id") is String or definition.id.is_empty() or not definition.get("name") is String: return false
	var kind = definition.get("type", "active")
	if kind not in ["active", "passive"]: return false
	if kind == "passive":
		if definition.has("cooldownTurns") or definition.has("nextAttackBonus"): return false
		var amount = definition.get("amount")
		return definition.get("effect") in ["victory_credits", "victory_heal", "opening_draw"] and (amount is int or amount is float) and is_finite(float(amount)) and amount > 0 and amount == floor(float(amount))
	var cooldown = definition.get("cooldownTurns", 1)
	if not (cooldown is int or cooldown is float) or not is_finite(float(cooldown)) or cooldown < 1 or cooldown != floor(float(cooldown)): return false
	match definition.get("effect", "next_attack_bonus"):
		"next_attack_bonus":
			var bonus = definition.get("nextAttackBonus")
			return (bonus is int or bonus is float) and is_finite(float(bonus)) and bonus > 0 and bonus == floor(float(bonus))
		"toggle_stance", "redraw_hand":
			return not definition.has("nextAttackBonus")
		"gain_energy":
			var amount = definition.get("amount")
			return not definition.has("nextAttackBonus") and (amount is int or amount is float) and is_finite(float(amount)) and amount > 0 and amount == floor(float(amount))
	return false

func cyberware_cooldown(id: String) -> int:
	return int(cyberware_cooldowns.get(id, 1 if id in used_cyberware else 0))

func cyberware_available(id: String) -> bool:
	if not outcome.is_empty() or player_hp <= 0 or cyberware_cooldown(id) > 0: return false
	for definition in cyberware_cards():
		if definition.id != id: continue
		if not valid_cyberware_definition(definition) or is_passive_cyberware(definition): return false
		return is_noren() or definition.get("effect", "next_attack_bonus") in ["next_attack_bonus", "redraw_hand"]
	return false

func advance_cyberware_cooldowns() -> void:
	for id in used_cyberware.duplicate():
		var remaining := cyberware_cooldown(id) - 1
		if remaining > 0:
			cyberware_cooldowns[id] = remaining
		else:
			cyberware_cooldowns.erase(id)
			used_cyberware.erase(id)

func activate_cyberware(id: String) -> bool:
	if not cyberware_available(id): return false
	for definition in cyberware_cards():
		if definition.id != id: continue
		match definition.get("effect", "next_attack_bonus"):
			"next_attack_bonus": buffs.apply(self, "technology", int(definition.nextAttackBonus))
			"toggle_stance": change_stance("toggle")
			"redraw_hand":
				var amount := hand.size()
				discard_pile.append_array(hand)
				hand.clear()
				draw_cards(amount)
			"gain_energy": energy += int(definition.amount)
		used_cyberware.append(id)
		cyberware_cooldowns[id] = int(definition.get("cooldownTurns", 1))
		log_lines.append("%s 已激活：%s" % [definition.name, definition.get("description", "下次攻击伤害增加。")])
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
		enemies.append(enemy)
	for enemy in enemies:
		enemy.intent = intent_for(enemy, 0)
	if player_hp <= 0: outcome = "lose"
	log_lines.append("战斗连接已建立。")

func intent_for(enemy: Dictionary, index: int) -> Dictionary:
	var sequence: Array = enemy.get("intentSequence", [])
	if enemy.get("intentPhase", "") == "ally_death": sequence = enemy.get("allyDeathIntentSequence", {}).get("sequence", sequence)
	return (profile.intent if sequence.is_empty() else sequence[index % sequence.size()]).duplicate(true)

func begin_round_intents() -> Array:
	# A full round is player actions followed by enemy actions.
	# Check only before the next player phase, after all enemy actions finish.
	# Phase and index travel with the snapshot and never reset a second time.
	var changes: Array = []
	for index in enemies.size():
		var enemy: Dictionary = enemies[index]
		if enemy.hp <= 0 or not enemy.has("allyDeathIntentSequence") or enemy.get("intentPhase", "") == "ally_death": continue
		var watched: Array = enemy.allyDeathIntentSequence.get("allyIds", [])
		if enemies.any(func(ally): return ally.id in watched and ally.hp <= 0):
			enemy.intentPhase = "ally_death"
			enemy.intentIndex = 0
			enemy.intent = intent_for(enemy, 0)
			changes.append({"type":"intent_change", "target":index, "intent":enemy.intent.duplicate(true), "intentIndex":0, "intentPhase":"ally_death"})
	return changes

func enemy_intent_damage(enemy: Dictionary, after_player_turn_end: bool = true, vulnerable_layers: int = -1) -> int:
	var amount := buffs.enemy_attack_damage(enemy, int(enemy.get("intent", {}).get("amount", 0)))
	# During the player's turn, show the amount that will actually be used after
	# their own turn-end decay, without changing any live status or intent state.
	# Playback supplies the displayed status because the live model has already
	# resolved every enemy action. Negative means the ordinary live-state preview.
	var layers := buffs.count(self, "vulnerable") if vulnerable_layers < 0 else vulnerable_layers
	layers -= 1 if after_player_turn_end else 0
	return roundi(amount * (1.5 if layers > 0 else 1.0))

func card(uid: String) -> Dictionary:
	return card_catalog.get(instances.get(uid, ""), {})

func card_preview(uid: String, target_index: int = -1, extra_ammo: int = -1) -> Dictionary:
	return preload("res://scripts/combat/card_preview.gd").build(self, uid, target_index, extra_ammo)

func enemy_intent_text(enemy: Dictionary, after_player_turn_end: bool = true, vulnerable_layers: int = -1) -> String:
	var intent: Dictionary = enemy.get("intent", {})
	if intent.get("type", "") == "pollution": return "污染 %d" % int(intent.get("amount", 0))
	if intent.get("type", "") == "vulnerable": return "易伤 %d" % int(intent.get("amount", 0))
	if intent.get("type", "") == "strength_allies": return "强化 +%d" % int(intent.get("amount", 0))
	if intent.get("type", "") != "attack": return str(intent.get("description", "非攻击行动"))
	var amount := int(intent.get("amount", 0))
	if is_noren(): amount = enemy_intent_damage(enemy, after_player_turn_end, vulnerable_layers)
	return "攻击 %d" % amount + (" ×%d" % int(intent.hits) if int(intent.get("hits", 1)) > 1 else "")

func attack_hit_count(effect: Dictionary, form: String, enemy_before: Dictionary, ammo_before: int = 0) -> int:
	if form == "ranged" and effect.get("allAmmoHits",false): return 1 + ammo_before
	return int(effect.get("hits", 1)) + (1 if form == "ranged" and effect.has("bleedExtraHit") and int(enemy_before.get("bleed", 0)) >= int(effect.bleedExtraHit) else 0)

func attack_hit_amount(definition: Dictionary, effect: Dictionary, form: String, ammo_before: int, enemy_before: Dictionary, bonus: int, extra: int) -> int:
	var base := int(effect.get("amount", 0)) + bonus + (buffs.count(self, "strength") if definition.get("type", "") == "attack" else 0)
	if form == "ranged":
		base += int(effect.get("rangedBonus",0))
		base += extra * int(definition.get("extraAmmoBonus", 0))
		if ammo_before == 1: base += int(effect.get("lastAmmoBonus", 0))
		if int(enemy_before.hp) * 2 <= int(enemy_before.maxHp): base += int(effect.get("executeBonus", 0))
	var multiplier := (2.0 if buffs.count(self,"ranged_mastery") > 0 else 1.5) if form == "ranged" else 1.0
	return roundi(maxi(0, base) * multiplier)

func draw_cards(amount: int = -1) -> Array:
	var drawn: Array = []
	if not outcome.is_empty(): return drawn
	var opening_bonus := passive_technology_amount("opening_draw") if not opening_draw_done and turn == 1 else 0
	opening_draw_done = true
	var desired := (int(profile.get("handSize", 3)) if amount < 0 else hand.size() + amount) + opening_bonus
	while hand.size() < desired:
		if draw_pile.is_empty():
			if discard_pile.is_empty() or not profile.get("recycleDiscardWhenEmpty", true): break
			draw_pile = discard_pile.duplicate()
			discard_pile.clear()
			draw_pile.shuffle()
			discard_recycled.emit(draw_pile.size(), str(draw_pile.back()))
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
	var transition: Dictionary = {}
	var phase_changed := advance_encounter_phase(false, transition)
	return {"phaseChanged":phase_changed,"phaseTurnEvents":transition.get("turnEvents", []),"uid":uid, "target":target_index, "damage":damage, "hits":hits,"discarded":transition.get("discarded", []),"drawn":transition.get("drawn", []), "outcome":outcome}

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
	var transition: Dictionary = {}
	var phase_changed := advance_encounter_phase(true, transition)
	if outcome.is_empty() and not phase_changed:
		turn += 1
		advance_cyberware_cooldowns()
		for enemy in enemies:
			enemy.intentIndex += 1
			enemy.intent = intent_for(enemy, int(enemy.intentIndex))
	var drawn: Array = transition.drawn if phase_changed else draw_cards()
	return {"phaseChanged":phase_changed,"discarded":discarded, "attacks":attacks, "drawn":drawn, "outcome":outcome}

func use_item(_item_id: String, _target_index: int, _inventory: Dictionary, _catalog: Dictionary) -> Dictionary:
	# No item effect contract is approved yet. Fail closed; never invent an effect.
	return {"ok":false, "reason":"道具效果待设计；当前没有可使用道具。"}

func snapshot() -> Dictionary:
	var saved := {"battleId":battle_id,"turn":turn,"playerHp":player_hp,"maxHp":max_hp,"drawPile":draw_pile.duplicate(),"hand":hand.duplicate(),"discardPile":discard_pile.duplicate(),"instances":instances.duplicate(true),"enemies":enemies.duplicate(true),"outcome":outcome,"log":log_lines.slice(-30),"profile":profile.duplicate(true),"cardCatalog":card_catalog.duplicate(true),"usedCyberware":used_cyberware.duplicate(),"nextAttackBonus":next_attack_bonus,"norenState":{"energy":energy,"block":block,"stance":stance,"ammo":ammo,"parry":parry,"exhaustPile":exhaust_pile.duplicate(),"powers":powers.duplicate(),"turnDamageBonus":turn_damage_bonus,"turnDiscount":turn_discount,"stanceDiscount":stance_discount,"pressureUsed":pressure_used,"dissectionUsed":dissection_used},"openingDrawDone":opening_draw_done}
	if profile.get("encounterId", "") == "dancer_duet": saved.encounterPhase = encounter_phase
	if not buff_state.is_empty(): saved.buffs = buff_state.duplicate(true)
	if not cyberware_cooldowns.is_empty(): saved.cyberwareCooldowns = cyberware_cooldowns.duplicate()
	return saved

func restore(data: Dictionary) -> void:
	encounter_phase = int(data.get("encounterPhase", 1))
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
	cyberware_cooldowns = data.get("cyberwareCooldowns", {}).duplicate()
	if not data.has("cyberwareCooldowns"):
		for id in used_cyberware: cyberware_cooldowns[id] = 1
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

func exhaust_candidates(uid: String) -> Array:
	return hand.filter(func(other): return other != uid)

func extra_ammo_limit(uid: String) -> int:
	if card(uid).get("consumeAllAmmo",false): return 0
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
		if effect.type == "exhaust_hand" and exhaust_candidates(uid).is_empty(): return "手中没有其他可消耗的牌。"
	return ""

func change_stance(value: String) -> Array:
	if value == "toggle": value = "ranged" if stance == "melee" else "melee"
	if value == stance: return []
	stance = value
	if stance == "melee": return draw_cards(2)
	buffs.apply(self, "stance_discount")
	return []

func gain_ammo(amount: int) -> void:
	ammo = mini(int(profile.get("ammoCap", 10)), ammo + amount)

func enemy_damage(index: int, amount: int, bypass: bool = false, attack_damage: bool = false) -> Dictionary:
	var enemy: Dictionary = enemies[index]
	amount = buffs.incoming_damage(self, amount, index) if attack_damage else maxi(0, amount)
	var absorbed := 0 if bypass else mini(amount, int(enemy.get("block", 0)))
	enemy.block = int(enemy.get("block", 0)) - absorbed
	var loss := mini(maxi(0, amount - absorbed), int(enemy.hp))
	enemy.hp -= loss
	# Only an alive-to-dead transition triggers death effects, for every damage source.
	var death_pollution := int(enemy.get("deathPollution",0)) if loss > 0 and enemy.hp == 0 else 0
	if death_pollution > 0:
		buffs.apply(self,"pollution",death_pollution)
		log_lines.append("%s 死亡，向角色施加 %d 层污染。" % [enemy.displayName,death_pollution])
	return {"target":index,"damage":loss,"blocked":absorbed,"hpAfter":enemy.hp,"blockAfter":enemy.block,"killed":enemy.hp == 0,"deathPollution":death_pollution,"playerPollutionAfter":buffs.count(self,"pollution")}

func player_damage(amount: int, attack_damage: bool = false) -> Dictionary:
	if attack_damage: amount = buffs.incoming_damage(self, amount)
	var absorbed := mini(block, maxi(0, amount))
	block -= absorbed
	var loss := mini(player_hp, maxi(0, amount - absorbed))
	player_hp -= loss
	return {"target":-1,"damage":loss,"blocked":absorbed,"hpAfter":player_hp,"blockAfter":block,"killed":player_hp == 0}

func apply_bleed(index: int, amount: int, card_stance: String, single: bool) -> void:
	buffs.apply(self, "bleed", amount, index, {"source":"card", "stance":card_stance, "single":single})

func resolve_outcome() -> void:
	if player_hp <= 0: outcome = "lose"
	elif enemies.all(func(enemy): return enemy.hp <= 0): outcome = "win"

func advance_encounter_phase(player_turn_ended: bool = false, transition: Dictionary = {}) -> bool:
	# Resolve only at whole-card / whole-turn boundaries. A killing AoE, bleed,
	# counter or multi-hit never spills into the newly spawned second phase.
	if player_hp <= 0:
		outcome = "lose"
		return false
	if outcome != "win" or encounter_phase != 1 or profile.get("encounterId", "") != "dancer_duet": return false
	transition.discarded = []
	transition.drawn = []
	transition.turnEvents = []
	if not player_turn_ended:
		# A card finishes in the old encounter before the old player turn closes.
		# The end-turn caller has already done both operations and must not repeat them.
		transition.discarded = hand.duplicate()
		discard_pile.append_array(hand)
		hand.clear()
		transition.turnEvents = buffs.player_turn_end(self)
		resolve_outcome()
		if player_hp <= 0: return false
	encounter_phase = 2
	outcome = ""
	enemies.clear()
	for definition in profile.phaseTwoEnemies:
		var enemy: Dictionary = definition.duplicate(true)
		enemy.hp = int(enemy.maxHp)
		enemy.block = 0
		enemy.bleed = 0
		enemy.weak = 0
		enemy.erase("buffs")
		enemy.intentIndex = 0
		enemy.intent = intent_for(enemy, 0)
		enemies.append(enemy)
	turn += 1
	buffs.own_turn_start(self)
	energy = int(profile.get("energyPerTurn", 3))
	advance_cyberware_cooldowns()
	transition.drawn = draw_cards()
	log_lines.append("灯光熄灭。双人舞者 · 第二幕。")
	return true

func play_noren_card(uid: String, target_index: int, discard_uid: String, extra_ammo: int) -> Dictionary:
	if not play_error(uid).is_empty(): return {}
	var definition := card(uid)
	var target_kind := card_target(uid)
	if target_kind == "enemy" and (target_index < 0 or target_index >= enemies.size() or enemies[target_index].hp <= 0): return {}
	if extra_ammo < 0 or extra_ammo > extra_ammo_limit(uid): return {}
	var effects: Array = definition.get("effects", [])
	if definition.has("consumeAllAmmo") and not definition.consumeAllAmmo is bool: return {}
	# Validate the complete transaction before spending resources or moving any card.
	var allowed := ["damage","ammo","draw","stance","discard_attack","exhaust_hand"]
	for effect in effects:
		if not effect is Dictionary: return {}
		if not effect.get("type", "") in allowed and not buffs.valid_card_effect(effect): return {}
		if effect.has("amount"):
			if not (effect.amount is int or effect.amount is float): return {}
			if effect.amount < 0 and not (effect.get("id", effect.type) == "strength" and buffs.valid_card_effect(effect)): return {}
		if effect.type == "discard_attack" and not discard_uid in discard_candidates(uid): return {}
		if effect.type == "exhaust_hand" and not discard_uid in exhaust_candidates(uid): return {}
		if effect.has("allAmmoHits") and not effect.allAmmoHits is bool: return {}
		for key in ["bleedTriggers","rangedBonus"]:
			if effect.has(key) and (not (effect[key] is int or effect[key] is float) or not is_finite(float(effect[key])) or effect[key] < 0 or effect[key] != floor(float(effect[key]))): return {}
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
	var segment_bonus := 0
	energy -= card_cost(uid)
	if attack:
		segment_bonus = buffs.attack_segment_bonus(self)
		bonus = buffs.begin_attack(self, at_start)
		if at_start == "ranged": ammo = 0 if definition.get("consumeAllAmmo",false) else ammo - 1 - extra_ammo
	hand.erase(uid)
	# Hold the resolving card outside all draw piles until its effects finish.
	var drawn: Array = []
	var discarded: Array = []
	var exhausted_cards: Array = []
	var hits: Array = []
	var damage := 0
	for effect in effects:
		if effect.get("when", at_start) != at_start: continue
		if effect.has("requiresBleed") and (target_index < 0 or int(before[target_index].get("bleed", 0)) < int(effect.requiresBleed)): continue
		var amount := int(effect.get("amount", 0))
		match effect.type:
			"damage":
				var ammo_segments := 0
				for index in targets_to_hit:
					var count := attack_hit_count(effect, at_start, before[index],ammo_before)
					for segment in count:
						if enemies[index].hp <= 0: break
						var amount_per_hit := attack_hit_amount(definition, effect, at_start, ammo_before, before[index], segment_bonus + (bonus if segment == 0 else 0), extra_ammo)
						var hit := enemy_damage(index, amount_per_hit, at_start == "ranged" and effect.get("rangedIgnoreBlock", false), attack)
						buffs.after_attack_hit(self, index, at_start, hit,int(effect.get("bleedTriggers",-1)))
						if attack and at_start == "melee":
							# A shared AoE segment grants ammo only once across its targets.
							if segment >= ammo_segments:
								gain_ammo(1)
								ammo_segments = segment + 1
							hit.ammoAfter = ammo
						damage += hit.damage
						hits.append(hit)
				bonus = 0
			"ammo": gain_ammo(amount)
			"draw": drawn.append_array(draw_cards(amount))
			"stance": drawn.append_array(change_stance(effect.value))
			"exhaust_hand":
				hand.erase(discard_uid)
				exhaust_pile.append(discard_uid)
				exhausted_cards.append(discard_uid)
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
	var transition: Dictionary = {}
	var phase_changed := advance_encounter_phase(false, transition)
	if transition.has("drawn"):
		# Mid-card draws belong to the closed turn and have just been discarded.
		drawn = transition.drawn
		discarded.append_array(transition.discarded)
	log_lines.append("%s · %s · 伤害 %d" % [definition.name, "近战" if at_start == "melee" else "远程", damage])
	return {"phaseChanged":phase_changed,"phaseTurnEvents":transition.get("turnEvents", []),"uid":uid,"target":target_index,"damage":damage,"hits":hits,"drawn":drawn,"discarded":discarded,"exhaustedCards":exhausted_cards,"exhausted":exhausted,"stance":at_start,"outcome":outcome}

func end_noren_turn() -> Dictionary:
	if not outcome.is_empty(): return {}
	var discarded := hand.duplicate()
	discard_pile.append_array(hand)
	hand.clear()
	var turn_events: Array = buffs.player_turn_end(self)
	resolve_outcome()
	var attacks: Array = []
	for index in enemies.size():
		if not outcome.is_empty(): break
		var enemy: Dictionary = enemies[index]
		if enemy.hp <= 0: continue
		buffs.own_turn_start(self, index)
		var intent: Dictionary = enemy.intent
		if intent.get("type", "") != "attack":
			var kind: String = intent.get("type", "")
			var amount := int(intent.get("amount", 0))
			if kind in ["pollution", "vulnerable"]:
				buffs.apply(self, kind, amount)
				turn_events.append({"type":"status_apply","source":index,"target":-1,"buffId":kind,"amount":amount,"stacksAfter":buffs.count(self, kind)})
				log_lines.append("%s 施加 %d 层%s。" % [enemy.displayName, amount, buffs.definition(kind).name])
			elif kind == "strength_allies":
				for ally_index in enemies.size():
					if enemies[ally_index].hp <= 0 or not enemies[ally_index].id in intent.get("targetIds", []): continue
					buffs.apply(self, "strength", amount, ally_index)
					turn_events.append({"type":"status_apply","source":index,"target":ally_index,"buffId":"strength","amount":amount,"stacksAfter":buffs.count(self, "strength", ally_index)})
				log_lines.append("%s 强化小弟，力量 +%d。" % [enemy.displayName, amount])
			turn_events.append_array(buffs.own_turn_end(self, index))
			resolve_outcome()
			continue
		var per_hit := buffs.enemy_attack_damage(enemy, int(intent.get("amount", 0)))
		var total := buffs.incoming_damage(self, per_hit) * int(intent.get("hits", 1))
		var hits: Array = []
		var damage := 0
		for segment in int(intent.get("hits", 1)):
			var hit := player_damage(per_hit, true)
			if hit.damage > 0:
				buffs.apply(self, "pollution", int(enemy.get("attackPollution", 0)))
			hit.pollutionAfter = buffs.count(self, "pollution")
			damage += hit.damage
			hits.append(hit)
			if player_hp == 0: break
		var counters: Array = buffs.after_enemy_attack(self, index, total)
		var attack := {"type":"attack","index":index,"id":enemy.id,"damage":damage,"hits":hits,"counters":counters}
		attacks.append(attack)
		turn_events.append(attack)
		turn_events.append_array(buffs.own_turn_end(self, index))
		resolve_outcome()
		if not outcome.is_empty(): break
	var transition: Dictionary = {}
	var phase_changed := advance_encounter_phase(true, transition)
	if outcome.is_empty() and not phase_changed:
		turn += 1
		buffs.own_turn_start(self)
		energy = int(profile.get("energyPerTurn", 3))
		advance_cyberware_cooldowns()
		for enemy in enemies:
			enemy.intentIndex += 1
			enemy.intent = intent_for(enemy, int(enemy.intentIndex))
		turn_events.append_array(begin_round_intents())
	var drawn: Array = transition.drawn if phase_changed else draw_cards()
	return {"phaseChanged":phase_changed,"discarded":discarded,"attacks":attacks,"turnEvents":turn_events,"drawn":drawn,"outcome":outcome}
