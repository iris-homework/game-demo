extends Node
const OUTPUT := "res://artifacts/qa/passive-technology-2026-10-24/shop"
var checks := 0
var failures: Array[String] = []
var good_path := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("TECHNOLOGY SHOP: " + message)

func reset() -> void:
	Game.save_enabled = false
	Game.save_path = good_path
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.state = Game.initial_state()
	# Explicit legacy-ownership fixture for duplicate-purchase coverage.
	Game.state.ownedCyberwareIds = ["dimensional_pocket", "accelerated_clock", "backup_energy"]
	Game.state.equippedCyberwareIds = Game.state.ownedCyberwareIds.duplicate()
	Game.state.currentScene = "place"
	Game.state.currentPlaceId = "mall"
	Game.page = "place"
	Game.state.credits = 2000

func unowned_fixture() -> void:
	# Isolated purchase fixture with no owned technologies.
	reset()
	Game.state.ownedCyberwareIds = []
	Game.state.equippedCyberwareIds = []

func same(left, right) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func test_catalog_and_purchase() -> void:
	reset()
	var defaults := Game.owned_cyberware_ids()
	check(defaults == ["dimensional_pocket", "accelerated_clock", "backup_energy"], "fixture owns three original technologies")
	var offers := Game.technology_shop_offers()
	check(offers.size() == 6 and offers.map(func(offer): return offer.id) == defaults + ["money_chip","healing_chip","swift_chip"], "shop lists three original active technologies and three passive chips")
	check(offers.all(func(offer): return offer.price == 125), "all six technologies cost 125")
	for index in 3:
		var before := Game.state.duplicate(true)
		var rev := Game.revision
		check(not Game.buy_shop_technology(index, rev) and Game.state == before and Game.revision == rev, "existing ownership cannot repurchase: " + offers[index].id)
	check(Game.prototype_rules.cyberware.cards.size() == 12, "catalog retains six legacy definitions plus six real technologies")
	for index in range(3,6): check(Game.buy_shop_technology(index,Game.revision), "fixture can purchase passive chip " + offers[index].id)
	check(Game.equipped_cyberware_ids() == defaults, "purchasing chips preserves default active equipment")
	offers[0].price = 1
	offers.clear()
	check(Game.technology_shop_offers()[0].price == 125, "public offers are a deep copy")
	unowned_fixture()
	var before := Game.state.duplicate(true)
	var rev := Game.revision
	var notices := [0]
	var on_status := func(): notices[0] += 1
	Game.status_changed.connect(on_status)
	check(Game.buy_shop_technology(0, rev), "unowned fixture purchase succeeds")
	Game.status_changed.disconnect(on_status)
	check(Game.revision == rev + 1 and notices[0] == 1, "purchase commits once and notifies once")
	check(Game.state.credits == before.credits - 125 and Game.owned_cyberware_ids() == ["dimensional_pocket"], "purchase charges once and records ownership")
	before.credits -= 125
	before.ownedCyberwareIds.append("dimensional_pocket")
	check(Game.state == before, "purchase changes only credits and ownership, no time equipment or other state")
	check(not Game.buy_shop_technology(0, rev) and not Game.buy_shop_technology(0, Game.revision), "stale and repeated purchase rejected")
	check(Game.state == before and Game.revision == rev + 1, "rejected purchase leaves all state and revision unchanged")
	for index in range(1, 6): check(Game.buy_shop_technology(index, Game.revision), "can buy remaining unowned technology " + str(index))
	check(Game.owned_cyberware_ids() == defaults + ["money_chip","healing_chip","swift_chip"] and Game.equipped_cyberware_ids().is_empty(), "all six owned without automatically equipping")
	Game.state.currentDay = 7
	check(not Game.buy_shop_technology(0, Game.revision), "day changes do not replenish owned technology")
	check(Game.initial_state().ownedCyberwareIds.is_empty() and Game.initial_state().equippedCyberwareIds.is_empty(), "production new adventure starts without technologies")

