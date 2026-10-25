class_name CombatBuffs
extends RefCounted
## Shared status catalog, model-only rules, save validation and read-only display.
## Each owner holds a RefCounted library; its cache is released with the owner.
## Existing fields stay on CombatModel for snapshot/API compatibility. New simple
## statuses may omit `field` to use its optional buff_state / enemy.buffs storage.
const CATALOG_PATH := "res://data/buffs/buffs.json"
const POSITIVE := "positive"
const NEGATIVE := "negative"
var _catalog: Dictionary = {}

func _definitions() -> Dictionary:
	if _catalog.is_empty():
		var rows = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		var errors := catalog_errors(rows)
		if not errors.is_empty():
			push_error("Invalid buff catalog: " + "; ".join(errors))
			return {}
		for entry in rows:
			_catalog[entry.id] = entry
	return _catalog

func catalog_errors(rows) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not rows is Array: return ["Expected an array"]
	var seen: Array = []
	for entry in rows:
		if not entry is Dictionary:
			errors.append("Expected an object")
			continue
		var missing := false
		for key in ["id", "name", "category", "target", "stacking", "duration", "handler", "icon", "color", "description"]:
			if not entry.get(key) is String or entry.get(key, "").is_empty():
				errors.append("Missing string: " + key)
				missing = true
		if missing: continue
		if entry.id in seen: errors.append("Duplicate: " + entry.id)
		seen.append(entry.id)
		if entry.category not in [POSITIVE, NEGATIVE]: errors.append(entry.id + ": invalid category")
		if entry.target not in ["player", "enemy", "both"]: errors.append(entry.id + ": invalid target")
		if entry.stacking not in ["add", "guarded_add", "flag", "unique"]: errors.append(entry.id + ": invalid stacking")
		if entry.duration not in ["battle", "player_turn_end", "own_turn_start", "own_turn_end_decay"]: errors.append(entry.id + ": invalid duration")
		if entry.handler not in ["block", "bleed", "weak", "pollution", "vulnerable", "strength", "parry", "energy_suit", "electric_charge", "attack_bonus", "attack_discount", "high_pressure", "dissection", "none"]: errors.append(entry.id + ": implement handler first")
		if entry.handler in ["block", "bleed", "weak", "pollution", "vulnerable", "strength", "parry", "energy_suit", "electric_charge", "high_pressure", "dissection"] and entry.id != entry.handler: errors.append(entry.id + ": specialized handler requires its canonical ID")
		if entry.handler in ["energy_suit", "electric_charge"] and entry.target != "enemy": errors.append(entry.id + ": currently requires enemy target")
		if entry.handler in ["attack_bonus", "attack_discount"] and entry.target != "player": errors.append(entry.id + ": attack modifier currently requires player target")
		if not entry.get("showBadge") is bool or not Color.html_is_valid(entry.color): errors.append(entry.id + ": invalid display")
		if entry.has("maxStacks") and not _valid_count(entry.maxStacks): errors.append(entry.id + ": invalid maximum")
		if entry.has("minStacks"):
			if not _valid_count(entry.minStacks, -1, -999) or entry.minStacks > entry.get("maxStacks", 0): errors.append(entry.id + ": invalid minimum")
			elif entry.minStacks < 0 and entry.handler != "strength": errors.append(entry.id + ": signed stacks require strength handler")
		if entry.has("consumeOnAttack") and not entry.consumeOnAttack is bool: errors.append(entry.id + ": invalid consumption flag")
		if entry.has("everyHit") and (not entry.everyHit is bool or entry.handler != "attack_bonus"): errors.append(entry.id + ": invalid every-hit modifier")
	return errors

func definition(id: String) -> Dictionary:
	return _definitions().get(id, {}).duplicate(true)

func definitions(category: String = "") -> Array:
	var result: Array = []
	for entry in _definitions().values():
		if category.is_empty() or entry.category == category: result.append(entry.duplicate(true))
	return result

func has(id: String) -> bool:
	return _definitions().has(id)

func accepts(id: String, enemy_index: int) -> bool:
	if not has(id): return false
	return _definitions()[id].target in ["both", "enemy" if enemy_index >= 0 else "player"]

