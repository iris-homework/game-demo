extends Node
## Run headlessly in a copied project with an independent user directory.
const OUT := "res://artifacts/qa/shop-intros-2026-10-25/"
const SAVE := OUT + "checkpoint.json"
const BLOCKED := OUT + "missing-directory/checkpoint.json"
var checks := 0
var failures := 0
var app: Control

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SHOP INTRO: " + detail)

func fresh() -> void:
	Game.save_enabled = false
	Game.save_path = SAVE
	Game.meta_path = OUT + "meta.json"
	Game.pending_save_kind = ""
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.page = "map"

func progress_snapshot() -> Dictionary:
	var result := {}
	for field in ["activeEventId", "activeNodeId", "currentDay", "credits", "currentHp", "deck", "completedEventIds", "claimedRewardIds", "refreshedEventIds", "battleId", "battleReward", "battlePassiveReward", "battleHistory"]:
		result[field] = Game.state[field].duplicate(true) if Game.state[field] is Array or Game.state[field] is Dictionary else Game.state[field]
	return result

func finish_normally() -> void:
	var guard := 0
	while Game.state.currentScene == "dialogue" and guard < 30:
		Game.advance(Game.revision)
		guard += 1
	check(guard < 30, "ordinary Continue terminates")

func test_authored_data() -> void:
	for place_id in ["market", "mall"]:
		var definition: Dictionary = Game.place_dialogues[place_id]
		var spoken := 0
		for node in definition.nodes.values():
			if node.get("type", "dialogue") != "dialogue": continue
			spoken += 1
			check(Game.characters.has(Game.resolve_character_id(node.get("speakerId", ""))), place_id + " speaker is registered")
			check(node.get("text", "") is String and not node.get("text", "").is_empty(), place_id + " dialogue has text")
			check(definition.nodes.has(node.get("next", "")), place_id + " next node exists")
		var expected_lines := 4 if place_id == "market" else 3
		check(spoken == expected_lines, place_id + " has expected introductory sentence count")
		var seen := []
		var current: String = definition.startNodeId
		while definition.nodes.has(current) and not current in seen:
			seen.append(current)
			var node: Dictionary = definition.nodes[current]
			if node.get("type", "dialogue") != "dialogue": break
			current = node.get("next", "")
		check(seen.size() == expected_lines + 1 and definition.nodes.get(current, {}).get("type", "") == "place", place_id + " all lines lead to storefront without cycle")

func test_first_visit(place_id: String) -> void:
	fresh()
	var definition: Dictionary = Game.place_dialogues[place_id]
	var before := progress_snapshot()
	Game.visit(place_id)
	check(Game.page == "dialogue" and Game.state.currentScene == "dialogue", place_id + " first visit opens dialogue")
	check(Game.state.get("placeDialogue", {}) == {"placeId":place_id, "nodeId":definition.startNodeId}, place_id + " starts at authored first sentence")
	check(Game.event_data().id == definition.id and Game.node_data() == definition.nodes[definition.startNodeId], place_id + " uses independent authored dialogue")
	check(Game.valid_save(Game.state), place_id + " first sentence is a valid checkpoint")
	check(not Game.state.flags.get(definition.completionFlag, false), place_id + " is unfinished while reading")
	var initial := Game.state.duplicate(true)
	Game.advance(Game.revision - 1)
	check(Game.state == initial, place_id + " stale Continue does not advance")
	Game.advance(Game.revision)
	check(Game.state.placeDialogue.nodeId != definition.startNodeId, place_id + " Continue advances the shop sentence")
	check(Game.state.activeNodeId == before.activeNodeId, place_id + " Continue preserves story anchor")
	finish_normally()
	check(Game.page == "place" and Game.state.currentPlaceId == place_id, place_id + " finishes directly at storefront")
	check(not Game.state.has("placeDialogue") and Game.state.flags.get(definition.completionFlag, false), place_id + " finish stores one-time flag and clears context")
	check(progress_snapshot() == before, place_id + " changes no date, money, deck, rewards or event pool")
	check(Game.valid_save(Game.state), place_id + " finished storefront checkpoint validates")
	var history_size: int = Game.state.dialogueHistory.size()
	check(history_size >= 3, place_id + " records authored conversation")
	for entry in Game.state.dialogueHistory:
		check(entry.eventId == definition.id and entry.title == definition.title, place_id + " history identifies shop conversation")
	Game.go_map()
	Game.visit(place_id)
	check(Game.page == "place" and Game.state.dialogueHistory.size() == history_size, place_id + " revisit does not replay conversation")
	fresh()
	Game.visit(place_id)
	Game.skip_dialogue(Game.revision)
	check(Game.page == "place" and Game.state.flags.get(definition.completionFlag, false), place_id + " Skip marks read and opens storefront")
	check(Game.valid_save(Game.state), place_id + " skipped checkpoint validates")

