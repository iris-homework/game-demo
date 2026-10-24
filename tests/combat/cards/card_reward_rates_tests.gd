extends Node

const OUTPUT := "res://artifacts/qa/card-reward-rates-2026-10-23/"
const RARITIES := ["B", "A", "S"]
var checks := 0
var failures: Array[String] = []
var observed: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func begin_battle(kind: String) -> void:
	Game.save_enabled = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.training_backup.clear()
	Game.battles.B04.battleType = kind
	Game.state = Game.initial_state()
	Game.state.targetId = "richard"
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.enter_node("battle")

func finish_battle() -> void:
	check(Game.battle_exit("win", Game.revision), "Victory enters post-battle story")
	var steps := 0
	while Game.state.currentScene == "dialogue" and steps < 100:
		if Game.node_data().has("next"): Game.advance(Game.revision)
		else: Game.choose(0, Game.revision)
		steps += 1
	check(steps < 100, "Post-battle story terminates")

func test_distribution() -> void:
	var expected := {"normal":{"B":60,"A":37,"S":3}, "elite":{"B":50,"A":40,"S":10}, "boss":{"B":0,"A":0,"S":100}}
	check(same(Game.card_reward_rates, expected), "Authored probabilities match the chosen Spire base rates")
	var before: Dictionary = Game.card_catalog.duplicate(true)
	for kind in expected:
		var slots := [{"B":0,"A":0,"S":0}, {"B":0,"A":0,"S":0}, {"B":0,"A":0,"S":0}]
		var cards: Dictionary = {}
		var distinct := true
		var eligible := true
		seed(20261023)
		for attempt in 20000:
			var options: Array[String] = Game.card_reward_sampler.sample(Game.card_catalog, Game.card_reward_rates[kind])
			if options.size() != 3:
				check(false, "Every sampled offer contains three cards")
				return
			distinct = distinct and options[0] != options[1] and options[0] != options[2] and options[1] != options[2]
			for i in 3:
				var rarity: String = Game.card_catalog[options[i]].rarity
				eligible = eligible and rarity in RARITIES
				slots[i][rarity] += 1
				cards[options[i]] = cards.get(options[i], 0) + 1
		check(distinct and eligible, kind + ": all 20,000 offers exclude C and contain distinct IDs")
		var percentages: Array = []
		for i in 3:
			var row := {}
			for rarity in RARITIES:
				var actual := float(slots[i][rarity]) / 200.0
				row[rarity] = actual
				check(absf(actual - expected[kind][rarity]) < 1.2, kind + ": slot %d %s follows the configured percent" % [i + 1, rarity])
			percentages.append(row)
		for rarity in RARITIES:
			var ids: Array = Game.card_catalog.keys().filter(func(id): return Game.card_catalog[id].rarity == rarity)
			var expected_per_card: float = float(expected[kind][rarity]) / ids.size()
			for id in ids:
				var actual: float = float(cards.get(id, 0)) / 600.0
				check(absf(actual - expected_per_card) < 0.8, kind + ": equal selection within rarity: " + id)
		observed[kind] = percentages
	check(same(Game.card_catalog, before), "Sampling never edits the card catalog")

func test_edge_pools() -> void:
	var sample := Game.card_reward_sampler
	var rates := {"B":60,"A":37,"S":3}
	var small := {"b":{"rarity":"B"}, "a":{"rarity":"A"}, "s":{"rarity":"S"}, "c":{"rarity":"C"}}
	var options: Array[String] = sample.sample(small, rates)
	options.sort()
	check(options == ["a","b","s"], "Exhausted rarity renormalizes to remaining eligible cards")
	check(sample.sample(small, {"B":0,"A":0,"S":100}).is_empty(), "Boss cannot substitute lower rarities when fewer than three S cards exist")
	for invalid in [{}, {"B":60,"A":37,"S":2}, {"B":60,"A":37,"S":3,"C":0}, {"B":-1,"A":98,"S":3}, {"B":"60","A":37,"S":3}, {"B":60.5,"A":36.5,"S":3}, {"B":INF,"A":0,"S":0}, {"B":true,"A":96,"S":3}]:
		check(not sample.valid_rates(invalid) and sample.sample(small, invalid).is_empty(), "Invalid rate table is rejected: " + str(invalid))
	check(sample.sample({}, rates).is_empty(), "Empty catalog cannot create offers")
	check(sample.sample({"c":{"rarity":"C"}}, rates).is_empty(), "Starter-only pool cannot create offers")
	check(sample.sample({"x":null,"y":{"rarity":"X"}}, rates).is_empty(), "Malformed definitions never enter the reward pool")

func test_flow() -> void:
	begin_battle("boss")
	Game.battles.B04.battleType = "normal"
	finish_battle()
	check(Game.state.battleReward.battleType == "boss", "Reward uses frozen battle type after config edit")
	check(Game.state.battleReward.options.all(func(id): return Game.card_catalog[id].rarity == "S"), "Boss grants three S options")
	var pending: Dictionary = Game.state.battleReward.duplicate(true)
	check(Game.save_game(), "Persist weighted pending reward")
	Game.state = {}
	check(Game.load_game() and same(Game.state.battleReward, pending), "Reload retains exact offers without rerolling")
	var actual_rates: Dictionary = Game.card_reward_rates.duplicate(true)
	Game.card_reward_rates.boss = {"B":100,"A":0,"S":0}
	Game.enter_node("finish")
	check(same(Game.state.battleReward, pending) and Game.state.credits == int(Game.config.initialCredits) + 50, "Changing rates and finish reentry preserve existing reward")
	Game.state.battleReward.erase("battleType")
	check(Game.save_game(), "Persist legacy-style pending reward")
	Game.state = {}
	check(Game.load_game() and Game.state.battleReward.options == pending.options, "Old pending offers remain unchanged")
	check(Game.choose_reward_card(pending.options[0], Game.revision), "Old pending reward can still be claimed")
	Game.card_reward_rates = actual_rates.duplicate(true)
	for fault in ["rates", "pool"]:
		begin_battle("boss")
		var catalog: Dictionary = Game.card_catalog
		if fault == "rates": Game.card_reward_rates.boss = {"B":0,"A":0,"S":0}
		else: Game.card_catalog = {"only_s":{"rarity":"S"}}
		finish_battle()
		check(Game.state.credits == int(Game.config.initialCredits) and Game.state.claimedRewardIds.is_empty() and Game.state.battleReward.is_empty(), "Bad " + fault + " cannot grant partial reward or consume claim")
		Game.card_catalog = catalog
		Game.card_reward_rates = actual_rates.duplicate(true)
		Game.prepare_battle_reward()
		check(Game.has_battle_reward() and Game.state.credits == int(Game.config.initialCredits) + 50, "Corrected configuration can retry reward exactly once")
	begin_battle("elite")
	var adventure: Dictionary = Game.state.duplicate(true)
	Game.start_training("B04")
	Game.battle_exit("win", Game.revision)
	check(not Game.training_mode and same(Game.state, adventure), "Training still restores adventure without rewards")

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	Game.save_enabled = false
	Game.save_path = OUTPUT + "checkpoint.json"
	Game.meta_path = OUTPUT + "meta.json"
	var battles: Dictionary = Game.battles.duplicate(true)
	test_distribution()
	test_edge_pools()
	test_flow()
	Game.battles = battles
	var file := FileAccess.open(OUTPUT + "card-reward-rates-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observedPercentBySlot":observed,"offersPerType":20000,"scope":"headless sampler, reward flow and save compatibility"}, "\t"))
	file.close()
	print("CARD REWARD RATES TESTS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
