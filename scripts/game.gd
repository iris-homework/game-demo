extends Node
const EnemyVisuals = preload("res://scripts/combat/enemy_visual_resolver.gd")
var buffs := preload("res://scripts/combat/effects/buff_library.gd").new()
## Owns state, condition evaluation, transactional actions and checkpoints.
## Views only request transitions; authored content lives in data/.
signal status_changed
signal changed
signal notice(message: String)
signal current_deck_requested
var assets: Dictionary
var characters: Dictionary
var player_characters: Dictionary
const LEGACY_PLAYER_CHARACTER_ID := "noren"
const PLAYER_REFERENCE := "@player"
const TRAINING_ENEMY_HP := 100
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
var noren_rules: Dictionary
var map_config: Dictionary
var meta_profile := {"schemaVersion":1, "cyberwareState":{}}
var meta_path := "user://meta_profile.json"
var transition_locked := false
var battle_busy := false
var training_mode := false
var training_backup: Dictionary = {}
# Session-only presentation preferences; neither field belongs to adventure saves.
var b04_scenery_choice := ""
var training_scenery_place_id := ""

func read_data(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))

func _ready() -> void:
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
	item_catalog = read_data("items/items.json")
	prototype_rules = read_data("prototype/combat.json")
	prototype_rules.cyberware = read_data("prototype/cyberware.json")
	reward_rules = read_data("prototype/rewards.json")
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
	if player_id.is_empty(): player_id = player_character_id()
	if not valid_player_character(player_id): return {}
	var rules: Dictionary = prototype_rules.cyberware.duplicate(true)
	rules.cards = []
	for id in player_characters[player_id].get("cyberwareIds", []):
		rules.cards.append(cyberware_definition(id).duplicate(true))
	return rules

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
		var amount = cyberware.get("nextAttackBonus")
		if not (amount is int or amount is float) or not is_finite(float(amount)) or amount < 1 or amount != floor(float(amount)): return false
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
	return {"schemaVersion":2, "playerCharacterId":player_id, "currentWeek":1, "currentDay":int(config.initialDay), "currentHp":hp, "maxHp":hp, "combat":{}, "inventory":{}, "currentScene":"dialogue", "currentPlaceId":"bar", "activeEventId":"E01", "activeNodeId":"intro_01", "targetId":"", "credits":int(config.initialCredits), "completedEventIds":[], "flags":{}, "claimedRewardIds":[], "choiceHistory":{}, "dialogueHistory":[], "battleId":"", "result":"", "battleHistory":[], "deck":[], "battleReward":{}, "portraits":{"left":PLAYER_REFERENCE, "right":"bartender"}}

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

func available_events(place_id: String = "") -> Array:
	var found: Array = []
	for e in events.values():
		if (place_id.is_empty() or e.placeId == place_id) and not e.id in state.get("completedEventIds", []) and meets(e.unlockCondition):
			found.append(e)
	found.sort_custom(func(a, b): return int(a.optional) < int(b.optional))
	return found

func map_target_events() -> Array:
	# UI targets are derived from authored progress, never the last activeEventId.
	if state.get("flags", {}).get("week1Complete", false): return []
	var targets: Array = []
	for e in available_events():
		var p := place_data(e.placeId)
		if not e.optional and not p.is_empty():
			targets.append(e)
	targets.sort_custom(func(a, b): return str(a.id) < str(b.id))
	return targets

func map_place_state(id: String) -> Dictionary:
	var p := place_data(id)
	if p.is_empty(): return {}
	var available: Array = available_events(id)
	available.sort_custom(func(a, b):
		if bool(a.optional) != bool(b.optional): return not bool(a.optional)
		return str(a.id) < str(b.id))
	var main_events: Array = []
	var optional_events: Array = []
	for e in available:
		if e.optional: optional_events.append(e)
		else: main_events.append(e)
	var completed := false
	for e in events.values():
		if e.placeId == id and e.id in state.get("completedEventIds", []):
			completed = true
			break
	return {"place":p, "open":true, "available":available,
		"main_events":main_events, "optional_events":optional_events,
		"current":state.get("currentPlaceId", "") == id,
		"target":not main_events.is_empty() and not state.get("flags", {}).get("week1Complete", false),
		"completed":completed and available.is_empty(), "services":p.get("services", [])}

