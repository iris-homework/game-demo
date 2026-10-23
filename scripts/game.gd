extends Node
const EnemyVisuals = preload("res://scripts/combat/enemy_visual_resolver.gd")
var buffs := preload("res://scripts/combat/effects/buff_library.gd").new()
## Owns state, condition evaluation, transactional actions and checkpoints.
## Views only request transitions; authored content lives in data/.
signal status_changed
signal changed
signal notice(message: String)
signal current_deck_requested
signal technology_loadout_requested
signal menu_requested
signal quit_requested
var assets: Dictionary
var characters: Dictionary
var player_characters: Dictionary
const LEGACY_PLAYER_CHARACTER_ID := "noren"
const PLAYER_REFERENCE := "@player"
const TRAINING_ENEMY_HP := 100
const BATTLE_TYPES := {"normal":"普通战斗", "elite":"精英战斗", "boss":"Boss战"}
const EVENT_REFRESH_LIMIT := 3
var event_refresh_rng := RandomNumberGenerator.new()
var places: Array
var events: Dictionary
var battles: Dictionary
var rewards: Dictionary
var config: Dictionary
var state: Dictionary = {}
var page := "menu"
var save_path := "user://checkpoint.json"
var save_enabled := true
var last_error := ""
var revision := 0
var card_catalog: Dictionary = {}
var enemy_catalog: Dictionary
var enemy_visuals := EnemyVisuals.new()
var item_catalog: Dictionary
var prototype_rules: Dictionary
var reward_rules: Dictionary
var card_reward_rates: Dictionary
var black_market_model := preload("res://scripts/black_market_model.gd").new()
var black_market_rules: Dictionary
var technology_shop_rules: Dictionary
var card_reward_sampler := preload("res://scripts/card_reward_sampler.gd").new()
var noren_rules: Dictionary
var map_config: Dictionary
var meta_profile := {"schemaVersion":1, "cyberwareState":{}}
var meta_path := "user://meta_profile.json"
var transition_locked := false
var battle_busy := false
# Victory routing may checkpoint internally; publish only after its one disk write.
var _defer_checkpoint := false
var training_mode := false
var training_backup: Dictionary = {}
var training_enemies: Array = []
var training_enemy_id := ""
var training_battle_id := ""
# Session-only presentation preferences; neither field belongs to adventure saves.
var b04_scenery_choice := ""
var training_scenery_place_id := ""

func read_data(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))

func _ready() -> void:
	event_refresh_rng.randomize()
	assets = read_data("assets.json")
	characters = read_data("characters.json")
	places = read_data("places.json")
	events = read_data("weeks/week1/events.json")
	battles = read_data("battles.json")
	rewards = read_data("rewards.json")
	config = read_data("config.json")
	for definition in read_data("cards/cards.json"):
		if definition is Dictionary and definition.has("id"): card_catalog[definition.id] = definition
	enemy_catalog = read_data("enemies/enemies.json")
	training_enemies = read_data("training_enemies.json")
	item_catalog = read_data("items/items.json")
	prototype_rules = read_data("prototype/combat.json")
	prototype_rules.cyberware = read_data("prototype/cyberware.json")
	reward_rules = read_data("prototype/rewards.json")
	card_reward_rates = read_data("card_reward_rates.json")
	black_market_rules = read_data("black_market.json")
	technology_shop_rules = read_data("technology_shop.json")
	reward_rules.cards.merge(card_catalog, true)
	noren_rules = read_data("combat/noren.json")
	player_characters = read_data("player_characters.json")
	map_config = read_data("map.json")
	load_meta()

func player_character_id() -> String:
	return state.get("playerCharacterId", config.defaultPlayerCharacterId)

func player_definition() -> Dictionary:
	return player_characters.get(player_character_id(), {})

func player_character() -> Dictionary:
	return characters.get(player_character_id(), {})

func player_asset_id(field: String = "portraitAssetId") -> String:
	return player_character().get(field, "")

func resolve_character_id(id: String) -> String:
	return player_character_id() if id == PLAYER_REFERENCE else id

func cyberware_definition(id: String) -> Dictionary:
	var found: Dictionary = {}
	for definition in prototype_rules.cyberware.cards:
		if not definition is Dictionary or definition.get("id") != id: continue
		if not found.is_empty(): return {} # Duplicate catalog IDs are ambiguous.
		found = definition
	return found

func player_cyberware(player_id: String = "") -> Dictionary:
	var use_loadout := player_id.is_empty()
	if player_id.is_empty(): player_id = player_character_id()
	if not valid_player_character(player_id): return {}
	var rules: Dictionary = prototype_rules.cyberware.duplicate(true)
	rules.cards = []
	for id in (equipped_cyberware_ids() if use_loadout else player_characters[player_id].get("cyberwareIds", [])):
		rules.cards.append(cyberware_definition(id).duplicate(true))
	return rules

func equipped_cyberware_ids() -> Array:
	return state.get("equippedCyberwareIds", player_definition().get("cyberwareIds", [])).duplicate()

func owned_cyberware_ids() -> Array:
	return state.get("ownedCyberwareIds", player_definition().get("cyberwareIds", [])).duplicate()

func valid_owned_technologies(ids) -> bool:
	if not ids is Array: return false
	var seen := []
	for id in ids:
		if not id is String or id in seen: return false
		var definition := cyberware_definition(id)
		if definition.is_empty() or not CombatModel.valid_cyberware_definition(definition): return false
		seen.append(id)
	return true

func valid_equipped_technologies(ids, owned) -> bool:
	if not ids is Array or ids.size() > CombatModel.CYBERWARE_LIMIT or not valid_owned_technologies(owned): return false
	var seen := []
	for id in ids:
		if not id is String or id in seen or not id in owned: return false
		seen.append(id)
	return true

func valid_technology_loadout(ids, player_id: String) -> bool:
	return valid_player_character(player_id) and valid_equipped_technologies(ids, player_characters[player_id].get("cyberwareIds", []))

func open_technology_loadout() -> void:
	if state.is_empty() or page != "map" or state.get("currentScene") != "map" or training_mode or transition_locked or battle_busy: return
	technology_loadout_requested.emit()

func set_technology_loadout(ids: Array, expected_revision: int) -> bool:
	if state.is_empty() or page != "map" or state.get("currentScene") != "map" or training_mode or transition_locked or battle_busy or expected_revision != revision: return false
	if not valid_equipped_technologies(ids, owned_cyberware_ids()): return false
	var previous: Array = equipped_cyberware_ids()
	state.equippedCyberwareIds = ids.duplicate()
	if save_enabled and not save_game():
		state.equippedCyberwareIds = previous
		return false
	revision += 1
	status_changed.emit()
	return true

func valid_player_character(id) -> bool:
	if not id is String or not player_characters.has(id) or not characters.has(id): return false
	var character = characters[id]
	if not character is Dictionary or not character.get("displayName") is String: return false
	if character.displayName.is_empty(): return false
	for field in ["portraitAssetId", "battlePortraitAssetId"]:
		if not character.get(field) is String: return false
	if character.has("mapAvatarCrop"):
		var crop = character.mapAvatarCrop
		if not crop is Array or crop.size() != 4: return false
		for value in crop:
			if not (value is int or value is float) or not is_finite(float(value)): return false
		if crop[0] < 0 or crop[1] < 0 or crop[2] <= 0 or crop[3] <= 0 or crop[0] + crop[2] > 1 or crop[1] + crop[3] > 1: return false
	var definition = player_characters[id]
	if not definition is Dictionary or not definition.get("attributes") is Dictionary: return false
	var hp = definition.attributes.get("maxHp")
	if not (hp is int or hp is float) or not is_finite(float(hp)) or hp < 1 or hp != floor(float(hp)): return false
	if not definition.get("startingDeck") is Array or definition.startingDeck.is_empty(): return false
	for card_id in definition.startingDeck:
		if not card_id is String or not (card_catalog.has(card_id) or prototype_rules.cards.has(card_id) or reward_rules.cards.has(card_id)): return false
	var cyberware_ids = definition.get("cyberwareIds", [])
	if not cyberware_ids is Array or cyberware_ids.size() > CombatModel.CYBERWARE_LIMIT: return false
	var seen_cyberware := []
	for cyberware_id in cyberware_ids:
		if not cyberware_id is String or cyberware_id in seen_cyberware: return false
		var cyberware := cyberware_definition(cyberware_id)
		if cyberware.is_empty(): return false
		if not cyberware.get("name") is String or not cyberware.get("description") is String: return false
		if not CombatModel.valid_cyberware_definition(cyberware): return false
		seen_cyberware.append(cyberware_id)
	# Skills are authored metadata until a specific effect contract is implemented.
	if not definition.get("skills") is Array: return false
	var seen := []
	for skill in definition.skills:
		if not skill is Dictionary: return false
		for field in ["id", "name", "description"]:
			if not skill.get(field) is String: return false
		if skill.id.is_empty() or skill.id in seen: return false
		seen.append(skill.id)
	return true

