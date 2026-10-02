extends Node
var app: Control

func capture(label_text: String) -> void:
	await get_tree().create_timer(0.6).timeout
	if Game.page == "dialogue": app.view.text_label.visible_characters = -1
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_temp_dir().path_join("midnight_" + label_text + ".png"))

func _ready() -> void:
	Game.save_enabled = false
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await capture("menu")
	Game.new_game()
	await get_tree().create_timer(2.5).timeout
	await capture("dialogue")
	Game.state.completedEventIds = ["E01"]
	Game.state.targetId = "richard"
	Game.go_map()
	await capture("map")
	Game.visit("hive")
	await capture("place")
	Game.start_event("E03")
	Game.enter_node("payment")
	await capture("choice")
	Game.enter_node("battle")
	await capture("battle")
	Game.battle_exit("lose",Game.revision)
	await capture("failure")
	Game.enter_node("finish")
	await capture("result")
	Game.state.flags.week1Complete = true
	Game.state.activeEventId = "E12"
	Game.state.currentPlaceId = "hive"
	Game.enter_node("finish")
	await capture("week_complete")
	get_tree().quit()
