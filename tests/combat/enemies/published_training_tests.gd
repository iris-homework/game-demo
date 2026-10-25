extends Node
## Run headlessly in a copied project with isolated HOME/XDG. Never touch player saves.
const Stage := preload("res://scripts/combat/test_stage.gd")
const AuthoredEffect := preload("res://scripts/combat/authored_attack_fx.gd")
const IDS := ["warden_shield", "chip_broker", "mutant_mouse", "luggage_lurker", "penitent_ascetic", "rogue_drone", "mirror_inspector", "pruning_hound", "powerline_repairman", "beacon_jellyfish"]
const FORMAL_BATTLES := {"pruning_hound":"B13", "powerline_repairman":"B14", "beacon_jellyfish":"B15"}
const OUTPUT := "res://artifacts/qa/unified-training-2026-10-24/"
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var original_battles: Dictionary
var original_enemies: Dictionary
var sentinel_paths: Array[String] = []
var menu: Control

func check(ok: bool, message: String) -> void:
	checks += 1
	records.append({"check":message, "passed":ok})
	if not ok:
		failures.append(message)
		push_error("PUBLISHED TRAINING: " + message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func reset(subject: Dictionary = {}) -> void:
	if Game.training_mode: Game.restore_training()
	Game.save_enabled = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.state = subject.duplicate(true)
	Game.page = "menu"
	# Cold no-save cases must use an absent checkpoint, not the corrupt sentinel.
	Game.save_path = OUTPUT + ("empty-checkpoint.json" if subject.is_empty() else "sentinel-checkpoint.json")

func check_catalogs(label: String) -> void:
	check(same(Game.battles, original_battles) and same(Game.enemy_catalog, original_enemies), label + ": temporary definitions removed; all formal definitions unchanged")

func check_disk(label: String) -> void:
	check(not FileAccess.file_exists(OUTPUT + "empty-checkpoint.json") and not FileAccess.file_exists(OUTPUT + "empty-checkpoint.json.bak"), label + ": no-save practice never creates an adventure checkpoint")
	for path in sentinel_paths:
		check(FileAccess.get_file_as_string(path) == "published-training-sentinel:" + path.get_file(), label + ": unchanged " + path.get_file())
	for path in [Game.save_path + ".tmp", Game.meta_path + ".tmp"]:
		check(not FileAccess.file_exists(path), label + ": no temporary save " + path.get_file())

func adventure() -> Dictionary:
	var s := Game.initial_state()
	s.currentScene = "map"
	s.currentPlaceId = "hive"
	s.currentHp = 47
	s.credits = 1234
	s.deck = ["noren_01", "noren_02", "noren_01"]
	s.equippedCyberwareIds = Game.player_characters.noren.cyberwareIds.slice(0, 1)
	s.completedEventIds = ["E01"]
	s.battleHistory = [{"battleId":"B02", "result":"win"}]
	s.claimedRewardIds = ["sentinel_reward"]
	return s

func test_config() -> void:
	var authored = Game.read_data("training_enemies.json")
	check(authored is Array and authored.size() == 10, "Exactly ten authored published training choices")
	var choices: Array[Dictionary] = Game.training_enemy_choices()
	var ids: Array[String] = []
	for choice in choices:
		ids.append(str(choice.id))
		check(choice.id in IDS and choice.combatVisualId == choice.id and not str(choice.displayName).is_empty(), "Choice identity/name/explicit visual: " + str(choice.id))
		check(not Game.place_data(choice.placeId).is_empty(), "Choice has existing place: " + str(choice.id))
		var sequence: Array = choice.intentSequence
		if FORMAL_BATTLES.has(choice.id):
			var formal_id: String = FORMAL_BATTLES[choice.id]
			var enemy_ids: Array = Game.battles[formal_id].enemyIds
			var definition: Dictionary = Game.enemy_catalog[enemy_ids[0]]
			var source: Dictionary = {}
			for entry in authored:
				if entry.id == choice.id: source = entry
			check(source.get("battleId") == formal_id and not source.has("maxHp") and not source.has("intentSequence") and not source.has("intentLoopStart"), "Formal-backed source contains a battle reference without duplicated HP or intent: " + str(choice.id))
			check(choice.get("battleId") == formal_id and same(choice.get("enemyIds"), enemy_ids) and choice.maxHp == definition.maxHp and same(sequence, definition.intentSequence) and choice.get("intentLoopStart", 0) == definition.get("intentLoopStart", 0), "Choice resolves current formal formation, HP and intent data: " + str(choice.id))
			if choice.id == "powerline_repairman":
				check(int(choice.maxHp) == 60 and sequence.size() == 3 and sequence[0].type == "energy_suit" and sequence[1].amount == 5 and sequence[2].amount == 3 and sequence[2].hits == 2 and choice.get("intentLoopStart") == 1, "Repairman choice has formal sixty HP and one-time suit / attack cycle")
			elif choice.id == "pruning_hound":
				check(int(choice.maxHp) == 35 and choice.displayName == "双修枝猎犬" and enemy_ids == ["pruning_hound", "pruning_hound_second"] and sequence.size() == 2 and sequence[0].amount == 4 and sequence[0].hits == 2 and sequence[1].type == "fortify" and sequence[1].amount == 5 and sequence[1].strength == 1, "Hound choice is the formal thirty-five HP pair with staggered actions")
			else:
				check(int(choice.maxHp) == 36 and enemy_ids == ["beacon_jellyfish"] and sequence.size() == 1 and sequence[0].amount == 6 and sequence[0].hits == 1, "Jellyfish choice follows formal thirty-six HP / attack6")
		else:
			check(int(choice.maxHp) == 100 and sequence.size() == 1 and sequence[0].type == "attack" and sequence[0].amount == 6 and sequence[0].hits == 1, "Unconnected enemy retains provisional 100 HP / single6: " + str(choice.id))
	ids.sort()
	var expected := IDS.duplicate()
	expected.sort()
	check(ids == expected, "Choice ids match the ten published enemies exactly")
	if not choices.is_empty():
		choices[0].displayName = "tampered"
		choices[0].intentSequence[0].amount = 999
		var fresh: Array[Dictionary] = Game.training_enemy_choices()
		check(fresh[0].displayName != "tampered" and fresh[0].intentSequence[0].amount == 6, "Choice API returns deeply independent data")

func choice_for(id: String) -> Dictionary:
	for choice in Game.training_enemy_choices():
		if choice.id == id: return choice
	return {}

func test_dynamic_formal_choices() -> void:
	for id in FORMAL_BATTLES:
		reset(adventure())
		var original := Game.state.duplicate(true)
		var battle_id: String = FORMAL_BATTLES[id]
		var primary_id: String = Game.battles[battle_id].enemyIds[0]
		var baseline: Dictionary = Game.enemy_catalog[primary_id].duplicate(true)
		Game.enemy_catalog[primary_id].maxHp = int(baseline.maxHp) + 7
		Game.enemy_catalog[primary_id].intentSequence[0].amount = int(baseline.intentSequence[0].amount) + 2
		var updated: Dictionary = Game.enemy_catalog[primary_id].duplicate(true)
		var choice := choice_for(id)
		check(choice.maxHp == updated.maxHp and same(choice.intentSequence, updated.intentSequence) and same(choice.enemyIds, Game.battles[battle_id].enemyIds), "Choice dynamically follows formal changes at read time: " + id)
		choice.intentSequence[0].amount = 999
		choice.enemyIds.clear()
		var independent := choice_for(id)
		check(same(independent.intentSequence, updated.intentSequence) and same(independent.enemyIds, Game.battles[battle_id].enemyIds) and same(Game.enemy_catalog[primary_id], updated), "Resolved choice data cannot mutate formal source or future reads: " + id)
		Game.save_enabled = true
		Game.start_enemy_training(id)
		check(Game.training_mode and Game.state.combat.enemies[0].hp == updated.maxHp and same(Game.state.combat.enemies[0].intentSequence, updated.intentSequence) and Game.state.combat.enemies[0].intent.amount == updated.intentSequence[0].amount, "Starting training uses changed formal HP and intent immediately: " + id)
		check(Game.training_enemy_id.is_empty() and Game.enemy_catalog.size() == original_enemies.size() and not Game.enemy_catalog.has("training_" + id), "Formal-backed practice never adds a temporary enemy: " + id)
		Game.menu()
		check(same(Game.state, original) and same(Game.enemy_catalog[primary_id], updated), "Leaving practice restores adventure and preserves formal source: " + id)
		Game.enemy_catalog[primary_id] = baseline
		check_catalogs("Dynamic formal " + id)
		check_disk("Dynamic formal " + id)

func test_start_and_restore() -> void:
	for id in IDS:
		for original in [{}, adventure()]:
			reset(original)
			Game.save_enabled = true
			Game.start_enemy_training(id)
			var label := str(id) + (" empty" if original.is_empty() else " adventure")
			check(Game.training_mode and Game.page == "battle" and Game.state.currentScene == "battle", label + ": enters playable battle")
			if not Game.training_mode or Game.state.get("combat", {}).is_empty(): continue
			check(Game.state.battleId == "training_" + id and Game.battles[Game.state.battleId].get("trainingOnly", false), label + ": session-only battle identifier")
			check(Game.state.battleStart.is_empty() and Game.state.battleReward.is_empty() and Game.state.dialogueHistory.is_empty() and Game.state.activeEventId.is_empty(), label + ": no story context, reward or persisted opening snapshot")
			check(Game.state.deck == original.get("deck", []), label + ": adventure reward cards carried into practice")
			if not original.is_empty(): check(Game.state.equippedCyberwareIds == original.equippedCyberwareIds, label + ": equipped technology retained")
			var model := CombatModel.new()
			model.restore(Game.state.combat)
			if FORMAL_BATTLES.has(id):
				var formal_ids: Array = Game.battles[FORMAL_BATTLES[id]].enemyIds
				check(model.enemies.size() == formal_ids.size() and same(Game.battles[Game.state.battleId].enemyIds, formal_ids) and Game.training_enemy_id.is_empty() and Game.enemy_catalog.size() == original_enemies.size(), label + ": actual practice uses formal formation without temporary enemy copies")
				for index in formal_ids.size():
					var definition: Dictionary = Game.enemy_catalog[formal_ids[index]]
					check(model.enemies[index].id == formal_ids[index] and model.enemies[index].hp == definition.maxHp and model.enemies[index].maxHp == definition.maxHp and same(model.enemies[index].intentSequence, definition.intentSequence) and model.enemies[index].combatVisualId == id, label + ": formal identity, HP and intent retained for slot" + str(index))
			else:
				check(model.enemies.size() == 1 and model.enemies[0].id == "training_" + id and model.enemies[0].hp == 100 and model.enemies[0].maxHp == 100 and model.enemies[0].combatVisualId == id and Game.training_enemy_id == "training_" + id, label + ": unconnected choice retains one temporary 100 HP enemy")
			check(Game.valid_combat(Game.state.combat), label + ": combat snapshot validates")
			var visual = Game.enemy_combat_visual(model.enemies[0])
			check(visual.id == id and visual.pipeline_active and visual.diagnostics.is_empty(), label + ": published visual resolves without fallback")
			check(visual.poses.get("idle") is Texture2D and visual.poses.size() >= 3, label + ": published runtime poses available")
			if id == "luggage_lurker": check(visual.attack_style_override == "bite" and visual.poses.has("bite_close"), label + ": bite presentation retained")
			elif id == "mirror_inspector": check(visual.attack_style_override == "shoot" and visual.poses.has("shoot"), label + ": shooting presentation retained")
			else: check(visual.poses.has("attack") or visual.poses.has("pierce") or visual.poses.has("slash") or visual.poses.has("hit"), label + ": attack pose available")
			var before_hp: int = model.player_hp
			model.end_turn()
			if id == "powerline_repairman":
				check(model.player_hp == before_hp and model.buffs.count(model, "energy_suit", 0) == 1 and model.enemies[0].intent.type == "attack" and model.enemies[0].intent.amount == 5, label + ": first turn equips suit without damage")
				model.end_turn()
				check(model.player_hp == before_hp - 5 and model.enemies[0].intent.amount == 3 and model.enemies[0].intent.hits == 2, label + ": second turn attacks5 and prepares two hits")
				model.end_turn()
				check(model.player_hp == before_hp - 11 and model.enemies[0].intent.amount == 5 and model.buffs.count(model, "energy_suit", 0) == 1, label + ": third turn attacks3 twice then loops attack5 with suit retained")
			elif id == "pruning_hound":
				check(model.player_hp == before_hp - 8 and model.enemies[0].intent.type == "fortify" and model.enemies[1].intent.type == "attack" and model.enemies[1].block == 5 and model.buffs.count(model, "strength", 1) == 1, label + ": first hound attacks4 twice while second fortifies")
				model.end_turn()
				check(model.player_hp == before_hp - 18 and model.enemies[0].block == 5 and model.buffs.count(model, "strength", 0) == 1 and model.enemies[1].block == 0, label + ": second hound clears block and attacks5 twice while first fortifies")
				model.end_turn()
				check(model.player_hp == before_hp - 28 and model.enemies[0].block == 0 and model.enemies[1].block == 5 and model.buffs.count(model, "strength", 1) == 2, label + ": pair continues staggered actions with additive individual strength")
			else:
				check(model.player_hp == before_hp - 6 and model.enemies[0].intent.type == "attack" and model.enemies[0].intent.amount == 6, label + ": real end_turn applies single 6-damage attack and repeats")
			Game.commit_combat(model)
			Game.menu()
			check(not Game.training_mode and Game.page == "menu" and same(Game.state, original), label + ": leaving midfight restores exact adventure or empty state")
			check_catalogs(label)
			check_disk(label)

func test_rejections() -> void:
	for id in IDS:
		reset()
		Game.save_path = OUTPUT + "sentinel-checkpoint.json"
		Game.start_enemy_training(id)
		check(not Game.training_mode and Game.state.is_empty() and Game.page == "menu", "Unreadable main and backup reject cold practice: " + id)
		check_catalogs("Unreadable checkpoint " + id)
		check_disk("Unreadable checkpoint " + id)
	for lock in ["unknown", "transition", "battle_busy", "page"]:
		reset(adventure())
		if lock == "transition": Game.transition_locked = true
		if lock == "battle_busy": Game.battle_busy = true
		if lock == "page": Game.page = "map"
		var before := Game.state.duplicate(true)
		Game.start_enemy_training("missing" if lock == "unknown" else IDS[0])
		check(not Game.training_mode and same(Game.state, before), "Reject " + lock + " atomically")
		check_catalogs("Reject " + lock)
	reset(adventure())
	Game.start_enemy_training(IDS[0])
	var before := Game.state.duplicate(true)
	var backup := Game.training_backup.duplicate(true)
	Game.start_enemy_training(IDS[1])
	check(same(Game.state, before) and same(Game.training_backup, backup) and Game.battles.size() == original_battles.size() + 1, "Repeated start cannot replace active training or original backup")
	Game.menu()
	check_catalogs("Repeated start restored")

func test_terminal_restore() -> void:
	for result in ["win", "lose"]:
		for original in [{}, adventure()]:
			reset(original)
			Game.save_enabled = true
			Game.start_enemy_training(IDS[0])
			var model := CombatModel.new()
			model.restore(Game.state.combat)
			model.draw_cards()
			var rounds := 0
			while model.outcome.is_empty() and rounds < 40:
				if result == "win":
					# Play actual available attack/block cards through the production model.
					for uid in model.hand.duplicate():
						if model.outcome.is_empty() and model.card(uid).type == "attack": model.play_card(uid, 0)
					for uid in model.hand.duplicate():
						if model.outcome.is_empty() and model.card(uid).id == "noren_02": model.play_card(uid, 0)
				if model.outcome.is_empty(): model.end_turn()
				rounds += 1
			check(model.outcome == result, "Real combat reaches " + result + " in " + str(rounds) + " rounds; outcome=" + model.outcome + "; hp=" + str(model.player_hp) + "; enemy=" + str(model.enemies[0].hp))
			Game.commit_combat(model)
			check(Game.battle_exit(result, Game.revision), "Training exit accepts " + result)
			check(not Game.training_mode and Game.page == "menu" and same(Game.state, original), result + ": exact restored state; no rewards/history/hp/deck/technology changes")
			check_catalogs(result)
			check_disk(result)

func test_existing_training() -> void:
	reset(adventure())
	var original := Game.state.duplicate(true)
	Game.start_training()
	check(Game.training_mode and Game.page == "battle" and Game.state.battleId == "B04", "Default practice uses retained B04")
	Game.menu()
	check(same(Game.state, original), "Default practice restores adventure")
	check_catalogs("Default practice")
	for id in ["B05A", "B05B", "B08", "B12"]:
		reset(adventure())
		var before := Game.state.duplicate(true)
		Game.start_training(id)
		check(not Game.training_mode and same(Game.state, before), "Retired " + id + " practice rejected atomically")
		check_catalogs("Retired " + id)
	for id in ["B02", "B04", "B11"]:
		reset(adventure())
		var before := Game.state.duplicate(true)
		Game.start_training(id)
		check(Game.training_mode and Game.page == "battle" and Game.state.battleId == id and not Game.state.combat.is_empty(), "Existing " + id + " practice still enters")
		for index in Game.battles[id].enemyIds.size():
			var definition: Dictionary = Game.enemy_catalog[Game.battles[id].enemyIds[index]]
			var enemy: Dictionary = Game.state.combat.enemies[index]
			check(enemy.id == definition.id and enemy.hp == definition.maxHp and enemy.maxHp == definition.maxHp and same(enemy.intentSequence, definition.intentSequence), "Classic practice follows formal HP and intent: " + id + " slot" + str(index))
		Game.menu()
		check(same(Game.state, before), "Existing " + id + " practice restores adventure")
		check_catalogs(id)

func test_attack_presentation() -> void:
	Engine.time_scale = 8.0
	for choice in Game.training_enemy_choices():
		reset(adventure())
		var original := Game.state.duplicate(true)
		Game.start_enemy_training(choice.id)
		var view: Control = load("res://scenes/battle.tscn").instantiate()
		add_child(view)
		var deadline := Time.get_ticks_msec() + 15000
		while not view.initialized and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(view.initialized and not Game.battle_busy, "Real battle scene initializes playable hand: " + str(choice.id))
		check(view.stage.enemies.size() == (2 if choice.id == "pruning_hound" else 1) and view.stage.enemies[0].kind == choice.id and view.stage.enemies[0].sprite.texture != null, "Real battle scene uses selected published actor count: " + str(choice.id))
		if choice.id == "pruning_hound":
			check(view.stage.enemies[1].kind == "pruning_hound" and view.stage.enemies[1].sprite.texture != null and view.model.enemies[1].hp == 35, "Real hound practice displays the second formal thirty-five HP actor")
		if view.initialized:
			var contact := {"count":0}
			var before_hp: int = view.model.player_hp
			var repairman: bool = choice.id == "powerline_repairman"
			var hound: bool = choice.id == "pruning_hound"
			var expected_damage := 8 if hound else 5 if repairman else 6
			var expected_hits := 2 if hound else 1
			var per_hit_damage := 4 if hound else expected_damage
			var expected_turn := 3 if repairman else 2
			if repairman:
				await view.end_turn_pressed()
				check(view.model.turn == 2 and view.model.player_hp == before_hp and view.model.buffs.count(view.model, "energy_suit", 0) == 1 and not Game.battle_busy, "Actual repairman first turn equips suit without attacking and releases input")
			var attack_intent: Dictionary = choice.intentSequence[1 if repairman else 0]
			var expected_pose: String = "bite_close" if choice.id == "luggage_lurker" else "shoot" if choice.id == "mirror_inspector" else str(attack_intent.animation)
			view.stage.phase_changed.connect(func(phase: String):
				if phase != "impact": return
				contact.count += 1
				check(view.stage.enemies[0].pose == expected_pose, "Actual battle contact uses selected attack pose: " + str(choice.id))
				# Authored attacks announce impact just before revealing the supplied hit.
				check_presented_contact.call_deferred(view, str(choice.id), before_hp, expected_damage, per_hit_damage * contact.count))
			await view.end_turn_pressed()
			check(contact.count == expected_hits, "Actual battle plays each configured enemy hit: " + str(choice.id))
			check(view.model.turn == expected_turn and view.model.player_hp == before_hp - expected_damage and Game.state.currentHp == before_hp - expected_damage and not Game.battle_busy, "Real end-turn commits configured damage once and releases input: " + str(choice.id))
			check(view.stage.enemies[0].pose == "idle" and view.model.hand.size() == 5, "Actual battle returns enemy idle and deals next hand: " + str(choice.id))
			if hound:
				check(view.model.enemies[1].block == 5 and view.model.buffs.count(view.model, "strength", 1) == 1 and view.stage.enemies[1].pose == "idle", "Real paired-hound turn also applies second hound's fortify once")
		view.queue_free()
		await get_tree().process_frame
		Game.menu()
		check(same(Game.state, original), "Real battle view leaves adventure unchanged after exit: " + str(choice.id))
		check_catalogs("Attack " + str(choice.id))
		check_disk("Real battle " + str(choice.id))
	Engine.time_scale = 1.0

func check_presented_contact(view: Control, id: String, before_hp: int, expected_damage: int = 6, presented_damage: int = -1) -> void:
	var shown_damage := expected_damage if presented_damage < 0 else presented_damage
	check(view.shown_player_hp == before_hp - shown_damage and view.model.player_hp == before_hp - expected_damage, "Actual battle contact presents model damage exactly once: " + id)
	if id in ["luggage_lurker", "mirror_inspector"]:
		var effects: Array[String] = []
		for child in view.stage.world.get_children():
			if child.get_script() == AuthoredEffect: effects.append(child.mode)
		if id == "luggage_lurker": check(effects.count("bite") == 1 or effects.count("hit") == 1, "Actual battle luggage bite spawns one authored contact effect")
		else: check(effects.count("hit") == 1, "Actual battle inspector shot spawns one authored impact effect")

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func test_menu() -> void:
	reset(adventure())
	menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var entry: Button = menu.training_toggle
	check(entry.text == "战斗演练" and not menu.training_open, "Single battle practice entry; modal starts hidden")
	check(menu.find_child("training_published_enemies", true, false) == null, "No separate new-enemy submenu entry")
	var original_states: Dictionary = {}
	for button in menu.ui_layer.find_children("*", "Button", true, false): original_states[button] = [button.disabled, button.focus_mode]
	entry.pressed.emit()
	await get_tree().process_frame
	var modal: Control = menu.training_container
	check(menu.training_open and modal.is_visible_in_tree(), "Single entry opens unified practice modal")
	var labels: Array = modal.find_children("*", "Label", true, false)
	check(labels.any(func(node): return node.text == "敌人演练") and labels.any(func(node): return node.text == "按当前敌人配置") and labels.all(func(node): return not "100 HP" in node.text and node.text != "单敌演练"), "Practice labels describe current enemy configuration without fixed HP or single-enemy claims")
	check(modal.find_child("enemy_choice_pruning_hound", true, false).text == "双修枝猎犬", "Practice button explicitly names the paired hounds")
	var buttons := modal.find_children("*", "Button", true, false)
	check(buttons.size() == 16, "Unified panel contains four battles, ten enemies, scenery and return")
	var choice_rects: Array[Rect2] = []
	var canvas := Rect2(Vector2.ZERO, Vector2(1440, 900))
	for button in buttons:
		var bounds: Rect2 = button.get_global_rect()
		check(button.get_minimum_size().x <= button.size.x and button.get_minimum_size().y <= button.size.y, "Button content fits: " + button.name)
		check(canvas.encloses(bounds), "Button lies within logical canvas: " + button.name)
		for previous in choice_rects: check(not bounds.intersects(previous), "Practice buttons do not overlap: " + button.name + "/" + str(previous.position))
		for label_node in modal.find_children("*", "Label", true, false):
			check(not bounds.intersects(label_node.get_global_rect()), "Practice button clears label: " + button.name + "/" + label_node.text)
		choice_rects.append(bounds)
		for path in [button.focus_next, button.focus_previous, button.focus_neighbor_left, button.focus_neighbor_right, button.focus_neighbor_top, button.focus_neighbor_bottom]:
			check(not path.is_empty() and button.get_node_or_null(path) in buttons, "Keyboard focus remains inside: " + button.name + "/" + str(path))
	check(modal.is_ancestor_of(get_viewport().gui_get_focus_owner()), "Practice modal initially owns keyboard focus")
	for button in original_states:
		check(button.disabled and button.focus_mode == Control.FOCUS_NONE, "Practice modal disables background: " + button.name)
	menu.request_new()
	check(not is_instance_valid(menu.confirm_dialog), "Practice modal blocks new commission overlay")
	menu.training_scenery_button.pressed.emit()
	await get_tree().process_frame
	check(is_instance_valid(menu.scenery_dialog), "Scenery opens above unified practice panel")
	for button in buttons: check(button.disabled and button.focus_mode == Control.FOCUS_NONE, "Scenery disables practice control: " + button.name)
	menu.find_child("training_B04", true, false).pressed.emit()
	menu.find_child("enemy_choice_" + IDS[0], true, false).pressed.emit()
	check(not Game.training_mode, "Covered practice buttons reject synthetic launches")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(menu.scenery_dialog) and menu.training_open, "First Escape closes only scenery")
	check(get_viewport().gui_get_focus_owner() == menu.training_scenery_button, "Scenery returns focus to practice scenery button")
	for button in buttons: check(not button.disabled and button.focus_mode == Control.FOCUS_ALL, "Scenery restores practice control: " + button.name)
	menu.open_scenery_picker()
	menu.find_child("scenery_choice_hive", true, false).pressed.emit()
	check(Game.b04_scenery_choice == "hive" and menu.training_scenery_button.text.contains("蜂巢"), "Scenery selection updates unified panel")
	await key(KEY_ESCAPE)
	check(not menu.training_open and not Game.training_mode, "Second Escape closes practice without starting battle")
	for button in original_states:
		check([button.disabled, button.focus_mode] == original_states[button], "Return restores background control: " + button.name)
	for id in IDS:
		reset(adventure())
		entry.pressed.emit()
		var choice := modal.find_child("enemy_choice_" + id, true, false) as Button
		check(choice != null, "Unified panel contains choice: " + id)
		if choice != null: choice.pressed.emit()
		check(Game.training_mode and Game.state.get("battleId", "") == "training_" + id, "Actual unified callback launches enemy: " + id)
		check(not menu.training_open, "Enemy selection closes practice panel: " + id)
		Game.menu()
		check_catalogs("UI " + id)
		await get_tree().process_frame
	for id in ["B04", "B11", "B02"]:
		reset(adventure())
		var original := Game.state.duplicate(true)
		entry.pressed.emit()
		modal.find_child("training_" + id, true, false).pressed.emit()
		check(Game.training_mode and Game.state.battleId == id and not menu.training_open, "Unified classic battle callback: " + id)
		check(Game.training_scenery_place_id == ("hive" if id == "B04" else ""), "Scenery override is confined to B04: " + id)
		Game.menu()
		check(same(Game.state, original), "Unified classic battle restores exact adventure: " + id)
	entry.pressed.emit()
	menu.training_cancel.pressed.emit()
	check(not menu.training_open and not Game.training_mode, "Return callback closes unified panel")
	for lock in ["transition", "busy"]:
		Game.transition_locked = lock == "transition"
		Game.battle_busy = lock == "busy"
		entry.pressed.emit()
		check(not menu.training_open, "Practice panel rejects " + lock + " lock")
	Game.transition_locked = false
	Game.battle_busy = false
	Game.set_b04_scenery_choice("")
	check_disk("Menu interactions")
	menu.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	Game.save_path = OUTPUT + "sentinel-checkpoint.json"
	Game.meta_path = OUTPUT + "sentinel-meta.json"
	Game.save_enabled = false
	for suffix in ["", ".bak", ".tmp"]:
		var empty_path: String = OUTPUT + "empty-checkpoint.json" + suffix
		if FileAccess.file_exists(empty_path): DirAccess.remove_absolute(empty_path)
	for path in [Game.save_path, Game.save_path + ".bak", Game.meta_path, Game.meta_path + ".bak"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("published-training-sentinel:" + path.get_file())
		file.close()
		sentinel_paths.append(path)
	original_battles = Game.battles.duplicate(true)
	original_enemies = Game.enemy_catalog.duplicate(true)
	check(original_battles.size() == 7 and original_enemies.size() == 17, "Formal baseline has seven battles / seventeen enemies")
	test_config()
	test_dynamic_formal_choices()
	test_start_and_restore()
	test_rejections()
	test_terminal_restore()
	test_existing_training()
	await test_attack_presentation()
	await test_menu()
	reset()
	check_disk("Final")
	var report := {"checks":checks, "failures":failures, "records":records, "headless":true, "mouse_input":false}
	var file := FileAccess.open(OUTPUT + "results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PUBLISHED_TRAINING_RESULT checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
