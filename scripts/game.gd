extends Node
## Owns state, condition evaluation, transactional actions and checkpoints.
## Views only request transitions; authored content lives in data/.
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

func initial_state() -> Dictionary:
	return {"schemaVersion":1, "currentWeek":1, "currentScene":"dialogue", "currentPlaceId":"bar", "activeEventId":"E01", "activeNodeId":"intro_01", "targetId":"", "faction":"", "credits":int(config.initialCredits), "completedEventIds":[], "flags":{}, "claimedRewardIds":[], "choiceHistory":{}, "battleId":"", "result":"", "battleHistory":[], "deck":[], "portraits":{"left":"noren", "right":"bartender"}}

func new_game() -> void:
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
	if save_enabled: save_game()
	page = state.currentScene
	changed.emit()

func go_map() -> void:
	state.currentScene = "map"
	checkpoint()

func visit(id: String) -> void:
	var p := place_data(id)
	if p.is_empty() or not meets(p.unlockCondition): return
	state.currentPlaceId = id
	state.currentScene = "place"
	checkpoint()

func start_event(id: String) -> bool:
	if not events.has(id): return false
	var e: Dictionary = events[id]
	if id in state.completedEventIds or not meets(e.unlockCondition): return false
	if not meets(place_data(e.placeId).unlockCondition): return false
	state.activeEventId = id
	state.currentPlaceId = e.placeId
	state.battleId = ""
	state.result = ""
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
	if expected_revision != revision or state.currentScene != "dialogue": return
	var n := node_data()
	if n.has("next"): enter_node(n.next)

func choose(index: int, expected_revision: int) -> bool:
	if expected_revision != revision or state.currentScene != "dialogue": return false
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
	if expected_revision != revision or state.currentScene != "battle": return false
	var b: Dictionary = battles.get(state.battleId, {})
	if not b.get("returnNodeByResult", {}).has(result): return false
	state.result = result
	state.battleHistory.append({"battleId":state.battleId, "result":result})
	enter_node(b.returnNodeByResult[result])
	return true

func claim_rewards(expected_revision: int) -> bool:
	if expected_revision != revision or state.currentScene != "result": return false
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
	if not s is Dictionary or s.get("schemaVersion", 0) != 1: return false
	for k in initial_state():
		if not s.has(k): return false
	if not s.completedEventIds is Array or not s.flags is Dictionary or not s.choiceHistory is Dictionary or not s.portraits is Dictionary: return false
	if not s.claimedRewardIds is Array or not s.battleHistory is Array: return false
	if not (s.credits is float or s.credits is int) or s.credits < 0: return false
	if not s.currentScene in ["map", "place", "dialogue", "battle", "result"]: return false
	if not s.targetId in ["", "richard", "lumina"] or not s.faction in ["", "company", "resistance"]: return false
	if not s.portraits.has("left") or not s.portraits.has("right"): return false
	if place_data(s.currentPlaceId).is_empty(): return false
	if not events.has(s.activeEventId) or not events[s.activeEventId].nodes.has(s.activeNodeId): return false
	if s.currentScene == "battle" and not battles.has(s.battleId): return false
	return true

func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")

func load_game() -> bool:
	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path): continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK: continue
		var data = parser.data
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
	page = "menu"
	changed.emit()

func resume() -> void:
	if state.is_empty(): load_game()
	else:
		page = state.currentScene
		changed.emit()