func test_resume_and_legacy(place_id: String) -> void:
	fresh()
	var definition: Dictionary = Game.place_dialogues[place_id]
	Game.visit(place_id)
	Game.advance(Game.revision)
	var reading := Game.state.duplicate(true)
	if place_id == "market":
		for removed_node in ["intro_04", "intro_05"]:
			var old_reading := reading.duplicate(true)
			old_reading.placeDialogue.nodeId = removed_node
			var migrated: Dictionary = Game.migrate_save(old_reading)
			check(migrated.placeDialogue.nodeId == "intro_06" and Game.valid_save(migrated), "removed market line resumes at remaining closing line")
	if place_id == "mall":
		for removed_node in ["intro_02", "intro_03", "intro_04"]:
			var old_reading := reading.duplicate(true)
			old_reading.placeDialogue.nodeId = removed_node
			var migrated: Dictionary = Game.migrate_save(old_reading)
			check(migrated.placeDialogue.nodeId == "intro_05" and Game.valid_save(migrated), "removed mall line resumes at remaining product introduction")
	check(Game.save_game(), place_id + " mid-conversation writes isolated checkpoint")
	Game.state = {}
	Game.page = "menu"
	check(Game.load_game(), place_id + " mid-conversation checkpoint reloads")
	check(Game.page == "dialogue" and Game.state.placeDialogue == reading.placeDialogue, place_id + " reload resumes exact sentence")
	check(Game.state.dialogueHistory == reading.dialogueHistory, place_id + " reload does not duplicate history")
	Game.skip_dialogue(Game.revision)
	check(Game.save_game(), place_id + " completion writes isolated checkpoint")
	Game.state = {}
	check(Game.load_game(), place_id + " completion checkpoint reloads")
	var history_size: int = Game.state.dialogueHistory.size()
	Game.go_map()
	Game.visit(place_id)
	check(Game.page == "place" and Game.state.dialogueHistory.size() == history_size, place_id + " completion survives application reload")
	fresh()
	var old_save := Game.state.duplicate(true)
	old_save.erase("placeDialogue")
	old_save.flags.erase(definition.completionFlag)
	Game.state = Game.migrate_save(old_save)
	check(Game.valid_save(Game.state), place_id + " legacy schema-2 checkpoint remains valid")
	Game.visit(place_id)
	check(Game.page == "dialogue", place_id + " existing save without flag receives introduction")
	Game.skip_dialogue(Game.revision)
	Game.new_game()
	check(not Game.state.flags.get(definition.completionFlag, false), place_id + " new adventure resets first-visit flag")
	Game.go_map()
	Game.visit(place_id)
	check(Game.page == "dialogue", place_id + " new adventure receives introduction again")

func test_interrupted_context() -> void:
	fresh()
	Game.visit("market")
	Game.go_map()
	check(not Game.state.has("placeDialogue") and Game.page == "map", "leaving unfinished dialogue clears its navigation context")
	Game.visit("market")
	check(Game.state.placeDialogue.nodeId == Game.place_dialogues.market.startNodeId, "unfinished visit restarts when entered again")
	Game.visit("mall")
	check(Game.state.placeDialogue.placeId == "mall", "entering another shop replaces unfinished context")
	Game.state.refreshedEventIds = ["E02"]
	check(Game.start_event("E02"), "normal story event can start after interrupted shop conversation")
	check(not Game.state.has("placeDialogue") and Game.event_data().id == "E02", "story entry clears shop context")
	fresh()
	Game.visit("market")
	var original := Game.state.duplicate(true)
	for broken in [null, [], {}, {"placeId":"unknown", "nodeId":"intro_01"}, {"placeId":"market", "nodeId":"unknown"}, {"placeId":42, "nodeId":"intro_01"}]:
		var bad := original.duplicate(true)
		bad.placeDialogue = broken
		check(not Game.valid_save(bad), "invalid place-dialogue checkpoint rejected: " + str(broken))
	var wrong_scene := original.duplicate(true)
	wrong_scene.currentScene = "map"
	check(not Game.valid_save(wrong_scene), "dialogue context on map rejected")
	var wrong_place := original.duplicate(true)
	wrong_place.currentPlaceId = "mall"
	check(not Game.valid_save(wrong_place), "mismatched dialogue location rejected")

