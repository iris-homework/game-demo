extends RefCounted
## Choose a rarity first, then an equally likely unoffered card in that rarity.
const RARITIES := ["B", "A", "S"]

func valid_rates(rates: Dictionary) -> bool:
	if rates.size() != RARITIES.size(): return false
	var total := 0
	for rarity in RARITIES:
		var value = rates.get(rarity)
		if not (value is int or value is float): return false
		if not is_finite(float(value)) or value < 0 or value > 100 or value != int(value): return false
		total += int(value)
	return total == 100

func sample(catalog: Dictionary, rates: Dictionary, count: int = 3) -> Array[String]:
	var options: Array[String] = []
	if count <= 0 or not valid_rates(rates): return options
	var pools := {"B":[], "A":[], "S":[]}
	var eligible := 0
	for id in catalog:
		if not id is String or not catalog[id] is Dictionary: continue
		var rarity = catalog[id].get("rarity", "")
		if rarity is String and rarity in RARITIES and rates[rarity] > 0:
			pools[rarity].append(id)
			eligible += 1
	# Reject before rolling if a complete offer cannot be produced.
	if eligible < count: return options
	for slot in count:
		var total := 0
		for rarity in RARITIES:
			if not pools[rarity].is_empty(): total += int(rates[rarity])
		var roll := randi_range(1, total)
		for rarity in RARITIES:
			if pools[rarity].is_empty(): continue
			roll -= int(rates[rarity])
			if roll <= 0:
				var index := randi_range(0, pools[rarity].size() - 1)
				options.append(pools[rarity][index])
				pools[rarity].remove_at(index)
				break
	return options