func test_catalog_limits() -> void:
	unowned_fixture()
	var rules: Dictionary = Game.technology_shop_rules.duplicate(true)
	var definitions: Dictionary = Game.prototype_rules.cyberware.duplicate(true)
	Game.technology_shop_rules.offers = []
	var before := Game.state.duplicate(true)
	check(Game.technology_shop_offers().is_empty() and not Game.buy_shop_technology(0, Game.revision) and Game.state == before, "empty catalog has no purchasable positions")
	Game.technology_shop_rules = {"offers":rules.offers.slice(0,3).duplicate(true)}
	check(Game.technology_shop_offers().size() == 3, "three-offer catalog accepted")
	for index in 3:
		var definition := Game.cyberware_definition("backup_energy").duplicate(true)
		definition.id = "qa_catalog_extra_" + str(index)
		Game.prototype_rules.cyberware.cards.append(definition)
		Game.technology_shop_rules.offers.append({"id":definition.id, "price":125})
	check(Game.technology_shop_offers().size() == 6 and Game.buy_shop_technology(5, Game.revision), "six valid offers accepted using temporary in-memory definitions")
	var seventh := Game.cyberware_definition("backup_energy").duplicate(true)
	seventh.id = "qa_catalog_extra_3"
	Game.prototype_rules.cyberware.cards.append(seventh)
	Game.technology_shop_rules.offers.append({"id":seventh.id, "price":125})
	check(Game.technology_shop_offers().is_empty() and not Game.buy_shop_technology(0, Game.revision), "more than six offers rejected")
	Game.technology_shop_rules = {"offers":[{"id":"test_cyberware_01", "price":125}]}
	check(Game.technology_shop_offers().is_empty() and not Game.buy_shop_technology(0, Game.revision), "legacy test placeholders cannot be sold")
	Game.technology_shop_rules = rules
	Game.prototype_rules.cyberware = definitions
	reset()

func test_guards() -> void:
	for mode in ["empty", "page", "scene", "place", "training", "transition", "busy", "defeat", "revision", "funds", "index_low", "index_high", "owned_invalid"]:
		unowned_fixture()
		var rev := Game.revision
		match mode:
			"empty": Game.state = {}
			"page": Game.page = "map"
			"scene": Game.state.currentScene = "map"
			"place": Game.state.currentPlaceId = "market"
			"training": Game.training_mode = true
			"transition": Game.transition_locked = true
			"busy": Game.battle_busy = true
			"defeat": Game.state.result = "lose"
			"revision": rev -= 1
			"funds": Game.state.credits = 124
			"owned_invalid": Game.state.ownedCyberwareIds = ["UNKNOWN"]
		var before := Game.state.duplicate(true)
		var actual_rev := Game.revision
		var index := -1 if mode == "index_low" else (6 if mode == "index_high" else 0)
		check(not Game.buy_shop_technology(index, rev), "reject purchase guard: " + mode)
		check(Game.state == before and Game.revision == actual_rev, "guard atomicity: " + mode)
	unowned_fixture()
	Game.state.credits = 125
	check(Game.buy_shop_technology(0, Game.revision) and Game.state.credits == 0, "exact price balance succeeds without negative balance")
	var rules: Dictionary = Game.technology_shop_rules.duplicate(true)
	for price in [-1, 0, 1.5, "125", null]:
		unowned_fixture()
		Game.technology_shop_rules.offers[0].price = price
		var before := Game.state.duplicate(true)
		var rev := Game.revision
		check(Game.technology_shop_offers().is_empty() and not Game.buy_shop_technology(0, rev), "invalid price rejected: " + str(price))
		check(Game.state == before and Game.revision == rev, "invalid price cannot mutate state")
		Game.technology_shop_rules = rules.duplicate(true)
	for id in ["UNKNOWN", rules.offers[1].id]:
		Game.technology_shop_rules.offers[0].id = id
		check(Game.technology_shop_offers().is_empty() and not Game.buy_shop_technology(0, Game.revision), "unknown or duplicate offers rejected")
		Game.technology_shop_rules = rules.duplicate(true)

