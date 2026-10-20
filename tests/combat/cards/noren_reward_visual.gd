extends "res://tests/combat/cards/noren_cards_visual.gd"
func _ready() -> void:
	Game.save_enabled=false
	Game.save_path="user://noren_reward_visual_unused.json"
	Game.meta_path="user://noren_reward_visual_meta_unused.json"
	Game.state=Game.initial_state()
	Game.state.targetId="richard"
	Game.state.activeEventId="E04"
	Game.state.currentPlaceId="alley"
	Game.enter_node("battle")
	Game.battle_exit("win",Game.revision)
	var steps:=0
	while Game.state.currentScene=="dialogue" and steps<100:
		if Game.node_data().has("next"):Game.advance(Game.revision)
		else:Game.choose(0,Game.revision)
		steps+=1
	check(Game.has_battle_reward(),"Authored victory reward exists")
	Game.state.battleReward.options=["noren_20","noren_23","noren_38"]
	app=preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(0.5).timeout
	app.view.reward_view.open_picker()
	await get_tree().create_timer(0.4).timeout
	await shot("reward-verified")
	await key(KEY_2)
	check(Game.state.deck==["noren_23"] and Game.state.battleReward.status=="claimed","Formal reward ownership")
	print("NOREN REWARD VISUAL: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
