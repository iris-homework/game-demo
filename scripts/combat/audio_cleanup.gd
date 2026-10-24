extends RefCounted
## AudioServer releases stopped playbacks on its own thread. Await the actual
## references, not simulated frame time (headless --fixed-fps runs much faster).

static func release(root: Node, tree: SceneTree) -> bool:
	var playbacks: Array[WeakRef] = []
	_stop_players(root, playbacks)
	var deadline := Time.get_ticks_msec() + 2000
	while true:
		var pending := false
		for playback in playbacks:
			if playback.get_ref() != null:
				pending = true
				break
		if not pending: return true
		if Time.get_ticks_msec() >= deadline:
			push_warning("Audio playback cleanup timed out after stopping players")
			return false
		# Yield to the real audio thread even during accelerated headless tests.
		OS.delay_msec(1)
		await tree.process_frame
	return true

static func _stop_players(node: Node, playbacks: Array[WeakRef]) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.has_stream_playback():
			playbacks.append(weakref(node.get_stream_playback()))
		node.stop()
		node.stream = null
	for child in node.get_children():
		_stop_players(child, playbacks)