func test_save_and_rollback() -> void:
	unowned_fixture()
	Game.save_enabled = true
	check(Game.buy_shop_technology(0, Game.revision), "purchase saves successfully")
	var saved := Game.state.duplicate(true)
	check(Game.valid_save(saved), "purchased technology produces a valid adventure save")
	Game.state = {}
	check(Game.load_game() and same(Game.state, saved), "disk roundtrip retains purchased ownership credits and equipment")
	Game.page = "place"
	check(not Game.buy_shop_technology(0, Game.revision), "reload cannot buy the same technology twice")
	Game.state.currentScene = "map"
	Game.page = "map"
	check(Game.set_technology_loadout(["dimensional_pocket"], Game.revision), "purchased technology can be equipped through real map API")
	saved = Game.state.duplicate(true)
	Game.state = {}
	check(Game.load_game() and same(Game.state, saved) and Game.equipped_cyberware_ids() == ["dimensional_pocket"], "purchased equipment survives disk reload")
	unowned_fixture()
	Game.save_enabled = true
	Game.save_path = good_path.get_base_dir().path_join("missing-folder/checkpoint.json")
	var before := Game.state.duplicate(true)
	var rev := Game.revision
	check(not Game.buy_shop_technology(0, rev), "failed disk write rejects purchase")
	check(Game.state == before and Game.revision == rev, "failed write rolls back balance ownership equipment and revision")
	Game.save_path = good_path
	check(Game.buy_shop_technology(0, rev), "same purchase can retry after storage recovers")
	check(Game.load_game() and "dimensional_pocket" in Game.owned_cyberware_ids(), "successful retry persisted")

func test_real_effects() -> void:
	for index in 3:
		unowned_fixture()
		var offer: Dictionary = Game.technology_shop_offers()[index]
		var definition := Game.cyberware_definition(offer.id)
		check(Game.buy_shop_technology(index, Game.revision), "effect fixture purchases " + offer.id)
		Game.page = "map"
		Game.state.currentScene = "map"
		check(Game.set_technology_loadout([offer.id], Game.revision), "map equips purchased " + offer.id)
		Game.state.battleId = "B02"
		Game.state.currentScene = "battle"
		Game.initialize_combat()
		check(Game.state.combat.profile.playerCyberwareIds == [offer.id] and Game.valid_combat(Game.state.combat), "new battle freezes purchased definition: " + offer.id)
		var model := CombatModel.new()
		model.restore(Game.state.combat)
		for enemy in model.enemies:
			enemy.hp = 1000
			enemy.maxHp = 1000
		model.draw_pile.sort()
		model.draw_cards()
		var baseline := CombatModel.new()
		baseline.restore(model.snapshot())
		check(model.activate_cyberware(offer.id), "actual combat activates " + offer.id)
		check(model.cyberware_cooldown(offer.id) == definition.cooldownTurns and not model.activate_cyberware(offer.id), "cooldown prevents repeat activation: " + offer.id)
		match definition.effect:
			"gain_energy":
				check(model.energy == baseline.energy + definition.amount, "purchased battery adds actual combat energy")
				var excess := model.snapshot()
				excess.norenState.energy += 1
				check(not Game.valid_combat(excess), "energy beyond frozen technology allowance rejected")
				excess = model.snapshot()
				excess.cyberwareCooldowns[offer.id] -= 1
				check(not Game.valid_combat(excess), "previous-turn technology cannot justify extra energy")
			"toggle_stance": check(model.stance == "ranged" and model.stance_discount and baseline.stance == "melee", "purchased switch uses actual stance change and attack discount")
			"redraw_hand": check(model.hand.size() == baseline.hand.size() and model.discard_pile == baseline.hand and model.hand != baseline.hand, "purchased recompiler performs actual discard and draw")
		check(Game.valid_combat(model.snapshot()), "effect snapshot remains valid: " + offer.id)

func _ready() -> void:
	var directory := ProjectSettings.globalize_path(OUTPUT.path_join("test-files"))
	DirAccess.make_dir_recursive_absolute(directory)
	good_path = directory.path_join("checkpoint-test.json")
	Game.meta_path = directory.path_join("meta-test.json")
	test_catalog_and_purchase()
	test_catalog_limits()
	test_guards()
	test_save_and_rollback()
	test_real_effects()
	Game.save_enabled = false
	var report := {"checks":checks, "failures":failures, "scope":"headless transactions, save roundtrip, guards, rollback, purchased equipment and real CombatModel effects; no rendered UI or physical input"}
	var file := FileAccess.open(OUTPUT.path_join("logic-result.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("TECHNOLOGY SHOP: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
