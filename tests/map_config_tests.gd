extends Node
## 验证实际地图控件消费配置，而不只是检查资源表里的路径存在。
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MAP CONFIG: " + message)

func verify_texture(expected: Texture2D, label_text: String) -> void:
	var view = load("res://scenes/map.tscn").instantiate()
	add_child(view)
	var image: TextureRect = view.find_child("map_texture", true, false)
	check(image != null and image.texture == expected, label_text)
	if image != null:
		var ratio := float(expected.get_width()) / float(expected.get_height())
		check(is_equal_approx(view.map_rect.size.x / view.map_rect.size.y, ratio), label_text + " keeps source aspect")
	remove_child(view)
	view.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	Game.save_enabled = false
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.state.completedEventIds = ["E01"]
	Game.page = "map"
	var original_config := Game.map_config.duplicate(true)
	var original_state := JSON.stringify(Game.state)
	var city := Game.texture("city_map")
	await verify_texture(Game.texture(str(Game.map_config.cityMapAssetId)), "authored map asset")
	Game.assets["map_test_fixture"] = {"path":"res://assets/characters/noren.png"}
	Game.map_config.cityMapAssetId = "map_test_fixture"
	await verify_texture(Game.texture("map_test_fixture"), "different configured asset reaches actual TextureRect")
	Game.map_config.erase("cityMapAssetId")
	await verify_texture(city, "missing key keeps legacy city map")
	Game.map_config.cityMapAssetId = "missing_map_fixture"
	await verify_texture(MidnightMapAssets.map_texture(), "unavailable asset retains existing fallback")
	Game.map_config.cityMapAssetId = ""
	await verify_texture(MidnightMapAssets.map_texture(), "empty asset retains existing fallback")
	Game.map_config = original_config
	Game.assets.erase("map_test_fixture")
	await verify_texture(city, "recreated map restores authored asset")
	check(JSON.stringify(Game.state) == original_state, "resource selection does not change progress")
	print("MAP CONFIG: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
