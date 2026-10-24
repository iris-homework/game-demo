extends Node
const Cleanup = preload("res://scripts/combat/audio_cleanup.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	Game.save_enabled = false
	await run()
	print("AUDIO CLEANUP TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func run() -> void:
	var scope := Node.new()
	add_child(scope)
	check(await Cleanup.release(scope, get_tree()), "An empty scope needs no audio wait")
	for round_index in 3:
		var playbacks: Array[WeakRef] = []
		var streams: Array[WeakRef] = []
		for kind in 3:
			var player: Node
			match kind:
				0: player = AudioStreamPlayer.new()
				1: player = AudioStreamPlayer2D.new()
				_: player = AudioStreamPlayer3D.new()
			scope.add_child(player)
			var stream := AudioStreamWAV.new()
			stream.mix_rate = 22050
			stream.data = PackedByteArray([0, 0, 1, 1, 2, 2, 1, 1])
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = 8
			player.stream = stream
			streams.append(weakref(stream))
			stream = null
			player.play()
			# Positional players start from the next physics frame.
			await get_tree().physics_frame
			await get_tree().process_frame
			check(player.has_stream_playback(), "Round %d kind %d starts playback" % [round_index, kind])
			if player.has_stream_playback(): playbacks.append(weakref(player.get_stream_playback()))
		check(await Cleanup.release(scope, get_tree()), "Audio thread completes cleanup within deadline")
		for playback in playbacks:
			check(playback.get_ref() == null, "Stopped playback has no remaining strong references")
		for stream in streams:
			check(stream.get_ref() == null, "Procedural sound data is released")
		for player in scope.get_children(): player.free()
	check(await Cleanup.release(scope, get_tree()), "Repeated cleanup is safe")
	scope.free()