func initial_state(player_id: String = "") -> Dictionary:
	if player_id.is_empty(): player_id = config.defaultPlayerCharacterId
	if not valid_player_character(player_id): return {}
	var hp := int(player_characters[player_id].attributes.maxHp)
	var fresh := {"schemaVersion":2, "playerCharacterId":player_id, "ownedCyberwareIds":player_characters[player_id].get("cyberwareIds", []).duplicate(), "equippedCyberwareIds":player_characters[player_id].get("cyberwareIds", []).duplicate(), "currentWeek":1, "currentDay":int(config.initialDay), "currentHp":hp, "maxHp":hp, "combat":{}, "battleStart":{}, "inventory":{}, "currentScene":"dialogue", "currentPlaceId":"bar", "activeEventId":"E01", "activeNodeId":"intro_01", "targetId":"", "credits":int(config.initialCredits), "completedEventIds":[], "flags":{}, "claimedRewardIds":[], "choiceHistory":{}, "dialogueHistory":[], "battleId":"", "result":"", "battleHistory":[], "deck":[], "removedStartingCards":[], "battleReward":{}, "battlePassiveReward":{}, "portraits":{"left":PLAYER_REFERENCE, "right":"bartender"}, "refreshedEventIds":[]}
	refresh_event_pool(fresh)
	black_market_model.refresh(fresh, card_catalog, black_market_rules)
	return fresh

func new_game(player_id: String = "") -> void:
	if transition_locked or battle_busy: return
	var fresh := initial_state(player_id)
	if fresh.is_empty():
		notice.emit("主角配置无效，无法开始委托。")
		return
	if training_mode: restore_training()
	if save_enabled: save_meta()
	state = fresh
	enter_node("intro_01")

func meets(condition: Dictionary, subject: Dictionary = {}) -> bool:
	var s: Dictionary = state if subject.is_empty() else subject
	if s.is_empty(): return condition.is_empty()
	for key in condition:
		var value = condition[key]
		match key:
			"all":
				for c in value:
					if not meets(c, s): return false
			"any":
				var found := false
				for c in value:
					if meets(c, s): found = true
				if not found: return false
			"completed":
				if not value in s.completedEventIds: return false
			"flag":
				if not s.flags.get(value, false): return false
			"target":
				if s.targetId != value: return false
			"creditsAtLeast":
				if s.credits < value: return false
			_:
				push_error("Unknown condition: " + key)
				return false
	return true

func place_data(id: String) -> Dictionary:
	for p in places:
		if p.id == id: return p
	return {}

func event_in_refresh_range(event: Dictionary, subject: Dictionary = {}) -> bool:
	var s: Dictionary = state if subject.is_empty() else subject
	var window = event.get("refreshTimeRange", {"startDay":null, "endDay":null})
	if not window is Dictionary: return false
	var start = window.get("startDay")
	var end = window.get("endDay")
	for bound in [start, end]:
		if bound == null: continue
		if not (bound is int or bound is float): return false
		if not is_finite(float(bound)) or bound < 1 or bound != floor(float(bound)): return false
	if start != null and end != null and start > end: return false
	var day := int(s.get("currentDay", config.initialDay))
	return (start == null or day >= start) and (end == null or day <= end)

func event_refresh_time_label(event: Dictionary) -> String:
	var window = event.get("refreshTimeRange", {})
	if not window is Dictionary: return "配置无效"
	var start = window.get("startDay")
	var end = window.get("endDay")
	if start == null and end == null: return "随时"
	if start == null: return "第%d天及以前" % int(end)
	if end == null: return "第%d天起" % int(start)
	return "第%d—%d天" % [int(start), int(end)]

func eligible_events(subject: Dictionary = {}) -> Array:
	var s: Dictionary = state if subject.is_empty() else subject
	if s.is_empty(): return []
	if not s.get("completedEventIds") is Array or not s.get("flags") is Dictionary: return []
	if not s.get("targetId") is String or not (s.get("credits") is int or s.get("credits") is float): return []
	if not (s.get("currentDay") is int or s.get("currentDay") is float): return []
	if not is_finite(float(s.currentDay)) or s.currentDay < 1 or s.currentDay != floor(float(s.currentDay)): return []
	var found: Array = []
	for e in events.values():
		if not e.id in s.get("completedEventIds", []) and meets(e.get("unlockCondition", {}), s) and event_in_refresh_range(e, s) and not place_data(e.placeId).is_empty():
			found.append(e)
	found.sort_custom(func(a, b): return str(a.id) < str(b.id))
	return found

func refresh_event_pool(subject: Dictionary = {}) -> void:
	var s: Dictionary = state if subject.is_empty() else subject
	if s.is_empty(): return
	var candidates: Array = eligible_events(s).map(func(e): return e.id)
	var kept: Array = []
	for id in s.get("refreshedEventIds", []):
		if id in candidates and not id in kept and kept.size() < EVENT_REFRESH_LIMIT:
			kept.append(id)
			candidates.erase(id)
	while kept.size() < EVENT_REFRESH_LIMIT and not candidates.is_empty():
		var index := event_refresh_rng.randi_range(0, candidates.size() - 1)
		kept.append(candidates[index])
		candidates.remove_at(index)
	s.refreshedEventIds = kept

func available_events(place_id: String = "") -> Array:
	# Queries never draw new events or mutate a checkpoint.
	var refreshed: Array = state.get("refreshedEventIds", [])
	var visible: Array = eligible_events().filter(func(e): return e.id in refreshed).slice(0, EVENT_REFRESH_LIMIT)
	return visible.filter(func(e): return place_id.is_empty() or e.placeId == place_id)

func map_target_events() -> Array:
	return available_events()

func map_event_type(event_id: String) -> String:
	# Map events use upcoming authored battles, never a previous frozen combat.
	# Dialogue-only events are normal; branches use the highest configured tier.
	var kind := "normal"
	for battle in battles.values():
		if str(battle.get("eventId", "")) != event_id: continue
		var candidate := configured_battle_type(str(battle.get("id", "")))
		if candidate == "boss": return "boss"
		if candidate == "elite": kind = "elite"
	return kind

func map_place_state(id: String) -> Dictionary:
	var p := place_data(id)
	if p.is_empty(): return {}
	var available: Array = available_events(id)
	var completed := false
	for e in events.values():
		if e.placeId == id and e.id in state.get("completedEventIds", []):
			completed = true
			break
	return {"place":p, "open":true, "available":available,
		"current":state.get("currentPlaceId", "") == id,
		"target":not available.is_empty(),
		"completed":completed and available.is_empty(), "services":p.get("services", [])}

func objective() -> String:
	if state.get("flags", {}).get("week1Complete", false): return "第一周已完成 · 可继续探索剩余事件"
	var targets := map_target_events()
	if targets.size() == 1: return targets[0].title + "  /  " + place_data(targets[0].placeId).name
	if targets.size() > 1: return "%d 个可进行的事件" % targets.size()
	return "探索城市，寻找新的线索"

func event_data() -> Dictionary:
	return events.get(state.get("activeEventId", ""), {})

func node_data() -> Dictionary:
	return event_data().get("nodes", {}).get(state.get("activeNodeId", ""), {})

func display_name(id: String) -> String:
	return characters.get(resolve_character_id(id), {}).get("displayName", "旁白")

func render_text(value: String) -> String:
	value = value.replace("{主角姓名}", display_name(PLAYER_REFERENCE))
	var target: String = state.get("targetId", "")
	if "{目标姓名}" in value:
		if target.is_empty():
			value = value.replace("{目标姓名}", "委托目标")
		elif not characters.has(target):
			push_error("Unresolved target variable")
			return "内容配置错误：缺少委托目标。"
		value = value.replace("{目标姓名}", display_name(target))
	if "{" in value:
		push_error("Unknown dialogue variable")
		return "内容配置错误：未知对白变量。"
	return value

func texture(id: String) -> Texture2D:
	var path: String = assets.get(id, {}).get("path", "")
	if path.is_empty() or not ResourceLoader.exists(path): return null
	return load(path)

func checkpoint() -> void:
	refresh_event_pool()
	if not training_mode: black_market_model.refresh(state, card_catalog, black_market_rules)
	revision += 1
	if _defer_checkpoint:
		page = state.currentScene
		return
	if save_enabled and not training_mode: save_game()
	page = state.currentScene
	changed.emit()

func go_map() -> void:
	if transition_locked or battle_busy or is_run_over(): return
	state.currentScene = "map"
	checkpoint()

func visit(id: String) -> void:
	if transition_locked or battle_busy or is_run_over(): return
	var p := place_data(id)
	if p.is_empty(): return
	state.currentPlaceId = id
	state.currentScene = "place"
	checkpoint()

func start_event(id: String) -> bool:
	if transition_locked or battle_busy or is_run_over(): return false
	if not events.has(id): return false
	var e: Dictionary = events[id]
	if not id in state.get("refreshedEventIds", []) or id in state.completedEventIds or not meets(e.unlockCondition) or not event_in_refresh_range(e): return false
	if place_data(e.placeId).is_empty(): return false
	state.activeEventId = id
	state.currentPlaceId = e.placeId
	state.battleId = ""
	state.result = ""
	state.battleReward = {}
	state.battlePassiveReward = {}
	state.combat = {}
	state.battleStart = {}
	state.portraits = {"left":PLAYER_REFERENCE, "right":""}
	enter_node(e.startNodeId)
	return true