func test_reward_context() -> void:
	fresh()
	Game.state.refreshedEventIds = ["E02"]
	check(Game.start_event("E02"), "reward fixture starts real commission")
	Game.skip_dialogue(Game.revision)
	check(Game.battle_exit("win", Game.revision), "reward fixture follows real victory route")
	Game.skip_dialogue(Game.revision)
	check(Game.has_battle_reward(), "reward fixture receives real frozen reward")
	check(Game.claim_rewards(Game.revision), "reward fixture exits reward page")
	var before := progress_snapshot()
	for place_id in ["market", "mall"]:
		Game.visit(place_id)
		check(Game.valid_save(Game.state), place_id + " dialogue preserves valid prior reward receipt")
		Game.skip_dialogue(Game.revision)
		check(progress_snapshot() == before and Game.valid_save(Game.state), place_id + " completion preserves prior battle/reward context")

func test_failed_completion() -> void:
	fresh()
	Game.visit("market")
	var definition: Dictionary = Game.place_dialogues.market
	var guard := 0
	while guard < 30:
		var current := Game.node_data()
		var next: Dictionary = definition.nodes.get(current.get("next", ""), {})
		if next.is_empty() or next.get("type", "dialogue") != "dialogue": break
		Game.advance(Game.revision)
		guard += 1
	check(guard < 30, "reaches final authored sentence before save-failure check")
	check(Game.save_game(), "pre-completion checkpoint saves")
	var disk := FileAccess.get_file_as_string(SAVE)
	Game.save_path = BLOCKED
	Game.save_enabled = true
	Game.advance(Game.revision)
	check(Game.pending_save_kind == "scene" and Game.page == "dialogue", "failed finish remains behind checkpoint gate")
	check(Game.state.currentScene == "place" and Game.state.flags.get(definition.completionFlag, false), "failed finish retains resolved one-time flag")
	var pending := Game.state.duplicate(true)
	Game.skip_dialogue(Game.revision)
	Game.visit("market")
	check(Game.state == pending, "pending save blocks repeat finish and navigation")
	check(FileAccess.get_file_as_string(SAVE) == disk, "failed finish preserves previous checkpoint on disk")
	Game.save_path = SAVE
	check(Game.retry_pending_save() and Game.page == "place", "storage recovery opens storefront")
	check(Game.state == pending and Game.valid_save(Game.state), "retry preserves conversation and one-time state")
	check(not Game.retry_pending_save(), "duplicate save retry is harmless")
	Game.save_enabled = false

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func visible_text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button: result += node.text + "\n"
	for child in node.get_children(): result += visible_text(child)
	return result

func has_texture(node: Node, texture: Texture2D) -> bool:
	if node is TextureRect and node.texture == texture: return true
	for child in node.get_children():
		if has_texture(child, texture): return true
	return false

func test_real_views() -> void:
	fresh()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	for place_id in ["market", "mall"]:
		Game.visit(place_id)
		await settle()
		check(app.view.get_script().resource_path.ends_with("dialogue.gd"), place_id + " real main displays standard conversation")
		check(app.view.text_label.text == Game.render_text(Game.node_data().text), place_id + " real view shows authored first line")
		check(not app.view.skip_button.disabled, place_id + " real Skip button is available")
		check(not "角色立绘待补" in visible_text(app.view) and not "老板娘" in visible_text(app.view), place_id + " first-visit view has no old NPC placeholder")
		if place_id == "market":
			check(app.view.get_node_or_null("black_market_art") != null, "market conversation uses layered storefront artwork")
		else:
			var original := Game.texture("woss_mall_shop")
			check(original != null and has_texture(app.view, original), "mall conversation uses original woss storefront texture")
		app.view.skip_button.pressed.emit()
		await settle()
		var script_name := "black_market.gd" if place_id == "market" else "technology_shop.gd"
		check(app.view.get_script().resource_path.ends_with(script_name), place_id + " real Skip routes to correct storefront")
		Game.go_map()
		Game.visit(place_id)
		await settle()
		check(app.view.get_script().resource_path.ends_with(script_name), place_id + " real revisit opens storefront immediately")
	check(await preload("res://scripts/combat/audio_cleanup.gd").release(app, get_tree()), "real view audio finishes cleanup before scene release")
	remove_child(app)
	app.queue_free()
	await settle()

func _ready() -> void:
	Game.save_enabled = false
	Game.meta_path = OUT + "meta.json"
	Game.save_path = SAVE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	test_authored_data()
	for place_id in ["market", "mall"]:
		test_first_visit(place_id)
		test_resume_and_legacy(place_id)
	test_interrupted_context()
	test_reward_context()
	test_failed_completion()
	await test_real_views()
	print("SHOP INTRO: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
