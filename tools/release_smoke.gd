extends SceneTree

var checks = 0
var failures: Array[String] = []
var resource_count = 0
var loaded_paths: Dictionary = {}
var json_count = 0
var game: Node
var app: Control
var output = OS.get_environment("MIDNIGHT_QA_OUTPUT")

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ", label)

func load_resource(path: String) -> bool:
	if loaded_paths.has(path): return loaded_paths[path]
	var resource = ResourceLoader.load(path)
	loaded_paths[path] = resource != null
	return resource != null

func scan(directory: String) -> void:
	var dir = DirAccess.open(directory)
	check(dir != null, "pack directory: " + directory)
	if dir == null: return
	for name in dir.get_files():
		var path = directory.path_join(name)
		if name.ends_with(".json"):
			var parser = JSON.new()
			check(parser.parse(FileAccess.get_file_as_string(path)) == OK, "parse JSON: " + path)
			json_count += 1
			if parser.data != null: scan_references(parser.data)
		elif name.get_extension() in ["png","jpg","svg","otf","tres","wav","ogg","tscn","gdshader"]:
			check(load_resource(path), "load resource: " + path)
			resource_count += 1
		elif name.ends_with(".import"):
			var original = path.trim_suffix(".import")
			check(load_resource(original), "load imported resource: " + original)
			resource_count += 1
		elif name.ends_with(".remap"):
			var original = path.trim_suffix(".remap")
			if original.get_extension() in ["gd","tscn","tres"]:
				check(load_resource(original), "load remapped resource: " + original)
				resource_count += 1
	for sub in dir.get_directories():
		if not sub.begins_with("."): scan(directory.path_join(sub))

func scan_references(value: Variant) -> void:
	if value is Dictionary:
		for child in value.values(): scan_references(child)
	elif value is Array:
		for child in value: scan_references(child)
	elif value is String and value.begins_with("res://"):
		if value.get_extension() in ["png","jpg","svg","otf","tres","wav","ogg","tscn","gdshader"]:
			check(load_resource(value), "JSON reference: " + value)

func settle() -> void:
	for frame in range(2400):
		await process_frame
		if not game.transition_locked and not game.battle_busy:
			await process_frame
			return
	check(false, "UI settles within 2400 frames")

func run() -> void:
	if output.is_empty() or not output.is_absolute_path():
		printerr("Set MIDNIGHT_QA_OUTPUT to an absolute disposable directory")
		quit(2)
		return
	Engine.time_scale = 4.0
	game = root.get_node("Game")
	game.save_enabled = false
	game.save_path = output.path_join("unused-checkpoint.json")
	game.meta_path = output.path_join("unused-meta.json")
	game.meta_profile = {"schemaVersion":1, "cyberwareState":{}}
	game.state.clear()
	check(not FileAccess.file_exists("res://project.godot"), "running exported PCK, not source project")
	for path in ["res://tests", "res://tools", "res://artifacts", "res://docs", "res://art_sources", "res://assets/audio/incoming", "res://enemy_asset_pipeline/published/backups"]:
		check(not DirAccess.dir_exists_absolute(path), "no development content: " + path)
	for path in ["res://data", "res://assets", "res://scenes", "res://scripts", "res://shaders", "res://enemy_asset_pipeline/runtime", "res://enemy_asset_pipeline/published"]:
		print("Scanning ", path)
		scan(path)
	check(game.card_catalog.size() == 40, "40 formal cards loaded")
	check(game.training_enemy_choices().size() == 10, "10 published enemy choices loaded")
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(app.shown_page == "menu", "main scene opens menu")
	game.open_card_library()
	await process_frame
	check(app.shown_page == "card_library", "card library opens")
	game.page = "menu"
	game.changed.emit()
	await process_frame
	var cases: Array = []
	for choice in game.training_enemy_choices(): cases.append({"enemy": choice.id})
	for id in ["B04", "B11", "B02", "B16"]:
		if game.battles.has(id): cases.append({"battle": id})
	for entry in cases:
		print("Training ", entry)
		if entry.has("enemy"): game.start_enemy_training(entry.enemy)
		else: game.start_training(entry.battle)
		await settle()
		check(game.training_mode and game.page == "battle" and app.shown_page == "battle", "training opens: " + str(entry))
		if game.training_mode:
			check(app.view.model != null and not app.view.model.enemies.is_empty(), "battle model and actors: " + str(entry))
			var previous_turn = app.view.model.turn
			app.view.end_turn_pressed()
			await settle()
			check(app.view.model.turn > previous_turn, "enemy turn and next player hand: " + str(entry))
			game.finish_training("win")
			await settle()
		check(game.page == "menu" and not game.training_mode, "training restores menu: " + str(entry))
	game.new_game()
	await settle()
	check(game.page == "dialogue" and not game.state.is_empty(), "new adventure opens introduction")
	check(not FileAccess.file_exists(game.save_path), "QA wrote no checkpoint")
	check(not FileAccess.file_exists(game.meta_path), "QA wrote no meta profile")
	var result = {"checks": checks, "failures": failures, "resources_loaded": resource_count, "json_files": json_count, "training_cases": cases.size(), "pack": ProjectSettings.globalize_path("res://"), "os": OS.get_name()}
	var file = FileAccess.open(output.path_join("smoke-result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("PACKAGE_SMOKE ", JSON.stringify(result))
	await app.quit_after_audio_cleanup()
	quit(0 if failures.is_empty() else 1)
