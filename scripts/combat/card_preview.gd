extends RefCounted
## Read-only numeric presentation. Copies status state, never plays a card,
## shuffles a deck, spends live resources, or stores preview data in snapshots.

static func build(model, uid: String, target: int, extra: int) -> Dictionary:
	var definition: Dictionary = model.card(uid)
	if definition.is_empty(): return {"text":"", "effects":[]}
	var candidates: Array = []
	var kind: String = model.card_target(uid)
	if target >= 0 and target < model.enemies.size() and model.enemies[target].hp > 0 and kind == "enemy":
		candidates.append(target)
	elif kind in ["enemy", "all"]:
		for index in model.enemies.size():
			if model.enemies[index].hp > 0: candidates.append(index)
	if candidates.is_empty(): candidates.append(-1)
	var variants: Array = []
	var limit: int = model.extra_ammo_limit(uid)
	var extras: Array = range(limit + 1) if extra < 0 else [clampi(extra, 0, limit)]
	for index in candidates:
		for spent in extras:
			variants.append(_variant(model, uid, index, spent))
	var lines: PackedStringArray = []
	var rows: Array = []
	for row_index in variants[0].size():
		var samples: Array = []
		for variant in variants: samples.append(variant[row_index])
		var row: Dictionary = samples[0].duplicate(true)
		var values: Array = []
		for sample in samples: values.append(sample.get("values", []))
		row.samples = values
		if row.has("finalCount"):
			row.finalSamples = samples.map(func(sample): return [sample.finalCount])
		if row.has("baseBranch"):
			row.baseBranchSamples = samples.map(func(sample): return [sample.baseBranch])
			row.woundedBranchSamples = samples.map(func(sample): return [sample.woundedBranch])
		rows.append(row)
		var number := _numbers(values)
		match row.type:
			"damage":
				lines.append(("对每名敌人造成" if kind == "all" else "造成") + number + "点伤害。" + ("无视格挡。" if row.get("bypass", false) else ""))
			"bleed_damage":
				if values.any(func(v): return v.any(func(n): return n > 0)):
					lines.append("裂伤追加" + number + "点伤害。")
			"attack_bleed": lines.append("剖解经验追加" + number + "层裂伤。")
			"ammo": lines.append("获得" + number + "弹药。")
			"attack_ammo": lines.append(("回弹" if model.stance == "melee" else "耗弹") + number + "。")
			"draw": lines.append("抽" + number + "张牌。")
			"stance": lines.append(row.text)
			"discard_attack": lines.append("弃置另一张攻击牌。")
			"exhaust_hand": lines.append("消耗另一张手牌。")
			"power": lines.append(row.text)
			"remove_soul_link": lines.append("使%s失去%s层灵魂连接。" % [row.name,number])
			"buff":
				var prefix := "对每名敌人施加" if row.enemy and kind == "all" else ("施加" if row.enemy else "获得")
				lines.append(prefix + number + row.unit + row.name + "。")
	if model.is_noren() and definition.get("exhaust", false): lines.append("消耗。")
	if extra < 0 and limit > 0: lines.append("可选额外耗弹0–%d。" % limit)
	return {"text":"\n".join(lines), "cardText":_card_text(definition, rows), "description":_card_text({"cardText":definition.get("description", "")}, rows), "effects":rows}

