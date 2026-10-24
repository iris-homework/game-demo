extends Node
## Headless checks for the isolated candidate-audio bank.

const AudioPreviewBankScript := preload("res://enemy_asset_pipeline/runtime/audio_preview_bank.gd")
const PipelineImageScript := preload("res://enemy_asset_pipeline/runtime/pipeline_image.gd")

const OGG_PATH := "res://assets/audio/incoming/ui/ui_click_balatro_01.ogg"
const MP3_PATH := "res://assets/audio/incoming/dialogue/text-blip-14855.mp3"
const WAV_PATH := "res://assets/audio/incoming/dialogue/dialogue_blip_cozy_soft_01.wav"
const LONG_PATH := "res://assets/audio/incoming/ambience/ambient_fire_balatro_01.ogg"

var checks := 0
var failures := 0


func check(ok: bool, title: String) -> void:
	checks += 1
	if ok:
		return
	failures += 1
	push_error("AUDIO BINDING: "+title)


func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func(): get_tree().quit(2))
	var bank = AudioPreviewBankScript.new()
	add_child(bank)

	_test_scan(bank)
	_test_rejected_bindings_and_paths(bank)
	_test_audio_formats()
	_test_default_bindings(bank)
	_test_reference_refresh(bank)
	await _test_playback(bank)
	_test_dialogue_pitch(bank)
	bank.stop_all()
	bank.bind("dialogue_blip",MP3_PATH)
	check(bank.play_cue("dialogue_blip"),"long dialogue candidate can play as a short excerpt")
	await get_tree().create_timer(0.20).timeout
	var active := false
	for child in bank.get_children():
		if child is AudioStreamPlayer and child.is_playing(): active = true
	check(not active,"dialogue cue caps an 8.832-second MP3 at a 100ms excerpt")
	check(bank.audition(MP3_PATH),"manual audition still plays the complete original candidate")
	await get_tree().create_timer(0.20).timeout
	active = false
	for child in bank.get_children():
		if child is AudioStreamPlayer and child.is_playing(): active = true
	check(active,"manual audition is not cut at the dialogue excerpt boundary")
	await preload("res://scripts/combat/audio_cleanup.gd").release(bank,get_tree())
	bank.stop_all()

	bank.free()
	print("AUDIO_PREVIEW_BANK_TESTS checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _test_scan(bank: Node) -> void:
	var scanned: Array = bank.scan()
	check(scanned.size() >= 96, "scan includes the original candidates, dialogue alternatives and reference refresh")
	check(scanned == bank.entries, "scan returns its current entries")
	var paths: Dictionary = {}
	var categories: Dictionary = {}
	for entry in scanned:
		check(entry.path.begins_with("res://assets/audio/incoming/"), "entry stays under candidate root")
		check(entry.path.get_extension().to_lower() in ["ogg", "wav", "mp3"], "entry has a supported extension")
		check(not entry.path.contains("/_originals/"), "original source files stay excluded")
		check(not entry.label.is_empty(), "entry has a display label")
		paths[entry.path] = true
		categories[entry.category] = true
	check(paths.has(OGG_PATH), "scan retains the UI OGG")
	check(paths.has(MP3_PATH), "scan retains the existing dialogue MP3")
	check(categories.has("cards") and categories.has("dialogue") and categories.has("world"), "category comes from the first directory")
	print("AUDIO_PREVIEW_BANK_SCAN entries=%d categories=%d" % [scanned.size(), categories.size()])
	check(bank.scan("res://assets/audio").is_empty(), "scan rejects a root outside candidates")
	check(bank.scan("res://assets/audio/incoming/_originals").is_empty(), "scan rejects the originals directory as a root")
	check(bank.entries.size() == scanned.size(), "invalid scan does not erase the current library")


func _test_rejected_bindings_and_paths(bank: Node) -> void:
	var original_click: String = bank.bindings["ui_click"]
	check(not bank.bind("not_a_cue", OGG_PATH), "unknown cue is rejected")
	check(not bank.bind("ui_click", "res://assets/audio/incoming/../combat/slash.wav"), "parent traversal is rejected")
	check(not bank.bind("ui_click", "user://outside.ogg"), "non-project path is rejected")
	check(not bank.audition("res://assets/audio/incoming/../combat/slash.wav"), "audition rejects parent traversal")
	check(not bank.audition("res://assets/audio/incoming/missing.ogg"), "audition rejects files outside entries")
	check(bank.bind("ui_click", ""), "empty binding mutes a known cue")
	check(not bank.play_cue("ui_click"), "muted cue plays silently and reports false")
	check(bank.bind("ui_click", original_click), "known cue can be restored after testing mute")


func _test_audio_formats() -> void:
	var ogg := PipelineImageScript.load_audio(OGG_PATH)
	var wav := PipelineImageScript.load_audio(WAV_PATH)
	var mp3 := PipelineImageScript.load_audio(MP3_PATH)
	check(ogg is AudioStreamOggVorbis, "unimported OGG loads through the shared loader")
	check(wav is AudioStreamWAV, "WAV loads through the shared loader")
	check(mp3 is AudioStreamMP3, "unimported MP3 loads through the shared loader")
	var references: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/incoming/_originals/dialogue_reference_20261025/manifest.json"))
	check(references is Dictionary and references.get("entries", []).size() == 7, "dialogue source manifest registers seven candidates")
	if references is Dictionary:
		for entry in references.get("entries", []):
			var candidate: AudioStream = PipelineImageScript.load_audio("res://" + str(entry.target))
			check(candidate != null and candidate.get_length() > 0.0, "new dialogue candidate decodes: " + str(entry.target))


func _test_default_bindings(bank: Node) -> void:
	check(bank.cues().size() >= 26, "the bank exposes the common cue contract")
	check(bank.bindings.get("dialogue_blip", "") == WAV_PATH, "dialogue blip defaults to the soft text candidate")
	var dialogue: AudioStream = PipelineImageScript.load_audio(WAV_PATH)
	check(dialogue != null and dialogue.get_length() <= 0.08, "default dialogue sound fits within its trigger interval")
	check(dialogue != null and bank.THROTTLE_USEC.dialogue_blip >= dialogue.get_length() * 1000000, "default dialogue sounds cannot overlap at the throttle boundary")
	check(bank.bindings.get("ui_click", "") == OGG_PATH, "UI click returns to its previous Balatro candidate")
	check(bank.bindings.get("card_hover", "") == "res://assets/audio/incoming/cards/card_hover_balatro_01.ogg", "card hover maps to its candidate")
	for cue in ["reward", "victory", "defeat", "transition", "turn_start", "energy"]:
		check(bank.bindings.has(cue) and bank.bindings[cue].is_empty(), "removed feedback has an explicit silent binding: " + cue)
		check(not bank.play_cue(cue), "removed feedback does not start a voice: " + cue)
	bank.scan()
	check(bank.bindings["reward"].is_empty() and bank.bindings["turn_start"].is_empty(), "rescanning preserves explicit silence")
	for cue in bank.bindings:
		var path: String = bank.bindings[cue]
		check(not path.contains("/ambience/"), "ambience is not auto-bound to a cue")
		check(path.is_empty() or bank.entries.any(func(entry): return entry.path == path), "every default points into the current library")


func _test_reference_refresh(bank: Node) -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/incoming/_originals/reference_refresh_20261025/manifest.json"))
	check(manifest is Dictionary and manifest.get("entries", []).size() == 13, "reference refresh registers thirteen replacements")
	if not manifest is Dictionary: return
	check(manifest.get("current_default_replacements", []).is_empty(), "removed reference feedback is no longer a default")
	for entry in manifest.get("entries", []):
		var path := "res://" + str(entry.target)
		var relative: String = entry.current_binding
		var expected := "" if relative.is_empty() else "res://assets/audio/incoming/" + relative
		check(bank.bindings.get(str(entry.cue), "") == expected, "requested defaults and reverted bindings are respected: " + str(entry.cue))
		var stream: AudioStream = PipelineImageScript.load_audio(path)
		check(stream != null and stream.get_length() > 0.0, "reference replacement decodes: " + str(entry.cue))
		if stream == null: continue
		check(absf(stream.get_length() - float(entry.duration_seconds)) < 0.025, "reference duration matches source metadata: " + str(entry.cue))
		if stream is AudioStreamOggVorbis:
			check(not stream.loop, "one-shot OGG does not loop: " + str(entry.cue))
		elif stream is AudioStreamWAV:
			check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "one-shot WAV does not loop: " + str(entry.cue))


