extends Node
## Owns state, condition evaluation, transactional actions and checkpoints.
## Views only request transitions; authored content lives in data/.
signal status_changed
signal changed
signal notice(message: String)
var assets: Dictionary
var characters: Dictionary
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
var item_catalog: Dictionary
var prototype_rules: Dictionary
var map_config: Dictionary
var meta_profile := {"schemaVersion":1, "cyberwareState":{}}
var meta_path := "user://meta_profile.json"
var transition_locked := false
var battle_busy := false
var training_mode := false
var training_backup: Dictionary = {}

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
	map_config = read_data("map.json")
	load_meta()

func initial_state() -> Dictionary:
	return {"schemaVersion":2, "currentWeek":1, "currentDay":1, "currentHp":100, "maxHp":100, "combat":{}, "inventory":{}, "currentScene":"dialogue", "currentPlaceId":"bar", "activeEventId":"E01", "activeNodeId":"intro_01", "targetId":"", "faction":"", "credits":int(config.initialCredits), "completedEventIds":[], "flags":{}, "claimedRewardIds":[], "choiceHistory":{}, "battleId":"", "result":"", "battleHistory":[], "deck":[], "portraits":{"left":"noren", "right":"bartender"}}

func new_game() -> void:
	if transition_locked or battle_busy: return
	if training_mode: restore_training()
	if save_enabled: save_meta()
	state = initial_state()
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
			"faction":
				if s.faction != value: return false
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

func objective() -> String:
	if state.get("flags", {}).get("week1Complete", false): return "第一周已完成 · 可继续探索支线"
	for e in available_events():
		if not e.optional: return e.title + "  /  " + place_data(e.placeId).name
	return "探索城市，寻找新的线索"

func event_data() -> Dictionary:
	return events.get(state.get("activeEventId", ""), {})

func node_data() -> Dictionary:
	return event_data().get("nodes", {}).get(state.get("activeNodeId", ""), {})

func display_name(id: String) -> String:
	return characters.get(id, {}).get("displayName", "旁白")

func render_text(value: String) -> String:
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
	if p.is_empty() or not meets(p.unlockCondition): return
	state.currentPlaceId = id
	state.currentScene = "place"
	checkpoint()

func start_event(id: String) -> bool:
	if transition_locked or battle_busy: return false
	if not events.has(id): return false
	var e: Dictionary = events[id]
	if id in state.completedEventIds or not meets(e.unlockCondition): return false
	if not meets(place_data(e.placeId).unlockCondition): return false
	state.activeEventId = id
	state.currentPlaceId = e.placeId
	state.battleId = ""
	state.result = ""
	state.combat = {}
	state.portraits = {"left":"noren", "right":""}
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
			"setFaction":
				if not a.get("value", "") in ["company", "resistance", ""]: return false
				draft.faction = a.value
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
		"battle":
			state.battleId = n.battleId
			state.currentScene = "battle"
			initialize_combat()
		_:
			state.currentScene = "dialogue"
			var side: String = n.get("speakerSide", "")
			if side in ["left", "right"] and not n.get("speakerId", "").is_empty():
				var speaker: String = n.speakerId
				var other := "right" if side == "left" else "left"
				if state.portraits[other] == speaker: state.portraits[other] = ""
				state.portraits[side] = speaker
	checkpoint()

func advance(expected_revision: int) -> void:
	if transition_locked or battle_busy or expected_revision != revision or state.currentScene != "dialogue": return
	var n := node_data()
	if n.has("next"): enter_node(n.next)

func choose(index: int, expected_revision: int) -> bool:
	if transition_locked or battle_busy or expected_revision != revision or state.currentScene != "dialogue": return false
	var choices: Array = node_data().get("choices", [])
	if index < 0 or index >= choices.size(): return false
	var c: Dictionary = choices[index]
	if not meets(c.get("condition", {})): return false
	if not event_data().nodes.has(c.next) and c.next != "@map": return false
	if not apply_actions(c.get("effects", [])): return false
	state.choiceHistory[state.activeEventId + ":" + state.activeNodeId] = c.id
	enter_node(c.next)
	return true

