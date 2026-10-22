extends Node2D
## Existing pose textures, calibrated by body proportions and soles (not canvas bounds).
var sprite := Sprite2D.new()
var home := Vector2.ZERO
var facing := -1.0
var kind := "noren"
var is_player := false
var pose := "idle"
var alive := true
var combat_stance := "melee"
var tint := Color("ff4c9b")
var poses: Dictionary = {}
var calibrations: Dictionary = {}
var pose_aliases: Dictionary = {}
var target_bounds := Rect2(-58,-130,116,145)
var attack_style_override := ""
var laser_muzzle := Vector2.ZERO
var laser_palm_width := 0.0
var hit_effect_texture: Texture2D
var white_key_poses: Dictionary = {}
var source_facing := -1.0
var white_key_material: ShaderMaterial
var weapon_shift: Node
var pipeline_frames: Dictionary = {}
var pipeline_shadow: Dictionary = {}
var pipeline_motion: Dictionary = {}
var pipeline_effects: Dictionary = {}
var pipeline_xsxb: Dictionary = {}
var pipeline_attack_trails: Dictionary = {}
var pipeline_attacks: Dictionary = {}
var pipeline_source := ""
var pipeline_diagnostics: Array[String] = []
var pipeline_active := false
var pipeline_frame_index := 0
var pipeline_frame_elapsed := 0.0
var pipeline_playing := false
var attachment_below: Node2D
var attachment_above: Node2D
var frame_audio_players: Array[AudioStreamPlayer] = []
var frame_audio_cursor := 0
var trail_adapter: Node2D
var frame_profile_id := ""
var _current_frame := 0
var pipeline_pose_elapsed := 0.0
var _runtime_animation_frames_cache: Dictionary = {}
var use_mipmapped_textures := false
var _mipmapped_textures: Dictionary = {}
const WeaponShift := preload("res://scripts/combat/weapon_shift_fx.gd")
const PipelineCatalogScript := preload("res://enemy_asset_pipeline/runtime/pipeline_catalog.gd")
const PipelineRuntimeProfileScript := preload("res://enemy_asset_pipeline/runtime/pipeline_runtime_profile.gd")
const PipelineTrailAdapterScript := preload("res://enemy_asset_pipeline/runtime/pipeline_trail_adapter.gd")
const NOREN := {
	"idle": [Vector2(710,1240),0.099], "move": [Vector2(920,1048),0.103],
	"slash": [Vector2(725,1110),0.103], "pierce": [Vector2(1000,941),0.132],
	"block": [Vector2(550,1140),0.103], "damaged": [Vector2(700,1230),0.099],
	"gun_idle": [Vector2(660,1230),0.099], "shoot": [Vector2(714,1210),0.099], "retreat": [Vector2(560,1155),0.099],
	"gun_block": [Vector2(550,1140),0.103], "gun_damaged": [Vector2(700,1230),0.099]
}

func pose_calibrations() -> Dictionary:
	return calibrations

func setup_player(origin: Vector2, direction: float) -> void:
	is_player = true
	kind = "noren"
	frame_profile_id = "noren"
	calibrations = NOREN.duplicate(true)
	for key in calibrations:
		poses[key] = load("res://assets/combat_test/noren/noren_%s.png" % key)
	poses["shoot"] = preload("res://assets/combat_test/noren/noren_shoot_planted.png")
	_apply_player_pipeline()
	_place(origin,direction)
	_configure_trails()

func setup_enemy(visual: EnemyVisualResolver.Visual, origin: Vector2, direction: float) -> void:
	# All parsing, resource loading and fallback have already finished at the boundary.
	is_player = false
	kind = visual.id
	frame_profile_id = visual.id
	poses = visual.poses.duplicate()
	calibrations = visual.calibrations.duplicate(true)
	pose_aliases = visual.pose_aliases.duplicate(true)
	target_bounds = visual.target_bounds
	attack_style_override = visual.attack_style_override
	laser_muzzle = visual.laser_muzzle
	laser_palm_width = visual.laser_palm_width
	hit_effect_texture = visual.hit_effect_texture
	white_key_poses = visual.white_key_poses.duplicate()
	source_facing = visual.source_facing
	pipeline_frames = visual.pipeline_frames.duplicate()
	pipeline_shadow = visual.pipeline_shadow.duplicate(true)
	pipeline_motion = visual.pipeline_motion.duplicate(true)
	pipeline_effects = visual.pipeline_effects.duplicate(true)
	pipeline_xsxb = visual.pipeline_xsxb.duplicate(true)
	pipeline_attack_trails = visual.pipeline_attack_trails.duplicate(true)
	pipeline_attacks = visual.pipeline_attacks.duplicate(true)
	pipeline_source = visual.pipeline_source
	pipeline_active = visual.pipeline_active
	_runtime_animation_frames_cache.clear()
	if true in white_key_poses.values():
		white_key_material = ShaderMaterial.new()
		white_key_material.shader = preload("res://shaders/white_key.gdshader")
	_place(origin,direction)
	_configure_trails()