func objective() -> String:
	if state.get("flags", {}).get("week1Complete", false): return "第一周已完成 · 可继续探索支线"
	var targets := map_target_events()
	if targets.size() == 1: return targets[0].title + "  /  " + place_data(targets[0].placeId).name
	if targets.size() > 1: return "%d 个可推进的主线目标" % targets.size()
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
		if not characters.has(target):
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
	revision += 1
	if save_enabled and not training_mode: save_game()
	page = state.currentScene
	changed.emit()

func go_map() -> void:
	if transition_locked or battle_busy: return
	state.currentScene = "map"
	checkpoint()

func visit(id: String) -> void:
	if transition_locked or battle_busy: return
	var p := place_data(id)
	if p.is_empty(): return
	state.currentPlaceId = id
	state.currentScene = "place"
	checkpoint()

func start_event(id: String) -> bool:
	if transition_locked or battle_busy: return false
	if not events.has(id): return false
	var e: Dictionary = events[id]
	if id in state.completedEventIds or not meets(e.unlockCondition): return false
	if place_data(e.placeId).is_empty(): return false
	state.activeEventId = id
	state.currentPlaceId = e.placeId
	state.battleId = ""
	state.result = ""
	state.battleReward = {}
	state.combat = {}
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
				if not a.id in draft.completedEventIds: draft.completedEventIds.append(a.id)
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
	state = draft
	return true

func enter_node(id: String) -> void:
	if transition_locked or battle_busy: return
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
	var b: Dictionary = battles.get(state.battleId, {})
	if not b.get("returnNodeByResult", {}).has(result): return false
	if training_mode:
		finish_training(result)
		return true
	state.result = result
	state.battleHistory.append({"battleId":state.battleId, "result":result})
	enter_node(b.returnNodeByResult[result])
	return true

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
	state.credits += int(reward_rules.credits)
	state.claimedRewardIds.append(claim_id)
	var options: Array = card_catalog.keys().filter(func(id): return card_catalog[id].get("rarity", "C") != "C")
	options.shuffle()
	options = options.slice(0, 3)
	if options.size() < 3: options = reward_rules.cards.keys().slice(0, 3)
	state.battleReward = {"claimId":claim_id, "eventId":state.activeEventId,
		"battleId":state.battleId, "credits":int(reward_rules.credits),
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

func save_game() -> bool:
	var temp := save_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = "存档无法写入，请检查目录权限。"
		notice.emit(last_error)
		return false
	file.store_string(JSON.stringify(state, "\t"))
	file.flush()
	file.close()
	# Keep the previous valid snapshot for recovery from interruption/corruption.
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(save_path, save_path + ".bak")
	var err := DirAccess.rename_absolute(temp, save_path)
	if err != OK:
		last_error = "保存检查点失败：" + str(err)
		notice.emit(last_error)
	return err == OK

func valid_save(s) -> bool:
	if not s is Dictionary or s.get("schemaVersion", 0) != 2: return false
	if s.has("faction"): return false # Legacy fields must pass through migration first.
	if not valid_player_character(s.get("playerCharacterId")): return false
	for k in initial_state(s.playerCharacterId):
		if not s.has(k): return false
	for key in ["currentScene", "currentPlaceId", "activeEventId", "activeNodeId", "targetId", "battleId", "result"]:
		if not s[key] is String: return false
	for key in ["maxHp", "currentHp", "currentDay", "credits"]:
		if not (s[key] is int or s[key] is float): return false
	if s.maxHp <= 0 or s.currentHp < 0 or s.currentHp > s.maxHp or s.currentDay < 1 or s.currentDay > 7: return false
	if not s.combat is Dictionary or not s.inventory is Dictionary: return false
	if not s.combat.is_empty() and not valid_combat(s.combat): return false
	if not s.combat.is_empty() and s.combat.profile.get("playerCharacterId", s.playerCharacterId) != s.playerCharacterId: return false
	if not s.completedEventIds is Array or not s.flags is Dictionary or not s.choiceHistory is Dictionary or not s.portraits is Dictionary: return false
	if not s.claimedRewardIds is Array or not s.battleHistory is Array: return false
	if not s.deck is Array or not s.battleReward is Dictionary: return false
	if not s.get("dialogueHistory", []) is Array: return false
	for entry in s.get("dialogueHistory", []):
		if not entry is Dictionary: return false
		for key in ["eventId", "title", "speaker", "text", "kind"]:
			if not entry.get(key) is String: return false
		if entry.kind not in ["dialogue", "choice"]: return false
	for id in s.deck:
		if not id is String or not (reward_rules.cards.has(id) or card_catalog.has(id) or prototype_rules.cards.has(id)): return false
	if not valid_battle_reward(s): return false
	if not (s.credits is float or s.credits is int) or s.credits < 0: return false
	if not s.currentScene in ["map", "place", "dialogue", "battle", "result"]: return false
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

func load_game() -> bool:
	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path): continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK: continue
		var data = migrate_save(parser.data)
		if not valid_save(data): continue
		state = data
		state.credits = int(state.credits)
		if state.dialogueHistory.is_empty() and state.currentScene == "dialogue": record_dialogue()
		page = state.currentScene
		revision += 1
		changed.emit()
		if path.ends_with(".bak"): notice.emit("已从备用检查点恢复进度。")
		if parser.data.get("activeEventId", "") in ["E06", "E07", "E09", "E10"]:
			notice.emit("旧阵营事件已移除，已返回港口。已有信用点和卡牌保留，该事件未选的奖励卡不再领取。")
		return true
	last_error = "存档格式不兼容或已损坏，无法继续；可以开始新游戏。"
	notice.emit(last_error)
	return false

