extends Node
## Presentation-only, independent voices so impacts never cut off attack tails.
signal cue_played(cue: String)

const CLIPS := {
	"slash": preload("res://assets/audio/combat/ruina_reference/kuro_Vert.wav"),
	"shoot": preload("res://assets/audio/combat/ruina_reference/roland/Roland_Shotgun.wav"),
	"snap": preload("res://assets/audio/combat/ruina_reference/Finger_Snapping.wav"),
	"bite": preload("res://assets/audio/combat/enemy_reference/monster_bite_lucasduff_467701.mp3"),
	"hit": preload("res://assets/audio/combat/enemy_reference/impact_strong_punch_mixkit_2155.mp3"),
}
# Leave headroom for repeated attacks overlapping their longer sampled tails.
const LEVELS := {"slash": -12.0, "shoot": -13.0, "snap": -10.0, "bite": -12.0, "hit": -12.0}
# Skip leading near-silence so the sampled attack starts at visual contact.
const START_OFFSETS := {"bite": 0.38, "hit": 0.04}
var muted_cues: Array[String] = []

func play_cue(cue: String) -> void:
	if not CLIPS.has(cue) or cue in muted_cues: return
	var voice := AudioStreamPlayer.new()
	voice.bus = "SFX"
	voice.stream = CLIPS[cue]
	voice.volume_db = LEVELS[cue]
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play(float(START_OFFSETS.get(cue, 0.0)))
	cue_played.emit(cue)
