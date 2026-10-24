extends RefCounted
## Borrow Game only for the lab's lifetime; production pages run with real rules.
const FIELDS := ["state", "page", "save_enabled", "save_path", "meta_path", "meta_profile", "revision", "last_error", "transition_locked", "battle_busy", "training_mode", "training_backup", "training_enemy_id", "training_battle_id", "training_scenery_place_id", "b04_scenery_choice", "pending_save_kind", "_defer_checkpoint", "technology_shop_rules"]
const SWIFT_CHIP_TEST_PRICE := 9999
var backup: Dictionary = {}
var active := false
var refresh_rng_state: int
var market_rng_state: int

func begin() -> void:
	if active: return
	for field in FIELDS:
		var value: Variant = Game.get(field)
		backup[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	refresh_rng_state = Game.event_refresh_rng.state
	market_rng_state = Game.black_market_model.rng.state
	active = true
	Game.technology_shop_rules = Game.technology_shop_rules.duplicate(true)
	for offer in Game.technology_shop_rules.get("offers", []):
		if offer.get("id") == "swift_chip": offer.price = SWIFT_CHIP_TEST_PRICE
	Game.save_enabled = false
	Game.save_path = "user://audio_lab_unused_checkpoint.json"
	Game.meta_path = "user://audio_lab_unused_meta.json"
	Game.pending_save_kind = ""
	Game._defer_checkpoint = false
	Game.training_mode = false
	Game.training_backup = {}
	Game.training_enemy_id = ""
	Game.training_battle_id = ""
	Game.training_scenery_place_id = ""
	Game.battle_busy = false
	Game.transition_locked = false

func reset(kind: String) -> bool:
	if not active or kind not in ["dialogue", "choices", "mall", "market", "battle", "reward", "map"]: return false
	Game.battle_busy = false
	Game.transition_locked = false
	Game.pending_save_kind = ""
	Game.state = Game.initial_state("noren")
	Game.state.credits = 2000
	Game.state.currentHp = maxi(1, int(Game.state.maxHp) - 10)
	Game.state.deck = ["noren_07", "noren_12", "noren_20"]
	Game.revision += 1
	match kind:
		"dialogue", "choices":
			Game.enter_node("contract" if kind == "choices" else "intro_01")
		"mall", "market":
			Game.state.currentPlaceId = kind
			Game.state.currentScene = "place"
			Game.page = "place"
		"battle", "reward":
			Game.state.activeEventId = "E04"
			Game.state.activeNodeId = "battle" if kind == "battle" else "finish"
			Game.state.currentPlaceId = "alley"
			Game.state.battleId = "B04"
			Game.state.currentScene = "battle" if kind == "battle" else "result"
			Game.page = Game.state.currentScene
			if kind == "battle": Game.initialize_combat()
			else:
				Game.state.result = "win"
				Game.state.battleHistory = [{"battleId":"B04", "result":"win"}]
				Game.prepare_battle_reward()
		"map":
			Game.state.currentScene = "map"
			Game.page = "map"
	return true

func restore() -> void:
	if not active: return
	for field in FIELDS: Game.set(field, backup[field])
	Game.event_refresh_rng.state = refresh_rng_state
	Game.black_market_model.rng.state = market_rng_state
	backup.clear()
	active = false