func apply_actions(actions: Array) -> bool:
	# Validate the entire list on a copy; a rejected action never partially commits.
	var draft := state.duplicate(true)
	for a in actions:
		match a.get("op", ""):
			"setFlag":
				if not a.get("key", "") is String or a.get("key", "").is_empty(): return false
				draft.flags[a.key] = a.get("value", true)
			"spendCredits":
				var amount := int(a.get("amount", -1))
				if amount < 0 or draft.credits < amount: return false
				draft.credits -= amount
			"addCredits":
				var amount := int(a.get("amount", -1))
				if amount < 0: return false
				draft.credits += amount
			"setTarget":
				if not a.get("value", "") in ["richard", "lumina"]: return false
				draft.targetId = a.value
			"completeEvent":
				if not events.has(a.get("id", "")): return false
				if not a.id in draft.completedEventIds:
					draft.completedEventIds.append(a.id)
					# The opening conversation completes normally without spending a day.
					if a.id != "E01":
						draft.currentDay = mini(7, int(draft.currentDay) + 1)
			"healHpPercent":
				var percent := float(a.get("percent", -1.0))
				if percent < 0.0 or percent > 1.0: return false
				draft.currentHp = mini(int(draft.maxHp), int(draft.currentHp) + roundi(draft.maxHp * percent))
			"advanceDay":
				var days := int(a.get("days", 1))
				if days < 0: return false
				draft.currentDay = mini(7, int(draft.currentDay) + days)
			"finishWeek":
				draft.flags.week1Complete = true
			"grantReward":
				var id: String = a.get("id", "")
				if not rewards.has(id): return false
				var claim_id: String = draft.activeEventId + ":" + id
				if claim_id in draft.claimedRewardIds: continue
				var reward: Dictionary = rewards[id]
				if reward.get("type", "") != "credits" or int(reward.get("amount", -1)) < 0: return false
				draft.claimedRewardIds.append(claim_id)
				draft.credits += int(reward.amount)
			_:
				push_error("Rejected action: " + str(a))
				return false
	if not training_mode: black_market_model.refresh(draft, card_catalog, black_market_rules)
	state = draft
	return true

func enter_node(id: String) -> void:
	if transition_locked or battle_busy or (not training_mode and is_run_over()): return
	if id == "@map":
		go_map()
		return
	if not event_data().nodes.has(id):
		notice.emit("对白节点不存在：" + id)
		return
	state.activeNodeId = id
	var n := node_data()
	match n.get("type", "dialogue"):
		"finish":
			var actions: Array = n.get("effects", []).duplicate(true)
			actions.append({"op":"completeEvent", "id":state.activeEventId})
			if not apply_actions(actions):
				notice.emit("事件配置错误，状态未提交。")
				return
			state.currentScene = "result"
			prepare_battle_reward()
		"battle":
			state.battleId = n.battleId
			state.currentScene = "battle"
			initialize_combat()
		_:
			state.currentScene = "dialogue"
			record_dialogue()
			var side: String = n.get("speakerSide", "")
			if side in ["left", "right"] and not n.get("speakerId", "").is_empty():
				var speaker: String = n.speakerId
				var other := "right" if side == "left" else "left"
				if resolve_character_id(state.portraits[other]) == resolve_character_id(speaker): state.portraits[other] = ""
				state.portraits[side] = speaker
	checkpoint()

func record_dialogue(choice_text: String = "") -> void:
	# Store rendered snapshots, never traverse unseen branches to reconstruct a log.
	if not state.has("dialogueHistory"): state.dialogueHistory = []
	var n := node_data()
	var speaker: String = n.get("speakerId", "")
	state.dialogueHistory.append({
		"eventId": state.activeEventId,
		"title": event_data().title,
		"speaker": "你的选择" if not choice_text.is_empty() else (display_name(speaker) if not speaker.is_empty() else "场景"),
		"text": render_text(choice_text if not choice_text.is_empty() else n.get("text", "")),
		"kind": "choice" if not choice_text.is_empty() else "dialogue"
	})

func advance(expected_revision: int) -> void:
	if transition_locked or battle_busy or expected_revision != revision or state.currentScene != "dialogue": return
	var n := node_data()
	if n.has("next"): enter_node(n.next)

func skip_dialogue(expected_revision: int) -> void:
	if transition_locked or battle_busy or expected_revision != revision or page != "dialogue" or state.currentScene != "dialogue": return
	# Follow the same route as Continue, preserving portraits, battle entry and rewards.
	# Never choose on the player's behalf, even if a choice node also has a next field.
	var visited: Dictionary = {}
	while state.currentScene == "dialogue" and not transition_locked and not battle_busy:
		var n := node_data()
		if not n.get("choices", []).is_empty() or not n.has("next"): return
		visited[state.activeNodeId] = true
		if visited.has(n.next):
			notice.emit("剧情路径存在循环，已停止跳过。")
			return
		var previous_revision := revision
		advance(revision)
		if revision == previous_revision: return

func choose(index: int, expected_revision: int) -> bool:
	if transition_locked or battle_busy or expected_revision != revision or state.currentScene != "dialogue": return false
	var choices: Array = node_data().get("choices", [])
	if index < 0 or index >= choices.size(): return false
	var c: Dictionary = choices[index]
	if not meets(c.get("condition", {})): return false
	if not event_data().nodes.has(c.next) and c.next != "@map": return false
	if not apply_actions(c.get("effects", [])): return false
	state.choiceHistory[state.activeEventId + ":" + state.activeNodeId] = c.id
	record_dialogue(c.label)
	enter_node(c.next)
	return true

func battle_exit(result: String, expected_revision: int) -> bool:
	if result not in ["win", "lose"]: return false
	if transition_locked or battle_busy or expected_revision != revision or state.currentScene != "battle": return false
	if not training_mode and is_run_over() and result != "lose": return false
	var b: Dictionary = battles.get(state.battleId, {})
	if b.is_empty(): return false
	if training_mode:
		finish_training(result)
		return true
	if result == "win" and not b.get("returnNodeByResult", {}).has(result): return false
	if result == "lose":
		mark_run_failed(state)
		checkpoint()
		return true
	if state.get("currentHp", 0) <= 0 or state.get("combat", {}).get("playerHp", 0) <= 0: return false
	# Keep ownership, payment, healing, claims and the first post-battle node in
	# one checkpoint. No scene/status signal escapes before the write succeeds.
	var previous := state
	var previous_page := page
	var previous_revision := revision
	state = state.duplicate(true)
	state.result = result
	state.battleHistory.append({"battleId":state.battleId, "result":result})
	state.battleStart = {}
	_apply_victory_technologies()
	_defer_checkpoint = true
	enter_node(b.returnNodeByResult[result])
	_defer_checkpoint = false
	if state.currentScene == "battle" or (save_enabled and not save_game()):
		state = previous
		page = previous_page
		revision = previous_revision
		return false
	changed.emit()
	return true

func _apply_victory_technologies() -> void:
	var claim_id: String = state.activeEventId + ":" + state.battleId + ":passive_victory"
	if claim_id in state.claimedRewardIds: return
	var credits := 0
	var healing := 0
	for definition in state.get("combat", {}).get("profile", {}).get("cyberware", {}).get("cards", []).slice(0, CombatModel.CYBERWARE_LIMIT):
		if not CombatModel.valid_cyberware_definition(definition) or not CombatModel.is_passive_cyberware(definition): continue
		if definition.effect == "victory_credits": credits += int(definition.amount)
		elif definition.effect == "victory_heal": healing += int(definition.amount)
	if credits == 0 and healing == 0: return
	healing = mini(healing, maxi(0, int(state.maxHp) - int(state.currentHp)))
	state.credits += credits
	state.currentHp += healing
	if not state.combat.is_empty(): state.combat.playerHp = state.currentHp
	state.claimedRewardIds.append(claim_id)
	state.battlePassiveReward = {"claimId":claim_id, "eventId":state.activeEventId, "battleId":state.battleId, "credits":credits, "healing":healing}

func battle_passive_summary() -> Dictionary:
	var reward: Dictionary = state.get("battlePassiveReward", {})
	if training_mode or reward.get("eventId", "") != state.get("activeEventId", "") or reward.get("battleId", "") != state.get("battleId", ""):
		return {"credits":0, "healing":0}
	return {"credits":int(reward.get("credits", 0)), "healing":int(reward.get("healing", 0))}

func valid_battle_passive_reward(subject: Dictionary) -> bool:
	var reward = subject.get("battlePassiveReward", {})
	if not reward is Dictionary: return false
	if reward.is_empty(): return true
	for key in ["claimId", "eventId", "battleId"]:
		if not reward.get(key) is String: return false
	for key in ["credits", "healing"]:
		var value = reward.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0 or value != floor(float(value)): return false
	if reward.healing > subject.maxHp: return false
	if reward.eventId != subject.activeEventId or reward.battleId != subject.battleId: return false
	if reward.claimId != reward.eventId + ":" + reward.battleId + ":passive_victory" or not reward.claimId in subject.claimedRewardIds: return false
	return {"battleId":reward.battleId, "result":"win"} in subject.battleHistory

func is_run_over(subject: Dictionary = {}) -> bool:
	var s: Dictionary = state if subject.is_empty() else subject
	return s.get("currentScene", "") == "defeat" or s.get("result", "") == "lose" or (s.get("currentScene", "") == "dialogue" and s.get("activeNodeId", "") == "lose") or (s.get("currentScene", "") == "battle" and s.get("combat", {}).get("outcome", "") == "lose")

func mark_run_failed(subject: Dictionary) -> void:
	# Also used for a lethal snapshot saved before its presentation has finished.
	if subject.get("result", "") != "lose" and subject.get("battleHistory") is Array:
		subject.battleHistory.append({"battleId":subject.get("battleId", ""), "result":"lose"})
	subject.result = "lose"
	subject.currentScene = "defeat"
	subject.battleStart = {}
	subject.battleReward = {}

