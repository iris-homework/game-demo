extends Node

var app: Control
var checks := 0
var failures := 0
var output := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func texts(node: Node) -> String:
	var result := ""
	if node is Label or node is Button or node is RichTextLabel: result += str(node.text) + "\n"
	for child in node.get_children(): result += texts(child)
	return result

func capture(name: String) -> void:
	await get_tree().create_timer(0.35).timeout
	if Game.page == "dialogue": app.view.text_label.visible_characters = -1
	var visible_text := texts(app.view)
	check(not visible_text.split("\n").has("自由佣兵"), name + " has no identity value")
	check(not "当前阵营" in visible_text, name + " contains no allegiance UI")
	check(not visible_text.split("\n").has("身份"), name + " has no identity heading")
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	check(picture.save_png(output.path_join(name + ".png")) == OK, name + " capture saved")

func _ready() -> void:
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(1))
	Game.save_enabled = false
	var size := DisplayServer.window_get_size()
	output = "res://artifacts/qa/remove-identity-2026-10-15/visual-%dx%d" % [size.x,size.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.new_game()
	await capture("01-opening")
	Game.state.completedEventIds = ["E01", "E03", "E04"]
	Game.state.flags = {"alleyClue":true,"portClue":true}
	Game.state.targetId = "richard"
	Game.go_map()
	await get_tree().process_frame
	app.view.select_place("camp")
	await capture("02-map-camp")
	check("归零运动营地" in texts(app.view), "Original camp name appears")
	check(Game.map_target_events().map(func(e): return e.id) == ["E02", "E11"], "Map shows the two remaining independent events")
	Game.visit("tower")
	await capture("03-tower")
	Game.menu()
	await capture("04-menu")
	check(app.view.progress_summary.text == "沃斯大楼", "Menu keeps location")
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.state.targetId = "lumina"
	Game.state.portraits = {"left":"@player", "right":"gang"}
	Game.enter_node("win_03")
	await capture("05-retained-dialogue")
	check("港口" in app.view.text_label.text, "Retained event displays its authored dialogue")
	print("MERCENARY VISUAL: %d checks, %d failures; %s" % [checks, failures, output])
	get_tree().quit(0 if failures == 0 else 1)
