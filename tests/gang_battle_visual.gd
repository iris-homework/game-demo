extends "res://tests/noren_cards_visual.gd"
## Exercise model commits plus actual battle presentation; no formal save writes.
var captured := {}
var monitored_view: Control
var saw_boundary_change := false
var saw_vulnerable_before_decay := false

func children_labels(root: Node) -> String:
	var lines: PackedStringArray = []
	for child in root.find_children("*", "Label", true, false): lines.append(child.text)
	return "|".join(lines)

func phase_sample(phase: String) -> void:
	if not is_instance_valid(monitored_view): return
	if monitored_view.presenting_enemy_turn and monitored_view.shown_enemies[2].get("intentPhase", "") == "ally_death": saw_boundary_change = true
	if phase == "home_glitch" and monitored_view.shown_player_buffs.get("vulnerable", 0) == 2: saw_vulnerable_before_decay = true

func snapshot_shot(label: String) -> void:
	var view = app.view
	captured[label] = {"hp":view.model.player_hp,"intents":view.shown_enemies.map(func(e): return e.intent),"playerBuffs":view.shown_player_buffs.duplicate(),"enemyBuffs":view.shown_enemies.map(func(e): return e.get("buffs",{}).duplicate()),"turn":view.model.turn}
	if DisplayServer.get_name() != "headless": await shot(label)

func finish_turn() -> void:
	app.view.end_turn_pressed()
	await idle()
	check(not Game.battle_busy and app.view.shown_player_hp == app.view.model.player_hp, "Enemy turn completes with displayed HP in sync")
	check(Game.valid_combat(Game.state.combat), "Every committed turn validates")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://gang_battle_visual_unused.json"
	Game.meta_path = "user://gang_battle_visual_meta_unused.json"
	output = "res://artifacts/qa/gang-alley-2026-10-19/battle-visuals/"
	var args := OS.get_cmdline_user_args()
	if args.has("--output-dir"): output = args[args.find("--output-dir")+1].trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state = Game.initial_state()
	var adventure := Game.state.duplicate(true)
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	monitored_view = app.view
	monitored_view.stage.phase_changed.connect(phase_sample)
	await snapshot_shot("01-entry")
	await finish_turn()
	var view = app.view
	check(view.model.player_hp == 92 and view.shown_player_hp == 92, "Two sequential attacks of four deal eight on first turn")
	check(view.shown_enemies[0].buffs.strength == 1 and view.shown_enemies[1].buffs.strength == 1, "Reinforcement badges appear on both henchmen after boss acts")
	check(view.enemy_statuses(view.shown_enemies[0])[0].buffId == "strength", "Strength badge reaches actual enemy HUD")
	await snapshot_shot("02-strengthened")
	# Give three existing starting attacks as an isolated, valid hand fixture.
	var attacks: Array = []
	for uid in view.model.instances:
		if view.model.instances[uid] == "noren_01": attacks.append(uid)
	view.model.draw_pile.append_array(view.model.hand)
	view.model.hand.clear()
	for uid in attacks.slice(0,3):
		view.model.draw_pile.erase(uid)
		view.model.discard_pile.erase(uid)
		view.model.hand.append(uid)
	view.commit()
	app.swap_view()
	await idle()
	view = app.view
	monitored_view = view
	view.stage.phase_changed.connect(phase_sample)
	for strike in 3:
		var uid: String = view.model.hand[0]
		view.select_card(uid)
		view.play_selected(0)
		await idle()
	check(view.model.enemies[0].hp == 0 and not view.stage.enemies[0].alive, "Three real card attacks kill one henchman with one model resolution per card")
	check(view.model.enemies[2].intent.type == "strength_allies" and view.shown_enemies[2].intent.type == "strength_allies", "Boss retains reinforcement throughout player-turn death presentation")
	await snapshot_shot("03-casualty-pending-boundary")
	await finish_turn()
	check(view.model.player_hp == 87 and view.shown_player_hp == 87 and view.shown_enemies[1].buffs.strength == 2, "Casualty round still reinforces after survivor attacks5")
	check(view.model.turn == 3 and view.shown_enemies[2].intent.type == "attack" and view.shown_enemies[2].intent.amount == 8 and view.model.enemies[2].intentIndex == 0, "Next full round starts with attack8 visible before player input")
	await snapshot_shot("04-next-round-attack8-intent")
	await finish_turn()
	check(view.model.player_hp == 73 and saw_boundary_change, "Following enemy phase: surviving henchman attacks6, then boss attacks8")
	check(view.model.enemies[2].intent.type == "vulnerable", "Attack8 advances to vulnerable2")
	await snapshot_shot("05-boss-attack8-complete")
	await finish_turn()
	check(view.model.player_hp == 67 and view.shown_player_buffs.get("vulnerable") == 2 and view.model.buffs.count(view.model,"vulnerable") == 2, "Boss applies two vulnerable after surviving henchman attacks6")
	check(view.model.buffs.player_badges(view.model,view.shown_player_parry,view.shown_player_pollution,view.shown_player_buffs).any(func(b): return b.buffId == "vulnerable" and b.count == 2), "Vulnerable tooltip and badge are visible with two stacks")
	check(saw_vulnerable_before_decay, "Application is displayed during current enemy turn before any next-turn decay")
	await snapshot_shot("06-vulnerable2")
	await finish_turn()
	check(view.model.player_hp == 49 and view.shown_player_buffs.get("vulnerable") == 1, "Next own turn end decays to one; attack6 becomes9 for both attackers")
	await snapshot_shot("07-vulnerable1-boss-attack6-complete")
	await finish_turn()
	check(view.model.player_hp == 35 and not view.shown_player_buffs.has("vulnerable"), "Last layer expires before enemy attacks: attack6 plus attack8")
	check(view.model.enemies[2].intent.type == "vulnerable", "Boss completes cycle and wraps normally")
	await snapshot_shot("08-vulnerable-expired")
	Game.menu()
	await idle()
	check(Game.state == adventure and not Game.training_mode, "Actual battle training restores adventure")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"states":captured,"physicalInput":false,"directViewActions":true},"\t"))
	print("GANG BATTLE VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
