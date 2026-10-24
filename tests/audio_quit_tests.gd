extends Node
## Run in an isolated project. "-- window-close" invokes the native-close
## handler directly; it does not open a window or inject operating-system input.
var app: Control
var playback_ref: WeakRef
var stream_ref: WeakRef
var checks := 0
var failures := 0
var mode := "menu"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	Game.save_enabled = false
	Game.state = {}
	Game.page = "menu"
	if "window-close" in OS.get_cmdline_user_args(): mode = "window-close"
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	check(not get_tree().auto_accept_quit, "Main owns native close cleanup")
	var voice := AudioStreamPlayer.new()
	app.add_child(voice)
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 22050
	stream.data = PackedByteArray([0, 0, 1, 1, 2, 2, 1, 1])
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 8
	voice.stream = stream
	stream_ref = weakref(stream)
	stream = null
	voice.play()
	playback_ref = weakref(voice.get_stream_playback())
	check(voice.playing and playback_ref.get_ref() != null, "Quit starts with a live looping sound")
	app.tree_exiting.connect(verify_exit)
	get_tree().create_timer(10.0).timeout.connect(func(): get_tree().quit(2))
	if mode == "window-close":
		app._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		Game.request_quit()
		check(is_instance_valid(app.exit_dialog), "Menu quit still requires its existing confirmation")
		app.confirm_exit()
	check(app.quitting and app.process_mode == Node.PROCESS_MODE_DISABLED, "Quit blocks new UI actions during cleanup")
	app.quit_after_audio_cleanup()
	check(app.quitting, "Duplicate quit request remains in the same shutdown")

func verify_exit() -> void:
	check(playback_ref.get_ref() == null, "Engine quits only after the audio playback is released")
	check(stream_ref.get_ref() == null, "Engine quits only after the sound data is released")
	check(Game.state.is_empty(), "Quit cleanup does not change adventure state")
	print("AUDIO QUIT %s: %d checks, %d failures" % [mode, checks, failures])
	if failures > 0: get_tree().quit(1)