func count(model, id: String, enemy_index: int = -1) -> int:
	if not accepts(id, enemy_index): return 0
	var entry: Dictionary = _definitions()[id]
	if enemy_index >= 0:
		if enemy_index >= model.enemies.size(): return 0
		return enemy_count(model.enemies[enemy_index], entry)
	if entry.get("field", "").is_empty(): return int(model.buff_state.get(id, 0))
	if entry.stacking == "unique": return 1 if id in model.powers else 0
	return int(model.get(entry.field))

func enemy_count(enemy: Dictionary, entry: Dictionary) -> int:
	if entry.get("field", "").is_empty(): return int(enemy.get("buffs", {}).get(entry.id, 0))
	return int(enemy.get(entry.field, 0))

func _write_count(model, id: String, value: int, enemy_index: int = -1) -> void:
	var entry: Dictionary = _definitions()[id]
	var field: String = entry.get("field", "")
	if enemy_index >= 0:
		var enemy: Dictionary = model.enemies[enemy_index]
		if not field.is_empty(): enemy[field] = value
		elif value != 0:
			if not enemy.has("buffs"): enemy.buffs = {}
			enemy.buffs[id] = value
		elif enemy.has("buffs"):
			enemy.buffs.erase(id)
			if enemy.buffs.is_empty(): enemy.erase("buffs")
	elif field.is_empty():
		if value != 0: model.buff_state[id] = value
		else: model.buff_state.erase(id)
	elif entry.stacking == "unique":
		if value > 0 and not id in model.powers: model.powers.append(id)
		elif value == 0: model.powers.erase(id)
	elif entry.stacking == "flag": model.set(field, value > 0)
	else: model.set(field, value)

func apply(model, id: String, amount: int = 1, enemy_index: int = -1, context: Dictionary = {}) -> bool:
	if not accepts(id, enemy_index): return false
	if amount < 0 and int(_definitions()[id].get("minStacks", 0)) >= 0: return false
	if enemy_index >= 0 and (enemy_index >= model.enemies.size() or model.enemies[enemy_index].hp <= 0): return false
	var entry: Dictionary = _definitions()[id]
	var current := count(model, id, enemy_index)
	if entry.handler == "bleed" and context.get("source", "") == "card":
		var form: String = context.get("stance", model.stance)
		if form == "ranged": amount = roundi(amount * 0.5)
		if amount > 0 and form == "melee" and context.get("single", false) and count(model, "dissection") > 0 and not model.dissection_used:
			amount += 1
			model.dissection_used = true
	var value := current + amount
	if context.get("fill", false): value = maxi(current, amount)
	elif entry.stacking == "guarded_add":
		# Keep each card's pre-add condition; parry also has a global cap below.
		if current >= int(context.get("cap", entry.get("maxStacks", 3))): return true
	elif entry.stacking in ["unique", "flag"]: value = 1
	elif entry.has("maxStacks"): value = mini(int(entry.maxStacks), value)
	if entry.id == "parry": value = mini(int(entry.get("maxStacks", 3)), value)
	value = maxi(int(entry.get("minStacks", 0)), value)
	_write_count(model, id, value, enemy_index)
	return true

func clear(model, id: String, enemy_index: int = -1) -> void:
	if accepts(id, enemy_index) and enemy_index < model.enemies.size(): _write_count(model, id, 0, enemy_index)

func is_card_effect(kind: String) -> bool:
	return has(kind) or kind in ["parry_fill", "power", "buff"]

func valid_card_effect(effect: Dictionary) -> bool:
	var kind: String = effect.get("type", "")
	if kind == "power":
		return has(str(effect.get("value", ""))) and _definitions()[effect.value].stacking == "unique"
	var id: String = str(effect.get("id", "")) if kind == "buff" else ("parry" if kind == "parry_fill" else kind)
	if not has(id): return false
	var entry: Dictionary = _definitions()[id]
	if not entry.get("cardApply", true): return false
	var target = effect.get("buffTarget", "player" if entry.target == "both" else entry.target)
	return target in ["player", "enemy"] and entry.target in ["both", target]

func apply_card_effect(model, effect: Dictionary, targets: Array, context: Dictionary) -> void:
	var kind: String = effect.type
	var id: String = effect.get("id", "") if kind == "buff" else kind
	if kind == "power": id = effect.value
	if kind == "parry_fill": id = "parry"
	var entry: Dictionary = _definitions()[id]
	var amount := int(effect.get("amount", 1 if entry.stacking == "unique" else 0))
	var options := context.duplicate()
	options.source = "card"
	if effect.has("cap"): options.cap = effect.cap
	if kind == "parry_fill": options.fill = true
	# block has always targeted the player, including enemy-targeting skill cards.
	var target: String = effect.get("buffTarget", "player" if entry.target == "both" else entry.target)
	if target == "player": apply(model, id, amount, -1, options)
	else:
		for index in targets:
			var stacks := amount
			if entry.handler == "bleed" and context.stance == "melee" and int(context.before[index].get("bleed", 0)) > 0:
				stacks = int(effect.get("woundedMeleeAmount", amount))
			apply(model, id, stacks, index, options)