func claim_rewards(expected_revision: int) -> bool:
	if transition_locked or battle_busy or expected_revision != revision or state.currentScene != "result": return false
	var actions: Array = []
	for id in event_data().get("rewardIds", []): actions.append({"op":"grantReward", "id":id})
	if not apply_actions(actions): return false
	if has_battle_reward() and state.battleReward.status == "pending":
		state.battleReward.status = "skipped"
	go_map()
	return true

func prepare_battle_reward() -> void:
	# Finish-node entry occurs only after all authored post-battle dialogue.
	if training_mode or state.result != "win": return
	var battle: Dictionary = battles.get(state.battleId, {})
	if battle.get("eventId", "") != state.activeEventId: return
	if not {"battleId":state.battleId, "result":"win"} in state.battleHistory: return
	var claim_id: String = state.activeEventId + ":" + state.battleId + ":victory"
	if claim_id in state.claimedRewardIds: return
	var kind := battle_type()
	var rates = card_reward_rates.get(kind, {})
	var options: Array[String] = card_reward_sampler.sample(card_catalog, rates) if rates is Dictionary else []
	if options.size() != 3:
		notice.emit("奖励卡牌配置错误：无法生成三个不同选项，请检查概率与卡牌池。")
		return
	state.credits += int(reward_rules.credits)
	state.claimedRewardIds.append(claim_id)
	state.battleReward = {"claimId":claim_id, "eventId":state.activeEventId,
		"battleId":state.battleId, "battleType":kind, "credits":int(reward_rules.credits),
		"options":options, "selectedCardId":"", "status":"pending"}

func has_battle_reward() -> bool:
	var reward: Dictionary = state.get("battleReward", {})
	return not training_mode and state.get("currentScene", "") == "result" and not reward.is_empty() and reward.get("eventId", "") == state.activeEventId and reward.get("battleId", "") == state.battleId

func choose_reward_card(id: String, expected_revision: int) -> bool:
	if transition_locked or battle_busy or expected_revision != revision or not has_battle_reward(): return false
	var reward: Dictionary = state.battleReward
	if reward.status != "pending" or not id in reward.options or not reward_rules.cards.has(id): return false
	# One checkpoint contains both ownership and the consumed choice.
	state.deck.append(id)
	reward.selectedCardId = id
	reward.status = "claimed"
	checkpoint()
	return true

func restart_unfinished_battle(subject: Dictionary) -> bool:
	# Old saves have no recoverable opening HP/deck order; retain their snapshot.
	# Completed results remain committed, including a lethal hit during playback.
	if subject.get("currentScene", "") != "battle": return false
	var opening: Dictionary = subject.get("battleStart", {})
	var combat: Dictionary = subject.get("combat", {})
	if opening.is_empty() or combat.is_empty() or not combat.get("outcome", "").is_empty(): return false
	subject.combat = opening.duplicate(true)
	subject.currentHp = int(opening.playerHp)
	return true

func save_game() -> bool:
	# Keep live combat in memory; only the restart point goes to disk until win/lose.
	var saved := state.duplicate(true)
	if not training_mode:
		if is_run_over(saved): mark_run_failed(saved)
		else: restart_unfinished_battle(saved)
	var temp := save_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = "存档无法写入，请检查目录权限。"
		notice.emit(last_error)
		return false
	file.store_string(JSON.stringify(saved, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "保存检查点写入失败：" + str(write_error)
		notice.emit(last_error)
		return false
	# Never replace a good recovery copy with a damaged primary checkpoint.
	# Stage the backup too: a failed copy must not truncate the existing backup.
	if checkpoint_file_is_valid(save_path):
		var backup_temp := save_path + ".bak.tmp"
		var backup_error := DirAccess.copy_absolute(save_path, backup_temp)
		if backup_error == OK:
			backup_error = DirAccess.rename_absolute(backup_temp, save_path + ".bak")
		if backup_error != OK:
			last_error = "备份检查点失败：" + str(backup_error)
			notice.emit(last_error)
			return false
	var err := DirAccess.rename_absolute(temp, save_path)
	if err != OK:
		last_error = "保存检查点失败：" + str(err)
		notice.emit(last_error)
	return err == OK

func checkpoint_file_is_valid(path: String) -> bool:
	if not FileAccess.file_exists(path): return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return false
	# Legacy validation may generate missing pools on a copy. Do not consume the
	# live adventure's random sequences merely to decide whether to rotate a file.
	var event_rng_state := event_refresh_rng.state
	var market_rng_state := black_market_model.rng.state
	var valid := valid_save(migrate_save(parser.data))
	event_refresh_rng.state = event_rng_state
	black_market_model.rng.state = market_rng_state
	return valid

func valid_save(s) -> bool:
	if not s is Dictionary or s.get("schemaVersion", 0) != 2: return false
	if s.has("faction"): return false # Legacy fields must pass through migration first.
	if not valid_player_character(s.get("playerCharacterId")): return false
	if not valid_equipped_technologies(s.get("equippedCyberwareIds"), s.get("ownedCyberwareIds")): return false
	for k in initial_state(s.playerCharacterId):
		if not s.has(k): return false
	for key in ["currentScene", "currentPlaceId", "activeEventId", "activeNodeId", "targetId", "battleId", "result"]:
		if not s[key] is String: return false
	for key in ["maxHp", "currentHp", "currentDay", "credits"]:
		if not (s[key] is int or s[key] is float): return false
	if s.maxHp <= 0 or s.currentHp < 0 or s.currentHp > s.maxHp: return false
	if not is_finite(float(s.currentDay)) or s.currentDay < 1 or s.currentDay > 7 or s.currentDay != floor(float(s.currentDay)): return false
	if not s.refreshedEventIds is Array or s.refreshedEventIds.size() > EVENT_REFRESH_LIMIT: return false
	var seen_events := []
	for id in s.refreshedEventIds:
		if not id is String or not events.has(id) or id in seen_events: return false
		seen_events.append(id)
	if not s.combat is Dictionary or not s.inventory is Dictionary: return false
	if not s.combat.is_empty() and not valid_combat(s.combat): return false
	if not valid_battle_start(s): return false
	if not s.combat.is_empty() and s.combat.profile.get("playerCharacterId", s.playerCharacterId) != s.playerCharacterId: return false
	if not s.completedEventIds is Array or not s.flags is Dictionary or not s.choiceHistory is Dictionary or not s.portraits is Dictionary: return false
	if not s.claimedRewardIds is Array or not s.battleHistory is Array: return false
	if not s.deck is Array or not s.battleReward is Dictionary: return false
	if not valid_removed_starting_cards(s): return false
	if not black_market_model.valid(s.get("blackMarket"), card_catalog, black_market_rules): return false
	if not s.get("dialogueHistory", []) is Array: return false
	for entry in s.get("dialogueHistory", []):
		if not entry is Dictionary: return false
		for key in ["eventId", "title", "speaker", "text", "kind"]:
			if not entry.get(key) is String: return false
		if entry.kind not in ["dialogue", "choice"]: return false
	for id in s.deck:
		if not id is String or not (reward_rules.cards.has(id) or card_catalog.has(id) or prototype_rules.cards.has(id)): return false
	if not valid_battle_reward(s) or not valid_battle_passive_reward(s): return false
	if not (s.credits is float or s.credits is int) or s.credits < 0: return false
	if not s.currentScene in ["map", "place", "dialogue", "battle", "result", "defeat"]: return false
	if s.currentScene == "defeat" and (s.result != "lose" or not s.battleStart.is_empty() or not s.battleReward.is_empty()): return false
	if not s.targetId in ["", "richard", "lumina"]: return false
	if not s.portraits.has("left") or not s.portraits.has("right"): return false
	for side in ["left", "right"]:
		var portrait_id = s.portraits[side]
		if not portrait_id is String: return false
		if not portrait_id in ["", PLAYER_REFERENCE] and not characters.has(portrait_id): return false
	if place_data(s.currentPlaceId).is_empty(): return false
	if not events.has(s.activeEventId) or not events[s.activeEventId].nodes.has(s.activeNodeId): return false
	if s.currentScene == "battle":
		if not battles.has(s.battleId): return false
		if not s.combat.is_empty() and (s.combat.battleId != s.battleId or s.combat.playerHp != s.currentHp): return false
	return true

func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")

func can_continue() -> bool:
	if not state.is_empty(): return not is_run_over()
	# Read only; follow the same main/backup precedence as load_game().
	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path): continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK: continue
		var data = migrate_save(parser.data)
		if valid_save(data): return not is_run_over(data)
	# Keep the existing damaged-save error available when neither file validates.
	return has_save()

func load_game() -> bool:
	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path): continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK: continue
		var data = migrate_save(parser.data)
		if not valid_save(data): continue
		restart_unfinished_battle(data)
		refresh_event_pool(data)
		var previous_state := state
		state = data
		state.credits = int(state.credits)
		# Persist newly generated legacy/stale stock so reloading cannot reroll it.
		if save_enabled and data.get("blackMarket") != parser.data.get("blackMarket"):
			if not save_game():
				state = previous_state
				return false
		if state.dialogueHistory.is_empty() and state.currentScene == "dialogue": record_dialogue()
		page = state.currentScene
		revision += 1
		changed.emit()
		if path.ends_with(".bak"): notice.emit("已从备用检查点恢复进度。")
		if parser.data.get("activeEventId", "") in ["E05A", "E05B", "E06", "E07", "E08", "E09", "E10", "E12"]:
			notice.emit("旧事件已移除。非战败进度已返回地图；已有信用点、卡牌和日期保留，未选奖励不再领取。")
		return true
	last_error = "存档格式不兼容或已损坏，无法继续；可以开始新游戏。"
	notice.emit(last_error)
	return false

