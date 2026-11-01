extends AudioStreamPlayer
## Battle-owned soundtrack; shared music preferences are applied through Music.
const TRACK_PATH := "res://assets/audio/music/chrono_ark_battle2_1.ogg"

func _ready() -> void:
	name = "NormalBattleMusic"
	bus = &"Music"
	volume_db = -12.0

func start_if_available() -> void:
	if playing or not ResourceLoader.exists(TRACK_PATH): return
	var source := load(TRACK_PATH) as AudioStreamOggVorbis
	if source == null: return
	# Configure this player without mutating the imported/shared resource.
	var music := source.duplicate() as AudioStreamOggVorbis
	music.loop = true
	stream = music
	play()