func attack_discount(model) -> int:
	var reduction := 0
	for entry in _definitions().values():
		if entry.handler == "attack_discount": reduction += count(model, entry.id)
	return reduction

func begin_attack(model, form: String) -> int:
	var bonus := 0
	for entry in _definitions().values():
		if entry.handler == "attack_bonus" and not entry.get("everyHit", false): bonus += count(model, entry.id)
		if entry.get("consumeOnAttack", false): clear(model, entry.id)
	if form == "ranged" and count(model, "high_pressure") > 0 and not model.pressure_used:
		bonus += 3
		model.pressure_used = true
	return bonus

func attack_segment_bonus(model) -> int:
	var bonus := 0
	for entry in _definitions().values():
		if entry.handler == "attack_bonus" and entry.get("everyHit", false): bonus += count(model,entry.id)
	return bonus

func after_attack_hit(model, index: int, form: String, hit: Dictionary, triggers: int = -1) -> void:
	hit.attackDamage = hit.damage
	hit.bleedDamage = 0
	var times := triggers if triggers >= 0 else (1 if form == "ranged" else 0)
	for tick in times:
		if model.enemies[index].hp <= 0 or count(model,"bleed",index) <= 0: break
		var bleeding: Dictionary = model.enemy_damage(index, count(model, "bleed", index))
		if count(model,"persistent_bleed") == 0: _write_count(model, "bleed", count(model, "bleed", index) - 1, index)
		hit.bleedDamage += bleeding.damage
		hit.damage += bleeding.damage
		hit.blocked += bleeding.blocked
		hit.hpAfter = bleeding.hpAfter
		hit.blockAfter = bleeding.blockAfter
		hit.killed = bleeding.killed
		hit.deathPollution = int(hit.get("deathPollution",0)) + int(bleeding.get("deathPollution",0))
		hit.playerPollutionAfter = bleeding.playerPollutionAfter
	hit.bleedAfter = count(model, "bleed", index)

func enemy_attack_damage(enemy: Dictionary, amount: int) -> int:
	var strength := definition("strength")
	var charge := enemy_count(enemy, definition("electric_charge"))
	var base := maxi(0, amount + (enemy_count(enemy, strength) if not strength.is_empty() else 0) + charge)
	return roundi(base * (0.75 if int(enemy.get("weak", 0)) > 0 else 1.0))

func after_incoming_attack(model, enemy_index: int, hp_loss: int) -> void:
	if count(model, "energy_suit", enemy_index) > 0:
		if hp_loss > 0: apply(model, "electric_charge", 1, enemy_index)
		return
	var layers := count(model, "electric_charge", enemy_index)
	if layers > 0: _write_count(model, "electric_charge", layers - 1, enemy_index)

func incoming_damage(model, amount: int, enemy_index: int = -1) -> int:
	return roundi(maxi(0, amount) * (1.5 if count(model, "vulnerable", enemy_index) > 0 else 1.0))

func after_enemy_attack(model, index: int, total: int) -> Array:
	var counters: Array = []
	var layers := count(model, "parry")
	if layers > 0 and model.enemies[index].hp > 0:
		var counter: Dictionary = model.enemy_damage(index, roundi(total * 0.5))
		model.gain_ammo(1)
		counter.ammoAfter = model.ammo
		counter.bleedAfter = count(model, "bleed", index)
		counters.append(counter)
		_write_count(model, "parry", layers - 1)
	return counters

func player_turn_end(model) -> Array:
	var events := own_turn_end(model)
	for entry in _definitions().values():
		if entry.duration != "player_turn_end": continue
		clear(model, entry.id)
		for index in model.enemies.size(): clear(model, entry.id, index)
	return events

func own_turn_start(model, enemy_index: int = -1) -> void:
	for entry in _definitions().values():
		if entry.duration == "own_turn_start": clear(model, entry.id, enemy_index)
		if enemy_index < 0 and entry.has("usedField"): model.set(entry.usedField, false)

