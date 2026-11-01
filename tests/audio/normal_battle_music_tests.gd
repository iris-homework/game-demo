extends "res://tests/audio/background_music_tests.gd"
## Copied project only. QA_EXPECT_NORMAL_MUSIC=1 requires an imported OGG (a QA tone or the selected source)
## at TRACK_PATH; =0 requires that optional resource to be absent.
const TRACK_PATH := "res://assets/audio/music/chrono_ark_battle2_1.ogg"
var expect_track := false

func normal_music() -> AudioStreamPlayer:
	return app.view.get_node_or_null("NormalBattleMusic") as AudioStreamPlayer

func active(player: AudioStreamPlayer) -> bool:
	return is_instance_valid(player) and player.playing and not player.stream_paused

func check_normal(title: String) -> void:
	var player := normal_music()
	check(is_instance_valid(player), title + " owns an ordinary-battle player")
	if not is_instance_valid(player): return
	check(not app.music_player.playing, title + " stops menu music")
	check(player.bus == &"Music" and is_equal_approx(player.volume_db, -12.0), title + " uses Music at the intended base volume")
	if expect_track:
		check(active(player) and player.stream is AudioStreamOggVorbis and player.stream.loop, title + " plays the optional OGG with native looping")
		check(player.stream != load(TRACK_PATH), title + " configures a private stream copy")
		if OS.get_environment("QA_TRACK_KIND") == "actual-source":
			var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/music/chrono_ark_battle2_1_source.json"))
			check(absf(player.stream.get_length() - float(source.duration_seconds)) < 0.01, title + " decodes the full selected source duration")
	else:
		check(not player.playing and player.stream == null, title + " stays silent without the optional file")

func check_excluded(title: String) -> void:
	check(not is_instance_valid(normal_music()), title + " creates no ordinary-battle music player")
	check(not app.music_player.playing, title + " keeps menu music stopped")

func enter_formal(frozen_kind: String, catalog_after: String) -> void:
	# Use the authored B02 battle node, including initialization and Main transition.
	fresh("menu")
	Game.state.activeEventId = "E02"
	Game.state.currentPlaceId = Game.battles.B02.placeId
	Game.state.targetId = "richard"
	Game.battles.B02.battleType = frozen_kind
	Game.enter_node("battle")
	check(Game.state.battleId == "B02" and not Game.training_mode, "formal B02 enters through its authored story node")
	check(Game.state.combat.profile.battleType == frozen_kind, "B02 snapshot freezes " + frozen_kind)
	# Change only the in-memory catalog before Main creates the battle view.
	Game.battles.B02.battleType = catalog_after
	check(Game.battle_type() == frozen_kind and Game.configured_battle_type("B02") == catalog_after, "frozen " + frozen_kind + " takes priority over catalog " + catalog_after)
	var saw_covered_battle := false
	var stayed_silent := true
	while Game.transition_locked:
		if app.shown_page == "battle":
			saw_covered_battle = true
			var player := normal_music()
			stayed_silent = stayed_silent and (not is_instance_valid(player) or not player.playing)
		await get_tree().process_frame
	check(saw_covered_battle and stayed_silent, "B02 music waits until its entry transition finishes")
	await settle()
	check(app.view.model.profile.battleType == frozen_kind, "battle view preserves the frozen " + frozen_kind + " type")

func leave_battle(title: String) -> void:
	var player := normal_music()
	var had_player := is_instance_valid(player)
	Game.menu()
	await settle()
	check(app.shown_page == "menu" and app.music_player.playing, title + " restores non-battle music")
	check(not had_player or not is_instance_valid(player), title + " releases its battle player")

