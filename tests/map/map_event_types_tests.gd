extends Node

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MAP EVENT TYPES: " + message)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://qa-map-event-types/checkpoint.json"
	Game.meta_path = "user://qa-map-event-types/meta.json"
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.state.currentDay = 1
	Game.state.completedEventIds = ["E01", "E11"]
	Game.state.currentPlaceId = "junkyard"
	# This suite checks marker types; random pool selection has its own coverage.
	Game.state.refreshedEventIds = ["E02", "E04", "E13"]
	Game.refresh_event_pool()
	Game.page = "map"
	var before: Dictionary = Game.state.duplicate(true)
	var authored: Dictionary = Game.battles.duplicate(true)
	var view = load("res://scripts/map.gd").new()
	view.map_rect = Rect2(0, 76, 1440, 824)
	for event in Game.events.values():
		var expected: String = "boss" if event.id == "E16" else "normal"
		check(Game.map_event_type(event.id) == expected, "authored event type " + event.id + " = " + expected)
	for tier in ["normal", "elite", "boss"]:
		Game.battles.B02.battleType = tier
		check(Game.map_event_type("E02") == tier, "event follows configured battle " + tier)
		var spec: Dictionary = view._make_spec(Game.place_data("junkyard"), null)
		check(spec.badges.size() == 1 and spec.badges[0].kind == tier, "event badge " + tier)
		check(spec.accent == view.EVENT_COLORS[tier] and spec.badges[0].color == spec.accent, "current place does not override event color " + tier)
		check(spec.avatar and spec.boss_effect == (tier == "boss"), "avatar and boss flag " + tier)
		var marker := MidnightMapMarker.new()
		marker.prepare({"id": "junkyard", "accent": spec.accent, "badges": spec.badges, "boss_effect": spec.boss_effect})
		check(marker._frame_tex.material.get_shader_parameter("boss_effect") == (tier == "boss"), "frame effect " + tier)
		check(marker._badges.size() == 1, "marker builds badge " + tier)
		var badge: MidnightMapBadge = marker._badges[0]
		check(badge._icon.material.get_shader_parameter("boss_effect") == (tier == "boss"), "icon effect " + tier)
		check(badge.is_processing() == (tier == "boss"), "only boss redraws continuously " + tier)
		check(badge.mouse_filter == Control.MOUSE_FILTER_IGNORE and badge.badge_size() == Vector2(28, 28), "badge size and input " + tier)
		var atlas: AtlasTexture = badge._icon.texture
		check(atlas.atlas == MidnightMapBadge.STATUS_ICONS[tier], "correct silhouette " + tier)
		marker.free()
	check(MidnightMapBadge.STATUS_ICONS.normal == MidnightMapBadge.STATUS_ICONS.elite, "normal and elite share exclamation")
	check(MidnightMapBadge.STATUS_ICONS.boss != MidnightMapBadge.STATUS_ICONS.normal, "boss has separate skull")
	Game.battles.B04.battleType = "elite"
	var main: Dictionary = view._make_spec(Game.place_data("alley"), null)
	check(main.target and main.badges[0].kind == "elite" and main.accent == view.EVENT_COLORS.elite, "event target uses elite red")
	Game.events["QA_MAP_NORMAL"] = {"id": "QA_MAP_NORMAL", "placeId": "junkyard", "unlockCondition": {}}
	Game.events["QA_MAP_ELITE"] = {"id": "QA_MAP_ELITE", "placeId": "junkyard", "unlockCondition": {}}
	Game.battles["QA_MAP_BATTLE"] = {"id": "QA_MAP_BATTLE", "eventId": "QA_MAP_ELITE", "battleType": "elite"}
	Game.state.refreshedEventIds = ["E02", "QA_MAP_NORMAL", "QA_MAP_ELITE"]
	var mixed: Dictionary = view._make_spec(Game.place_data("junkyard"), null)
	check(mixed.badges.map(func(b): return b.kind) == ["normal", "elite", "boss"], "mixed event tiers remain separate")
	check(mixed.boss_effect and mixed.accent == view.EVENT_COLORS.boss, "highest tier colors mixed place")
	Game.events["QA_MAP_NORMAL2"] = {"id": "QA_MAP_NORMAL2", "placeId": "junkyard", "unlockCondition": {}}
	Game.state.refreshedEventIds = ["E02", "QA_MAP_NORMAL", "QA_MAP_NORMAL2"]
	mixed = view._make_spec(Game.place_data("junkyard"), null)
	check(mixed.badges[0].count == 2, "two normal events aggregate within the three-event limit")
	var mixed_marker := MidnightMapMarker.new()
	mixed_marker.prepare({"id": "junkyard", "accent": mixed.accent, "badges": mixed.badges, "boss_effect": true})
	mixed_marker.set_tip(Vector2(400, 400))
	for badge in mixed_marker._badges:
		check(Rect2(Vector2.ZERO, mixed_marker.size).encloses(Rect2(badge.position, badge.size)), "mixed badge stays inside click bounds " + badge.kind)
	check(mixed_marker.get_frame_rect().get_center().x == 400, "expanded bounds keep frame on map anchor")
	mixed_marker.free()
	var count_badge := MidnightMapBadge.new()
	count_badge.setup("normal", 2, view.EVENT_COLORS.normal, null)
	check(count_badge.badge_size().x > 28 and count_badge.badge_size().y == 28, "count sits beside fixed circle")
	count_badge.free()
	Game.battles["QA_MAP_BRANCH"] = {"id": "QA_MAP_BRANCH", "eventId": "E04", "battleType": "boss"}
	check(Game.map_event_type("E04") == "boss", "highest branch battle wins")
	Game.battles.B02.battleType = "invalid"
	check(Game.map_event_type("E02") == "normal", "invalid type uses existing normal fallback")
	Game.battles.B02.erase("battleType")
	check(Game.map_event_type("E02") == "normal", "missing type is normal")
	Game.battles.B02.battleType = "boss"
	Game.state.combat = {"battleId": "B02", "profile": {"battleType": "normal"}}
	check(Game.map_event_type("E02") == "boss", "previous frozen combat cannot change upcoming marker")
	for id in ["QA_MAP_NORMAL", "QA_MAP_NORMAL2", "QA_MAP_ELITE"]: Game.events.erase(id)
	Game.state = before.duplicate(true)
	Game.state.completedEventIds.append("E02")
	var completed: Dictionary = view._make_spec(Game.place_data("junkyard"), null)
	check(completed.badges.is_empty() and not completed.boss_effect, "completed event has no badge or boss effect")
	Game.state = before.duplicate(true)
	view.free()
	# Build the actual map once to verify data reaches live nodes and selection.
	var live = load("res://scripts/map.gd").new()
	add_child(live)
	await get_tree().process_frame
	check(live.markers.junkyard.boss_effect and live.markers.junkyard._badges[0].kind == "boss", "live map wires boss skull")
	live.select_place("junkyard")
	check(live.selected_id == "junkyard" and is_instance_valid(live.detail), "event detail still opens")
	check(live.markers.junkyard.has_avatar, "current avatar coexists with boss")
	check(Game.state == before, "map presentation and selection leave state unchanged")
	for id in ["market", "mall", "clinic"]:
		live.select_place(id)
		var content: Dictionary = live._card_content(id)
		check(content.resident and not content.state_label.contains("暂无"), "resident header has no empty-event notice " + id)
		var text := ""
		for node in live.detail.find_children("*", "Label", true, false): text += node.text
		check(not text.contains("暂无新的事件"), "resident body has no empty-event notice " + id)
		if id == "market":
			var enter: Button = live.detail.find_child("enter_place", true, false)
			check(enter.text == "进入黑市    →", "market entry has explicit destination")
			check(enter.get_theme_stylebox("normal").bg_color == DemoUI.PINK, "market entry uses red accent style")
		if id == "clinic":
			check(live.detail.find_child("heal_place", true, false) == null, "resident clinic map defers healing to service page")
			check(live.detail.find_child("enter_place", true, false) != null, "resident clinic keeps a map entry without tasks")
	live.select_place("tower")
	var ordinary_text := ""
	for node in live.detail.find_children("*", "Label", true, false): ordinary_text += node.text
	check(ordinary_text.contains("暂无新的事件"), "ordinary eventless location retains existing notice")
	check(live.detail.find_child("enter_place", true, false) == null, "ordinary eventless location offers no entry action")
	live.select_place("junkyard")
	var task_enter: Button = live.detail.find_child("enter_place", true, false)
	check(task_enter != null and task_enter.text == "进入地点    →", "ordinary location with task retains one generic entry")
	check(live.detail.find_child("event_E02", true, false) == null, "map detail never starts the task directly")
	check(Game.state == before, "resident detail changes do not modify adventure state")
	live.queue_free()
	await get_tree().process_frame
	Game.battles = authored
	# Verify the actual authored Boss survives the merged map -> briefing route.
	Game.state = before.duplicate(true)
	Game.state.currentDay = 7
	Game.refresh_event_pool()
	Game.page = "map"
	var boss_before: Dictionary = Game.state.duplicate(true)
	var boss_map = load("res://scripts/map.gd").new()
	add_child(boss_map)
	await get_tree().process_frame
	check(Game.available_events("hive").map(func(e): return e.id) == ["E16"], "seventh-day hive presents the authored Boss")
	check(boss_map.markers.hive.boss_effect and boss_map.markers.hive._badges.size() == 1 and boss_map.markers.hive._badges[0].kind == "boss", "actual Boss reaches hive skull and effect")
	boss_map.select_place("hive")
	var boss_enter: Button = boss_map.get_detail_button("enter_place")
	check(boss_enter != null and boss_enter.text == "进入地点    →", "Boss location exposes generic entry before briefing")
	check(boss_map.get_detail_button("event_E16") == null and Game.state == boss_before, "Boss map detail has no direct start and does not mutate state")
	if boss_enter != null:
		boss_enter.pressed.emit()
		check(Game.page == "place" and Game.state.currentPlaceId == "hive" and Game.state.activeEventId == boss_before.activeEventId, "Boss entry opens briefing without accepting the event")
		var briefing = load("res://scripts/place.gd").new()
		add_child(briefing)
		briefing.set_process(false)
		var info: Label = briefing.find_child("task_info_E16", true, false)
		var start: Button = briefing.find_child("event_E16", true, false)
		check(info != null and start != null, "Boss briefing exposes authored task information and start action")
		if info != null and start != null:
			check(info.text.contains(Game.events.E16.title) and info.text.contains(Game.events.E16.description) and start.disabled, "Boss briefing begins with full authored text pending reveal")
			briefing._process(10.0)
			check(not start.disabled, "Boss start enables after briefing finishes")
			start.pressed.emit()
			check(Game.page == "dialogue" and Game.state.activeEventId == "E16" and Game.state.activeNodeId == Game.events.E16.startNodeId, "Boss start routes to authored introduction exactly once")
			var accepted: Dictionary = Game.state.duplicate(true)
			var accepted_revision: int = Game.revision
			start.pressed.emit()
			check(Game.state == accepted and Game.revision == accepted_revision, "repeated Boss start cannot restart accepted introduction")
		briefing.queue_free()
	boss_map.queue_free()
	await get_tree().process_frame
	print("MAP EVENT TYPES: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