static func _card_text(definition: Dictionary, rows: Array) -> String:
	# Keep authored rules. Replace effect numbers; dynamic multi-hit attacks need
	# explicit first/later wording when their segment values differ. Implicit
	# attack ammo, stance rewards and bleed triggers never introduce new lines.
	var text: String = definition.get("cardText", definition.get("description", ""))
	var damage_rows: Array = rows.filter(func(row): return row.type == "damage")
	var pattern := RegEx.new()
	pattern.compile("造成\\s*(\\d+)\\s*点伤害(?:[，,]\\s*共\\s*(\\d+)\\s*次)?")
	var matches := pattern.search_all(text)
	# Work backwards so replacements cannot shift the remaining source offsets.
	for index in range(mini(matches.size(), damage_rows.size()) - 1, -1, -1):
		var found: RegExMatch = matches[index]
		var samples: Array = damage_rows[index].samples
		if damage_rows[index].get("dynamicHits", false) and samples[0].size() > 1:
			var first: Array = []
			var later: Array = []
			for sample in samples:
				first.append(sample[0])
				later.append_array(sample.slice(1))
			if _range(first) != _range(later):
				var replacement := "首段造成%s点伤害，后续每段造成%s点伤害" % [_range(first), _range(later)]
				text = text.substr(0, found.get_start()) + replacement + text.substr(found.get_end())
				continue
		var repeated := found.get_start(2) >= 0
		var parts: PackedStringArray = []
		var count: int = samples[0].size() if repeated else 1
		for segment in count:
			var values: Array = []
			for sample in samples: values.append(sample[segment] if segment < sample.size() else 0)
			parts.append(_range(values))
		var number := parts[0] if Array(parts).all(func(value): return value == parts[0]) else "／".join(parts)
		text = text.substr(0, found.get_start(1)) + number + text.substr(found.get_end(1))
	var draw_rows: Array = rows.filter(func(row): return row.type == "draw")
	pattern.compile("抽\\s*(\\d+)\\s*张牌")
	matches = pattern.search_all(text)
	for index in range(mini(matches.size(),draw_rows.size())-1,-1,-1):
		var found: RegExMatch=matches[index]
		text=text.substr(0,found.get_start(1))+_numbers(draw_rows[index].samples)+text.substr(found.get_end(1))
	for row in rows:
		var expression := ""
		var number := _numbers(row.samples)
		match row.type:
			"ammo": expression = "获得\\s*(\\d+)\\s*颗弹药"
			"draw": continue
			"buff":
				match row.id:
					"block": expression = "(\\d+)\\s*点格挡"
					"weak": expression = "施加\\s*(\\d+)\\s*层虚弱"
					"bleed":
						if row.get("conditionalBleed", false):
							pattern.compile("施加\\s*(\\d+)\\s*层裂伤")
							matches = pattern.search_all(text)
							for branch in range(matches.size() - 1, -1, -1):
								# The melee-only alternative stays authored while ranged.
								if branch > 0 and not row.has("baseBranchSamples"): continue
								var value := _numbers(row.baseBranchSamples if branch == 0 else row.woundedBranchSamples) if row.has("baseBranchSamples") else number
								var found: RegExMatch = matches[branch]
								text = text.substr(0, found.get_start(1)) + value + text.substr(found.get_end(1))
							continue
						# Some authored cards explicitly print base and halved amounts.
						# Update the result, preserving the base amount in that rule.
						expression = "减半后(?:为|实际施加)?\\s*(\\d+)\\s*层" if "减半后" in text else "施加\\s*(\\d+)\\s*层裂伤"
					"parry":
						if row.sourceType == "parry_fill":
							expression = "补至\\s*(\\d+)\\s*层"
							number = _numbers(row.finalSamples)
						else: expression = "获得\\s*(\\d+)\\s*层弹反"
					"next_damage", "next_hit_damage": expression = "基础伤害(?:增加|[+])\\s*(\\d+)"
					"next_discount": expression = "费用降低\\s*(\\d+)"
		if expression.is_empty(): continue
		pattern.compile(expression)
		matches = pattern.search_all(text)
		matches.reverse()
		for found in matches:
			text = text.substr(0, found.get_start(1)) + number + text.substr(found.get_end(1))
	return text