func check_playback_and_settings() -> void:
	var player := normal_music()
	if not is_instance_valid(player): return
	var stream := player.stream
	if expect_track and active(player) and stream != null:
		check(stream.get_length() > 0.7, "selected track has enough duration for two boundary probes")
		for crossing in range(2):
			# Native OGG seek resets loop_count, so each crossing starts its own probe.
			player.seek(stream.get_length() - 0.12)
			await get_tree().create_timer(0.5).timeout
			check(active(player) and player.stream == stream and player.get_stream_playback().get_loop_count() > 0 and player.get_playback_position() < 0.7, "ordinary track crosses native loop boundary %d" % (crossing + 1))
	var playback := player.get_stream_playback() if expect_track and player.playing else null
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	PlayerSettings.set_music_enabled(false)
	check(AudioServer.is_bus_mute(music_bus) and player.stream == stream and player.playing == expect_track, "music switch mutes the bus while preserving playback or missing-file silence")
	PlayerSettings.set_music_enabled(true)
	check(not AudioServer.is_bus_mute(music_bus) and player.stream == stream and player.playing == expect_track, "music switch restores the same stream without starting a missing track")
	check(not expect_track or player.get_stream_playback() == playback, "music toggle preserves the live playback object without restarting")
	PlayerSettings.set_music_volume(0.25)
	check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.25)), "music volume changes the independent Music bus")
	check(is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus), 0.0) and not AudioServer.is_bus_mute(sfx_bus), "music volume leaves SFX unchanged")
	PlayerSettings.sfx_enabled = false
	PlayerSettings.sfx_volume = 0.0
	PlayerSettings._apply_audio()
	check(AudioServer.is_bus_mute(sfx_bus) and not AudioServer.is_bus_mute(music_bus) and player.playing == expect_track, "SFX mute preserves ordinary music or missing-file silence")
	PlayerSettings.set_music_volume(0.0)
	check(AudioServer.is_bus_mute(music_bus) and player.stream == stream, "zero music volume silences the same stream")
	PlayerSettings.master_volume = 0.0
	PlayerSettings._apply_audio()
	check(AudioServer.is_bus_mute(0), "master volume also covers ordinary music")
	PlayerSettings.master_volume = 1.0
	PlayerSettings.sfx_enabled = true
	PlayerSettings.sfx_volume = 1.0
	PlayerSettings.set_music_volume(1.0)
	check(not AudioServer.is_bus_mute(0) and not AudioServer.is_bus_mute(music_bus) and player.playing == expect_track, "restoring settings preserves the correct playback state")

func _ready() -> void:
	var expectation := OS.get_environment("QA_EXPECT_NORMAL_MUSIC")
	if not OS.get_user_data_dir().contains("normal-battle-music-qa") or expectation not in ["0", "1"]:
		push_error("Run in a copied project with normal-battle-music-qa in its user directory and QA_EXPECT_NORMAL_MUSIC=0 or 1")
		get_tree().quit(2)
		return
	get_tree().create_timer(120).timeout.connect(func(): push_error("Normal battle music QA timed out"); get_tree().quit(2))
	expect_track = expectation == "1"
	Game.save_enabled = false
	Game.save_path = "user://normal-music-unused-checkpoint.json"
	Game.meta_path = "user://normal-music-unused-meta.json"
	PlayerSettings.settings_path = "user://normal-music-settings.cfg"
	PlayerSettings.reset_defaults()
	check(ResourceLoader.exists(TRACK_PATH) == expect_track, "optional resource presence matches the selected QA mode")
	var original_kind: String = Game.battles.B02.battleType
	fresh("menu")
	app = App.instantiate()
	add_child(app)
	await settle()
	check(app.music_player.playing, "menu initially uses its existing non-battle music")

	await enter_formal("normal", "elite")
	check_normal("formal B02 with frozen normal / current elite")
	await check_playback_and_settings()
	await leave_battle("leaving formal ordinary battle")
	await enter_formal("elite", "normal")
	check_excluded("frozen elite / current normal")
	await leave_battle("leaving elite battle")
	await enter_formal("boss", "normal")
	check(app.view.model.profile.get("encounterId", "") != "dancer_duet", "boss exclusion fixture is not the dancer encounter")
	check_excluded("frozen non-dancer boss / current normal")
	await leave_battle("leaving non-dancer boss battle")
	Game.battles.B02.battleType = original_kind

	Game.start_enemy_training("fish")
	await settle()
	check(Game.training_mode and not Game.tutorial_mode and Game.battle_type() == "normal", "published ordinary practice retains normal classification")
	check_normal("ordinary enemy practice")
	await leave_battle("leaving ordinary practice")
	Game.start_tutorial()
	await settle()
	check(Game.tutorial_mode and Game.battle_type() == "normal", "tutorial is a normal-type fixture that must still be excluded")
	check_excluded("tutorial")
	await leave_battle("leaving tutorial")
	Game.start_enemy_training("dancer_duet")
	await settle()
	check_excluded("dancer encounter")
	var dancer := app.view.get_node_or_null("DancerMusic") as AudioStreamPlayer
	check(is_instance_valid(dancer) and dancer.playing and dancer.stream != null and dancer.stream.resource_path == "res://assets/audio/music/dancer_rain_loop.ogg", "dancer practice retains its existing dedicated music")
	await leave_battle("leaving dancer practice")

	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "QA writes no adventure or profile saves")
	check(await Cleanup.release(app, get_tree()), "existing audio cleanup drains the menu after battle transitions")
	app.free()
	await get_tree().process_frame
	var report := {"checks": checks, "failures": failures, "optional_track_present": expect_track, "audio": "Dummy", "track_kind": OS.get_environment("QA_TRACK_KIND"), "scope": "formal B02; frozen normal/elite/non-dancer boss; two loops; settings and bus isolation; ordinary practice/tutorial/dancer isolation; playback checks only, no human listening assessment"}
	var output := OS.get_environment("QA_OUT_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join("normal-battle-music-result.json"), FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("NORMAL_BATTLE_MUSIC_TESTS expected_track=%s checks=%d failures=%d" % [expect_track, checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
