extends Node
var checks := 0
var failures := 0
var qa_dir := "res://artifacts/qa/black-market-2026-10-23"
var good_path := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BLACK MARKET: " + message)

func reset() -> void:
	Game.save_enabled = false
	Game.save_path = good_path
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.state = Game.initial_state()
	Game.state.currentScene = "place"
	Game.state.currentPlaceId = "market"
	Game.page = "place"
	Game.state.credits = 2000

func unchanged(before: Dictionary, rev: int, label: String) -> void:
	check(Game.state == before and Game.revision == rev, label)

func test_inventory() -> void:
	reset()
	check(Game.valid_save(Game.state), "new adventure is valid")
	var stock := Game.black_market_state()
	check(stock.slots.size() == 9 and stock.restockDay == 1 and not stock.soldCardUsed, "day one creates nine slots with one available sale")
	var seen := []
	for slot in stock.slots:
		check(Game.card_catalog[slot.cardId].rarity in ["B", "A", "S"], "inventory excludes C: " + slot.cardId)
		check(not slot.cardId in seen and abs(int(slot.price)-Game.market_buy_price(slot.cardId)) <= 10, "unique inventory has configured price range")
		seen.append(slot.cardId)
	stock.slots.clear()
	check(Game.black_market_state().slots.size() == 9, "public inventory is a deep copy")
	for day in [1, 2, 3]:
		Game.state.currentDay = day
		check(Game.ensure_black_market() and Game.black_market_state().slots.map(func(slot): return slot.cardId) == seen, "no refresh before fourth day: " + str(day))

func test_buy_sell() -> void:
	reset()
	var rev := Game.revision
	var before := Game.state.duplicate(true)
	var slot: Dictionary = before.blackMarket.slots[0]
	check(Game.buy_market_card(0, rev), "purchase succeeds")
	check(Game.revision == rev + 1 and Game.state.credits == before.credits - slot.price and Game.state.deck == [slot.cardId], "purchase charges once and adds actual card")
	check(Game.state.blackMarket.slots[0].sold and Game.state.blackMarket.slots.size() == 9, "purchased slot stays sold out")
	before = Game.state.duplicate(true)
	check(not Game.buy_market_card(0, rev) and not Game.buy_market_card(0, Game.revision), "stale request and sold out purchase rejected")
	unchanged(before, rev + 1, "duplicate buy is atomic")
	check(Game.sell_market_card(slot.cardId, Game.revision), "purchased card can be sold")
	check(Game.state.deck.is_empty() and Game.state.blackMarket.soldCardUsed and not slot.cardId in Game.full_deck_ids(), "sale removes actual purchased card and consumes round allowance")
	before = Game.state.duplicate(true); rev = Game.revision
	check(not Game.sell_market_card(Game.full_deck_ids()[0], rev), "second sale before restock rejected")
	unchanged(before, rev, "rejected second sale leaves state unchanged")
	reset()
	var starter: String = Game.full_deck_ids()[0]
	var count: int = Game.owned_card_counts()[starter]
	var size := Game.full_deck_ids().size()
	check(Game.card_catalog[starter].rarity == "C" and Game.sell_market_card(starter, Game.revision), "starting C card can be sold")
	check(Game.owned_card_counts().get(starter, 0) == count - 1 and Game.full_deck_ids().size() == size - 1, "one duplicate starter is removed from complete deck")
	check(Game.state.removedStartingCards == [starter] and Game.valid_save(Game.state), "starting removal persists as valid record")
	Game.state.battleId = "B02"
	Game.state.currentScene = "battle"
	Game.initialize_combat()
	check(Game.state.combat.profile.deck.size() == size - 1 and Game.state.combat.profile.deck.count(starter) == count - 1, "new battle uses sold starter removal")
	Game.state.currentScene = "place"; Game.state.battleId = ""; Game.state.combat = {}; Game.state.battleStart = {}
	var adventure := Game.state.duplicate(true)
	Game.start_training("B02")
	check(Game.state.combat.profile.deck.size() == size - 1 and Game.state.combat.profile.deck.count(starter) == count - 1, "training also uses actual current deck")
	Game.finish_training("win")
	check(Game.state == adventure, "training restores exact market stock and removed starter state")
	reset()
	Game.state.deck = [starter, starter]
	check(Game.sell_market_card(starter, Game.revision) and Game.state.deck == [starter] and Game.state.removedStartingCards.is_empty(), "sale removes one added duplicate before starting copies")

