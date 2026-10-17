extends Node
## Presentation-only, independent voices so impacts never cut off attack tails.
signal cue_played(cue: String)

const CLIPS := {
	"slash": preload("res://assets/audio/combat/slash.wav"),
	"shoot": preload("res://assets/audio/combat/shotgun.wav"),
	"snap": preload("res://assets/audio/combat/finger_snap.wav"),
}
const LEVELS := {"slash": -7.0, "shoot": -8.0, "snap": -5.0}

func play_cue(cue: String) -> void:
	if not CLIPS.has(cue): return
	var voice := AudioStreamPlayer.new()
	voice.stream = CLIPS[cue]
	voice.volume_db = LEVELS[cue]
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()
	cue_played.emit(cue)
