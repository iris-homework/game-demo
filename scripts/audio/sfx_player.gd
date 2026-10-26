extends Node
## Shared presentation-only SFX player for released scenes and developer previews.

signal cue_played(cue: String, path: String)
signal library_changed

const MAX_VOICES := 8
const SUPPORTED_EXTENSIONS := ["ogg", "wav", "mp3"]
const CUE_NAMES := [
	"ui_click", "ui_cancel", "ui_error",
	"card_hover", "card_select", "card_deselect", "card_play",
	"card_draw", "card_discard", "card_shuffle", "card_exhaust",
	"dialogue_blip", "dialogue_advance",
	"trade_success", "coin", "reward", "victory", "defeat",
	"technology", "stance", "ammo", "block", "parry",
	"turn_start", "heal", "transition", "energy",
]
const DEFAULT_BINDINGS := {
	"ui_click": "ui/ui_click_balatro_01.ogg",
	"ui_cancel": "ui/ui_cancel_balatro_01.ogg",
	"ui_error": "ui/ui_cancel_balatro_01.ogg",
	"card_hover": "cards/card_hover_balatro_01.ogg",
	"card_select": "cards/card_select_balatro_01.ogg",
	"card_deselect": "cards/card_deselect_balatro_01.ogg",
	"card_play": "cards/card_draw_balatro_01.ogg",
	"card_draw": "cards/card_draw_balatro_01.ogg",
	"card_discard": "cards/card_crumple_balatro_01.ogg",
	"card_shuffle": "cards/card_fan_balatro_02.ogg",
	"card_exhaust": "combat/effect_whoosh_out_balatro_02.ogg",
	"dialogue_blip": "dialogue/dialogue_blip_cozy_soft_01.wav",
	"dialogue_advance": "world/notice_highlight_balatro_01.ogg",
	"trade_success": "world/credits_coin_balatro_07.ogg",
	"coin": "world/credits_coin_balatro_01.ogg",
	"reward": "",
	"victory": "",
	"defeat": "",
	"technology": "cards/card_holo_apply_balatro_01.ogg",
	"stance": "cards/card_select_balatro_01.ogg",
	"ammo": "combat/effect_trigger_balatro_01.ogg",
	"block": "cards/card_foil_apply_balatro_01.ogg",
	"parry": "combat/effect_slice_balatro_01.ogg",
	"turn_start": "",
	"heal": "cards/card_foil_trigger_balatro_02.ogg",
	"transition": "",
	"energy": "",
}
const THROTTLE_USEC := {
	"dialogue_blip": 80000,
	"card_hover": 70000,
}
const DIALOGUE_PITCHES := {"noren": 0.88, "npc": 1.0, "narrator": 1.0}

var bindings: Dictionary = {}
var master_volume_db: float = -12.0:
	set(value):
		master_volume_db = value
		_apply_master_volume()

var _players: Array[AudioStreamPlayer] = []
var _stream_cache: Dictionary = {}
var _last_play_usec: Dictionary = {}
var _excerpt_tweens: Array[Tween] = []


var _registered_streams: Dictionary = {}

func _ready() -> void:
	_ensure_players()

func _exit_tree() -> void:
	stop_all()

func cues() -> Array[String]:
	var result: Array[String] = []
	for cue in CUE_NAMES:
		result.append(cue)
	return result


func bind(cue: String, path: String) -> bool:
	if not CUE_NAMES.has(cue):
		return false
	if path.is_empty():
		bindings[cue] = ""
		library_changed.emit()
		return true
	if not _has_entry(path):
		return false
	bindings[cue] = path
	library_changed.emit()
	return true


func play_dialogue(role: String) -> bool:
	return play_cue("dialogue_blip", float(DIALOGUE_PITCHES.get(role, DIALOGUE_PITCHES.narrator)))


func play_cue(cue: String, pitch_scale: float = 1.0) -> bool:
	if not is_finite(pitch_scale) or pitch_scale <= 0.0: return false
	if not CUE_NAMES.has(cue) or not bindings.has(cue):
		return false
	var path: String = bindings[cue]
	if path.is_empty() or not _has_entry(path) or _is_throttled(cue):
		return false
	if not _start(path, 0.10 if cue == "dialogue_blip" else 0.0, pitch_scale):
		return false
	_last_play_usec[cue] = Time.get_ticks_usec()
	cue_played.emit(cue, path)
	return true


func audition(path: String) -> bool:
	if not _has_entry(path):
		return false
	return _start(path)


func stop_all() -> void:
	for fade in _excerpt_tweens:
		if fade.is_valid(): fade.kill()
	_excerpt_tweens.clear()
	_ensure_players()
	for player in _players:
		player.stop()
		player.stream = null
	_stream_cache.clear()
	_last_play_usec.clear()


func _has_entry(path: String) -> bool:
	return _registered_streams.has(path)

func _load_stream(path: String) -> AudioStream:
	return _registered_streams.get(path) as AudioStream

func _is_throttled(cue: String) -> bool:
	if not THROTTLE_USEC.has(cue) or not _last_play_usec.has(cue):
		return false
	return Time.get_ticks_usec() - int(_last_play_usec[cue]) < int(THROTTLE_USEC[cue])


func _start(path: String, excerpt_seconds: float = 0.0, pitch_scale: float = 1.0) -> bool:
	var player := _acquire_player()
	if player == null:
		return false
	var stream: AudioStream = _stream_cache.get(path)
	if stream == null:
		stream = _load_stream(path)
		if stream == null:
			return false
		_stream_cache[path] = stream
	player.stream = stream
	player.volume_db = master_volume_db
	player.pitch_scale = pitch_scale
	var generation := int(player.get_meta("excerpt_generation",0))+1
	player.set_meta("excerpt_generation",generation)
	player.play()
	if excerpt_seconds > 0.0 and stream.get_length() / pitch_scale > excerpt_seconds:
		for i in range(_excerpt_tweens.size()-1,-1,-1):
			if not _excerpt_tweens[i].is_valid() or not _excerpt_tweens[i].is_running(): _excerpt_tweens.remove_at(i)
		var reference: WeakRef = weakref(player)
		var fade := create_tween()
		_excerpt_tweens.append(fade)
		fade.tween_interval(maxf(0.0,excerpt_seconds-0.015))
		fade.tween_method(_excerpt_volume.bind(reference,generation),master_volume_db,-60.0,0.015)
		fade.tween_callback(_finish_excerpt.bind(reference,generation))
	return true

func _excerpt_volume(level: float, reference: WeakRef, generation: int) -> void:
	var player: AudioStreamPlayer = reference.get_ref()
	if is_instance_valid(player) and int(player.get_meta("excerpt_generation",0)) == generation: player.volume_db = level

func _finish_excerpt(reference: WeakRef, generation: int) -> void:
	var player: AudioStreamPlayer = reference.get_ref()
	if is_instance_valid(player) and int(player.get_meta("excerpt_generation",0)) == generation:
		player.stop()
		player.stream = null


func _ensure_players() -> void:
	if not _players.is_empty():
		return
	for index in MAX_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%02d" % (index + 1)
		player.bus = "SFX"
		player.volume_db = master_volume_db
		add_child(player)
		_players.append(player)


func _acquire_player() -> AudioStreamPlayer:
	_ensure_players()
	for player in _players:
		if not player.is_playing():
			return player
	return null


func _apply_master_volume() -> void:
	for player in _players:
		player.volume_db = master_volume_db
