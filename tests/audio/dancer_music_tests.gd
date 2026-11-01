extends "res://tests/audio/background_music_tests.gd"
## Run in a copied project using a dedicated dancer-music-settings-qa user directory.
const DANCER_TRACK := "res://assets/audio/music/dancer_rain_loop.ogg"

func dancer_music() -> AudioStreamPlayer:
	return app.view.get_node_or_null("DancerMusic") as AudioStreamPlayer

func plays(player: AudioStreamPlayer, expected: String) -> bool:
	if not is_instance_valid(player) or not player.playing or player.stream_paused or player.stream == null:
		return false
	return player.stream.resource_path == expected

func check_loop(player: AudioStreamPlayer, title: String) -> void:
	var stream := player.stream
	check(stream is AudioStreamOggVorbis and stream.loop, title + " uses native OGG looping")
	# Native decoder seek resets its loop counter; each crossing must reach > 0 anew.
	for crossing in range(2):
		player.seek(stream.get_length() - 0.12)
		await get_tree().create_timer(0.55).timeout
		check(plays(player, DANCER_TRACK) and player.stream == stream and player.get_stream_playback().get_loop_count() > 0 and player.get_playback_position() < 1.0, title + " crosses native loop boundary %d without replacing the stream" % (crossing + 1))

func observe_change(view: Control, player: AudioStreamPlayer) -> void:
	var stream := player.stream
	var covered := false
	var silent := true
	var same_stream := true
	var frozen := true
	var frozen_position := -1.0
	var revealed := false
	var heard_start := false
	var held_silence := false
	var resumed_position := -1.0
	var onset_seconds := -1.0
	while Game.battle_busy or Game.transition_locked:
		same_stream = same_stream and player.stream == stream
		if is_instance_valid(view.dancer_blackout):
			covered = true
			# AudioStreamPlayer.playing can remain true while stream_paused silences it.
			silent = silent and player.stream_paused and not app.music_player.playing
			if frozen_position < 0.0:
				frozen_position = player.get_playback_position()
			frozen = frozen and absf(player.get_playback_position() - frozen_position) <= 0.08
		elif covered and not heard_start:
			if not revealed:
				revealed = true
				held_silence = player.stream_paused and not app.music_player.playing
			if plays(player, DANCER_TRACK):
				var lights = view.stage.dancer_lights
				onset_seconds = lights.reveal_progress * lights.REVEAL_DURATION
				resumed_position = player.get_playback_position()
				heard_start = true
			else:
				held_silence = held_silence and player.stream_paused and not app.music_player.playing
				frozen = frozen and absf(player.get_playback_position() - frozen_position) <= 0.08
		await get_tree().process_frame
	print("DANCER_MUSIC_CONTINUITY frozen=%.3f resumed=%.3f reveal_delay=%.3f same_stream=%s frozen_through_wait=%s" % [frozen_position, resumed_position, onset_seconds, same_stream, frozen])
	check(covered and silent, "stream stays paused and menu music stays stopped on every blackout frame")
	check(revealed and held_silence, "music remains paused after the dancers appear until the reveal delay")
	check(same_stream and player.stream == stream, "phase change preserves the same music stream")
	check(frozen and frozen_position >= 11.5, "blackout and reveal delay freeze the established playback position (%.3f s)" % frozen_position)
	check(heard_start and onset_seconds >= 0.33 and onset_seconds <= 0.45, "same track unpauses after the short reveal pause (%.3f s)" % onset_seconds)
	check(heard_start and absf(resumed_position - frozen_position) <= 0.15, "reveal continues from the paused position instead of restarting (%.3f -> %.3f s)" % [frozen_position, resumed_position])
	await settle()
	await get_tree().create_timer(0.2).timeout
	check(plays(player, DANCER_TRACK) and player.get_playback_position() > resumed_position + 0.1, "unpaused music advances after the reveal")