## User navigation asks the main view to confirm before changing adventure state.
func request_menu() -> void:
	if transition_locked or battle_busy or page == "menu": return
	if page in ["card_library", "cyberware", "defeat"]:
		menu()
	else:
		menu_requested.emit()

func request_quit() -> void:
	if transition_locked or battle_busy or page != "menu": return
	quit_requested.emit()

func menu() -> void:
	if transition_locked or battle_busy: return
	if training_mode: restore_training()
	elif is_run_over() and state.get("currentScene", "") != "defeat":
		mark_run_failed(state)
		revision += 1
	elif restart_unfinished_battle(state): revision += 1
	page = "menu"
	changed.emit()

func resume() -> void:
	if state.is_empty(): load_game()
	else:
		if not training_mode:
			if is_run_over():
				mark_run_failed(state)
				revision += 1
			elif restart_unfinished_battle(state): revision += 1
		page = state.currentScene
		changed.emit()


func enemy_combat_visual(enemy: Dictionary) -> EnemyVisuals.Visual:
	return enemy_visuals.resolve(enemy, enemy_catalog)

func configured_battle_type(battle_id: String) -> String:
	var value = battles.get(battle_id, {}).get("battleType", "normal")
	return value if value is String and BATTLE_TYPES.has(value) else "normal"

func battle_type(battle_id: String = "") -> String:
	var id: String = state.get("battleId", "") if battle_id.is_empty() else battle_id
	var combat: Dictionary = state.get("combat", {})
	# Existing battles retain their frozen type; legacy snapshots count as normal.
	if not combat.is_empty() and combat.get("battleId", "") == id:
		return combat.get("profile", {}).get("battleType", "normal")
	return configured_battle_type(id)

func battle_type_label(kind: String) -> String:
	return BATTLE_TYPES.get(kind, BATTLE_TYPES.normal)

func initialize_combat() -> void:
	state.battlePassiveReward = {}
	var battle: Dictionary = battles[state.battleId]
	var definitions: Array = []
	for id in battle.enemyIds:
		var definition: Dictionary = enemy_catalog[id].duplicate(true)
		if training_mode and battle.get("trainingEnemyHp", TRAINING_ENEMY_HP) != null:
			definition.maxHp = int(battle.get("trainingEnemyHp", TRAINING_ENEMY_HP))
		definitions.append(definition)
	var model := CombatModel.new()
	var rules := prototype_rules.duplicate(true)
	var player := player_definition()
	if player.get("combatRules", "") == "noren_v1": rules.merge(noren_rules, true)
	rules.battleType = configured_battle_type(state.battleId)
	rules.playerCharacterId = player_character_id()
	rules.playerAttributes = player.attributes.duplicate(true)
	rules.playerSkills = player.skills.duplicate(true)
	rules.playerCyberwareIds = equipped_cyberware_ids()
	rules.cyberware = player_cyberware()
	rules.deck = full_deck_ids()
	rules.cards.merge(reward_rules.cards, false)
	model.initialize(state.battleId, int(state.currentHp), int(state.maxHp), rules, definitions, card_catalog)
	state.combat = model.snapshot()
	# Capture after the initial shuffle, before the first draw; never reroll on resume.
	state.battleStart = {} if training_mode else state.combat.duplicate(true)

func commit_combat(model: CombatModel) -> void:
	state.combat = model.snapshot()
	state.currentHp = model.player_hp
	revision += 1
	if save_enabled and not training_mode: save_game()
	status_changed.emit()

func healing_service(place_id: String) -> Dictionary:
	# Views and commits consume the same authored price, percentage and availability.
	var p := place_data(place_id)
	for service in p.get("services", []):
		if not service is Dictionary or service.get("type", "") != "healHpPercent": continue
		var percent_value = service.get("percent", -1)
		var cost_value = service.get("creditsCost", 0)
		if not (percent_value is int or percent_value is float) or not (cost_value is int or cost_value is float): return {}
		var percent := float(percent_value)
		var cost := int(cost_value)
		if not is_finite(percent) or percent <= 0.0 or percent > 1.0 or cost_value != cost or cost < 0: return {}
		var amount := mini(int(state.get("maxHp", 0)) - int(state.get("currentHp", 0)), roundi(int(state.get("maxHp", 0)) * percent))
		var reason := ""
		if int(state.get("currentHp", 0)) >= int(state.get("maxHp", 0)):
			reason = "生命值已满，无需治疗"
		elif amount <= 0:
			reason = "当前生命值无法恢复"
		elif int(state.get("credits", 0)) < cost:
			reason = "信用点不足（需要 %d）" % cost
		var price := "%d 信用点" % cost if cost > 0 else "免费"
		var label_text := "治疗 %d%% · %s" % [roundi(percent * 100.0), price]
		var hint := "回复 %d%% 最大生命值；%s；不推进日期。" % [roundi(percent * 100.0), price]
		if not reason.is_empty(): hint += "\n" + reason + "。"
		return {"percent":percent, "credits_cost":cost, "amount":amount, "can_heal":reason.is_empty(), "reason":reason, "label":label_text, "hint":hint}
	return {}

func heal_at(place_id: String) -> bool:
	if transition_locked or battle_busy or not state.currentScene in ["map", "place"]: return false
	var service := healing_service(place_id)
	if service.is_empty(): return false
	if not service.can_heal:
		notice.emit(service.reason)
		return false
	var previous := int(state.currentHp)
	var actions: Array = [
		{"op":"spendCredits", "amount":service.credits_cost},
		{"op":"healHpPercent", "percent":service.percent},
	]
	if not apply_actions(actions): return false
	checkpoint()
	var payment := "支付 %d 信用点 · " % service.credits_cost if service.credits_cost > 0 else ""
	notice.emit(payment + "生命恢复 +%d  /  %d HP" % [int(state.currentHp)-previous, state.maxHp])
	return true

func training_scenery_choices() -> Array[Dictionary]:
	var choices: Array[Dictionary] = [{"id":"", "name":"默认场景（后巷）"}]
	for place_id in ["garden","hive","port","pump","junkyard","hotel","tower","block5","church","alley","bar"]:
		var place: Dictionary = place_data(place_id)
		var asset_id: String = assets.get(place.get("backgroundAssetId",""),{}).get("battleAssetId","")
		var definition: Dictionary = assets.get(asset_id,{})
		if definition.get("battleEnabled",true) and definition.get("trainingSelectable",false) and texture(asset_id) != null:
			choices.append({"id":place_id,"name":place.name})
	return choices

func set_b04_scenery_choice(place_id: String) -> bool:
	if training_mode or transition_locked or battle_busy: return false
	for choice in training_scenery_choices():
		if choice.id == place_id:
			b04_scenery_choice = place_id
			return true
	return false

func training_enemy_choices() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for definition in training_enemies:
		choices.append(definition.duplicate(true))
	return choices

func start_enemy_training(id: String) -> void:
	if page != "menu" or transition_locked or battle_busy or training_mode: return
	for definition in training_enemies:
		if definition.id != id: continue
		var temporary_id := "training_" + id
		if battles.has(temporary_id) or enemy_catalog.has(temporary_id): return
		# Practice definitions exist only for this session, never in story content.
		var enemy: Dictionary = definition.duplicate(true)
		enemy.id = temporary_id
		enemy.characterId = id
		enemy.battlePortraitAssetId = ""
		enemy.prototype = false
		enemy_catalog[temporary_id] = enemy
		battles[temporary_id] = {
			"id":temporary_id, "eventId":"", "name":definition.displayName + "演练",
			"battleType":"normal", "placeId":definition.placeId,
			"enemyIds":[temporary_id], "trainingOnly":true, "trainingEnemyHp":100
		}
		training_enemy_id = temporary_id
		training_battle_id = temporary_id
		start_training(temporary_id)
		if not training_mode: _clear_training_encounter()
		return

func _clear_training_encounter() -> void:
	if not training_enemy_id.is_empty(): enemy_catalog.erase(training_enemy_id)
	if not training_battle_id.is_empty(): battles.erase(training_battle_id)
	training_enemy_id = ""
	training_battle_id = ""

func start_training(battle_id: String = "B04") -> void:
	if transition_locked or battle_busy or training_mode or not battles.has(battle_id): return
	if not battles[battle_id].get("trainingOnly", false):
		var event: Dictionary = events.get(battles[battle_id].eventId, {})
		if event.is_empty() or not event.get("nodes", {}).has("battle") or event.nodes.battle.get("battleId") != battle_id: return
	var fresh := initial_state(player_character_id())
	if fresh.is_empty(): return
	fresh.deck = state.get("deck", []).duplicate()
	fresh.removedStartingCards = state.get("removedStartingCards", []).duplicate()
	if valid_equipped_technologies(state.get("equippedCyberwareIds"), state.get("ownedCyberwareIds")):
		fresh.ownedCyberwareIds = owned_cyberware_ids()
		fresh.equippedCyberwareIds = equipped_cyberware_ids()
	training_backup = state.duplicate(true)
	training_scenery_place_id = ""
	if battle_id == "B04":
		for choice in training_scenery_choices():
			if choice.id == b04_scenery_choice:
				training_scenery_place_id = b04_scenery_choice
				break
	training_mode = true
	state = fresh
	state.targetId = "richard"
	state.activeEventId = battles[battle_id].eventId
	state.currentPlaceId = battles[battle_id].placeId
	if battles[battle_id].get("trainingOnly", false):
		state.battleId = battle_id
		state.currentScene = "battle"
		initialize_combat()
		checkpoint()
	else:
		enter_node("battle")