static func _variant(model, uid: String, target: int, extra: int) -> Array:
	# Instantiate through the caller to avoid a model <-> preview script cycle.
	var copy = model.get_script().new()
	copy.restore(model.snapshot())
	# Definitions are immutable; share the loaded library rather than rereading JSON.
	copy.buffs = model.buffs
	var definition: Dictionary = copy.card(uid)
	var form: String = copy.stance
	var ammo_before: int = copy.ammo
	var before: Array = copy.enemies.duplicate(true)
	if target < 0:
		before.append({"hp":100, "maxHp":100, "bleed":0, "weak":0, "block":0})
		copy.enemies.append(before.back().duplicate(true))
		target = before.size() - 1
	var rows: Array = []
	var bonus := 0
	var segment_bonus := 0
	var attack: bool = definition.get("type", "") == "attack"
	if attack:
		if copy.is_noren(): segment_bonus=copy.buffs.attack_segment_bonus(copy)
		bonus = copy.buffs.begin_attack(copy, form) if copy.is_noren() else copy.next_attack_bonus
		if copy.is_noren():
			if form == "ranged": copy.ammo = 0 if definition.get("consumeAllAmmo",false) else copy.ammo - 1 - extra
			rows.append({"type":"attack_ammo", "values":[absi(copy.ammo - ammo_before)]})
	# Track executed hits for ammo without changing potential damage presentation.
	var ammo_targets: Array = []
	if model.card_target(uid) == "all":
		for index in copy.enemies.size():
			if copy.enemies[index].hp > 0: ammo_targets.append(index)
	else: ammo_targets.append(target)
	var ammo_hp := {}
	var ammo_block := {}
	for index in ammo_targets:
		ammo_hp[index] = int(copy.enemies[index].hp)
		ammo_block[index] = int(copy.enemies[index].get("block",0))
	copy.hand.erase(uid)
	copy.draw_pile.erase(uid)
	copy.discard_pile.erase(uid)
	var draw_available: int = copy.draw_pile.size() + (copy.discard_pile.size() if copy.profile.get("recycleDiscardWhenEmpty", true) else 0)
	for effect in definition.get("effects", []):
		if copy.is_noren() and effect.get("when", form) != form: continue
		var active: bool = not effect.has("requiresBleed") or int(before[target].get("bleed", 0)) >= int(effect.requiresBleed)
		var amount := int(effect.get("amount", 0)) if active else 0
		match effect.type:
			"damage":
				if copy.is_noren() and attack and form == "melee" and active:
					var segments := 0
					for index in ammo_targets:
						for segment in copy.attack_hit_count(effect, form, before[index],ammo_before):
							if ammo_hp[index] <= 0: break
							var requested: int = copy.attack_hit_amount(definition, effect, form, ammo_before, before[index],segment_bonus+(bonus if segment == 0 else 0),extra)
							requested = copy.buffs.incoming_damage(copy, requested, index)
							var absorbed: int = mini(ammo_block[index],requested)
							ammo_block[index] -= absorbed
							ammo_hp[index] -= maxi(0,requested-absorbed)
							segments = maxi(segments,segment+1)
					var previous: int = copy.ammo
					copy.gain_ammo(segments)
					rows[0].values[0] += copy.ammo - previous
				var hits: Array = []
				var bleeding: Array = []
				var attack_bleed := 0
				var count: int = copy.attack_hit_count(effect, form, before[target],ammo_before) if copy.is_noren() else 1
				for segment in count:
					var per_hit: int = copy.attack_hit_amount(definition, effect, form, ammo_before, before[target], segment_bonus+(bonus if segment == 0 else 0), extra) if copy.is_noren() else amount + bonus
					if copy.is_noren() and attack: per_hit = copy.buffs.incoming_damage(copy, per_hit, target)
					hits.append(per_hit)
					if copy.is_noren() and attack and active:
						attack_bleed += copy.buffs.apply_melee_attack_bleed(copy, target, form)
					var times: int=int(effect.get("bleedTriggers",1 if form=="ranged" else 0)) if copy.is_noren() else 0
					for tick in times:
						var layers := int(copy.enemies[target].get("bleed",0))
						bleeding.append(layers)
						# Keep HP/block intact for potential damage, advancing only nominal layers.
						if active and layers>0 and copy.buffs.count(copy,"persistent_bleed")==0: copy.enemies[target].bleed=layers-1
				bonus = 0
				rows.append({"type":"damage", "values":hits if active else [0], "dynamicHits":effect.get("allAmmoHits", false), "bypass":copy.is_noren() and form == "ranged" and effect.get("rangedIgnoreBlock", false)})
				rows.append({"type":"bleed_damage", "values":bleeding if active else [0]})
				if copy.is_noren() and attack and form == "melee" and copy.buffs.count(copy, "melee_attack_bleed") > 0:
					rows.append({"type":"attack_bleed", "values":[attack_bleed]})
			"ammo":
				var previous: int = copy.ammo
				copy.gain_ammo(amount)
				rows.append({"type":"ammo", "values":[copy.ammo - previous]})
			"draw":
				var drawn := mini(amount, draw_available)
				draw_available -= drawn
				rows.append({"type":"draw", "values":[drawn]})
			"stance":
				var value: String = effect.value
				if value == "toggle": value = "ranged" if copy.stance == "melee" else "melee"
				var changed: bool = copy.stance != value and active
				var text := "切换至近战。" if value == "melee" else "切换至远程。"
				if changed:
					copy.stance = value
					if value == "melee":
						var drawn := mini(2, draw_available)
						draw_available -= drawn
						text += "抽%d张牌。" % drawn
					else:
						copy.buffs.apply(copy, "stance_discount")
						text += "下次攻击费用−1。"
				else: text = "保持当前形态。"
				rows.append({"type":"stance", "text":text})
			"exhaust_hand":
				rows.append({"type":"exhaust_hand"})
			"discard_attack":
				if copy.profile.get("recycleDiscardWhenEmpty", true) and not copy.discard_candidates(uid).is_empty(): draw_available += 1
				rows.append({"type":"discard_attack"})
			"remove_soul_link":
				var removed := 0
				var recipient := "白舞者" if effect.get("enemyId", "") == "dancer_white" else "黑舞者"
				for index in copy.enemies.size():
					if copy.enemies[index].get("id", "") == effect.get("enemyId", "") and copy.enemies[index].hp > 0:
						removed = mini(amount,copy.buffs.count(copy,"soul_link",index))
						break
				rows.append({"type":"remove_soul_link","name":recipient,"values":[removed]})
			_:
				var id: String = effect.get("id", "") if effect.type == "buff" else ("parry" if effect.type == "parry_fill" else str(effect.get("value", "")) if effect.type == "power" else str(effect.type))
				if not copy.buffs.has(id): continue
				var entry: Dictionary = copy.buffs.definition(id)
				var enemy: bool = effect.get("buffTarget", "enemy" if id == "weak" else "player" if entry.target == "both" else entry.target) == "enemy"
				var index := target if enemy else -1
				var previous: int = copy.buffs.count(copy, id, index)
				var branches: Dictionary = {}
				if id == "bleed" and effect.has("woundedMeleeAmount"):
					branches.conditionalBleed = true
					if form == "melee":
						branches.baseBranch = _bleed_branch_gain(copy, effect, before, target, false, model.card_target(uid) == "enemy")
						branches.woundedBranch = _bleed_branch_gain(copy, effect, before, target, true, model.card_target(uid) == "enemy")
				if active: copy.buffs.apply_card_effect(copy, effect, [target], {"stance":form, "before":before, "single":model.card_target(uid) == "enemy"})
				var gained: int = copy.buffs.count(copy, id, index) - previous
				if effect.type == "power":
					rows.append({"type":"power", "text":definition.get("cardText", definition.get("description", "")) + ("\n已生效，不叠加。" if gained == 0 else "")})
				else:
					rows.append({"type":"buff", "id":id, "sourceType":effect.type, "finalCount":copy.buffs.count(copy, id, index), "name":entry.name, "enemy":enemy, "unit":"点" if id in ["block", "next_damage", "next_hit_damage", "next_discount"] else "层", "values":[gained]})
					rows.back().merge(branches)
	return rows