func _ready() -> void:
	if not OS.get_user_data_dir().contains("dancer-music-settings-qa"):
		push_error("Dancer music tests require a copied project with dancer-music-settings-qa in the user directory")
		get_tree().quit(2)
		return
	get_tree().create_timer(90).timeout.connect(func(): push_error("Dancer music QA timed out"); get_tree().quit(2))
	Game.save_enabled = false
	Game.save_path = "user://dancer-current.json"
	Game.meta_path = "user://dancer-meta.json"
	PlayerSettings.settings_path = "user://dancer-settings.cfg"
	PlayerSettings.reset_defaults()
	fresh("map")
	Game.state.currentDay = 7
	Game.refresh_event_pool()
	check(Game.start_event("E16"), "formal day-seven event starts")
	app = App.instantiate()
	add_child(app)
	await settle()
	check(app.music_player.playing, "boss dialogue retains non-battle music")
	Game.skip_dialogue(Game.revision)
	while app.shown_page != "battle":
		await get_tree().process_frame
	var entry_player := dancer_music()
	check(is_instance_valid(entry_player) and not entry_player.playing, "first phase opens in silence")
	while Game.transition_locked:
		await get_tree().process_frame
	var entry_wait := 0.0
	while is_instance_valid(entry_player) and not entry_player.playing and entry_wait < 1.0:
		await get_tree().process_frame
		entry_wait += get_process_delta_time()
	check(plays(entry_player, DANCER_TRACK) and entry_wait >= 0.28 and entry_wait <= 0.45, "first phase starts after a short pause (%.3f s)" % entry_wait)
	await settle()
	var view: Control = app.view
	var player := dancer_music()
	check(plays(player, DANCER_TRACK) and not app.music_player.playing, "formal B16 uses the single loop exclusively")
	if player == null or player.stream == null:
		get_tree().quit(1)
		return
	check(player.bus == &"Music", "battle music uses player music preferences")
	await check_loop(player, "phase one")
	PlayerSettings.set_music_enabled(false)
	check(player.playing and AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "disabling music mutes the live boss track")
	PlayerSettings.set_music_enabled(true)
	player.seek(12.0)
	await get_tree().create_timer(0.1).timeout
	# The first black dancer strikes into a lethal parry, traversing the real enemy-turn presentation.
	view.model.enemies[0].hp = 1
	view.shown_enemies[0].hp = 1
	view.model.parry = 1
	view.shown_player_parry = 1
	view.end_turn_pressed()
	await observe_change(view, player)
	check(view.shown_encounter_phase == 2 and plays(player, DANCER_TRACK), "settled duet continues the same loop")
	await check_loop(player, "phase two")
	var legacy := Game.state.duplicate(true)
	legacy.erase("battleStart")
	check(Game.save_game(), "current checkpoint writes to isolated test path")
	Game.menu()
	await settle()
	check(not is_instance_valid(player) and app.music_player.playing, "leaving the battle frees its player and restores menu music")
	check(Game.load_game(), "regular in-progress boss checkpoint can load")
	await settle()
	check(app.view.shown_encounter_phase == 1 and plays(dancer_music(), DANCER_TRACK), "current saves restart the fight with the single loop")
	Game.menu()
	await settle()
	Game.save_path = "user://dancer-legacy.json"
	var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	check(Game.load_game(), "legacy phase-two checkpoint without battleStart loads")
	await settle()
	check(app.view.shown_encounter_phase == 2 and plays(dancer_music(), DANCER_TRACK), "legacy phase-two snapshot starts the same loop")
	check(not is_instance_valid(app.view.dancer_blackout) and not app.music_player.playing, "restored duet needs no blackout or menu track")
	Game.menu()
	await settle()
	Game.start_enemy_training("dancer_duet")
	await settle()
	player = dancer_music()
	check(Game.training_mode and plays(player, DANCER_TRACK), "published boss practice uses the same loop with the temporary battle ID")
	view = app.view
	player.seek(12.0)
	await get_tree().create_timer(0.1).timeout
	var card_uid := str(view.model.hand[0])
	view.model.instances[card_uid] = "noren_01"
	view.model.enemies[0].hp = 1
	view.shown_enemies[0].hp = 1
	view.select_card(card_uid)
	view.play_selected(0)
	await observe_change(view, player)
	Game.finish_training("win")
	await settle()
	check(not is_instance_valid(player) and app.music_player.playing, "practice completion releases duet music and resumes the menu track")
	Game.start_enemy_training("fish")
	await settle()
	player = dancer_music()
	check((player == null or not player.playing) and not app.music_player.playing, "ordinary practice has no boss or menu track")
	Game.menu()
	await settle()
	Game.start_tutorial()
	await settle()
	player = dancer_music()
	check((player == null or not player.playing) and not app.music_player.playing, "tutorial has no boss or menu track")
	check(await Cleanup.release(app, get_tree()), "audio drains at shutdown")
	app.free()
	await get_tree().process_frame
	print("DANCER_MUSIC_TESTS checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