func restore_training() -> void:
	state = training_backup.duplicate(true)
	training_backup.clear()
	_clear_training_encounter()
	training_mode = false
	training_scenery_place_id = ""

func finish_training(result: String) -> void:
	if not training_mode or result not in ["win", "lose"]: return
	restore_training()
	page = "menu"
	revision += 1
	changed.emit()
	notice.emit("演练结束：%s。冒险进度和血量未改变。" % {"win":"胜利","lose":"失败"}.get(result,result))

func open_cyberware() -> void:
	if transition_locked or battle_busy: return
	page = "cyberware"
	changed.emit()

func open_card_library() -> void:
	if transition_locked or battle_busy or page != "menu": return
	# Like the archive, this is a menu page, never an adventure checkpoint.
	page = "card_library"
	changed.emit()

func open_current_deck() -> void:
	if state.is_empty() or transition_locked or battle_busy: return
	current_deck_requested.emit()

func library_cards() -> Array:
	# Enumerate definitions, not owned copies or a battle's frozen snapshot.
	# Match combat's precedence: formal definitions win over prototype IDs.
	var catalog := card_catalog.duplicate(true)
	# Retired test cards stay loadable, but are not in the new 40-card catalogue.
	var definitions: Array = catalog.values()
	definitions.sort_custom(card_display_before)
	return definitions.duplicate(true)

func card_display_before(a: Dictionary, b: Dictionary) -> bool:
	var ranks := {"C":0,"B":1,"A":2,"S":3}
	var a_rank: int = ranks.get(str(a.get("rarity", "")).to_upper(),4)
	var b_rank: int = ranks.get(str(b.get("rarity", "")).to_upper(),4)
	if a_rank != b_rank: return a_rank < b_rank
	var a_order := int(a.get("sortOrder",2147483647))
	var b_order := int(b.get("sortOrder",2147483647))
	if a_order != b_order: return a_order < b_order
	return str(a.get("id", "")).naturalnocasecmp_to(str(b.get("id", ""))) < 0

func load_meta() -> bool:
	if not FileAccess.file_exists(meta_path): return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(meta_path)) != OK: return false
	if not json.data is Dictionary or json.data.get("schemaVersion",0) != 1 or not json.data.get("cyberwareState") is Dictionary: return false
	meta_profile = json.data
	return true

func save_meta() -> bool:
	var file := FileAccess.open(meta_path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(meta_profile, "\t"))
	file.close()
	return DirAccess.rename_absolute(meta_path + ".tmp", meta_path) == OK

func migrate_save(data):
	if not data is Dictionary: return data
	data = data.duplicate(true)
	# Legacy checkpoints always belonged to Noren, even if the default changes.
	if not data.has("playerCharacterId"):
		data.playerCharacterId = LEGACY_PLAYER_CHARACTER_ID
		if data.get("portraits") is Dictionary:
			for side in ["left", "right"]:
				if data.portraits.get(side) == LEGACY_PLAYER_CHARACTER_ID:
					data.portraits[side] = PLAYER_REFERENCE
	if not data.has("battleReward"): data.battleReward = {}
	if not data.has("battlePassiveReward"): data.battlePassiveReward = {}
	if not data.has("dialogueHistory"): data.dialogueHistory = []
	if not data.has("battleStart"): data.battleStart = {}
	if not data.has("equippedCyberwareIds") and valid_player_character(data.get("playerCharacterId")):
		data.equippedCyberwareIds = player_characters[data.playerCharacterId].get("cyberwareIds", []).duplicate()
	if not data.has("ownedCyberwareIds") and valid_player_character(data.get("playerCharacterId")):
		data.ownedCyberwareIds = player_characters[data.playerCharacterId].get("cyberwareIds", []).duplicate()
	if data.get("schemaVersion",0) == 1:
		data = data.duplicate(true)
		data.schemaVersion = 2
		data.currentHp = 100
		data.maxHp = 100
		data.currentDay = 1
		data.combat = {}
		data.battleStart = {}
		data.inventory = {}
	if not data.has("removedStartingCards"): data.removedStartingCards = []
	black_market_model.refresh(data, card_catalog, black_market_rules)
	migrate_mercenary_story(data)
	# Keep an existing draw across reloads; legacy saves get a pool without
	# retroactively charging days for events they completed before this rule.
	if not data.has("refreshedEventIds"):
		data.refreshedEventIds = []
		refresh_event_pool(data)
	# Additive schema-2 upgrade: old battles gain the temporary catalog, with
	# no used cards or pending buff. Existing snapshots retain their own rules.
	var combat = data.get("combat", {})
	if combat is Dictionary and not combat.is_empty():
		if combat.get("profile") is Dictionary and not combat.profile.has("cyberware"):
			if valid_player_character(data.get("playerCharacterId")):
				combat.profile.cyberware = player_cyberware(data.playerCharacterId)
	# New terminal page and old authored lose nodes share the same failed run.
	# Keep malformed combat data for valid_save() to reject rather than hide it.
	if data.get("combat", {}) is Dictionary and is_run_over(data): mark_run_failed(data)
	return data

func migrate_mercenary_story(data: Dictionary) -> void:
	# Retire removed content without replaying completion, rewards or day costs.
	data.erase("faction")
	var retired_events := ["E05A", "E05B", "E06", "E07", "E08", "E09", "E10", "E12"]
	var retired_battles := ["B05A", "B05B", "B08", "B09", "B10", "B12"]
	var retired_characters := ["reception", "rift", "victor", "fitz", "company_robot", "ally_robot", "wolves"]
	var active = data.get("activeEventId", "")
	var retired_context: bool = active in retired_events or data.get("battleId", "") in retired_battles
	if retired_context:
		# A retired encounter must never turn a failed run back into a live one.
		var failed: bool = data.get("currentScene", "") == "defeat" or data.get("result", "") == "lose" or (data.get("currentScene", "") == "dialogue" and data.get("activeNodeId", "") == "lose")
		var combat = data.get("combat", {})
		if combat is Dictionary and combat.get("outcome", "") == "lose": failed = true
		if failed: mark_run_failed(data)
		data.activeEventId = "E01"
		data.activeNodeId = "finish"
		data.currentPlaceId = "bar"
		data.currentScene = "defeat" if failed else "map"
		data.battleId = ""
		data.result = "lose" if failed else ""
		data.combat = {}
		data.battleStart = {}
		# Credits and already selected cards stay; pending retired offers are closed.
		data.battleReward = {}
		data.battlePassiveReward = {}
		data.portraits = {"left":PLAYER_REFERENCE, "right":""}
	if data.get("completedEventIds") is Array:
		data.completedEventIds = data.completedEventIds.filter(func(id): return not id in retired_events)
	if data.get("refreshedEventIds") is Array:
		data.refreshedEventIds = data.refreshedEventIds.filter(func(id): return not id in retired_events)
	if data.get("choiceHistory") is Dictionary:
		for key in data.choiceHistory.keys():
			if key is String and key.get_slice(":", 0) in retired_events:
				data.choiceHistory.erase(key)
	if data.get("flags") is Dictionary:
		# The authored first-week finale has been removed with E12.
		data.flags.erase("week1Complete")
	if data.get("portraits") is Dictionary:
		for side in ["left", "right"]:
			if data.portraits.get(side, "") in retired_characters: data.portraits[side] = ""

func valid_battle_start(s: Dictionary) -> bool:
	var opening = s.get("battleStart", {})
	if not opening is Dictionary: return false
	if opening.is_empty(): return true # Legacy in-progress battles remain loadable.
	if s.get("currentScene") != "battle" or s.combat.is_empty(): return false
	if not valid_combat(opening): return false
	if opening.battleId != s.get("battleId") or opening.battleId != s.combat.battleId: return false
	if opening.turn != 1 or opening.maxHp != s.get("maxHp"): return false
	if opening.outcome != ("lose" if opening.playerHp == 0 else ""): return false
	if opening.get("openingDrawDone") != false or not opening.hand.is_empty() or not opening.discardPile.is_empty(): return false
	if not opening.get("norenState", {}).get("exhaustPile", []).is_empty(): return false
	# Both snapshots must describe the same frozen encounter and card instances.
	for field in ["profile", "cardCatalog", "instances", "maxHp"]:
		if opening[field] != s.combat[field]: return false
	if opening.enemies.size() != s.combat.enemies.size(): return false
	for i in opening.enemies.size():
		var enemy_id = opening.enemies[i].get("id")
		if not enemy_id is String or enemy_id != s.combat.enemies[i].get("id"): return false
		if opening.enemies[i].maxHp != s.combat.enemies[i].maxHp: return false
	return true