func _test_playback(bank: Node) -> void:
	var played: Array[String] = []
	bank.cue_played.connect(func(cue: String, _path: String): played.append(cue))
	check(bank.audition("res://assets/audio/incoming/cards/card_select_balatro_01.ogg"), "audition starts a candidate")
	check(bank.play_cue("ui_click"), "retained button cue starts playback")
	check(played.has("ui_click"), "successful cue emits cue_played")
	check(bank.play_cue("dialogue_blip"), "dialogue blip starts once")
	check(not bank.play_cue("dialogue_blip"), "dialogue blip is throttled within 80 ms")
	check(bank.play_cue("card_hover"), "card hover starts once")
	check(not bank.play_cue("card_hover"), "card hover is throttled within 70 ms")
	var playbacks := _collect_playbacks(bank)
	bank.stop_all()
	check(await _wait_for_release(playbacks), "stopped cue playbacks release from the audio thread")
	for index in 8:
		check(bank.audition(LONG_PATH), "voice pool accepts voice %d" % (index + 1))
	check(not bank.audition("res://assets/audio/incoming/cards/card_select_balatro_01.ogg"), "a ninth concurrent voice is rejected")

	var voice_count := 0
	var active_count := 0
	for child in bank.get_children():
		if child is AudioStreamPlayer:
			voice_count += 1
			if child.is_playing():
				active_count += 1
	check(voice_count == 8, "bank has a fixed eight-voice pool")
	check(active_count <= 8, "bank never exceeds eight active voices")

	playbacks = _collect_playbacks(bank)
	bank.stop_all()
	var released := true
	for child in bank.get_children():
		if child is AudioStreamPlayer and (child.is_playing() or child.stream != null):
			released = false
	check(released, "stop_all stops voices and clears stream references")
	check(await _wait_for_release(playbacks), "saturated voice playbacks release from the audio thread")
	check(not bank.play_cue("not_a_cue"), "unknown cue stays silent")