func test_restock() -> void:
	reset()
	check(Game.buy_market_card(0, Game.revision), "purchase before restock")
	check(Game.sell_market_card(Game.full_deck_ids()[0], Game.revision), "sale before restock")
	var old := Game.black_market_state()
	check(Game.apply_actions([{"op":"advanceDay", "days":2}]), "date advances to third day")
	check(Game.black_market_state() == old, "day three retains bought and unbought stock")
	check(Game.apply_actions([{"op":"advanceDay", "days":1}]), "date advances to fourth day")
	var fourth := Game.black_market_state()
	check(fourth.restockDay == 4 and not fourth.soldCardUsed and fourth.slots.all(func(slot): return not slot.sold), "day four replaces all slots and resets sale immediately before UI entry")
	check(fourth != old and fourth.slots.size() == 9, "whole stock replacement preserves nine slots")
	check(Game.sell_market_card(Game.full_deck_ids()[0], Game.revision), "fresh sale allowance available")
	check(Game.apply_actions([{"op":"advanceDay", "days":3}]), "date advances to seventh day")
	var seventh := Game.black_market_state()
	check(seventh.restockDay == 7 and not seventh.soldCardUsed and seventh.slots.all(func(slot): return not slot.sold), "day seven replaces all stock")
	check(Game.buy_market_card(1, Game.revision) and Game.sell_market_card(Game.full_deck_ids()[0], Game.revision), "day seven transactions succeed")
	seventh = Game.black_market_state()
	check(Game.apply_actions([{"op":"advanceDay", "days":1}]), "advance at day cap accepted")
	Game.checkpoint()
	check(Game.ensure_black_market() and Game.black_market_state() == seventh, "day seven refresh only happens once despite repeat checkpoints/advance")
	reset()
	Game.state.currentDay = 3
	check(Game.apply_actions([{"op":"completeEvent", "id":"E02"}]) and Game.state.blackMarket.restockDay == 4, "event completion refreshes market at start of fourth day")
	reset()
	var before := Game.state.duplicate(true)
	check(not Game.apply_actions([{"op":"advanceDay", "days":3}, {"op":"spendCredits", "amount":999999}]), "failed date batch rejected")
	check(Game.state == before, "failed date batch does not replace stock")

func test_compatibility() -> void:
	reset()
	Game.state.deck = ["test_reward_01"]
	check(Game.market_sell_price("test_reward_01") == int(Game.black_market_rules.legacySellPrice), "legacy card without rarity has configured recovery value")
	check(Game.sell_market_card("test_reward_01", Game.revision) and Game.state.deck.is_empty(), "actual legacy extra card can be sold")
	reset()
	var old_price: int = Game.state.blackMarket.slots[0].price
	var id: String = Game.state.blackMarket.slots[0].cardId
	var rarity: String = Game.card_catalog[id].rarity
	var configured = Game.black_market_rules.buyPrices[rarity]
	Game.black_market_rules.buyPrices[rarity] = old_price + 999
	check(Game.valid_save(Game.state) and Game.ensure_black_market(), "valid existing inventory survives pricing config changes")
	var credits: int = Game.state.credits
	check(Game.buy_market_card(0, Game.revision) and Game.state.credits == credits - old_price, "purchase uses frozen slot price")
	Game.black_market_rules.buyPrices[rarity] = configured
	reset()
	var cards := Game.full_deck_ids()
	cards.clear()
	check(not Game.full_deck_ids().is_empty(), "full deck query returns a copy")
	for malformed in [null, {}, []]:
		var invalid := Game.state.duplicate(true)
		invalid.blackMarket = malformed
		check(not Game.valid_save(Game.migrate_save(invalid)), "explicit malformed stock never silently regenerates")
	reset()
	Game.state.currentDay = 4
	Game.save_enabled = true
	Game.save_path = good_path.get_base_dir().path_join("missing-folder/checkpoint.json")
	var before := Game.state.duplicate(true)
	var rev := Game.revision
	check(not Game.ensure_black_market(), "failed storage blocks explicit restock commit")
	unchanged(before, rev, "failed explicit restock rolls back inventory and revision")

