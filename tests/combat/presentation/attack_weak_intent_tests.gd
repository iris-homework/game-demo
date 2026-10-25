extends Node
## Headless widget and actual first-phase enemy-turn regression; no physical input.
const Intent = preload("res://scripts/combat/enemy_intent.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ATTACK WEAK INTENT: " + message)

func settle() -> void:
	var start := Time.get_ticks_msec()
	while Game.battle_busy or Game.transition_locked:
		await get_tree().process_frame
		if Time.get_ticks_msec()-start > 25000:
			check(false,"battle playback completes within timeout")
			get_tree().quit(2)
			return
	await get_tree().process_frame

func compound_value(widget: Control) -> Label:
	return widget.find_child("IntentWeakAmount",true,false) as Label

func _ready() -> void:
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(2))
	Game.save_enabled = false
	Game.save_path = "user://attack_weak_unused.json"
	Game.meta_path = "user://attack_weak_meta_unused.json"
	var font := ThemeDB.fallback_font
	for text in ["攻击 10","攻击 8","攻击 10 ×3"]:
		var widget: Control = Intent.new()
		widget.setup({"type":"attack","amount":10,"hits":3 if "×" in text else 1,"onHitWeak":2},text,font)
		var weak := compound_value(widget)
		check(weak != null and weak.text == "2","head intent explicitly displays two weak stacks: "+text)
		check(widget.value_label.text == text.trim_prefix("攻击 ").replace(" ",""),"damage preview remains its own numeric field: "+text)
		if weak != null:
			check(widget.value_label.position.x+widget.value_label.size.x <= weak.position.x,"attack and weak amounts never overlap")
			check(Rect2(Vector2.ZERO,widget.size).encloses(Rect2(weak.position,weak.size)),"weak amount stays inside the existing head HUD")
		widget.free()
	var ordinary: Control = Intent.new()
	ordinary.setup({"type":"attack","amount":15},"攻击 15",font)
	check(compound_value(ordinary)==null and ordinary.value_label.size.x==96,"ordinary attack keeps its original centered presentation")
	ordinary.free()
	var weak_only: Control = Intent.new()
	weak_only.setup({"type":"weak","amount":2},"虚弱 2",font)
	check(weak_only.kind=="weak" and weak_only.value_label.text=="2" and compound_value(weak_only)==null,"standalone weak intention is unchanged")
	weak_only.free()
	Engine.time_scale = 4.0
	Game.state = Game.initial_state()
	var adventure := Game.state.duplicate(true)
	var app := preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B16")
	await settle()
	var battle: Control = app.view
	var initial_hp: int = battle.model.player_hp
	check(battle.model.encounter_phase==1 and battle.enemy_intents[0].value_label.text=="15","actual Boss opens with ordinary attack fifteen")
	battle.end_turn_pressed()
	await settle()
	var weak := compound_value(battle.enemy_intents[0])
	check(battle.model.encounter_phase==1 and battle.enemy_intents[0].value_label.text=="10" and weak!=null and weak.text=="2","actual second first-phase intention shows attack ten and weak two together")
	check(battle.model.weak==0 and battle.shown_player_weak==0,"displaying the upcoming weak intention does not apply the debuff early")
	check(battle.enemy_intents[0].tooltip_data.plain.contains("2 层虚弱"),"compound intention retains its detailed weakness tooltip")
	battle.end_turn_pressed()
	await settle()
	check(battle.model.player_hp==initial_hp-25 and battle.shown_player_hp==battle.model.player_hp,"two actual phase-one attacks resolve the displayed damage once")
	check(battle.model.weak==2 and battle.shown_player_weak==2,"post-attack weak application synchronizes model and player display")
	var badges: Array = battle.player_plate.badges.filter(func(b): return b.symbol=="weak")
	check(badges.size()==1 and badges[0].amount==2 and badges[0].is_visible_in_tree(),"player shows the two-stack weak badge after the actual attack")
	check(battle.enemy_intents[0].value_label.text=="15" and compound_value(battle.enemy_intents[0])==null,"looping back removes the previous attack's weak marker")
	Game.finish_training("lose")
	await settle()
	check(Game.state==adventure,"training playback restores the previous adventure")
	app.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	Engine.time_scale=1.0
	print("ATTACK WEAK INTENT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