func _place(origin: Vector2, direction: float) -> void:
	home = origin
	position = origin
	facing = direction
	tint = Color("ff4c9b") if is_player else Color("6ae4f2")
	add_child(sprite)
	sprite.centered = false
	if use_mipmapped_textures: sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_pose("idle")
	queue_redraw()

func _apply_player_pipeline() -> void:
	pipeline_diagnostics.clear()
	var raw := PipelineCatalogScript.get_profile("noren")
	if raw.is_empty(): return
	var problems: Array[String] = []
	var runtime = PipelineRuntimeProfileScript.parse(raw,"noren",problems)
	if runtime == null or not runtime.has_pipeline:
		pipeline_diagnostics = problems
		if not problems.is_empty():
			push_warning("Noren pipeline profile rejected: "+"; ".join(problems))
		return
	pipeline_frames = runtime.frames
	pipeline_shadow = runtime.shadow
	pipeline_motion = runtime.motion
	pipeline_effects = runtime.effects
	pipeline_xsxb = runtime.xsxb
	pipeline_attack_trails = runtime.attack_trails
	pipeline_attacks = runtime.attacks
	# Player profiles may introduce a new pose as well as replace a built-in one.
	for key in raw.get("poses", {}):
		if not pipeline_frames.has(key) or pipeline_frames[key].is_empty(): continue
		poses[key] = pipeline_frames[key][0].texture
		if not calibrations.has(key): calibrations[key] = [Vector2.ZERO, 1.0]
	pipeline_source = PipelineCatalogScript.get_profile_source("noren")
	pipeline_active = true
	_runtime_animation_frames_cache.clear()
	if runtime.source_facing != 0.0: source_facing = runtime.source_facing

func set_pose(value: String) -> void:
	value = pose_aliases.get(value, value)
	if is_player and combat_stance == "ranged" and value in ["idle","block","damaged"]:
		value = "gun_"+value
	pose = value if poses.has(value) else "idle"
	# Player stance transitions temporarily own the sprite's material.
	if not is_player:
		sprite.material = white_key_material if white_key_poses.get(pose, false) else null
	pipeline_frame_index = 0
	pipeline_frame_elapsed = 0.0
	pipeline_pose_elapsed = 0.0
	_current_frame = 0
	_show_current_pose()

func face_toward(point: Vector2) -> void:
	var next_facing := 1.0 if point.x >= position.x else -1.0
	if is_equal_approx(next_facing,facing): return
	facing = next_facing
	_refresh_pose_transform()

func _show_current_pose() -> void:
	var frames: Array = pipeline_frames.get(pose, [])
	if not frames.is_empty():
		_show_pipeline_frame(frames,pipeline_frame_index)
		return
	_show_legacy_pose()

func _show_legacy_pose() -> void:
	pipeline_playing = false
	_current_frame = 0
	_clear_attachments()
	var calibration: Array = pose_calibrations().get(pose,pose_calibrations().get("idle",[Vector2.ZERO,1.0]))
	var anchor: Vector2 = calibration[0]
	var factor: float = calibration[1]
	sprite.texture = _display_texture(poses.get(pose,poses.get("idle")))
	var mirror := facing*source_facing
	# Legacy calibration remains unchanged when no pipeline frame exists.
	sprite.transform = Transform2D(Vector2(mirror*factor,0),Vector2(0,factor),Vector2(-anchor.x*mirror*factor,-anchor.y*factor))
	_sync_trails(false)