func valid_battle_reward(s: Dictionary) -> bool:
	var r: Dictionary = s.battleReward
	if r.is_empty(): return true
	if not r.get("battleType", "normal") is String or not BATTLE_TYPES.has(r.get("battleType", "normal")): return false
	for key in ["claimId", "eventId", "battleId", "selectedCardId", "status"]:
		if not r.get(key) is String: return false
	if r.eventId != s.activeEventId or r.battleId != s.battleId: return false
	if not battles.has(r.battleId) or battles[r.battleId].eventId != r.eventId: return false
	if r.claimId != r.eventId + ":" + r.battleId + ":victory" or not r.claimId in s.claimedRewardIds: return false
	if not (r.get("credits") is int or r.get("credits") is float) or r.credits != int(reward_rules.credits): return false
	if not r.get("options") is Array or r.options.size() != 3: return false
	var seen := []
	for id in r.options:
		if not id is String or not reward_rules.cards.has(id) or id in seen: return false
		seen.append(id)
	if not r.status in ["pending", "claimed", "skipped"]: return false
	# A claim records the past selection; the acquired copy may since have been sold.
	# The claim receipt and original offer remain validated above, independently of ownership.
	if r.status == "claimed": return r.selectedCardId in r.options
	return r.selectedCardId.is_empty()

func valid_frozen_card(definition) -> bool:
	# Validate the frozen shape, never compare historical balance values to today's catalog.
	if not definition is Dictionary: return false
	for key in ["name", "type"]:
		if not definition.get(key) is String or definition[key].is_empty(): return false
	for key in ["id", "description", "cardText", "rarity", "target", "artAssetId"]:
		if definition.has(key) and not definition[key] is String: return false
	if definition.has("rarity") and (not definition.has("cost") or not definition.get("description") is String): return false
	if definition.has("cost") and definition.cost != null:
		if not (definition.cost is int or definition.cost is float) or not is_finite(float(definition.cost)): return false
	for key in ["exhaust", "consumeAllAmmo"]:
		if definition.has(key) and not definition[key] is bool: return false
	if not definition.get("effects") is Array: return false
	for effect in definition.effects:
		if not effect is Dictionary or not effect.get("type") is String or effect.type.is_empty(): return false
		for key in ["id", "value", "when"]:
			if effect.has(key) and not effect[key] is String: return false
		for key in ["amount", "hits", "cap", "executeBonus", "lastAmmoBonus", "rangedBonus", "requiresBleed", "bleedTriggers", "woundedMeleeAmount"]:
			if effect.has(key) and (not (effect[key] is int or effect[key] is float) or not is_finite(float(effect[key]))): return false
		for key in ["allAmmoHits", "rangedIgnoreBlock"]:
			if effect.has(key) and not effect[key] is bool: return false
	return true

func valid_combat(c: Dictionary) -> bool:
	for key in ["battleId","turn","playerHp","maxHp","drawPile","hand","discardPile","instances","enemies","outcome","log","profile","cardCatalog"]:
		if not c.has(key): return false
	if not c.battleId is String or not battles.has(c.battleId): return false
	for key in ["turn", "playerHp", "maxHp"]:
		if not (c[key] is float or c[key] is int): return false
	if c.turn < 1 or c.maxHp <= 0 or c.playerHp < 0 or c.playerHp > c.maxHp: return false
	for key in ["drawPile","hand","discardPile","enemies","log"]:
		if not c[key] is Array: return false
	for key in ["instances","profile","cardCatalog"]:
		if not c[key] is Dictionary: return false
	if not c.profile.get("battleType", "normal") is String or not BATTLE_TYPES.has(c.profile.get("battleType", "normal")): return false
	if not c.outcome in ["", "win", "lose", "surrender"]: return false
	if not valid_cyberware_state(c): return false
	if c.profile.get("ruleset", "") == "noren_v1" and not valid_noren_state(c): return false
	var seen: Array = []
	var exhausted: Array = c.get("norenState", {}).get("exhaustPile", []) if c.profile.get("ruleset", "") == "noren_v1" else []
	for uid in c.drawPile + c.hand + c.discardPile + exhausted:
		if not uid is String or uid in seen or not c.instances.has(uid): return false
		seen.append(uid)
		if not c.instances[uid] is String or not c.cardCatalog.has(c.instances[uid]): return false
		if not valid_frozen_card(c.cardCatalog[c.instances[uid]]): return false
	if seen.size() != c.instances.size(): return false
	for enemy in c.enemies:
		if not enemy is Dictionary: return false
		for key in ["id","displayName","hp","maxHp","intent","intentIndex","battlePortraitAssetId"]:
			if not enemy.has(key): return false
		if not enemy.intent is Dictionary: return false
		for key in ["hp", "maxHp", "intentIndex"]:
			if not (enemy[key] is float or enemy[key] is int): return false
		if enemy.hp < 0 or enemy.maxHp <= 0 or enemy.hp > enemy.maxHp: return false
		if not enemy.intent.get("amount",0) is float and not enemy.intent.get("amount",0) is int: return false
		if not enemy.intent.get("hits",1) is float and not enemy.intent.get("hits",1) is int: return false
		if enemy.intent.get("amount",0) < 0 or enemy.intent.get("hits",1) < 1: return false
		if not valid_conditional_intent(enemy, c.enemies): return false
	return true

func valid_conditional_intent(enemy: Dictionary, encounter: Array) -> bool:
	# Optional phase data is frozen per encounter; old saves need no migration.
	if not enemy.has("allyDeathIntentSequence"): return not enemy.has("intentPhase")
	var branch = enemy.allyDeathIntentSequence
	if not branch is Dictionary or not branch.get("allyIds") is Array or not branch.get("sequence") is Array: return false
	if branch.allyIds.is_empty() or branch.sequence.is_empty() or not enemy.get("intentSequence") is Array: return false
	var seen: Array = []
	for id in branch.allyIds:
		if not id is String or id == enemy.id or id in seen or not encounter.any(func(ally): return ally is Dictionary and ally.get("id") == id): return false
		seen.append(id)
	if enemy.get("intentPhase", "") not in ["", "ally_death"]: return false
	if not buffs._valid_count(enemy.intentIndex): return false
	for intent in enemy.intentSequence + branch.sequence + [enemy.intent]:
		if not intent is Dictionary or intent.get("type", "") not in ["attack", "vulnerable", "strength_allies"]: return false
		if not buffs._valid_count(intent.get("amount"), 999): return false
		if not buffs._valid_count(intent.get("hits", 1)) or intent.get("hits", 1) < 1: return false
		if intent.type == "strength_allies":
			if not intent.get("targetIds") is Array or intent.targetIds.is_empty(): return false
			for id in intent.targetIds:
				if not id in branch.allyIds: return false
	return true

func valid_cyberware_state(c: Dictionary) -> bool:
	var used = c.get("usedCyberware", [])
	var bonus = c.get("nextAttackBonus", 0)
	if not used is Array or not (bonus is int or bonus is float): return false
	if not is_finite(float(bonus)) or bonus < 0 or bonus != floor(float(bonus)): return false
	var rules = c.profile.get("cyberware", {})
	if not rules is Dictionary or not rules.get("cards", []) is Array: return false
	var catalog := {}
	var cooldown_limits := {}
	var passive_ids := []
	for definition in rules.get("cards", []):
		if not definition is Dictionary: return false
		if not CombatModel.valid_cyberware_definition(definition): return false
		if catalog.has(definition.id): return false
		catalog[definition.id] = int(definition.get("nextAttackBonus", 0))
		cooldown_limits[definition.id] = int(definition.get("cooldownTurns", 1))
		if CombatModel.is_passive_cyberware(definition): passive_ids.append(definition.id)
	# New battles freeze the character's list beside its definitions. Older
	# snapshots may also carry a longer historical list; the current slot limit
	# applies to new character configurations, not frozen save definitions.
	if c.profile.has("playerCyberwareIds"):
		var ids = c.profile.playerCyberwareIds
		if not ids is Array or ids != catalog.keys(): return false
	var seen := []
	var maximum := 0
	# Preserve the historical upper bound for unspent attack bonuses.
	# New non-damage technologies contribute zero, even while on cooldown.
	for amount in catalog.values(): maximum += amount * (int(c.turn) - 1)
	for id in used:
		if not id is String or id in seen or not catalog.has(id) or id in passive_ids: return false
		seen.append(id)
		maximum += catalog[id]
	if c.has("cyberwareCooldowns"):
		var cooldowns = c.cyberwareCooldowns
		if not cooldowns is Dictionary or cooldowns.size() != used.size(): return false
		for id in cooldowns:
			if not id is String or not id in used: return false
			var remaining = cooldowns[id]
			if not (remaining is int or remaining is float) or not is_finite(float(remaining)): return false
			if remaining < 1 or remaining != floor(float(remaining)) or remaining > cooldown_limits[id]: return false
	else:
		# Only historical one-turn definitions may omit the new cooldown state.
		for id in used:
			if cooldown_limits[id] != 1: return false
	return bonus <= maximum

func valid_removed_starting_cards(subject: Dictionary) -> bool:
	var removed = subject.get("removedStartingCards")
	if not removed is Array: return false
	var available: Array = player_characters.get(subject.get("playerCharacterId", ""), {}).get("startingDeck", []).duplicate()
	for id in removed:
		if not id is String or not id in available: return false
		available.erase(id)
	return true

func full_deck_ids(subject: Dictionary = {}) -> Array:
	var source: Dictionary = state if subject.is_empty() else subject
	var player_id: String = source.get("playerCharacterId", config.defaultPlayerCharacterId)
	var ids: Array = player_characters.get(player_id, {}).get("startingDeck", []).duplicate()
	for id in source.get("removedStartingCards", []): ids.erase(id)
	ids.append_array(source.get("deck", []))
	return ids

