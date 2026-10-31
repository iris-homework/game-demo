extends AudioStreamPlayer
## One continuous non-battle track, owned by Main rather than individual views.
const TRACK := preload("res://assets/audio/music/team_energy.mp3")

func _ready() -> void:
	name = "BackgroundMusic"
	bus = "Music"
	volume_db = -12.0
	# Keep loop configuration local to this player and out of the shared resource.
	var music := TRACK.duplicate() as AudioStreamMP3
	music.loop = true
	stream = music

func set_page(page: String) -> void:
	if page == "battle":
		stop()
	elif not playing and stream != null:
		play()
