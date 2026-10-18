extends Node
## A second process reloads the profile saved by the rendered workspace check.

func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(func():
		push_error("Background restart check timed out")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var index := args.find("--profile-path")
	if index < 0 or index + 1 >= args.size() or not args[index + 1].begins_with("res://artifacts/qa/"):
		push_error("Restart check requires a QA-only --profile-path")
		get_tree().quit(2)
		return
	var profile: String = args[index + 1]
	var bench := preload("res://tests/battle_background_preview.tscn").instantiate()
	bench.profile_path = profile
	add_child(bench)
	while not bench.ready_for_preview: await get_tree().process_frame
	var checks := {
		"saved_scene":bench.profiles.current_id == "harbor",
		"fractional_values":is_equal_approx(bench.settings.scale, 0.61) and is_equal_approx(bench.settings.brightness, 1.07),
		"zero_values":bench.settings.saturation == 0 and bench.settings.contrast == 0,
		"saved_ui":bench.profile_state.text.contains("已保存") and not bench.profiles.is_dirty(),
		"saving_isolated":not Game.save_enabled and Game.save_path.ends_with("battle_background_preview_unused.json")
	}
	await RenderingServer.frame_post_draw
	var destination := profile.get_base_dir()
	checks.screenshot = get_viewport().get_texture().get_image().save_png(destination + "/restart.png") == OK
	var failures := 0
	for result in checks.values():
		if not result: failures += 1
	FileAccess.open(destination + "/restart-result.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}, "\t"))
	print("BACKGROUND RESTART: %d checks, %d failures" % [checks.size(), failures])
	get_tree().quit(0 if failures == 0 else 1)
