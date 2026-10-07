extends Node
## Stages existing game screens for rendered review; never writes adventure saves.

var app: Control
var target := "menu"
var output := ""

func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func():
		push_error("QA capture timed out")
		get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--target" and i + 1 < args.size(): target = args[i + 1]
		if args[i] == "--output" and i + 1 < args.size(): output = args[i + 1]
	if output.is_empty(): output = OS.get_temp_dir().path_join("midnight_qa_" + target + ".png")
	Game.save_enabled = false
	Game.save_path = OS.get_temp_dir().path_join("midnight_qa_capture_checkpoint.json")
	Game.meta_path = OS.get_temp_dir().path_join("midnight_qa_capture_meta.json")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	match target:
		"menu": pass
		"dialogue": Game.new_game()
		"map", "place":
			Game.new_game()
			Game.state.completedEventIds = ["E01"]
			Game.state.targetId = "richard"
			Game.go_map()
			if target == "place": Game.visit("bar")
		"battle", "pile": Game.start_training("B12")
		"cyberware": Game.open_cyberware()
		_:
			push_error("Unknown QA target: " + target)
			get_tree().quit(1)
			return
	await settle()
	if target == "dialogue": app.view.text_label.visible_characters = -1
	if target == "pile":
		for i in 2:
			app.view.select_card(app.view.model.hand[0])
			await app.view.play_selected(0)
			await settle()
		app.view.show_pile("弃牌堆", app.view.model.discard_pile)
		await settle()
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(output)
	if err != OK:
		push_error("Could not save QA screenshot: " + output)
		get_tree().quit(1)
		return
	print("QA CAPTURE OK: %s -> %s" % [target, output])
	get_tree().quit(0)

func settle() -> void:
	while Game.transition_locked or Game.battle_busy:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
