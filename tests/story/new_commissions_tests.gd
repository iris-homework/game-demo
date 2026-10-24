extends Node
## Run in an isolated copied project, headless; no formal player saves or mouse input.
const CASES := [
	["E13", "B13", "pruning_hound", "garden", 36, 6],
	["E14", "B14", "powerline_repairman", "power", 48, 8],
	["E15", "B15", "beacon_jellyfish", "port", 36, 6],
]
var checks := 0
var failures: Array[String] = []
var output := "res://artifacts/qa/new-commissions-2026-10-24"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("NEW COMMISSIONS: " + message)

func same(a, b) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func fresh() -> void:
	if Game.training_mode: Game.restore_training()
	Game.save_enabled = false
	Game.save_path = output.path_join("checkpoint.json")
	Game.meta_path = output.path_join("meta.json")
	Game.transition_locked = false
	Game.battle_busy = false
	Game.new_game()
	Game.skip_dialogue(Game.revision)
	check(Game.choose(1, Game.revision), "take healing chip")
	Game.skip_dialogue(Game.revision)
	check(Game.claim_rewards(Game.revision), "opening returns to map")

func offer(id: String) -> void:
	# Pin the candidate for branch coverage; the independent pool test covers discovery.
	Game.state.refreshedEventIds = [id]
	Game.refresh_event_pool()
	check(Game.start_event(id), "start refreshed event " + id)

func texts(node: Node) -> String:
	var result := ""
	if node is Label or node is Button or node is RichTextLabel: result += str(node.text) + "\n"
	for child in node.get_children(): result += texts(child)
	return result

func portrait_texture(node: Node, path: String) -> TextureRect:
	if node is TextureRect and node.texture != null and node.texture.resource_path == path:
		return node
	for child in node.get_children():
		var found := portrait_texture(child, path)
		if found != null: return found
	return null

func test_dialogue_portraits() -> void:
	for c in CASES:
		fresh()
		offer(c[0])
		var asset_id: String = Game.characters[c[2]].portraitAssetId
		var path := "res://assets/characters/enemies_dialogue_v1/%s_dialogue_v1.png" % c[2]
		check(Game.assets[asset_id].path == path and not Game.assets[asset_id].whiteKey, c[0] + " uses existing RGBA dialogue portrait")
		for node_id in ["intro_01", "intro_02", "choice", "fight_01", "win_01", "leave_01"]:
			Game.enter_node(node_id)
			# Simulate a prior checkpoint without a newly authored enemy portrait in state.
			Game.state.portraits.right = "plant_electrician" if c[0] == "E14" else ""
			var before := Game.state.duplicate(true)
			var view = load("res://scenes/dialogue.tscn").instantiate()
			add_child(view)
			var pic := portrait_texture(view, path)
			var expected: bool = node_id in ["intro_01", "intro_02", "choice", "fight_01"] or (c[0] == "E14" and node_id == "win_01")
			check((pic != null) == expected, c[0] + ":" + node_id + " portrait follows stage presence, not who speaks")
			if pic != null:
				check(pic.material == null, c[0] + ":" + node_id + " preserves transparent art and pale details")
				check(pic.size.x > 0 and pic.size.y > 0 and pic.is_visible_in_tree(), c[0] + ":" + node_id + " image is actually in the dialogue view")
			check(not "角色立绘待补" in texts(view) and same(before, Game.state), c[0] + ":" + node_id + " no placeholder or save mutation")
			var noren := portrait_texture(view, Game.assets.noren.path)
			check(noren != null and noren.material is ShaderMaterial, "existing Noren white-background material preserved")
			view.free()
	# The repairman speaks; the two creatures remain silent despite being visible.
	for id in ["E13", "E15"]:
		check(Game.events[id].nodes.values().all(func(n): return n.get("speakerId", "") not in ["pruning_hound", "beacon_jellyfish"]), id + " creature portraits add no human speech")