func menu() -> void:
	if transition_locked or battle_busy: return
	if training_mode: restore_training()
	page = "menu"
	changed.emit()

func resume() -> void:
	if state.is_empty(): load_game()
	else:
		page = state.currentScene
		changed.emit()


func enemy_combat_visual(enemy: Dictionary) -> EnemyVisuals.Visual:
	return enemy_visuals.resolve(enemy, enemy_catalog)

func initialize_combat() -> void:
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
	rules.playerCharacterId = player_character_id()
	rules.playerAttributes = player.attributes.duplicate(true)
	rules.playerSkills = player.skills.duplicate(true)
	rules.playerCyberwareIds = player.get("cyberwareIds", []).duplicate()
	rules.cyberware = player_cyberware()
	rules.deck = player.startingDeck.duplicate()
	rules.cards.merge(reward_rules.cards, false)
	rules.deck.append_array(state.deck)
	model.initialize(state.battleId, int(state.currentHp), int(state.maxHp), rules, definitions, card_catalog)
	state.combat = model.snapshot()

func commit_combat(model: CombatModel) -> void:
	state.combat = model.snapshot()
	state.currentHp = model.player_hp
	revision += 1
	if save_enabled and not training_mode: save_game()
	status_changed.emit()

func heal_at(place_id: String) -> bool:
	if transition_locked or battle_busy or not state.currentScene in ["map", "place"]: return false
	var p := place_data(place_id)
	if p.is_empty(): return false
	for service in p.get("services", []):
		if service.type == "healHpPercent":
			var previous := int(state.currentHp)
			if not apply_actions([{"op":"healHpPercent", "percent":service.percent}]): return false
			checkpoint()
			notice.emit("生命恢复 +%d  /  %d HP" % [int(state.currentHp)-previous, state.maxHp])
			return true
	return false

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

func start_training(battle_id: String = "B12") -> void:
	if transition_locked or battle_busy or training_mode or not battles.has(battle_id): return
	var fresh := initial_state(player_character_id())
	if fresh.is_empty(): return
	fresh.deck = state.get("deck", []).duplicate()
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
	enter_node("battle")

func restore_training() -> void:
	state = training_backup.duplicate(true)
	training_backup.clear()
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
	if not data.has("dialogueHistory"): data.dialogueHistory = []
	if data.get("schemaVersion",0) == 1:
		data = data.duplicate(true)
		data.schemaVersion = 2
		data.currentHp = 100
		data.maxHp = 100
		data.currentDay = 1
		data.combat = {}
		data.inventory = {}
	migrate_mercenary_story(data)
	# Additive schema-2 upgrade: old battles gain the temporary catalog, with
	# no used cards or pending buff. Existing snapshots retain their own rules.
	var combat = data.get("combat", {})
	if combat is Dictionary and not combat.is_empty():
		if combat.get("profile") is Dictionary and not combat.profile.has("cyberware"):
			if valid_player_character(data.get("playerCharacterId")):
				combat.profile.cyberware = player_cyberware(data.playerCharacterId)
	return data

