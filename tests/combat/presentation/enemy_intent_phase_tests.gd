extends Node
## Headless presentation-state regression; no scenes, saves, screenshots or input.
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
	print("ENEMY INTENT PHASE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
