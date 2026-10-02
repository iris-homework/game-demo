extends Node
var app: Control
var out := OS.get_temp_dir().path_join("midnight_r1_")
var failures := 0

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func idle() -> void:
	var frames := 0
	while Game.transition_locked or Game.battle_busy:
		await get_tree().process_frame
		frames += 1
		if frames > 3000:
			push_error("Animation stuck")
			get_tree().quit(1)
			return
	await get_tree().process_frame

func shot(id: String) -> void:
	await get_tree().create_timer(0.18).timeout
	if Game.page == "dialogue": app.view.text_label.visible_characters = -1
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out+id+".png")

func _ready() -> void:
	Game.save_enabled = false
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await shot("menu")
	Game.start_training("B12")
	await get_tree().create_timer(0.19).timeout
	await shot("transition")
	await idle()
	verify(app.view.cards.size() == 3,"3 rendered cards")
	await shot("battle")
	await app.view.end_turn_pressed()
	verify(Game.state.currentHp == 99,"UI end-turn damages HP")
	await shot("enemy_turn")
	app.view.select_card(app.view.model.hand[0])
	await shot("target")
	app.view.play_selected(0)
	app.view.play_selected(0)
	await idle()
	verify(app.view.model.enemies[0].hp == 2,"Duplicate click during animation ignored")
	await shot("after_hit")
	for i in 2:
		app.view.select_card(app.view.model.hand[0])
		await app.view.play_selected(0)
		await idle()
	verify(Game.page == "menu" and Game.state.is_empty(),"Training exit restores empty adventure")
	Game.new_game()
	Game.state.completedEventIds = ["E01","E03"]
	Game.state.flags.alleyClue = true
	Game.state.targetId = "richard"
	Game.start_event("E04")
	Game.enter_node("battle")
	await idle()
	await shot("missing_enemy")
	verify(app.view.enemy_portraits[0] == null,"Missing enemy stays transparent")
	Game.state.currentHp = 1
	app.view.model.player_hp = 1
	await app.view.end_turn_pressed()
	await idle()
	verify(Game.state.currentScene == "dialogue" and Game.state.activeNodeId == "lose" and Game.state.currentHp == 0,"Natural defeat returns lose node")
	await shot("defeat")
	Game.go_map()
	await shot("map")
	Game.visit("hospital")
	Game.state.currentHp = 50
	Game.checkpoint()
	await shot("hospital")
	Game.heal_at("hospital")
	verify(Game.state.currentHp == 80,"Healing wired")
	Game.open_cyberware()
	await shot("cyberware")
	print("VISUAL INTEGRATION: %d failures; screenshots: %s" % [failures,out])
	get_tree().quit(0 if failures == 0 else 1)