func test_pool_and_old_save() -> void:
	fresh()
	var seen: Dictionary = {}
	for index in 48:
		Game.event_refresh_rng.seed = index
		Game.state.refreshedEventIds = []
		Game.refresh_event_pool()
		check(Game.state.refreshedEventIds.size() == 3, "three-event cap seed " + str(index))
		for id in Game.state.refreshedEventIds: seen[id] = true
	for c in CASES: check(seen.has(c[0]), "new event naturally discovered " + c[0])
	Game.state.refreshedEventIds = ["E02", "E04", "E11"]
	Game.refresh_event_pool()
	check(Game.state.refreshedEventIds == ["E02", "E04", "E11"], "adding content preserves a full existing draw")
	Game.state.completedEventIds = ["E01", "E02", "E04", "E11", "E01R"]
	Game.state.refreshedEventIds = []
	Game.state.currentDay = 4
	var before := Game.state.duplicate(true)
	check(Game.save_game() and Game.load_game(), "old completed adventure loads")
	check(Game.state.refreshedEventIds.size() == 3 and Game.state.refreshedEventIds.all(func(id): return id in ["E13", "E14", "E15"]), "old empty pool receives all three new commissions")
	for key in ["credits", "deck", "currentDay", "currentHp", "completedEventIds", "claimedRewardIds"]:
		check(same(Game.state[key], before[key]), "old adventure retains " + key)

