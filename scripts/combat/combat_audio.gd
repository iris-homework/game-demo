extends Node
## Presentation-only, independent voices so impacts never cut off attack tails.
signal cue_played(cue: String)

const CLIPS := {
	"slash": preload("res://assets/audio/combat/ruina_reference/kuro_Vert.wav"),
	"shoot": preload("res://assets/audio/combat/ruina_reference/roland/Roland_Shotgun.wav"),
	"snap": preload("res://assets/audio/combat/ruina_reference/Finger_Snapping.wav"),
}
# Leave headroom for repeated attacks overlapping their longer sampled tails.
const LEVELS := {"slash": -12.0, "shoot": -13.0, "snap": -10.0}
var muted_cues: Array[String] = []

func play_cue(cue: String) -> void:
	if not CLIPS.has(cue) or cue in muted_cues: return
	var voice := AudioStreamPlayer.new()
	voice.bus = "SFX"
	voice.stream = CLIPS[cue]
	voice.volume_db = LEVELS[cue]
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()
	cue_played.emit(cue)
