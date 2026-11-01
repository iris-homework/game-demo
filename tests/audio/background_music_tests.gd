extends Node
## Run only in a copied project with an isolated user directory. Native MP3
## playback/looping and real Main routing; no production save or pointer input.
const App := preload("res://scenes/main.tscn")
const Cleanup := preload("res://scripts/combat/audio_cleanup.gd")
var app: Control
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("BACKGROUND MUSIC: " + message)

func settle() -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while Game.transition_locked or Game.battle_busy:
		if Time.get_ticks_msec() >= deadline:
			check(false, "routing settles before timeout")
			break
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

func fresh(page: String, place := "bar") -> void:
	Game.state = Game.initial_state("noren")
	Game.state.currentPlaceId = place
	Game.state.currentScene = page
	Game.page = page
	Game.revision += 1
	Game.pending_save_kind = ""

func _ready() -> void:
	if not OS.get_user_data_dir().contains("music-settings-qa"):
		push_error("Requires a copied project with music-settings-qa in its custom user directory")
		get_tree().quit(2)
		return
	get_tree().create_timer(100).timeout.connect(func(): push_error("MUSIC QA TIMEOUT"); get_tree().quit(2))
	Game.save_enabled = false
	Game.save_path = "user://music-checkpoint.json"
	Game.meta_path = "user://music-profile.json"
	PlayerSettings.settings_path = "user://music-settings.cfg"
	PlayerSettings.reset_defaults()
	fresh("menu")
	app = App.instantiate()
	add_child(app)
	await settle()
	var music: AudioStreamPlayer = app.music_player
	var music_id := music.get_instance_id()
	check(music.playing, "main menu starts the selected track")
	check(music.stream is AudioStreamMP3 and music.stream.get_length() > 200.0 and music.stream.get_length() < 205.0, "downloaded full-length Team Energy decodes")
	check(music.stream.loop, "native MP3 looping is enabled")
	check(music.bus == "Music" and AudioServer.get_bus_send(AudioServer.get_bus_index("Music")) == &"Master" and is_equal_approx(music.volume_db, -12.0), "music uses its independent bus and retains the intended base level")
	check(not music.stream == preload("res://assets/audio/music/team_energy.mp3"), "loop configuration belongs to an independent stream")

	# Cross the actual stream boundary without waiting three minutes.
	music.seek(music.stream.get_length() - 0.12)
	await get_tree().create_timer(0.5).timeout
	check(music.playing and music.get_stream_playback().get_loop_count() >= 1, "native decoder loops through the end of the downloaded MP3")

	for page in ["menu", "map", "place", "dialogue", "result", "defeat", "cyberware", "card_library"]:
		fresh(page)
		music.seek(30.0)
		var snapshot := Game.state.duplicate(true)
		app.show_page()
		await settle()
		check(music.playing and music.get_instance_id() == music_id, "same player continues on " + page)
		check(music.get_playback_position() >= 29.5, "page change does not restart the track: " + page)
		check(Game.state == snapshot, "music/page rendering does not mutate the fixture: " + page)
	for place in ["market", "mall"]:
		fresh("place", place)
		app.show_page()
		await settle()
		check(music.playing, "special shop keeps background music: " + place)

	fresh("menu")
	app.show_page()
	await settle()
	app.open_exit_confirmation("quit")
	check(is_instance_valid(app.exit_dialog) and music.playing, "menu confirmation keeps music playing")
	app.close_exit_confirmation()
	music.seek(40.0)
	PlayerSettings.set_music_enabled(false)
	check(music.playing and AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music switch silences the live stream without restarting it")
	await get_tree().create_timer(0.05).timeout
	PlayerSettings.set_music_enabled(true)
	check(music.playing and music.get_playback_position() >= 39.5 and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "reenabling music continues the same stream")
	PlayerSettings.sfx_enabled = false
	PlayerSettings.sfx_volume = 0.0
	PlayerSettings._apply_audio()
	check(music.playing and not AudioServer.is_bus_mute(0) and AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "SFX mute does not mute music")
	PlayerSettings.master_volume = 0.0
	PlayerSettings._apply_audio()
	check(AudioServer.is_bus_mute(0), "master mute covers music")
	PlayerSettings.master_volume = 1.0
	PlayerSettings.sfx_enabled = true
	PlayerSettings.sfx_volume = 1.0
	PlayerSettings._apply_audio()

	Game.start_enemy_training(Game.training_enemy_choices()[0].id)
	check(not music.playing, "entering a real training battle stops music before the transition")
	await settle()
	check(app.shown_page == "battle" and not music.playing, "battle keeps the non-battle track stopped after opening draw and transition")
	PlayerSettings.set_music_enabled(false)
	PlayerSettings.set_music_enabled(true)
	check(not music.playing, "changing music preferences during battle cannot start the stopped track")
	var battle_snapshot := Game.state.duplicate(true)
	app.open_exit_confirmation("menu")
	check(is_instance_valid(app.exit_dialog) and not music.playing, "battle confirmation never resumes background music")
	app.close_exit_confirmation()
	Game.changed.emit()
	await settle()
	check(not music.playing and Game.state == battle_snapshot, "battle redraw neither starts music nor changes the combat snapshot")
	Game.menu()
	check(not music.playing and app.shown_page == "battle", "outgoing battle keeps the non-battle track stopped during transition cover")
	await settle()
	check(app.shown_page == "menu" and music.playing, "returning from training restarts the background music")
	check(music.get_playback_position() < 3.0, "leaving battle starts the track from its beginning")
	Game.start_tutorial()
	check(not music.playing, "tutorial battle stops the background music immediately")
	await settle()
	check(Game.tutorial_mode and app.shown_page == "battle" and not music.playing, "tutorial stays silent")
	Game.finish_training("win")
	await settle()
	check(app.shown_page == "menu" and music.playing, "tutorial completion restores music")

	# A restored battle can be the first view, without ever showing the menu.
	Game.start_enemy_training(Game.training_enemy_choices()[0].id)
	await settle()
	check(await Cleanup.release(app, get_tree()), "audio drains before replacing Main")
	app.free()
	await get_tree().process_frame
	app = App.instantiate()
	add_child(app)
	await settle()
	check(app.shown_page == "battle" and not app.music_player.playing, "initial battle view does not briefly start music")
	for page in ["result", "defeat"]:
		fresh(page)
		app.show_page()
		await settle()
		check(app.music_player.playing, "leaving battle to a terminal page restores music: " + page)
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "QA creates no adventure or profile saves")
	check(await Cleanup.release(app, get_tree()), "looping music drains in the existing quit cleanup")
	check(not app.music_player.playing and app.music_player.stream == null, "cleanup clears the looping stream and cannot restart it")
	app.free()
	await get_tree().process_frame
	var report := {"checks": checks, "failures": failures, "audio": "Dummy", "scope": "native MP3 decode/loop; Main views, transitions, training, tutorial, mute and cleanup; no listening assessment"}
	var output := OS.get_environment("QA_OUT_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join("music-result.json"), FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("BACKGROUND_MUSIC_TESTS checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