func technology_shop_offers() -> Array:
	# Fixed catalog; adventure ownership is the purchase record, with no restock.
	var offers = technology_shop_rules.get("offers")
	if not offers is Array or offers.size() > 6: return []
	var seen := []
	for offer in offers:
		if not offer is Dictionary or not offer.get("id") is String or offer.id in seen: return []
		if offer.id.begins_with("test_"): return []
		var definition := cyberware_definition(offer.id)
		if definition.is_empty() or not CombatModel.valid_cyberware_definition(definition): return []
		var price = offer.get("price")
		if not (price is int or price is float) or not is_finite(float(price)) or price <= 0 or price != floor(float(price)): return []
		seen.append(offer.id)
	return offers.duplicate(true)

func buy_shop_technology(index: int, expected_revision: int) -> bool:
	if state.is_empty() or page != "place" or state.get("currentScene") != "place" or state.get("currentPlaceId") != "mall":
		return _market_reject("请先进入沃斯商场。")
	if training_mode or transition_locked or battle_busy or is_run_over(): return _market_reject("当前无法购买科技。")
	if expected_revision != revision: return _market_reject("商场状态已更新，请重新选择。")
	var offers := technology_shop_offers()
	if offers.is_empty(): return _market_reject("科技商品配置无效。")
	if index < 0 or index >= offers.size(): return _market_reject("无效的科技商品位置。")
	var offer: Dictionary = offers[index]
	var owned := owned_cyberware_ids()
	if not valid_owned_technologies(owned): return _market_reject("已有科技记录无效。")
	if offer.id in owned: return _market_reject("本次冒险已经拥有这项科技。")
	if state.credits < offer.price: return _market_reject("信用点不足。")
	var draft := state.duplicate(true)
	draft.credits -= int(offer.price)
	owned.append(offer.id)
	draft.ownedCyberwareIds = owned
	return _commit_market(draft)

func market_buy_price(card_id: String) -> int:
	return black_market_model.price(card_catalog.get(card_id, {}), black_market_rules)

func market_sell_price(card_id: String) -> int:
	var definition: Dictionary = card_catalog.get(card_id, reward_rules.cards.get(card_id, prototype_rules.cards.get(card_id, {})))
	if not definition.is_empty() and definition.get("rarity", "") not in ["C", "B", "A", "S"]:
		return int(black_market_rules.get("legacySellPrice", 25))
	return black_market_model.price(definition, black_market_rules, false)

func black_market_state() -> Dictionary:
	return state.get("blackMarket", {}).duplicate(true)

func ensure_black_market() -> bool:
	if state.is_empty() or training_mode or transition_locked or battle_busy: return false
	var draft := state.duplicate(true)
	if not black_market_model.refresh(draft, card_catalog, black_market_rules):
		return black_market_model.valid(state.get("blackMarket"), card_catalog, black_market_rules)
	return _commit_market(draft)

func _market_reject(message: String) -> bool:
	last_error = message
	notice.emit(message)
	return false

func _market_can_trade(expected_revision: int) -> bool:
	if state.is_empty() or page != "place" or state.get("currentScene") != "place" or state.get("currentPlaceId") != "market":
		return _market_reject("请先进入黑市。")
	if training_mode or transition_locked or battle_busy or is_run_over(): return _market_reject("当前无法交易。")
	if expected_revision != revision: return _market_reject("黑市状态已更新，请重新选择。")
	var stock = state.get("blackMarket")
	if not black_market_model.valid(stock, card_catalog, black_market_rules): return _market_reject("黑市库存无效。")
	if stock.week != state.currentWeek or stock.restockDay != black_market_model.period(int(state.currentDay), black_market_rules):
		return _market_reject("黑市已到补货时间，请重新进入。")
	return true

func _commit_market(draft: Dictionary) -> bool:
	var previous := state
	state = draft
	if save_enabled and not save_game():
		state = previous
		return false
	revision += 1
	last_error = ""
	status_changed.emit()
	return true

func buy_market_card(index: int, expected_revision: int) -> bool:
	if not _market_can_trade(expected_revision): return false
	if index < 0 or index >= state.blackMarket.slots.size(): return _market_reject("无效的商品位置。")
	var slot: Dictionary = state.blackMarket.slots[index]
	if slot.sold: return _market_reject("这张卡牌已经售罄。")
	if state.credits < slot.price: return _market_reject("信用点不足。")
	var draft := state.duplicate(true)
	draft.credits -= int(slot.price)
	draft.deck.append(slot.cardId)
	draft.blackMarket.slots[index].sold = true
	return _commit_market(draft)

func sell_market_card(card_id: String, expected_revision: int) -> bool:
	if not _market_can_trade(expected_revision): return false
	if state.blackMarket.soldCardUsed: return _market_reject("本轮已出售过卡牌，补货后可再次出售。")
	if not card_id in full_deck_ids(): return _market_reject("当前卡组没有这张卡牌。")
	var price := market_sell_price(card_id)
	if price <= 0: return _market_reject("这张卡牌暂不支持回收。")
	var draft := state.duplicate(true)
	# Added copies are removed first; otherwise record one removed starting copy.
	if card_id in draft.deck: draft.deck.erase(card_id)
	else: draft.removedStartingCards.append(card_id)
	draft.credits += price
	draft.blackMarket.soldCardUsed = true
	return _commit_market(draft)

func owned_card_counts() -> Dictionary:
	var counts := {}
	var ids := full_deck_ids()
	for id in ids: counts[id] = int(counts.get(id, 0)) + 1
	return counts

func resolve_card_id(query: String) -> String:
	if card_catalog.has(query): return query
	for definition in card_catalog.values():
		if definition.name == query or (query.is_valid_int() and int(definition.number) == int(query)):
			return definition.id
	return ""

func console_command(command: String) -> String:
	var args := command.strip_edges().split(" ", false)
	if args.is_empty(): return "输入 help 查看指令。"
	match args[0].to_lower():
		"help": return "cards [关键词]：查询卡牌名称、编号和 ID\nowned：查看已拥有数量\naddcard <牌名/编号/ID> [数量]：添加卡牌（默认 1，最多 99）\n示例：addcard 深度伤口 2　或　addcard 36 2\n新增卡牌保存至当前冒险，下场战斗生效；新委托重置。"
		"cards":
			var lines: PackedStringArray = []
			var query := args[1] if args.size() > 1 else ""
			for definition in library_cards():
				if query.is_empty() or query in definition.name or query in definition.id or query == definition.number:
					lines.append("%s  %s [%s]  %s" % [definition.number, definition.name, definition.rarity, definition.id])
			return "\n".join(lines) if not lines.is_empty() else "没有匹配的卡牌。"
		"owned":
			if state.is_empty(): return "请先开始或继续委托。"
			var counts := owned_card_counts()
			var lines: PackedStringArray = []
			for id in counts:
				var definition: Dictionary = card_catalog.get(id, reward_rules.cards.get(id, prototype_rules.cards.get(id, {})))
				lines.append("%s ×%d" % [definition.get("name", id), counts[id]])
			return "\n".join(lines)
		"addcard":
			if not config.developmentMode: return "开发模式未开启。"
			if state.is_empty(): return "请先开始或继续委托，再添加卡牌。"
			if training_mode: return "演练不写入冒险；请退出演练后加牌。"
			if transition_locked or battle_busy: return "请等当前动作结束后再加牌。"
			if args.size() < 2 or args.size() > 3: return "用法：addcard <牌名/编号/ID> [数量]"
			var id := resolve_card_id(args[1])
			if id.is_empty(): return "未找到卡牌。输入 cards 查询。"
			if args.size() == 3 and not args[2].is_valid_int(): return "数量必须为 1～99 的整数。"
			var amount := int(args[2]) if args.size() == 3 else 1
			if amount < 1 or amount > 99: return "数量必须为 1～99 的整数。"
			var old_deck: Array = state.deck.duplicate()
			for i in amount: state.deck.append(id)
			if save_enabled and not save_game():
				state.deck = old_deck
				return "添加失败：存档无法写入，已撤回本次加牌。"
			return "已添加 %s ×%d；当前拥有 %d 张。下场战斗生效。" % [card_catalog[id].name, amount, owned_card_counts()[id]]
	return "未知指令。输入 help 查看指令。"

func valid_noren_state(c: Dictionary) -> bool:
	var n = c.get("norenState")
	if not n is Dictionary or not c.get("openingDrawDone") is bool: return false
	for key in ["energy", "ammo"]:
		var value = n.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0 or value != floor(float(value)): return false
	# Energy resets each turn; only technologies activated this turn can raise
	# its ceiling. Use frozen definitions so older battles keep their own rules.
	var maximum_energy := int(c.profile.get("energyPerTurn", 3))
	for definition in c.profile.get("cyberware", {}).get("cards", []).slice(0, CombatModel.CYBERWARE_LIMIT):
		if definition.get("effect", "") != "gain_energy" or not definition.id in c.get("usedCyberware", []): continue
		if int(c.get("cyberwareCooldowns", {}).get(definition.id, 1)) == int(definition.get("cooldownTurns", 1)):
			maximum_energy += int(definition.amount)
	if n.energy > maximum_energy or n.ammo > int(c.profile.get("ammoCap", 10)): return false
	if n.get("stance") not in ["melee", "ranged"]: return false
	if not n.get("exhaustPile") is Array: return false
	return buffs.valid_snapshot(c)
