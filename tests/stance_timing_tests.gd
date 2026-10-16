extends "res://tests/noren_cards_visual.gd"

func exercise(number: int, before: String, after: String) -> void:
	await install_hand([number,1,2],before)
	var view = app.view
	var actor = view.stage.player
	var played = view.cards["card_000"]
	var attack := number in [9,10]
	view.select_card("card_000")
	view.play_selected(0 if attack else -1)
	check(view.model.stance==after and Game.battle_busy,"Card commits once and locks input: %02d"%number)
	if attack:
		check(not is_instance_valid(actor.weapon_shift) and actor.combat_stance==before,"Attack begins before shift: %02d"%number)
	else:
		check(is_instance_valid(actor.weapon_shift) and played.visible,"Shift starts in same call as discard flight: %02d"%number)
	var committed: Dictionary = view.model.snapshot()
	view.select_card("card_001");view.play_selected(0)
	view.end_turn_pressed()
	check(committed==view.model.snapshot(),"Busy lock rejects another card and end turn")
	var saw_shift := false
	var damage_ready := true
	var started := Time.get_ticks_msec()
	while Game.battle_busy:
		if is_instance_valid(actor.weapon_shift):
			saw_shift=true
			if attack: damage_ready=damage_ready and view.shown_enemies[0].hp==view.model.enemies[0].hp
		await get_tree().process_frame
		if Time.get_ticks_msec()-started>10000:
			check(false,"Playback timed out")
			get_tree().quit(1)
			return
	check(saw_shift and damage_ready,"Shift runs after displayed attack damage when applicable")
	check(not is_instance_valid(actor.weapon_shift) and (not is_instance_valid(played) or not played.visible),"Unlock waits for both animations")
	check(actor.combat_stance==after and view.model.snapshot()==committed,"Final stance is correct without repeated model effects")
	check(view.cards.size()==view.model.hand.size(),"Draw reward finishes before unlock")
	print("STANCE TIMING: card %02d %s -> %s complete"%[number,before,after])

func _ready() -> void:
	Game.save_enabled=false
	Game.save_path="user://stance_timing_unused.json"
	Game.meta_path="user://stance_timing_meta_unused.json"
	Game.state=Game.initial_state()
	app=preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	print("STANCE TIMING: training ready")
	await exercise(4,"melee","ranged")
	await exercise(3,"ranged","melee")
	await exercise(8,"melee","ranged")
	await exercise(8,"ranged","melee")
	await exercise(9,"ranged","melee")
	await exercise(10,"melee","ranged")
	print("STANCE TIMING: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