func migrate_mercenary_story(data: Dictionary) -> void:
	# Removed story content is handled here only; no live allegiance remains.
	data.erase("faction")
	var retired_events := ["E06", "E07", "E09", "E10"]
	var retired_battles := ["B09", "B10"]
	var retired_characters := ["reception", "rift", "victor", "fitz", "company_robot", "ally_robot", "wolves"]
	var active = data.get("activeEventId", "")
	if active in retired_events:
		var port_event := "E05A" if active in ["E06", "E09"] else "E05B"
		if data.get("completedEventIds") is Array:
			if not port_event in data.completedEventIds: data.completedEventIds.append(port_event)
		if data.get("targetId", "") == "":
			data.targetId = "richard" if port_event == "E05A" else "lumina"
		data.activeEventId = port_event
		data.activeNodeId = "finish"
		data.currentPlaceId = "port"
		data.currentScene = "map"
		data.battleId = ""
		data.result = ""
		data.combat = {}
		# Already paid credits and selected cards stay in their original fields.
		# An unselected reward belonging to a removed encounter is retired with it.
		data.battleReward = {}
		data.portraits = {"left":PLAYER_REFERENCE, "right":""}
	elif active in ["E05A", "E05B"]:
		var node = data.get("activeNodeId", "")
		var removed_node: bool = node == "join" or (node is String and (node.begins_with("accept_") or node.begins_with("refuse_") or node in ["win_05", "win_06", "win_07"]))
		if removed_node:
			data.activeNodeId = "win_03"
			data.portraits = {"left":PLAYER_REFERENCE, "right":""}
	if data.get("completedEventIds") is Array:
		data.completedEventIds = data.completedEventIds.filter(func(id): return not id in retired_events)
	if data.get("choiceHistory") is Dictionary:
		for key in data.choiceHistory.keys():
			if not key is String: continue
			if key.get_slice(":", 0) in retired_events or key in ["E05A:join", "E05B:join"]:
				data.choiceHistory.erase(key)
	if data.get("battleId", "") in retired_battles:
		data.battleId = ""
		data.result = ""
		data.combat = {}
		data.battleReward = {}
	if data.get("portraits") is Dictionary:
		for side in ["left", "right"]:
			if data.portraits.get(side, "") in retired_characters: data.portraits[side] = ""

func valid_battle_reward(s: Dictionary) -> bool:
	var r: Dictionary = s.battleReward
	if r.is_empty(): return true
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
	if r.status == "claimed": return r.selectedCardId in r.options and r.selectedCardId in s.deck
	return r.selectedCardId.is_empty()

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
	if not c.outcome in ["", "win", "lose", "surrender"]: return false
	if not valid_cyberware_state(c): return false
	if c.profile.get("ruleset", "") == "noren_v1" and not valid_noren_state(c): return false
	var seen: Array = []
	var exhausted: Array = c.get("norenState", {}).get("exhaustPile", []) if c.profile.get("ruleset", "") == "noren_v1" else []
	for uid in c.drawPile + c.hand + c.discardPile + exhausted:
		if not uid is String or uid in seen or not c.instances.has(uid): return false
		seen.append(uid)
		if not c.cardCatalog.has(c.instances[uid]): return false
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
	for definition in rules.get("cards", []):
		if not definition is Dictionary: return false
		if not definition.get("id") is String or not definition.get("name") is String: return false
		if catalog.has(definition.id): return false
		var amount = definition.get("nextAttackBonus", 0)
		if not (amount is int or amount is float): return false
		if not is_finite(float(amount)) or amount <= 0 or amount != floor(float(amount)): return false
		catalog[definition.id] = int(amount)
	# New battles freeze the character's list beside its definitions. Older
	# snapshots may also carry a longer historical list; the current slot limit
	# applies to new character configurations, not frozen save definitions.
	if c.profile.has("playerCyberwareIds"):
		var ids = c.profile.playerCyberwareIds
		if not ids is Array or ids != catalog.keys(): return false
	var seen := []
	var maximum := 0
	# Unspent buffs can carry over from earlier turns, while cooldown IDs only
	# describe the current turn. Allow at most one activation per card per turn.
	for amount in catalog.values(): maximum += amount * (int(c.turn) - 1)
	for id in used:
		if not id is String or id in seen or not catalog.has(id): return false
		seen.append(id)
		maximum += catalog[id]
	return bonus <= maximum

func owned_card_counts() -> Dictionary:
	var counts := {}
	var ids: Array = player_definition().get("startingDeck", []).duplicate()
	ids.append_array(state.get("deck", []))
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
	if n.energy > int(c.profile.get("energyPerTurn", 3)) or n.ammo > int(c.profile.get("ammoCap", 10)): return false
	if n.get("stance") not in ["melee", "ranged"]: return false
	if not n.get("exhaustPile") is Array: return false
	return buffs.valid_snapshot(c)
