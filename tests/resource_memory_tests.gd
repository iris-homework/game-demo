extends Node
## Use an isolated project/user directory. GPU mode reports actual texture memory;
## headless runs verify ownership only, not rendering memory or frame smoothness.
const BATTLE_TEXTURE := "res://assets/combat_fx/noren_red_slash.png"
const BATTLE_MUSIC := "res://assets/audio/music/dancer_rain_loop.ogg"
const MENU_TEXTURE := "res://assets/menu/noren-bar-seated-v2-detail.png"
var checks := 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var app: Control
var output := ""
var operation_started := 0
var last_frame_usec := 0
var max_frame_ms := 0.0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("RESOURCE MEMORY: " + message)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if last_frame_usec > 0:
		max_frame_ms = maxf(max_frame_ms, float(now - last_frame_usec) / 1000.0)
	last_frame_usec = now

func begin_operation() -> void:
	operation_started = Time.get_ticks_usec()
	last_frame_usec = operation_started
	max_frame_ms = 0.0

func snapshot(stage: String) -> void:
	var operation_ms := float(Time.get_ticks_usec() - operation_started) / 1000.0
	var rss_kib := -1
	if OS.get_name() in ["macOS", "Linux"]:
		var result: Array = []
		if OS.execute("/bin/ps", ["-o", "rss=", "-p", str(OS.get_process_id())], result) == 0 and not result.is_empty():
			rss_kib = str(result[0]).strip_edges().to_int()
	var sample := {
		"stage": stage, "pid": OS.get_process_id(), "display": DisplayServer.get_name(),
		"static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"static_peak_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		"texture_bytes": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"rss_kib": rss_kib, "operation_ms": operation_ms, "max_frame_ms": max_frame_ms,
	}
	samples.append(sample)
	print("RESOURCE_MEMORY_SAMPLE " + JSON.stringify(sample))
	if OS.get_environment("QA_CAPTURE") == "1" and DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(false)
		check(get_viewport().get_texture().get_image().save_png(output.path_join(stage + ".png")) == OK, "screenshot " + stage)

func settle(page: String) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if app.shown_page == page and not Game.transition_locked and not Game.battle_busy:
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().create_timer(0.25).timeout
			return true
		await get_tree().process_frame
	check(false, "page becomes ready before timeout: " + page)
	return false

func resource_reference(path: String) -> WeakRef:
	return weakref(load(path))

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not OS.get_user_data_dir().to_lower().contains("qa") or not output.is_absolute_path():
		push_error("Use an isolated QA user directory and absolute QA_OUT_DIR")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	Game.state = Game.initial_state()
	Game.page = "menu"
	get_tree().root.set_meta("startup_splash_played", true)
	begin_operation()
	app = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(app)
	await settle("menu")
	check(app.view.get_script().resource_path == "res://scripts/menu.gd", "real main opens menu")
	check(not ResourceLoader.has_cached(BATTLE_TEXTURE), "menu does not retain battle effect artwork")
	check(not ResourceLoader.has_cached(BATTLE_MUSIC), "menu does not retain dancer music")
	await snapshot("menu-initial")
	var initial_state := Game.state.duplicate(true)
	for iteration in 3:
		var menu_ref := resource_reference(MENU_TEXTURE)
		seed(20261106 + iteration)
		begin_operation()
		Game.start_training("B04")
		if not await settle("battle"): break
		check(Game.training_mode and app.view.model.enemies.size() == 3, "training uses the real three-enemy encounter")
		check(app.view.cards.size() > 0, "battle completes opening draw")
		check(menu_ref.get_ref() == null, "leaving menu releases its background texture")
		var battle_ref := resource_reference(BATTLE_TEXTURE)
		var music_ref := resource_reference(BATTLE_MUSIC)
		var prepared = app.view.stage.get("strike_textures")
		check(prepared is Array and prepared.size() == 3, "battle prepares all strike art before attacks")
		prepared = null
		await snapshot("battle-%d" % iteration)
		begin_operation()
		Game.menu()
		if not await settle("menu"): break
		check(not Game.training_mode and Game.state == initial_state, "return restores adventure state")
		check(battle_ref.get_ref() == null, "leaving battle releases effect artwork")
		check(music_ref.get_ref() == null, "leaving battle releases dancer music")
		await snapshot("menu-return-%d" % iteration)
	await load("res://scripts/combat/audio_cleanup.gd").release(app, get_tree())
	app.queue_free()
	app = null
	await get_tree().process_frame
	await get_tree().process_frame
	_test_map_ownership()
	_test_mipmap_reuse()
	var summary := {"checks": checks, "failures": failures, "samples": samples}
	FileAccess.open(output.path_join("memory-results.json"), FileAccess.WRITE).store_string(JSON.stringify(summary, "\t"))
	print("RESOURCE_MEMORY_TESTS checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_map_ownership() -> void:
	var maps = load("res://scripts/map/map_assets.gd")
	var first: Texture2D = maps.map_texture()
	check(first != null, "fallback map remains loadable")
	var reference: WeakRef = weakref(first)
	check(maps.map_texture() == first, "live map owners share the imported texture")
	first = null
	check(reference.get_ref() == null, "static map catalog does not retain large fallback artwork")
	var second: Texture2D = maps.map_texture()
	check(second != null and second.get_width() > 0, "released fallback reloads for a later map view")

func _test_mipmap_reuse() -> void:
	var actor = load("res://scripts/combat/pose_actor.gd").new()
	actor.add_child(actor.sprite)
	var imported: Texture2D = load("res://assets/combat_test/noren/noren_idle.png")
	var reference: WeakRef = weakref(imported)
	check(actor._display_texture(imported) == imported, "imported mipmapped artwork is unchanged")
	check(actor._mipmapped_textures.get(imported.get_instance_id()) == imported, "imported texture decision is reused without image readback")
	check(actor._display_texture(imported) == imported, "repeated pose selects the same texture")
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.25, 0.5, 0.75, 1.0))
	var source := ImageTexture.create_from_image(image)
	var generated: Texture2D = actor._display_texture(source)
	check(generated != source and generated.get_image().has_mipmaps(), "unimported textures still receive mipmaps")
	check(actor._display_texture(source) == generated, "generated mipmaps are reused")
	actor.use_mipmapped_textures = false
	check(actor._display_texture(source) == source, "sampling opt-out preserves original texture")
	imported = null
	actor.free()
	check(reference.get_ref() == null, "actor cache releases its textures with the actor")
