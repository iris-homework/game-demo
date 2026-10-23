extends RefCounted
## Inventory generation/validation is independent of the page and transactions.
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

func period(day: int, rules: Dictionary) -> int:
	var result := 1
	for boundary in rules.get("restockDays", [1, 4, 7]):
		if day >= int(boundary): result = int(boundary)
	return result

func price(card: Dictionary, rules: Dictionary, buying: bool = true) -> int:
	return int(rules.get("buyPrices" if buying else "sellPrices", {}).get(card.get("rarity", ""), 0))

func offer_price(card: Dictionary, rules: Dictionary) -> int:
	var base := price(card, rules)
	var variation := maxi(0, int(rules.get("buyPriceVariation", 0)))
	return maxi(1, base + rng.randi_range(-variation, variation))

func generate(day: int, week: int, catalog: Dictionary, rules: Dictionary) -> Dictionary:
	var candidates: Array = []
	for id in catalog:
		if catalog[id].get("rarity", "") in ["B", "A", "S"] and price(catalog[id], rules) > 0:
			candidates.append(id)
	candidates.sort()
	# Partial Fisher-Yates: preserve unique slots without consuming gameplay RNG.
	var count := int(rules.get("slots", 9))
	if candidates.size() < count: return {}
	var slots: Array = []
	for index in count:
		var selected := rng.randi_range(index, candidates.size() - 1)
		var id: String = candidates[selected]
		candidates[selected] = candidates[index]
		candidates[index] = id
		slots.append({"cardId":id, "price":offer_price(catalog[id], rules), "sold":false})
	return {"restockDay":period(day, rules), "week":week, "slots":slots, "soldCardUsed":false, "pricingVersion":int(rules.get("pricingVersion",1))}

func whole_number(value, minimum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value == floor(float(value))

func valid(stock, catalog: Dictionary, rules: Dictionary) -> bool:
	if not stock is Dictionary: return false
	if not whole_number(stock.get("week"), 1) or not whole_number(stock.get("restockDay"), 1): return false
	if not int(stock.restockDay) in rules.get("restockDays", [1, 4, 7]).map(func(value): return int(value)): return false
	if stock.has("pricingVersion") and not whole_number(stock.pricingVersion, 1): return false
	if not stock.get("soldCardUsed") is bool or not stock.get("slots") is Array: return false
	if stock.slots.size() != int(rules.get("slots", 9)): return false
	var seen := []
	for slot in stock.slots:
		if not slot is Dictionary or not slot.get("cardId") is String or not slot.get("sold") is bool: return false
		if slot.cardId in seen or not catalog.has(slot.cardId): return false
		if not catalog[slot.cardId].get("rarity", "") in ["B", "A", "S"]: return false
		if not whole_number(slot.get("price"), 1): return false
		seen.append(slot.cardId)
	return true

func refresh(subject: Dictionary, catalog: Dictionary, rules: Dictionary) -> bool:
	if not whole_number(subject.get("currentDay"), 1) or subject.currentDay > 7: return false
	if not whole_number(subject.get("currentWeek"), 1): return false
	var stock = subject.get("blackMarket")
	# Never conceal an explicitly malformed stored inventory during migration.
	if subject.has("blackMarket") and not valid(stock, catalog, rules): return false
	if stock != null and int(stock.week) == int(subject.currentWeek) and int(stock.restockDay) == period(int(subject.currentDay), rules):
		# Explicit price revision updates remaining offers without replacing cards,
		# restoring sold slots, refunding past trades, or resetting the sale limit.
		var version := int(rules.get("pricingVersion",1))
		if int(stock.get("pricingVersion",1)) >= version: return false
		for slot in stock.slots:
			if not slot.sold: slot.price = offer_price(catalog[slot.cardId], rules)
		stock.pricingVersion = version
		return true
	var fresh := generate(int(subject.currentDay), int(subject.currentWeek), catalog, rules)
	if fresh.is_empty(): return false
	subject.blackMarket = fresh
	return true