func _show_pipeline_frame(frames: Array, index: int) -> void:
	if frames.is_empty(): return
	pipeline_frame_index = clampi(index,0,frames.size()-1)
	_current_frame = pipeline_frame_index
	var frame = frames[pipeline_frame_index]
	pipeline_playing = true
	sprite.texture = _display_texture(frame.texture)
	_apply_pipeline_transform(frame.transform)
	_show_attachments(frame.attachments,frame.transform)
	_play_frame_audio(frame)
	_sync_trails()

func _apply_pipeline_transform(local_transform: Transform2D) -> void:
	# transform[6] already includes the source anchor and all visual scales.
	var mirror := facing*source_facing
	sprite.transform = Transform2D(Vector2(mirror,0),Vector2(0,1),Vector2.ZERO)*local_transform

func _refresh_pose_transform() -> void:
	var frames: Array = pipeline_frames.get(pose, [])
	if frames.is_empty():
		_show_legacy_pose()
		return
	var frame = frames[clampi(pipeline_frame_index,0,frames.size()-1)]
	_apply_pipeline_transform(frame.transform)
	_show_attachments(frame.attachments,frame.transform)
	_sync_trails(pipeline_playing)

func _process(delta: float) -> void:
	if not pipeline_playing or pipeline_frames.is_empty(): return
	var frames: Array = pipeline_frames.get(pose, [])
	if frames.is_empty():
		pipeline_playing = false
		return
	pipeline_frame_elapsed += delta
	pipeline_pose_elapsed += delta
	while pipeline_playing:
		var frame = frames[pipeline_frame_index]
		if pipeline_frame_elapsed < frame.duration: break
		pipeline_frame_elapsed -= frame.duration
		var next_index := pipeline_frame_index+1
		if next_index < frames.size():
			_show_pipeline_frame(frames,next_index)
		elif frame.loop:
			pipeline_pose_elapsed = pipeline_frame_elapsed
			_show_pipeline_frame(frames,0)
		else:
			pipeline_frame_elapsed = 0.0
			pipeline_playing = false
			_sync_trails(false)
	if pipeline_playing:
		_sync_trails()

func _clear_attachments() -> void:
	for container in [attachment_below,attachment_above]:
		if not is_instance_valid(container): continue
		for child in container.get_children():
			child.free()

func _ensure_attachment_nodes() -> void:
	if not is_instance_valid(attachment_below):
		attachment_below = Node2D.new()
		attachment_below.name = "PipelineAttachmentsBelow"
		attachment_below.z_index = -1
		add_child(attachment_below)
	if not is_instance_valid(attachment_above):
		attachment_above = Node2D.new()
		attachment_above.name = "PipelineAttachmentsAbove"
		attachment_above.z_index = 1
		add_child(attachment_above)

func _show_attachments(attachments: Array, _frame_transform: Transform2D = Transform2D.IDENTITY) -> void:
	_clear_attachments()
	if attachments.is_empty(): return
	_ensure_attachment_nodes()
	var sorted: Array = attachments.duplicate()
	sorted.sort_custom(func(a, b): return a.layer_order < b.layer_order)
	var owner := pipeline_owner_transform()
	for attachment in sorted:
		var node := Sprite2D.new()
		node.texture = _display_texture(attachment.texture)
		if use_mipmapped_textures: node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		node.centered = attachment.centered
		if attachment.use_affine:
			node.transform = owner*attachment.transform
		else:
			var radians := deg_to_rad(attachment.rotation_degrees)
			var x_axis: Vector2 = Vector2(cos(radians),sin(radians))*attachment.visual_scale.x
			var y_axis: Vector2 = Vector2(-sin(radians),cos(radians))*attachment.visual_scale.y
			var local_transform := Transform2D(x_axis,y_axis,Vector2(attachment.offset.x,attachment.offset.y))
			# Match the native tuner: attachments are children of the frame
			# owner, so their local offset is scaled once by the owner basis.
			node.transform = owner*local_transform
		if attachment.layer_order < 0.0:
			attachment_below.add_child(node)
		else:
			attachment_above.add_child(node)


func set_mipmap_sampling(enabled: bool) -> void:
	use_mipmapped_textures = enabled
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if enabled else CanvasItem.TEXTURE_FILTER_LINEAR
	_refresh_display_textures()
	queue_redraw()


