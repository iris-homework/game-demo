class_name PipelineImage
extends RefCounted
## Safe project-local resource loading shared by the resolver and runtime actor.

static func is_project_path(path: String) -> bool:
	if not path.begins_with("res://") or path.contains("\\"):
		return false
	var relative := path.trim_prefix("res://")
	if relative.is_empty():
		return false
	for part in relative.split("/"):
		if part.is_empty() or part == "." or part == "..":
			return false
	return true


static func load_texture(path: String, force_image_fallback: bool = false) -> Texture2D:
	if not is_project_path(path):
		return null
	if not force_image_fallback and ResourceLoader.exists(path):
		var resource := ResourceLoader.load(path)
		if resource is Texture2D and resource.get_width() > 0 and resource.get_height() > 0:
			return resource as Texture2D
	# Newly copied PNGs may not have a .godot import cache yet. Image.load reads
	# the source file through FileAccess and keeps the fallback inside res://.
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK or image.get_width() <= 0 or image.get_height() <= 0:
		return null
	return ImageTexture.create_from_image(image)


static func audio_format(path: String) -> String:
	if not is_project_path(path):
		return ""
	var extension := path.get_extension().to_lower()
	return extension if extension in ["wav","ogg","mp3"] else ""


static func load_audio(path: String) -> AudioStream:
	var format := audio_format(path)
	if format.is_empty() or not FileAccess.file_exists(path):
		return null
	if ResourceLoader.exists(path,"AudioStream"):
		var resource := ResourceLoader.load(path,"AudioStream")
		if resource is AudioStream:
			return resource as AudioStream
	# Raw WAV/OGG/MP3 copied by the backend may not have a Godot import cache
	# yet. These loaders stay inside res:// and mirror the tuner's file playback.
	match format:
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null