func test_price_revision() -> void:
	reset()
	var expected := {"C":25,"B":50,"A":100,"S":150}
	for rarity in expected:
		var matching: Array = Game.card_catalog.values().filter(func(card): return card.rarity == rarity)
		check(matching.all(func(card): return Game.market_sell_price(card.id) == expected[rarity]), "all " + rarity + " cards sell at fixed exact value")
	var old: Dictionary = Game.black_market_state()
	old.erase("pricingVersion")
	for slot in old.slots: slot.price = 999
	old.slots[0].sold = true
	old.soldCardUsed = true
	Game.state.blackMarket = old.duplicate(true)
	var credits: int = Game.state.credits
	var deck: Array = Game.full_deck_ids()
	check(Game.ensure_black_market(), "old pricing upgrades in place")
	var upgraded: Dictionary = Game.black_market_state()
	check(upgraded.slots.map(func(slot): return slot.cardId) == old.slots.map(func(slot): return slot.cardId), "price migration keeps all card identities and order")
	check(upgraded.slots[0].sold and upgraded.slots[0].price == 999 and upgraded.soldCardUsed, "price migration preserves prior purchase and sale consumption")
	check(Game.state.credits == credits and Game.full_deck_ids() == deck and upgraded.restockDay == old.restockDay, "price migration leaves balances deck and period untouched")
	check(upgraded.slots.slice(1).all(func(slot): return abs(int(slot.price)-Game.market_buy_price(slot.cardId)) <= 10), "all remaining offers use revised price ranges")
	check(Game.ensure_black_market() and Game.black_market_state() == upgraded, "reopening does not reroll revised prices")
	Game.save_enabled = true
	check(Game.save_game(), "new floating prices persist")
	Game.state = {}
	check(Game.load_game() and same_saved_state(Game.black_market_state(), upgraded), "reload retains every floating price and used allowance")
	reset()
	Game.state.blackMarket.erase("pricingVersion")
	for slot in Game.state.blackMarket.slots: slot.price = 999
	var before: Dictionary = Game.state.duplicate(true)
	var rev := Game.revision
	Game.save_enabled = true
	Game.save_path = good_path.get_base_dir().path_join("missing-folder/checkpoint.json")
	check(not Game.ensure_black_market(), "failed price migration storage rejects commit")
	unchanged(before,rev,"failed price migration preserves old prices and revision")
	Game.save_enabled = false
	Game.save_path = good_path