func _refresh_display_textures() -> void:
	var frames: Array = pipeline_frames.get(pose, [])
	if not frames.is_empty():
		var frame = frames[clampi(pipeline_frame_index,0,frames.size()-1)]
		sprite.texture = _display_texture(frame.texture)
		_show_attachments(frame.attachments,frame.transform)
		return
	sprite.texture = _display_texture(poses.get(pose,poses.get("idle")))
	_clear_attachments()


func _display_texture(source: Texture2D) -> Texture2D:
	if source == null or not use_mipmapped_textures: return source
	var key := source.get_instance_id()
	var cached = _mipmapped_textures.get(key)
	if cached is Texture2D and is_instance_valid(cached): return cached
	var image := source.get_image()
	if image == null: return source
	if image.has_mipmaps(): return source
	if image.is_compressed(): image.decompress()
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_mipmapped_textures[key] = texture
	return texture

func _play_frame_audio(frame) -> void:
	if frame.audio.is_empty(): return
	for stream in frame.audio:
		var player := _next_audio_player()
		player.stream = stream
		player.play()

func _next_audio_player() -> AudioStreamPlayer:
	for player in frame_audio_players:
		if not player.playing: return player
	if frame_audio_players.size() < 4:
		var created := AudioStreamPlayer.new()
		created.volume_db = -10.0
		add_child(created)
		frame_audio_players.append(created)
		return created
	var selected := frame_audio_players[frame_audio_cursor%frame_audio_players.size()]
	frame_audio_cursor = (frame_audio_cursor+1)%frame_audio_players.size()
	return selected

func _configure_trails() -> void:
	if is_instance_valid(trail_adapter):
		trail_adapter.queue_free()
	trail_adapter = null
	if pipeline_xsxb.is_empty() and pipeline_attack_trails.is_empty():
		return
	trail_adapter = PipelineTrailAdapterScript.new()
	trail_adapter.name = "PipelineAttackTrails"
	add_child(trail_adapter)
	trail_adapter.call("configure",self,frame_profile_id,pipeline_xsxb,pipeline_attack_trails)
	if not bool(trail_adapter.call("has_renderers")):
		trail_adapter.queue_free()
		trail_adapter = null
		return
	_sync_trails(pipeline_playing)

func _sync_trails(playing: bool = true) -> void:
	if not is_instance_valid(trail_adapter):
		return
	trail_adapter.call("sync",pipeline_owner_transform(),pose,pipeline_pose_elapsed,playing)


func pipeline_owner_transform() -> Transform2D:
	# The generated matrix maps the texture's top-left corner. XSXB trail and
	# attachment data live in owner/group space, whose origin is the sprite
	# centre after the manifest frame anchor has been applied.
	if sprite == null or sprite.texture == null:
		return sprite.transform if sprite != null else Transform2D.IDENTITY
	var half := Vector2(sprite.texture.get_width(),sprite.texture.get_height())*0.5
	return Transform2D(sprite.transform.x,sprite.transform.y,sprite.transform*half)

func trail_frame_duration(animation_name: String, frame_index: int) -> float:
	var runtime_frames := _runtime_animation_frames(animation_name)
	for entry in runtime_frames:
		if int(entry.get("index",-1)) == frame_index:
			return maxf(0.000001,float(entry.get("durationMs",0.0))/1000.0)
	var sequence_index := _visible_sequence_index(animation_name,frame_index)
	var frames: Array = pipeline_frames.get(animation_name, [])
	if frames.is_empty():
		return 1.0/12.0
	return maxf(0.000001,float(frames[clampi(sequence_index,0,frames.size()-1)].duration))

func trail_frame_arrival_time(animation_name: String, frame_index: int, frame_phase: float) -> float:
	var runtime_frames := _runtime_animation_frames(animation_name)
	if not runtime_frames.is_empty():
		var runtime_elapsed := 0.0
		for position in runtime_frames.size():
			var entry: Dictionary = runtime_frames[position]
			var index := int(entry.get("index",position))
			var duration_s := maxf(0.0,float(entry.get("durationMs",0.0))/1000.0)
			if index == frame_index:
				return runtime_elapsed+duration_s*clampf(frame_phase,0.0,1.0)
			runtime_elapsed += duration_s
	var frames: Array = pipeline_frames.get(animation_name, [])
	if frames.is_empty():
		return 0.0
	var index := clampi(_visible_sequence_index(animation_name,frame_index),0,frames.size()-1)
	var elapsed := 0.0
	for i in index:
		elapsed += float(frames[i].duration)
	return elapsed+float(frames[index].duration)*clampf(frame_phase,0.0,1.0)

