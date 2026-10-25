extends Node
## Headless presentation-state regression plus real robot scene playback.
## No save writes, screenshots or physical input.
class IntentProbe extends "res://scripts/battle.gd":
	var displayed_texts: Array = []
	func refresh_enemy_hud() -> void:
		displayed_texts.clear()
		for enemy in shown_enemies:
			displayed_texts.append(displayed_enemy_intent(enemy))

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fixture(definitions: Array, vulnerable: int = 0) -> IntentProbe:
	var view := IntentProbe.new()
	view.model = CombatModel.new()
	view.model.initialize("intent_phase", 100, 100, {"ruleset":"noren_v1", "deck":[], "handSize":0}, definitions)
	view.model.buffs.apply(view.model, "vulnerable", vulnerable)
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.shown_player_buffs = view.model.buff_state.duplicate(true)
	return view

func enemy(id: String, intent: Dictionary) -> Dictionary:
	return {"id":id, "displayName":id, "maxHp":100, "intentSequence":[intent]}

func settle() -> void:
	var started := Time.get_ticks_msec()
	while Game.battle_busy or Game.transition_locked:
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > 20000:
			check(false, "Real robot playback timed out")
			get_tree().quit(2)
			return
	await get_tree().process_frame
	await get_tree().process_frame

func test_real_robot_playback() -> void:
	Engine.time_scale = 4.0
	Game.state = Game.initial_state()
	var adventure := Game.state.duplicate(true)
	var app := preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B02")
	await settle()
	var battle: Control = app.view
	var starting_hp: int = battle.model.player_hp
	battle.end_turn_pressed()
	await settle()
	check(battle.model.player_hp == starting_hp - 10 and battle.enemy_intents[0].kind == "charge" and battle.enemy_intents[0].value_label.text == "+5", "Actual first laser applies ten once and advances to charge icon")
	battle.end_turn_pressed()
	await settle()
	check(battle.model.player_hp == starting_hp - 10 and battle.model.buffs.count(battle.model,"electric_charge",0) == 5, "Actual charge presentation grants five stacks without HP loss")
	check(battle.enemy_plates[0].badges.size() == 1 and battle.enemy_plates[0].badges[0].amount == 5 and battle.enemy_intents[0].value_label.text == "10×2", "Actual HUD shows five charge stacks and boosted double attack")
	# Use a real three-hit ranged card, including bleed, through the battle view.
	var uid: String = battle.model.hand[0]
	battle.model.instances[uid] = "noren_35"
	battle.model.stance = "ranged"
	battle.model.buffs.apply(battle.model,"bleed",5,0)
	battle.shown_enemies = battle.model.enemies.duplicate(true)
	battle.refresh_enemy_hud()
	battle.select_card(uid)
	battle.play_selected(0)
	var shown_layers: Array = []
	while Game.battle_busy:
		var layers: int = battle.model.buffs.enemy_count(battle.shown_enemies[0], battle.model.buffs.definition("electric_charge"))
		if shown_layers.is_empty() or shown_layers.back() != layers: shown_layers.append(layers)
		await get_tree().process_frame
	await settle()
	check(shown_layers.has(4) and shown_layers.has(3) and shown_layers.has(2), "Actual card callbacks display each individual charge reduction")
	check(battle.model.buffs.count(battle.model,"electric_charge",0) == 2 and battle.enemy_intents[0].value_label.text == "7×2", "Real three-hit card and bleed leave two charge and preview seven twice")
	battle.end_turn_pressed()
	await settle()
	check(battle.model.player_hp == starting_hp - 24 and battle.shown_player_hp == starting_hp - 24, "Actual double laser applies both seven-point hits exactly once")
	check(battle.model.buffs.count(battle.model,"electric_charge",0) == 0 and battle.enemy_plates[0].badges.all(func(badge): return badge.symbol != "electric_charge"), "Actual attack consumes all electric charge and clears its badge")
	check(battle.enemy_intents[0].value_label.text == "10" and battle.model.turn == 4, "Actual cycle returns to attack ten on the fourth player turn")
	Game.finish_training("lose")
	await settle()
	check(Game.state == adventure, "Complete robot playback leaves the original adventure intact")
	app.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	Engine.time_scale = 1.0

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://enemy_intent_phase_unused.json"
	Game.meta_path = "user://enemy_intent_phase_meta_unused.json"
	var view := fixture([enemy("boss", {"type":"attack", "amount":6, "hits":1})], 2)
	check(view.displayed_enemy_intent(view.shown_enemies[0]) == "攻击 9", "Player phase predicts damage after one vulnerable decay")
	view.presenting_enemy_turn = true
	var result := view.model.end_turn()
	check(result.attacks[0].hits[0].damage == 9, "The authoritative attack keeps the remaining vulnerable layer")
	var resolved := view.model.snapshot()
	for event in result.turnEvents:
		if event.type == "status_decay": view.apply_shown_status(event)
	check(view.shown_player_buffs.vulnerable == 1, "Playback applies exactly one vulnerable decay")
	check(view.displayed_texts == ["攻击 9"], "Decay refresh keeps intent at nine during enemy playback")
	check(view.model.snapshot() == resolved, "Intent playback never mutates the resolved combat model")
	view.presenting_enemy_turn = false
	check(view.displayed_enemy_intent(view.shown_enemies[0]) == "攻击 6", "Next player phase predicts expiration of the last vulnerable layer")
	view.free()

	# A later boss action must not retroactively amplify the earlier henchman's HUD.
	view = fixture([enemy("henchman", {"type":"attack", "amount":4, "hits":1}), enemy("boss", {"type":"vulnerable", "amount":2})])
	view.presenting_enemy_turn = true
	result = view.model.end_turn()
	resolved = view.model.snapshot()
	check(view.model.buffs.count(view.model,"vulnerable") == 2 and result.attacks[0].damage == 4, "Whole-round model contains the boss status after an unmodified earlier attack")
	view.refresh_enemy_hud()
	check(view.displayed_texts == ["攻击 4", "易伤 2"], "Unplayed boss status cannot leak into earlier displayed attacks")
	for event in result.turnEvents:
		if event.type == "status_apply": view.apply_shown_status(event)
	check(view.displayed_texts == ["攻击 6", "易伤 2"], "The boss impact immediately refreshes intents with displayed vulnerable")
	check(view.model.snapshot() == resolved, "Status presentation does not reapply the boss effect")
	view.free()

	# Strength granted later and weakness expiring after an attack also stay ordered.
	var henchman := enemy("henchman", {"type":"attack", "amount":4, "hits":2})
	view = fixture([henchman, enemy("boss", {"type":"strength_allies", "amount":1, "targetIds":["henchman"]})])
	view.model.enemies[0].weak = 1
	view.model.buffs.apply(view.model,"strength",2,0)
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.presenting_enemy_turn = true
	result = view.model.end_turn()
	check(result.attacks[0].hits.all(func(hit): return hit.damage == 5), "Strength then weakness round per segment to five")
	check(view.model.enemies[0].weak == 0 and view.model.buffs.count(view.model,"strength",0) == 3, "Final model has expired weakness and later strength")
	view.refresh_enemy_hud()
	check(view.displayed_texts[0] == "攻击 5 ×2", "Current attack reads displayed strength and weakness instead of final values")
	for event in result.turnEvents:
		if event.type == "status_apply": view.apply_shown_status(event)
	check(view.shown_enemies[0].buffs.strength == 3, "Later strength applies to the enemy display snapshot")
	view.presenting_enemy_turn = false
	view.shown_enemies = view.model.enemies.duplicate(true)
	check(view.displayed_enemy_intent(view.shown_enemies[0]) == "攻击 7 ×2", "Next player phase reads updated strength and expired weakness")
	view.free()

	# Charge gain and consumption follow playback, without leaking the next intent.
	var robot := enemy("robot", {"type":"charge", "amount":5})
	robot.intentSequence = [{"type":"charge", "amount":5}, {"type":"attack", "amount":5, "hits":2}]
	view = fixture([robot])
	view.presenting_enemy_turn = true
	result = view.model.end_turn()
	resolved = view.model.snapshot()
	check(view.model.buffs.count(view.model,"electric_charge",0) == 5 and result.attacks.is_empty(), "Charge action gains five stacks without attacking")
	check(view.model.buffs.enemy_badges(view.shown_enemies[0]).is_empty(), "Resolved charge does not appear before its presentation event")
	for event in result.turnEvents:
		if event.type == "status_apply": view.apply_shown_status(event)
	check(view.model.buffs.enemy_badges(view.shown_enemies[0])[0].count == 5, "Charge event displays a five-stack badge")
	check(view.displayed_texts == ["充能 +5 电能"] and view.model.snapshot() == resolved, "Charge display preserves the action until next-round synchronization")
	var tip := preload("res://scripts/combat/intent_tooltip.gd").describe(view.shown_enemies[0], view.displayed_texts[0])
	check(tip.title == "充能" and tip.plain.contains("每受到一段攻击减少1层"), "Charge tooltip explains gain and per-segment decay")
	var icon := preload("res://scripts/combat/enemy_intent.gd").new()
	icon.setup(robot.intentSequence[0], view.displayed_texts[0], ThemeDB.fallback_font)
	check(icon.kind == "charge" and icon.value_label.text == "+5", "Charge intent has its own icon type and compact value")
	icon.free()
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.presenting_enemy_turn = false
	check(view.displayed_enemy_intent(view.shown_enemies[0]) == "攻击 10 ×2", "Charged next attack previews ten damage per segment")
	view.presenting_enemy_turn = true
	result = view.model.end_turn()
	resolved = view.model.snapshot()
	view.present_attack_start(result.attacks[0],0)
	check(view.model.buffs.enemy_badges(view.shown_enemies[0]).is_empty(), "Starting the attack removes its spent charge badge")
	check(view.displayed_texts == ["攻击 10 ×2"] and result.attacks[0].hits.all(func(hit): return hit.damage == 10), "Spent-charge playback retains the actual ten-by-two attack preview")
	check(view.model.snapshot() == resolved, "Charge consumption presentation never applies damage or status twice")
	view.shown_enemies = view.model.enemies.duplicate(true)
	check(view.displayed_enemy_intent(view.shown_enemies[0]) == "充能 +5 电能", "Next-round synchronization restores the next authored action")
	view.free()
	await test_real_robot_playback()
	print("ENEMY INTENT PHASE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