func _test_dialogue_pitch(bank: Node) -> void:
	for role in {"noren": 0.88, "npc": 1.0, "narrator": 1.0}:
		bank.stop_all()
		check(bank.play_dialogue(role), "dialogue role starts: " + role)
		var expected: float = bank.DIALOGUE_PITCHES[role]
		check(is_equal_approx(_active_voice_pitch(bank), expected), "voice player uses the chosen role pitch: " + role)
		var voice: AudioStream = PipelineImageScript.load_audio(WAV_PATH)
		check(voice.get_length() / expected <= bank.THROTTLE_USEC.dialogue_blip / 1000000.0, "role pitch keeps the default short sound within its trigger interval: " + role)
	bank.stop_all()
	check(bank.play_dialogue("unknown") and is_equal_approx(_active_voice_pitch(bank), 1.0), "unknown dialogue roles fall back to narration pitch")
	bank.stop_all()
	bank.play_dialogue("noren")
	bank.stop_all()
	check(bank.play_cue("ui_click") and is_equal_approx(_active_voice_pitch(bank), 1.0), "ordinary cues reset pitch after a dialogue voice")
	bank.stop_all()
	bank.play_dialogue("noren")
	bank.stop_all()
	check(bank.audition(WAV_PATH) and is_equal_approx(_active_voice_pitch(bank), 1.0), "manual full-file audition resets pitch after dialogue")
	bank.stop_all()


func _active_voice_pitch(bank: Node) -> float:
	for player in bank.get_children():
		if player is AudioStreamPlayer and player.is_playing(): return player.pitch_scale
	return -1.0


func _collect_playbacks(root: Node) -> Array[WeakRef]:
	var playbacks: Array[WeakRef] = []
	for child in root.get_children():
		if child is AudioStreamPlayer and child.has_stream_playback():
			playbacks.append(weakref(child.get_stream_playback()))
	return playbacks


func _wait_for_release(playbacks: Array[WeakRef]) -> bool:
	var deadline := Time.get_ticks_msec() + 2000
	while true:
		var pending := false
		for playback in playbacks:
			if playback.get_ref() != null:
				pending = true
				break
		if not pending:
			return true
		if Time.get_ticks_msec() >= deadline:
			return false
		OS.delay_msec(1)
		await get_tree().process_frame
	return false