func test_event(c: Array) -> void:
	var id: String = c[0]
	fresh()
	offer(id)
	check(Game.events[id].nodes.values().all(func(n): return n.get("choices", []).is_empty()), id + " has no event choices")
	var view = load("res://scenes/dialogue.tscn").instantiate()
	add_child(view)
	check(view.choice_buttons.is_empty() and not view.skip_button.disabled, id + " dialogue has no choice buttons and allows skip")
	view.free()
	Game.skip_dialogue(Game.revision)
	check(Game.page == "battle" and Game.state.battleId == c[1], id + " skip directly reaches battle")
	fresh()
	offer(id)
	Game.enter_node("choice")
	check(Game.save_game() and Game.load_game(), id + " old choice checkpoint still loads")
	check(Game.node_data().get("choices", []).is_empty(), id + " old checkpoint has no choices")
	Game.skip_dialogue(Game.revision)
	check(Game.page == "battle" and Game.state.battleId == c[1], id + " old choice checkpoint reaches battle")
	fresh()
	offer(id)
	var day: int = Game.state.currentDay
	var credits: int = Game.state.credits
	var steps := 0
	while Game.page == "dialogue" and steps < 20:
		check(Game.state.activeNodeId not in ["choice", "leave_01"], id + " normal route bypasses legacy nodes")
		Game.advance(Game.revision)
		steps += 1
	check(Game.page == "battle" and Game.state.battleId == c[1], id + " enters authored battle")
	check(Game.state.currentDay == day and Game.state.credits == credits, id + " entering battle spends no day or reward")
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	check(model.enemies.size() == 1 and model.enemies[0].id == c[2] and model.enemies[0].maxHp == c[4], id + " formal enemy and HP")
	var visual = Game.enemy_combat_visual(model.enemies[0])
	check(visual.id == c[2] and visual.pipeline_active and visual.diagnostics.is_empty(), id + " published art resolves without fallback")
	check(visual.poses.get("idle") is Texture2D, id + " actual idle texture loaded")
	var hp: int = model.player_hp
	model.end_turn()
	check(model.player_hp == hp - int(c[5]), id + " actual enemy turn applies configured damage")
	Game.commit_combat(model)
	check(Game.state.currentHp == model.player_hp, id + " progressed combat commits")
	check(Game.save_game() and Game.load_game(), id + " midbattle saves and loads")
	check(Game.state.combat.turn == 1 and Game.state.currentHp == hp and Game.state.combat.enemies[0].hp == c[4], id + " reload restarts fixed opening")
	model.restore(Game.state.combat)
	model.enemy_damage(0, 999)
	model.resolve_outcome()
	Game.commit_combat(model)
	check(model.outcome == "win" and Game.state.combat.outcome == "win", id + " model victory commits")
	check(Game.battle_exit("win", Game.revision), id + " returns to victory dialogue")
	check(Game.state.activeNodeId == "win_01" and not id in Game.state.completedEventIds, id + " no early completion before epilogue")
	check(Game.save_game() and Game.load_game() and Game.state.activeNodeId == "win_01", id + " victory dialogue survives reload")
	Game.skip_dialogue(Game.revision)
	check(Game.page == "result" and id in Game.state.completedEventIds and Game.state.currentDay == day + 1, id + " finish grants completion and one day")
	check(Game.state.credits == credits + 1000 and Game.state.battleReward.options.size() == 3 and Game.state.battleReward.battleType == "normal", id + " standard credits and normal card reward")
	var reward: Dictionary = Game.state.battleReward.duplicate(true)
	check(Game.save_game() and Game.load_game() and same(reward, Game.state.battleReward), id + " pending reward remains frozen")
	Game.prepare_battle_reward()
	check(Game.state.credits == credits + 1000 and same(reward, Game.state.battleReward), id + " reward cannot duplicate or reroll")
	check(Game.choose_reward_card(reward.options[0], Game.revision), id + " reward card can be selected")
	check(Game.claim_rewards(Game.revision) and not Game.start_event(id), id + " completed event cannot repeat")
	var saved := Game.state.duplicate(true)
	var authored: Dictionary = Game.enemy_catalog[c[2]].duplicate(true)
	Game.menu()
	Game.start_enemy_training(c[2])
	check(Game.training_mode and Game.state.combat.enemies[0].maxHp == 100, id + " training retains its separate HP")
	Game.finish_training("lose")
	check(same(saved, Game.state) and same(authored, Game.enemy_catalog[c[2]]), id + " training restores adventure and formal enemy")
	# A separate actual defeat must remain terminal and unrewarded.
	fresh()
	offer(id)
	Game.skip_dialogue(Game.revision)
	model.restore(Game.state.combat)
	model.player_damage(999)
	Game.commit_combat(model)
	check(Game.battle_exit("lose", Game.revision) and Game.page == "defeat", id + " formal defeat ends adventure")
	check(not id in Game.state.completedEventIds and Game.state.battleReward.is_empty() and Game.state.currentDay == 1, id + " defeat has no completion, reward or day cost")
	check(Game.save_game() and Game.load_game() and not Game.can_continue(), id + " failed checkpoint remains terminal")

func test_three_commissions() -> void:
	fresh()
	for c in CASES:
		offer(c[0])
		Game.skip_dialogue(Game.revision)
		Game.battle_exit("win", Game.revision)
		Game.skip_dialogue(Game.revision)
		Game.claim_rewards(Game.revision)
		check(Game.meets(Game.events.E01R.unlockCondition) == (c[0] == "E15"), "new commission count for return " + c[0])
	check(Game.state.currentDay == 4, "three new commissions consume three days")
	offer("E01R")
	Game.skip_dialogue(Game.revision)
	var credits: int = Game.state.credits
	check(Game.choose(0, Game.revision) and Game.state.credits == credits + 1000 and Game.state.currentDay == 4, "new commissions qualify for one no-time bar reward")
	Game.claim_rewards(Game.revision)
	check(not Game.start_event("E01R"), "bar return remains one-time")

func _ready() -> void:
	if not "MidnightNewCommissionsQA" in OS.get_user_data_dir():
		push_error("Run only in isolated MidnightNewCommissionsQA project")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	test_dialogue_portraits()
	test_pool_and_old_save()
	for c in CASES: test_event(c)
	test_three_commissions()
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures}, "\t"))
	file.close()
	print("NEW COMMISSIONS: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