static func _bleed_branch_gain(model, effect: Dictionary, before: Array, target: int, wounded: bool, single: bool) -> int:
	var branch = model.get_script().new()
	branch.restore(model.snapshot())
	branch.buffs = model.buffs
	var branch_before := before.duplicate(true)
	branch_before[target].bleed = 1 if wounded else 0
	var previous: int = branch.buffs.count(branch, "bleed", target)
	branch.buffs.apply_card_effect(branch, effect, [target], {"stance":"melee", "before":branch_before, "single":single})
	return branch.buffs.count(branch, "bleed", target) - previous

static func _range(values: Array) -> String:
	var low: int = values.min()
	var high: int = values.max()
	return str(low) if low == high else "%d–%d" % [low, high]

static func _numbers(samples: Array) -> String:
	if samples.is_empty() or samples[0].is_empty(): return "0"
	var counts: Array = []
	for sample in samples: counts.append(sample.size())
	if counts.min() != counts.max():
		var totals: Array = []
		for sample in samples:
			var total := 0
			for number in sample: total += int(number)
			totals.append(total)
		return _range(totals) + "（%s段）" % _range(counts)
	var parts: PackedStringArray = []
	for index in samples[0].size():
		var values: Array = []
		for sample in samples: values.append(sample[index])
		parts.append(_range(values))
	if parts.size() > 1 and Array(parts).all(func(value): return value == parts[0]):
		return "%s×%d" % [parts[0], parts.size()]
	return "＋".join(parts)