func trail_animation_elapsed(_animation_name: String) -> float:
	return pipeline_pose_elapsed


func trail_frame_index(_animation_name: String) -> int:
	var frames: Array = pipeline_frames.get(pose, [])
	if frames.is_empty():
		return _current_frame
	var frame = frames[clampi(pipeline_frame_index,0,frames.size()-1)]
	if frame.source_index >= 0:
		return int(frame.source_index)
	return pipeline_frame_index


func pipeline_pose_total_duration() -> float:
	var frames: Array = pipeline_frames.get(pose, [])
	var total := 0.0
	for frame in frames:
		total += float(frame.duration)
	return total


func pipeline_pose_elapsed_time() -> float:
	return pipeline_pose_elapsed


func pipeline_pose_remaining() -> float:
	return maxf(0.0,pipeline_pose_total_duration()-pipeline_pose_elapsed)


func _visible_sequence_index(animation_name: String, source_index: int) -> int:
	var frames: Array = pipeline_frames.get(animation_name, [])
	for index in frames.size():
		if int(frames[index].source_index) == source_index:
			return index
	if source_index >= 0 and source_index < frames.size():
		return source_index
	return clampi(pipeline_frame_index,0,maxi(0,frames.size()-1))


func _runtime_animation_frames(animation_name: String) -> Array:
	if _runtime_animation_frames_cache.has(animation_name):
		return _runtime_animation_frames_cache[animation_name]
	var profile: Dictionary = {}
	var profiles_value = pipeline_xsxb.get("profiles",null)
	if profiles_value is Array:
		for profile_value in profiles_value:
			if not profile_value is Dictionary:
				continue
			if String(profile_value.get("id","")) == frame_profile_id:
				profile = profile_value
				break
			if profile.is_empty():
				profile = profile_value
	elif profiles_value is Dictionary:
		var selected = profiles_value.get(frame_profile_id,null)
		profile = selected if selected is Dictionary else {}
	elif pipeline_xsxb.has("animations"):
		profile = pipeline_xsxb
	var result: Array = []
	for animation_value in profile.get("animations",[]):
		if not animation_value is Dictionary:
			continue
		if String(animation_value.get("id",animation_value.get("name",""))) != animation_name:
			continue
		for frame_value in animation_value.get("frames",[]):
			if frame_value is Dictionary:
				result.append(frame_value)
		break
	_runtime_animation_frames_cache[animation_name] = result
	return result

func _draw() -> void:
	var points := PackedVector2Array()
	var shadow_size := Vector2(32,9)
	var shadow_offset := Vector2(0,2)
	var shadow_opacity := 0.7
	if not pipeline_shadow.is_empty():
		if not bool(pipeline_shadow.get("enabled",true)): return
		shadow_size = pipeline_shadow.get("size",shadow_size)
		shadow_offset = pipeline_shadow.get("offset",shadow_offset)
		shadow_opacity = float(pipeline_shadow.get("opacity",shadow_opacity))
	for i in 40:
		var angle := i*TAU/40.0
		points.append(Vector2(cos(angle)*shadow_size.x+shadow_offset.x,sin(angle)*shadow_size.y+shadow_offset.y))
	draw_colored_polygon(points,Color(0,0,0,shadow_opacity))

func set_combat_stance(value: String) -> void:
	# Initial load / restore / turn sync must never replay the presentation.
	if is_instance_valid(weapon_shift): weapon_shift.cancel()
	weapon_shift = null
	combat_stance = value
	set_pose("idle")

func transition_combat_stance(value: String) -> void:
	if not is_player or value == combat_stance or not is_inside_tree():
		set_combat_stance(value)
		return
	if is_instance_valid(weapon_shift): weapon_shift.cancel()
	set_pose("idle")
	var effect := WeaponShift.new()
	weapon_shift = effect
	add_child(effect)
	effect.start(sprite,func():
		combat_stance = value
		set_pose("idle"))
	await effect.finished
	if weapon_shift == effect: weapon_shift = null