func test_guards() -> void:
	for mode in ["transition", "busy", "training", "page", "scene", "place", "revision", "funds", "index", "card"]:
		reset()
		var rev := Game.revision
		match mode:
			"transition": Game.transition_locked = true
			"busy": Game.battle_busy = true
			"training": Game.training_mode = true
			"page": Game.page = "menu"
			"scene": Game.state.currentScene = "map"
			"place": Game.state.currentPlaceId = "bar"
			"revision": rev -= 1
			"funds": Game.state.credits = 0
		var before := Game.state.duplicate(true)
		var actual_revision := Game.revision
		if mode == "card": check(not Game.sell_market_card("UNKNOWN", rev), "unknown card sale rejected")
		else: check(not Game.buy_market_card(-1 if mode == "index" else 0, rev), "buy guard: " + mode)
		if not mode in ["funds", "index", "card"]: check(not Game.sell_market_card(Game.full_deck_ids()[0], rev), "sell guard: " + mode)
		unchanged(before, actual_revision, "guard leaves stock/credits/deck/revision unchanged: " + mode)
	reset()
	for removed in ["noren_01", ["UNKNOWN"], ["noren_01", "noren_01", "noren_01", "noren_01", "noren_01", "noren_01"]]:
		var invalid := Game.state.duplicate(true); invalid.removedStartingCards = removed
		check(not Game.valid_save(invalid), "invalid starter removal rejected")
	for field in ["price", "sold", "cardId"]:
		var invalid := Game.state.duplicate(true)
		invalid.blackMarket.slots[0][field] = -1
		check(not Game.valid_save(Game.migrate_save(invalid)), "malformed stock rejected instead of silently regenerated: " + field)

func same_saved_state(left: Dictionary, right: Dictionary) -> bool:
	# JSON numbers load as floats; normalize both operands before comparing.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func test_save() -> void:
	reset()
	Game.save_enabled = true
	check(Game.buy_market_card(0, Game.revision), "purchase persists")
	var starter: String = Game.full_deck_ids()[0]
	check(Game.sell_market_card(starter, Game.revision), "starter sale persists")
	var saved := Game.state.duplicate(true)
	Game.state = {}
	check(Game.load_game() and same_saved_state(Game.state, saved), "roundtrip retains inventory sold slots sale allowance credits and complete deck")
	var legacy := saved.duplicate(true)
	legacy.erase("blackMarket"); legacy.erase("removedStartingCards"); legacy.currentDay = 4
	var file := FileAccess.open(good_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy)); file.close()
	check(Game.load_game() and Game.state.blackMarket.restockDay == 4 and Game.state.removedStartingCards.is_empty(), "legacy checkpoint initializes current stock and starter removal list")
	check(Game.sell_market_card(starter, Game.revision), "legacy checkpoint allows sale of actual starting card")
	saved = Game.state.duplicate(true)
	check(Game.load_game() and same_saved_state(Game.state, saved), "legacy sale survives reload without inventory reroll")
	reset()
	Game.save_enabled = true
	Game.save_path = good_path.get_base_dir().path_join("missing-folder/checkpoint.json")
	var before := Game.state.duplicate(true)
	var rev := Game.revision
	check(not Game.buy_market_card(0, rev), "write failure rejects purchase")
	unchanged(before, rev, "write failure rolls back charge card sold slot and revision")
	check(not Game.sell_market_card(starter, rev), "write failure rejects sale")
	unchanged(before, rev, "write failure preserves actual card and sale allowance")
	Game.save_path = good_path
	check(Game.sell_market_card(starter, rev), "sale can retry after storage recovers")
	reset()
	Game.state.currentDay = 7
	Game.save_enabled = true
	check(Game.save_game(), "stale legacy cycle fixture saved")
	Game.state = {}
	check(Game.load_game() and Game.state.blackMarket.restockDay == 7, "loading old cycle catches up to seventh day")
	saved = Game.state.duplicate(true)
	check(Game.load_game() and same_saved_state(Game.state, saved), "catchup refresh is persisted and never rerolled on reload")

func _ready() -> void:
	var directory := ProjectSettings.globalize_path(qa_dir.path_join("test-files"))
	DirAccess.make_dir_recursive_absolute(directory)
	good_path = directory.path_join("checkpoint-test.json")
	Game.meta_path = directory.path_join("meta-test.json")
	test_inventory()
	test_buy_sell()
	test_restock()
	test_guards()
	test_compatibility()
	test_price_revision()
	test_save()
	Game.save_enabled = false
	var result := {"checks":checks, "failures":failures, "scope":"headless model, transactions, saves, day changes; no rendered UI or physical input"}
	var file := FileAccess.open(qa_dir.path_join("logic-result.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result, "\t")); file.close()
	print("BLACK MARKET: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