func own_turn_end(model, enemy_index: int = -1) -> Array:
	var events: Array = []
	if (model.player_hp if enemy_index < 0 else model.enemies[enemy_index].hp) <= 0: return events
	for entry in _definitions().values():
		if entry.duration != "own_turn_end_decay" or not accepts(entry.id, enemy_index): continue
		var layers := count(model, entry.id, enemy_index)
		if layers <= 0: continue
		if entry.handler == "pollution":
			# Status damage uses ordinary block, and never enters attack hooks.
			var tick: Dictionary = model.player_damage(layers) if enemy_index < 0 else model.enemy_damage(enemy_index, layers)
			tick.merge({"type":"status_tick","buffId":entry.id,"stacksAfter":layers - 1})
			events.append(tick)
			model.log_lines.append("污染造成 %d 点伤害，格挡 %d，剩余 %d 层。" % [tick.damage, tick.blocked, layers - 1])
		_write_count(model, entry.id, layers - 1, enemy_index)
		if entry.handler == "vulnerable":
			events.append({"type":"status_decay", "target":enemy_index, "buffId":entry.id, "stacksAfter":layers - 1})
	return events

func _badge(entry: Dictionary, amount: int, used: bool = false) -> Dictionary:
	var description: String = entry.description.format({"count":amount, "triggered":"已触发" if used else "待触发"})
	return {"id":entry.icon,"buffId":entry.id,"category":entry.category,"count":amount,"color":entry.color,"description":description}

func enemy_badges(enemy: Dictionary) -> Array:
	var result: Array = []
	for entry in _definitions().values():
		if not entry.showBadge or entry.target == "player": continue
		var amount := enemy_count(enemy, entry)
		if amount != 0: result.append(_badge(entry, amount))
	return result

func player_badges(model, shown_parry: int = -1, shown_pollution: int = -1, shown_extra = null) -> Array:
	var result: Array = []
	for entry in _definitions().values():
		if not entry.showBadge or entry.target == "enemy": continue
		var amount := shown_parry if entry.id == "parry" and shown_parry >= 0 else count(model, entry.id)
		if entry.id == "pollution" and shown_pollution >= 0: amount = shown_pollution
		if shown_extra is Dictionary and entry.get("field", "").is_empty() and entry.id != "pollution": amount = int(shown_extra.get(entry.id, 0))
		if amount == 0: continue
		var used: bool = model.get(entry.usedField) if entry.has("usedField") else false
		result.append(_badge(entry, amount, used))
	return result

func _valid_count(value, maximum: int = -1, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value == floor(float(value)) and (maximum < 0 or value <= maximum)

func valid_extra_state(state, target: String) -> bool:
	if not state is Dictionary: return false
	for id in state:
		if not has(str(id)): return false
		var entry: Dictionary = _definitions()[id]
		if not entry.get("field", "").is_empty() or entry.target not in ["both", target]: return false
		var maximum := 1 if entry.stacking in ["unique", "flag"] else int(entry.get("maxStacks", -1))
		if not _valid_count(state[id], maximum, int(entry.get("minStacks", 0))): return false
	return true

func restore_extra_state(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in state: result[id] = int(state[id])
	return result

func valid_snapshot(snapshot: Dictionary) -> bool:
	var state: Dictionary = snapshot.norenState
	if not state.get("powers") is Array: return false
	var seen: Array = []
	for id in state.powers:
		if not has(str(id)) or _definitions()[id].stacking != "unique" or id in seen: return false
		seen.append(id)
	for entry in _definitions().values():
		if entry.get("field", "").is_empty(): continue
		if entry.target != "enemy" and entry.id != "technology" and entry.stacking != "unique":
			var value = state.get(entry.saveKey)
			if entry.stacking == "flag":
				if not value is bool: return false
			elif not _valid_count(value, int(entry.get("maxStacks", -1))): return false
		if entry.has("usedSaveKey") and not state.get(entry.usedSaveKey) is bool: return false
		if entry.target != "player":
			for enemy in snapshot.enemies:
				if not enemy is Dictionary or not _valid_count(enemy.get(entry.saveKey), int(entry.get("maxStacks", -1))): return false
	if not valid_extra_state(snapshot.get("buffs", {}), "player"): return false
	for enemy in snapshot.enemies:
		if not valid_extra_state(enemy.get("buffs", {}), "enemy"): return false
	return true