func battle_exit(result: String, expected_revision: int) -> bool:
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
	go_map()
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
	for k in initial_state():
		if not s.has(k): return false
	for key in ["currentScene", "currentPlaceId", "activeEventId", "activeNodeId", "targetId", "faction", "battleId", "result"]:
		if not s[key] is String: return false
	for key in ["maxHp", "currentHp", "currentDay", "credits"]:
		if not (s[key] is int or s[key] is float): return false
	if s.maxHp <= 0 or s.currentHp < 0 or s.currentHp > s.maxHp or s.currentDay < 1 or s.currentDay > 7: return false
	if not s.combat is Dictionary or not s.inventory is Dictionary: return false
	if not s.combat.is_empty() and not valid_combat(s.combat): return false
	if not s.completedEventIds is Array or not s.flags is Dictionary or not s.choiceHistory is Dictionary or not s.portraits is Dictionary: return false
	if not s.claimedRewardIds is Array or not s.battleHistory is Array: return false
	if not (s.credits is float or s.credits is int) or s.credits < 0: return false
	if not s.currentScene in ["map", "place", "dialogue", "battle", "result"]: return false
	if not s.targetId in ["", "richard", "lumina"] or not s.faction in ["", "company", "resistance"]: return false
	if not s.portraits.has("left") or not s.portraits.has("right"): return false
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
		page = state.currentScene
		revision += 1
		changed.emit()
		if path.ends_with(".bak"): notice.emit("已从备用检查点恢复进度。")
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


func initialize_combat() -> void:
	var battle: Dictionary = battles[state.battleId]
	var definitions: Array = []
	for id in battle.enemyIds: definitions.append(enemy_catalog[id])
	var model := CombatModel.new()
	model.initialize(state.battleId, int(state.currentHp), int(state.maxHp), prototype_rules, definitions, card_catalog)
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
	if p.is_empty() or not meets(p.unlockCondition): return false
	for service in p.get("services", []):
		if service.type == "healHpPercent":
			var previous := int(state.currentHp)
			if not apply_actions([{"op":"healHpPercent", "percent":service.percent}]): return false
			checkpoint()
			notice.emit("生命恢复 +%d  /  %d HP" % [int(state.currentHp)-previous, state.maxHp])
			return true
	return false

func start_training(battle_id: String = "B12") -> void:
	if transition_locked or battle_busy or training_mode or not battles.has(battle_id): return
	training_backup = state.duplicate(true)
	training_mode = true
	state = initial_state()
	state.targetId = "richard"
	state.activeEventId = battles[battle_id].eventId
	state.currentPlaceId = battles[battle_id].placeId
	enter_node("battle")

func restore_training() -> void:
	state = training_backup.duplicate(true)
	training_backup.clear()
	training_mode = false

func finish_training(result: String) -> void:
	restore_training()
	page = "menu"
	revision += 1
	changed.emit()
	notice.emit("演练结束：%s。冒险进度和血量未改变。" % {"win":"胜利","lose":"失败","surrender":"投降"}.get(result,result))

func open_cyberware() -> void:
	if transition_locked or battle_busy: return
	page = "cyberware"
	changed.emit()

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
	if data.get("schemaVersion",0) == 1:
		data = data.duplicate(true)
		data.schemaVersion = 2
		data.currentHp = 100
		data.maxHp = 100
		data.currentDay = 1
		data.combat = {}
		data.inventory = {}
	# Additive schema-2 upgrade: old battles gain the temporary catalog, with
	# no used cards or pending buff. Existing snapshots retain their own rules.
	var combat = data.get("combat", {})
	if combat is Dictionary and not combat.is_empty():
		if combat.get("profile") is Dictionary and not combat.profile.has("cyberware"):
			combat.profile.cyberware = prototype_rules.cyberware.duplicate(true)
	return data

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
	var seen: Array = []
	for uid in c.drawPile + c.hand + c.discardPile:
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
