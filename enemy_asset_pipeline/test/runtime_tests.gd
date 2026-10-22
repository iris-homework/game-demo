extends Node
## Headless integration checks. Fixtures live only under the test user directory.

const PipelineCatalogScript := preload("res://enemy_asset_pipeline/runtime/pipeline_catalog.gd")
const PipelineImageScript := preload("res://enemy_asset_pipeline/runtime/pipeline_image.gd")
const RuntimeProfileScript := preload("res://enemy_asset_pipeline/runtime/pipeline_runtime_profile.gd")
const TrailAdapterScript := preload("res://enemy_asset_pipeline/runtime/pipeline_trail_adapter.gd")
const TrailRendererScript := preload("res://enemy_asset_pipeline/runtime/xsxb_attack_trail_renderer.gd")
const Resolver := preload("res://scripts/combat/enemy_visual_resolver.gd")
const Actor := preload("res://scripts/combat/pose_actor.gd")
const Stage := preload("res://scripts/combat/test_stage.gd")

const TEST_DIR := "user://enemy_asset_pipeline_runtime_tests"
const TEST_RUNTIME := "res://enemy_asset_pipeline/test/runtime"
const RAW_WAV := TEST_RUNTIME+"/raw_probe.wav"
const IDLE_TEXTURE := "res://assets/combat_test/Finn/finn_idle.webp"
const MOVE_TEXTURE := "res://assets/combat_test/Finn/finn_move.webp"
const ATTACHMENT_TEXTURE := "res://assets/combat_test/Finn/finn_block.webp"
const AUDIO_PATH := "res://assets/audio/combat/slash.wav"
const TRAIL_SHADER := "res://enemy_asset_pipeline/runtime/xsxb_attack_trail.gdshader"

var checks := 0
var failures := 0


func check(ok: bool, title: String) -> void:
	checks += 1
	if ok:
		return
	failures += 1
	push_error("PIPELINE RUNTIME: "+title)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	DirAccess.make_dir_recursive_absolute(TEST_RUNTIME)
	PipelineCatalogScript.clear_preview()
	PipelineCatalogScript.clear_published_path()
	_test_merged_preview()
	_test_invalid_preview_fallback()
	_test_standalone_visual_id()
	_test_enemy_bindings()
	_test_catalog_refresh_before_new_battle()
	_test_stage_setup_reads_preview()
	_test_published_preview_isolation()
	_test_noren_override()
	_test_image_and_audio_fallback()
	_test_attachment_transform()
	_test_trail_adapter_and_renderer()
	_test_attack_pose_wait()
	PipelineCatalogScript.clear_preview()
	PipelineCatalogScript.clear_published_path()
	_remove_fixture(RAW_WAV)
	print("PIPELINE_RUNTIME_TESTS checks=%d failures=%d" % [checks,failures])
	get_tree().quit(1 if failures > 0 else 0)


func _frame(texture: String, transform: Array, duration: float, loop: bool, extra: Dictionary = {}) -> Dictionary:
	var value := {
		"texture": texture,
		"transform": transform,
		"duration": duration,
		"loop": loop,
		"audio": [],
	}
	value.merge(extra,true)
	return value


func _visual_profile(id: String, frames: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var poses: Dictionary = {}
	for pose in frames:
		poses[pose] = {"texture":IDLE_TEXTURE,"anchor":[150,237],"scale":0.3,"whiteKey":false}
	if not poses.has("idle"):
		poses.idle = {"texture":IDLE_TEXTURE,"anchor":[150,237],"scale":0.3,"whiteKey":false}
	var profile := {
		"id":id,
		"label":id,
		"kind":"actor",
		"sourceFacing":"left",
		"targetRect":[-65,-145,130,155],
		"poseAliases":{},
		"attackStyleOverride":"",
		"hitEffectTexture":"",
		"poses":poses,
		"pipelineFrames":frames,
		"pipelineShadow":{"enabled":true,"size":[32,9],"offset":[0,2],"opacity":0.7},
		"pipelineMotion":{"speed":2300,"reach":105,"windup":0.045,"recovery":0.12},
		"pipelineEffects":{"scale":1,"offset":[0,0]},
	}
	profile.merge(extra,true)
	return profile


func _write_preview(name: String, profiles: Dictionary, bindings: Dictionary = {}, schema_version: int = 1) -> String:
	var path := _write_catalog(name,profiles,bindings,schema_version)
	PipelineCatalogScript.set_preview_path(path)
	return path


func _write_catalog(name: String, profiles: Dictionary, bindings: Dictionary = {}, schema_version: int = 1) -> String:
	var path := TEST_DIR.path_join(name+".json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"fixture can be written: "+path)
	if file == null:
		return path
	file.store_string(JSON.stringify({"schemaVersion":schema_version,"profiles":profiles,"bindings":bindings},"\t"))
	file.close()
	return path


func _remove_fixture(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _write_raw_wav(path: String) -> bool:
	var sample_data := PackedByteArray()
	for _index in 16:
		sample_data.append(0)
	var bytes := PackedByteArray()
	bytes.append_array("RIFF".to_ascii_buffer())
	bytes.append_array(_u32le(36+sample_data.size()))
	bytes.append_array("WAVE".to_ascii_buffer())
	bytes.append_array("fmt ".to_ascii_buffer())
	bytes.append_array(_u32le(16))
	bytes.append_array(_u16le(1))
	bytes.append_array(_u16le(1))
	bytes.append_array(_u32le(22050))
	bytes.append_array(_u32le(44100))
	bytes.append_array(_u16le(2))
	bytes.append_array(_u16le(16))
	bytes.append_array("data".to_ascii_buffer())
	bytes.append_array(_u32le(sample_data.size()))
	bytes.append_array(sample_data)
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


func _u16le(value: int) -> PackedByteArray:
	return PackedByteArray([value & 0xff, (value >> 8) & 0xff])


func _u32le(value: int) -> PackedByteArray:
	return PackedByteArray([value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >> 24) & 0xff])


func _test_merged_preview() -> void:
	var attachment := {
		"path": ATTACHMENT_TEXTURE,
		"transform": {"offset": [8,-10], "scale": 0.2, "rotation": 15},
		"layerOrder": -1,
	}
	var idle_frames := [
		_frame(IDLE_TEXTURE,[0.5,0.0,0.0,0.5,10.0,20.0],0.05,false,{"audio":[AUDIO_PATH],"attachments":[attachment],"xsxb":{"index":0,"groupId":"idle"}}),
		_frame(MOVE_TEXTURE,[0.6,0.0,0.0,0.6,12.0,22.0],0.05,true,{"xsxb":{"index":1}}),
	]
	var pose_loop_frame := _frame(MOVE_TEXTURE,[0.6,0.0,0.0,0.6,12.0,22.0],0.05,false)
	pose_loop_frame.erase("loop")
	var single_frames := [
		_frame(IDLE_TEXTURE,[0.4,0.0,0.0,0.4,4.0,6.0],0.05,false),
		_frame(MOVE_TEXTURE,[0.4,0.0,0.0,0.4,5.0,7.0],0.05,false),
	]
	var profile := _visual_profile("finn",{
		"idle":idle_frames,
		"block":{"frames":[pose_loop_frame],"loop":true},
		"damaged":single_frames,
	},{
		"pipelineShadow":{"enabled":true,"size":[40,12],"offset":[2,3],"opacity":0.45},
		"pipelineMotion":{"speed":1800,"reach":125,"windup":0.07,"recovery":0.18},
		"pipelineEffects":{"scale":1.25,"offset":[4,-3],"hitStop":0.06,"shake":{"strength":11,"duration":0.3}},
		"pipelineXsxb":{"profileId":"finn","profiles":[{"id":"finn","animations":[{"id":"idle","attackTrails":[{"enabled":true,"sticks":[]}]}]}]},
	})
	var path := _write_preview("merged",{"finn":profile})
	var resolver := Resolver.new()
	var visual := resolver.resolve({"id":"ike","combatVisualId":"finn"},{"ike":{"combatVisualId":"finn"}})
	check(visual.id == "finn" and visual.pipeline_active,"formal enemy receives preview pipeline")
	check(visual.pipeline_source == "preview","resolved profile reports preview source")
	check(visual.pipeline_frames.has("idle") and visual.pipeline_frames.idle.size() == 2,"multi-frame sequence validates")
	check(not visual.pipeline_xsxb.is_empty(),"raw XSXB profile is preserved")
	check(visual.pipeline_frames.idle[0].source_index == 0 and visual.pipeline_frames.idle[1].source_index == 1,"frame xsxb index is retained")
	var actor := Actor.new()
	add_child(actor)
	actor.setup_enemy(visual,Vector2(100,300),-1.0)
	check(actor.sprite.texture == load(IDLE_TEXTURE),"first pipeline frame supplies texture")
	check(actor.sprite.transform.origin.is_equal_approx(Vector2(10,20)),"transform translation is not recalibrated from poses.scale")
	check(actor.attachment_below != null and actor.attachment_below.get_child_count() == 1,"negative layer attachment renders below")
	check(actor.frame_audio_players.size() >= 1,"frame audio creates a player")
	var owner := actor.pipeline_owner_transform()
	var expected_center: Vector2 = actor.sprite.transform*(Vector2(actor.sprite.texture.get_width(),actor.sprite.texture.get_height())*0.5)
	check(owner.origin.is_equal_approx(expected_center),"trail owner origin is the anchored sprite centre")
	var local := Transform2D(Vector2(cos(deg_to_rad(15)),sin(deg_to_rad(15)))*0.2,Vector2(-sin(deg_to_rad(15)),cos(deg_to_rad(15)))*0.2,Vector2(8,-10))
	var expected_attachment := owner*local
	check(actor.attachment_below.get_child(0).transform.origin.is_equal_approx(expected_attachment.origin),"attachment inherits owner transform and local offset")
	actor.face_toward(Vector2(220,300))
	check(actor.sprite.transform.origin.is_equal_approx(Vector2(-10,20)),"facing mirrors final transform x translation")
	check(is_equal_approx(actor.sprite.transform.x.x,-0.5),"facing mirrors final transform x basis")
	actor.set_pose("idle")
	actor._process(0.051)
	check(actor.pipeline_frame_index == 1,"duration advances to the next frame")
	actor.face_toward(Vector2(0,300))
	check(actor.pipeline_frame_index == 1,"face_toward does not restart the current sequence")
	check(actor.sprite.texture == load(MOVE_TEXTURE),"face_toward keeps the active frame texture")
	actor._process(0.051)
	check(actor.pipeline_frame_index == 0 and actor.pipeline_playing,"last frame loop wraps to frame zero")
	actor.set_pose("block")
	actor._process(0.051)
	check(actor.pipeline_frame_index == 0 and actor.pipeline_playing,"pose-level loop is honored")
	actor.set_pose("damaged")
	actor._process(0.051)
	actor._process(0.051)
	check(actor.pipeline_frame_index == 1 and not actor.pipeline_playing,"one-shot sequence stops on the last frame")
	check(actor.pipeline_shadow["size"][0] == 40.0 and actor.pipeline_shadow.opacity == 0.45,"shadow config reaches actor")
	var stage := Stage.new()
	add_child(stage)
	check(is_equal_approx(stage._motion_value(actor,"speed",2300.0),1800.0),"motion speed reaches stage")
	check(is_equal_approx(stage._motion_value(actor,"reach",105.0),125.0),"motion reach reaches stage")
	check(is_equal_approx(stage._hit_stop(actor,0.1),0.06),"hit stop reaches stage")
	check(is_equal_approx(stage._effect_scale(actor),1.25),"effect scale reaches stage")
	check(stage._effect_offset(actor).is_equal_approx(Vector2(4,-3)),"effect offset reaches stage")
	actor.free()
	_dispose_stage(stage)
	_remove_fixture(path)
	PipelineCatalogScript.clear_preview()


func _test_invalid_preview_fallback() -> void:
	var invalid_frame := _frame(IDLE_TEXTURE,[0.5,0.0],0.05,false)
	var profile := _visual_profile("finn",{"idle":[invalid_frame]})
	var path := _write_preview("invalid",{"finn":profile})
	var resolver := Resolver.new()
	var visual := resolver.resolve({"id":"ike","combatVisualId":"finn"},{"ike":{"combatVisualId":"finn"}})
	check(visual.id == "finn" and not visual.pipeline_active,"invalid pipeline keeps the original visual")
	check(not visual.diagnostics.is_empty() and "pipeline overlay rejected" in "; ".join(visual.diagnostics),"invalid pipeline leaves diagnostics")
	_remove_fixture(path)
	PipelineCatalogScript.clear_preview()


func _test_standalone_visual_id() -> void:
	var profile := _visual_profile("runtime_only_visual",{"idle":[_frame(IDLE_TEXTURE,[1,0,0,1,0,0],0.1,false)]})
	var path := _write_preview("standalone",{"runtime_only_visual":profile})
	var resolver := Resolver.new()
	var visual := resolver.resolve({"id":"fixture","combatVisualId":"runtime_only_visual"},{})
	check(visual.id == "runtime_only_visual" and visual.pipeline_active,"visual.id resolves without a legacy catalog entry")
	check(PipelineCatalogScript.load_profiles().has("runtime_only_visual"),"load_profiles lists new draft ids")
	_remove_fixture(path)
	PipelineCatalogScript.clear_preview()


func _test_enemy_bindings() -> void:
	var profile_a := _visual_profile("bound_a",{"idle":[_frame(IDLE_TEXTURE,[1,0,0,1,0,0],0.1,true)]})
	var profile_b := _visual_profile("bound_b",{"idle":[_frame(MOVE_TEXTURE,[1,0,0,1,0,0],0.1,true)]})
	var visual_only := _visual_profile("visual_only",{"idle":[_frame(ATTACHMENT_TEXTURE,[1,0,0,1,0,0],0.1,true)]})
	var published_path := _write_catalog("bindings_published",{"bound_a":profile_a},{"ike":"bound_a"})
	var published_bytes := FileAccess.get_file_as_bytes(published_path)
	PipelineCatalogScript.set_published_path(published_path)
	var preview_path := _write_catalog("bindings_preview",{"bound_b":profile_b,"visual_only":visual_only},{"ike":"bound_b","preview_visual_only":"bound_a"})
	PipelineCatalogScript.set_preview_path(preview_path)
	var enemies := {"ike":{"combatVisualId":"finn"},"robot":{"combatVisualId":"finn"}}
	var resolver := Resolver.new()
	check(PipelineCatalogScript.get_bound_profile_id("ike","finn") == "bound_b","preview binding overrides published binding")
	var bound := resolver.resolve({"id":"ike","combatVisualId":"finn"},enemies)
	check(bound.id == "bound_b","binding wins over the original combatVisualId")
	var unbound := resolver.resolve({"id":"robot","combatVisualId":"bound_a"},enemies)
	check(unbound.id == "bound_a","unbound enemy keeps its combatVisualId")
	var preview_visual := resolver.resolve({"id":"preview_visual_only","combatVisualId":"visual_only"},enemies)
	check(preview_visual.id == "visual_only","single visual preview is not swallowed by an enemy-id binding")
	PipelineCatalogScript.clear_preview()
	var restored := resolver.resolve({"id":"ike","combatVisualId":"finn"},enemies)
	check(PipelineCatalogScript.get_bound_profile_id("ike","finn") == "bound_a","removing preview restores the published binding")
	check(restored.id == "bound_a","restored binding is used by the resolver")
	var none := resolver.resolve({"id":"robot","combatVisualId":"finn"},enemies)
	check(none.id == "finn","missing binding keeps the original combatVisualId")
	PipelineCatalogScript.set_published_path(published_path)
	check(FileAccess.get_file_as_bytes(published_path) == published_bytes,"catalog reads never rewrite the published fixture")
	var dangling_path := _write_catalog("bindings_dangling",{"bound_a":profile_a},{"ike":"missing_profile"})
	PipelineCatalogScript.set_published_path(dangling_path)
	check(PipelineCatalogScript.get_bound_profile_id("ike","finn") == "finn","dangling binding falls back to the visual id")
	check("has no profile" in "; ".join(PipelineCatalogScript.get_diagnostics()),"dangling binding is diagnosed")
	PipelineCatalogScript.clear_preview()
	PipelineCatalogScript.clear_published_path()
	_remove_fixture(published_path)
	_remove_fixture(preview_path)
	_remove_fixture(dangling_path)


func _test_published_preview_isolation() -> void:
	var profile_a := _visual_profile("iso_published",{"idle":[_frame(IDLE_TEXTURE,[1,0,0,1,0,0],0.1,true)]})
	var profile_b := _visual_profile("iso_preview",{"idle":[_frame(MOVE_TEXTURE,[1,0,0,1,0,0],0.1,true)]})
	var published_path := _write_catalog("isolation_published",{"iso_published":profile_a})
	PipelineCatalogScript.set_published_path(published_path)
	var published_before := JSON.stringify(PipelineCatalogScript.get_profiles())
	var bytes_before := FileAccess.get_file_as_bytes(published_path)
	var preview_path := _write_preview("isolation",{"iso_preview":profile_b})
	check(PipelineCatalogScript.get_profile_source("iso_preview") == "preview","preview adds a distinct profile")
	check(PipelineCatalogScript.load_profiles().has("iso_preview"),"load_profiles refreshes the active catalog")
	var before_refresh := PipelineCatalogScript.revision()
	PipelineCatalogScript.refresh()
	check(PipelineCatalogScript.revision() > before_refresh,"refresh invalidates the cached read")
	PipelineCatalogScript.clear_preview()
	check(JSON.stringify(PipelineCatalogScript.get_profiles()) == published_before,"published catalog returns unchanged after preview")
	check(FileAccess.get_file_as_bytes(published_path) == bytes_before,"loader never rewrites production JSON")
	PipelineCatalogScript.clear_published_path()
	_remove_fixture(published_path)
	_remove_fixture(preview_path)


func _test_stage_setup_reads_preview() -> void:
	var profile := _visual_profile("noren",{
		"idle":[_frame(MOVE_TEXTURE,[0.4,0.0,0.0,0.4,6.0,8.0],0.2,true)],
		"gun_idle":[_frame(MOVE_TEXTURE,[0.3,0.0,0.0,0.3,4.0,7.0],0.2,true)],
	})
	var path := _write_preview("stage_refresh",{"noren":profile})
	var stage := Stage.new()
	add_child(stage)
	var visuals: Array[EnemyVisualResolver.Visual] = []
	stage.setup(500.0,visuals)
	check(stage.player != null and stage.player.pipeline_active,"stage setup refreshes before creating the player")
	check(stage.player.sprite.texture == load(MOVE_TEXTURE),"stage setup keeps the preview override while refreshing")
	_dispose_stage(stage)
	_remove_fixture(path)
	PipelineCatalogScript.clear_preview()


func _test_catalog_refresh_before_new_battle() -> void:
	var profile_a := _visual_profile("cache_a",{"idle":[_frame(IDLE_TEXTURE,[1,0,0,1,0,0],0.1,true)]})
	var published_path := _write_catalog("refresh_published",{"cache_a":profile_a},{"ike":"cache_a"})
	PipelineCatalogScript.set_published_path(published_path)
	PipelineCatalogScript.clear_preview()
	var enemies := {"ike":{"combatVisualId":"finn"}}
	var first := Resolver.new().resolve({"id":"ike","combatVisualId":"finn"},enemies)
	check(first.id == "cache_a","first battle resolves the current catalog")
	var preview_path := _write_preview("refresh_preview",{"cache_a":profile_a})
	PipelineCatalogScript.refresh()
	check(PipelineCatalogScript.preview_path_override == preview_path,"refresh keeps the preview override path")
	check(PipelineCatalogScript.get_profile_source("cache_a") == "preview","refresh still reads the preview catalog")
	PipelineCatalogScript.clear_preview()
	var profile_b := _visual_profile("cache_bb",{"idle":[_frame(MOVE_TEXTURE,[1,0,0,1,0,0],0.1,true)]})
	_write_catalog("refresh_published",{"cache_bb":profile_b},{"ike":"cache_bb"})
	var second := Resolver.new().resolve({"id":"ike","combatVisualId":"finn"},enemies)
	check(second.id == "cache_bb","new battle resolution refreshes a changed catalog")
	check(first.id == "cache_a","existing parsed visual is not mutated by refresh")
	PipelineCatalogScript.clear_published_path()
	_remove_fixture(published_path)
	_remove_fixture(preview_path)


func _test_noren_override() -> void:
	var profile := _visual_profile("noren",{
		"idle":[_frame(IDLE_TEXTURE,[0.4,0.0,0.0,0.4,6.0,8.0],0.2,true)],
		"gun_idle":[_frame(MOVE_TEXTURE,[0.3,0.0,0.0,0.3,4.0,7.0],0.2,true)],
	})
	var path := _write_preview("noren",{"noren":profile})
	var actor := Actor.new()
	add_child(actor)
	actor.setup_player(Vector2(100,300),1.0)
	check(actor.pipeline_active and actor.sprite.texture == load(IDLE_TEXTURE),"noren catalog profile overrides idle after setup")
	actor.set_combat_stance("ranged")
	check(actor.pose == "gun_idle" and actor.sprite.texture == load(MOVE_TEXTURE),"noren stance mapping still selects gun_idle")
	actor.set_pose("block")
	check(actor.pose == "gun_block","noren stance mapping remains active without a pipeline frame")
	actor.free()
	_remove_fixture(path)
	PipelineCatalogScript.clear_preview()


func _test_image_and_audio_fallback() -> void:
	var png_path := "res://assets/combat_test/noren/noren_idle.png"
	var fallback := PipelineImageScript.load_texture(png_path,true)
	check(fallback is Texture2D and fallback.get_width() > 0,"Image.load fallback reads a project PNG")
	check(PipelineImageScript.load_texture("user://outside.png") == null,"image loader rejects non-project paths")
	check(PipelineImageScript.load_texture("res://../outside.png") == null,"image loader rejects parent traversal")
	check(PipelineImageScript.load_audio("user://outside.wav") == null,"audio loader rejects non-project paths")
	check(PipelineImageScript.load_audio("res://../outside.wav") == null,"audio loader rejects parent traversal")
	check(_write_raw_wav(RAW_WAV),"raw WAV fixture can be written")
	var raw_stream := PipelineImageScript.load_audio(RAW_WAV)
	check(raw_stream is AudioStream,"raw res:// WAV loads without an import cache")
	check(FileAccess.file_exists(AUDIO_PATH) and PipelineImageScript.load_audio(AUDIO_PATH) is AudioStream,"imported project WAV still loads")
	check(PipelineImageScript.audio_format("res://audio/probe.ogg") == "ogg","OGG extension selects the native loader")
	check(PipelineImageScript.audio_format("res://audio/probe.mp3") == "mp3","MP3 extension selects the native loader")
	check(PipelineImageScript.audio_format("res://audio/probe.txt").is_empty(),"unsupported audio extensions are rejected")
	var missing_profile := _visual_profile("missing_audio",{
		"idle":[_frame(IDLE_TEXTURE,[1,0,0,1,0,0],0.1,true,{"audio":[RAW_WAV,TEST_RUNTIME+"/missing.wav"]})],
	})
	var problems: Array[String] = []
	var runtime = RuntimeProfileScript.parse(missing_profile,"missing_audio",problems)
	check(runtime != null and runtime.frames.idle[0].audio.size() == 1 and runtime.frames.idle[0].audio_paths.has(RAW_WAV),"missing optional audio is skipped; raw WAV is retained")
	check(ResourceLoader.exists(TRAIL_SHADER) and load(TRAIL_SHADER) is Shader,"runtime shader is importable outside vendor/.gdignore")


func _test_attachment_transform() -> void:
	var attachments := [
		{"path":ATTACHMENT_TEXTURE,"offset":[-4,6],"scale":0.3,"rotation":-30,"layerOrder":-1},
		{"path":IDLE_TEXTURE,"offset":[2,3],"scale":0.5,"rotation":0,"layerOrder":1},
		{"path":MOVE_TEXTURE,"offset":[8,-10],"scale":0.2,"rotation":15,"layerOrder":2},
	]
	var profile := _visual_profile("attachment_actor",{
		"idle":[_frame(IDLE_TEXTURE,[0.5,0,0,0.5,10,20],0.1,true,{"attachments":attachments})],
	})
	var path := _write_preview("attachments",{"attachment_actor":profile})
	var resolver := Resolver.new()
	var visual := resolver.resolve({"id":"preview_attachment","combatVisualId":"attachment_actor"},{})
	var actor := Actor.new()
	add_child(actor)
	actor.setup_enemy(visual,Vector2(100,300),-1.0)
	check(actor.attachment_below != null and actor.attachment_below.get_child_count() == 1,"layerOrder below selects the lower container")
	check(actor.attachment_above != null and actor.attachment_above.get_child_count() == 2,"positive layerOrder renders above the sprite")
	check(actor.attachment_above.get_child(0).texture == load(IDLE_TEXTURE) and actor.attachment_above.get_child(1).texture == load(MOVE_TEXTURE),"attachments sort by layerOrder")
	var owner := actor.pipeline_owner_transform()
	var expected_center: Vector2 = actor.sprite.transform*(Vector2(actor.sprite.texture.get_width(),actor.sprite.texture.get_height())*0.5)
	check(owner.origin.is_equal_approx(expected_center),"attachment owner uses the sprite centre")
	var radians := deg_to_rad(-30.0)
	var local := Transform2D(Vector2(cos(radians),sin(radians))*0.3,Vector2(-sin(radians),cos(radians))*0.3,Vector2(-4,6))
	var expected := owner*local
	var below: Node2D = actor.attachment_below.get_child(0) as Node2D
	check(below.transform.origin.is_equal_approx(expected.origin),"below attachment offset is scaled once by the owner")
	check(below.transform.x.is_equal_approx(expected.x) and below.transform.y.is_equal_approx(expected.y),"below attachment inherits owner rotation and scale")
	var before_x: float = below.to_global(Vector2.ZERO).x
	actor.face_toward(Vector2(actor.position.x+100,actor.position.y))
	var after_child: Node2D = actor.attachment_below.get_child(0) as Node2D
	var after_x: float = after_child.to_global(Vector2.ZERO).x
	check(absf((before_x-actor.position.x)+(after_x-actor.position.x)) < 0.05,"attachments mirror around the owner")
	actor.free()
	_remove_fixture(path)
	PipelineCatalogScript.clear_preview()


func _trail_profile() -> Dictionary:
	var sticks := [
		_stick(0,0.1,"behind",Vector2(-200,-80),Vector2(-190,-40)),
		_stick(0,0.3,"behind",Vector2(-120,-120),Vector2(-110,-50)),
		_stick(0,0.5,"front",Vector2(-40,-140),Vector2(-30,-60)),
		_stick(2,0.3,"front",Vector2(40,-150),Vector2(55,-60)),
		_stick(2,0.6,"front",Vector2(120,-130),Vector2(140,-55)),
		_stick(2,0.9,"front",Vector2(210,-100),Vector2(235,-45)),
	]
	var segment := {
		"id":"arc",
		"enabled":true,
		"generated":true,
		"layer":"behind",
		"texture":{"path":ATTACHMENT_TEXTURE},
		"sticks":sticks,
		"frameSlices":[
			{"frame":0,"enabled":true,"tailProgress":0.15,"headProgress":0.45},
			{"frame":2,"enabled":true,"tailProgress":0.0,"headProgress":1.0},
		],
		"tailSamples":5,
		"stableSeed":73129,
	}
	var xsxb := {
		"schemaVersion":1,
		"projectId":"runtime-tests",
		"id":"trail_actor",
		"animations":[
			{"id":"idle","fps":10,"frames":[{"index":0,"durationMs":100,"disabled":false}],"attackTrails":[]},
			{"id":"slash","fps":10,"frames":[
				{"index":0,"durationMs":50,"disabled":false},
				{"index":1,"durationMs":0,"disabled":true},
				{"index":2,"durationMs":50,"disabled":false},
			],"attackTrails":[segment]},
		],
	}
	return _visual_profile("trail_actor",{
		"idle":[_frame(IDLE_TEXTURE,[0.5,0,0,0.5,10,20],0.1,true,{"xsxb":{"index":0}})],
		"slash":[
			_frame(IDLE_TEXTURE,[0.5,0,0,0.5,10,20],0.05,false,{"xsxb":{"index":0}}),
			_frame(MOVE_TEXTURE,[0.6,0,0,0.6,12,22],0.05,false,{"xsxb":{"index":2}}),
		],
	},{"pipelineXsxb":xsxb})


func _stick(frame: int, phase: float, layer_value: String, top: Vector2, bottom: Vector2) -> Dictionary:
	return {
		"frame":frame,
		"framePhase":phase,
		"headFrame":true,
		"top":{"x":top.x,"y":top.y},
		"bottom":{"x":bottom.x,"y":bottom.y},
		"layer":layer_value,
	}


func _test_trail_adapter_and_renderer() -> void:
	var profile := _trail_profile()
	var path := _write_preview("trails",{"trail_actor":profile})
	var resolver := Resolver.new()
	var visual := resolver.resolve({"id":"preview_trail_actor","combatVisualId":"trail_actor"},{})
	check(visual.id == "trail_actor" and visual.pipeline_active,"trail fixture resolves")
	check(visual.pipeline_frames.slash[1].source_index == 2,"disabled manifest frame index is retained")
	var derived := TrailAdapterScript.derive_bindings("trail_actor",visual.pipeline_xsxb,visual.pipeline_attack_trails)
	check(derived.has("trail_actor/slash") and derived["trail_actor/slash"].size() == 1,"single-profile runtime data derives attack trails")
	var wrapped := {"profiles":[visual.pipeline_xsxb]}
	check(TrailAdapterScript.derive_bindings("trail_actor",wrapped,{}).has("trail_actor/slash"),"wrapped single-profile runtime data also derives attack trails")
	var actor := Actor.new()
	add_child(actor)
	actor.setup_enemy(visual,Vector2(300,400),-1.0)
	check(actor.trail_adapter != null and actor.trail_adapter.has_renderers(),"actor creates behind/front renderers")
	actor.set_pose("slash")
	check(actor.trail_frame_index("slash") == 0,"first frame maps to manifest index zero")
	check(is_equal_approx(actor.trail_frame_arrival_time("slash",2,0.5),0.075),"trail timing uses runtime durations across disabled indices")
	check(is_equal_approx(actor.trail_frame_duration("slash",2),0.05),"trail duration reads the runtime frame duration")
	actor._process(0.012)
	check(actor.trail_frame_index("slash") == 0,"first frame remains active before its duration")
	var behind: Node2D = actor.trail_adapter.behind
	var front: Node2D = actor.trail_adapter.front
	check(behind.z_index < actor.z_index and front.z_index > actor.z_index,"trail layers straddle the actor sprite")
	check(_index_count(behind) > 0 and _index_count(front) > 0,"behind and front layer triangles are both built")
	var bounds_before := _mesh_bounds(behind)
	check(bounds_before.size.x > 0.0,"trail mesh has a visible per-frame extent")
	var vertices := _mesh_vertices(behind)
	check(not vertices.is_empty(),"behind mesh exposes sample vertices")
	var sample: Vector2 = vertices[vertices.size()-1]
	var sign_before := signf(behind.transform.x.x)
	var global_before: Vector2 = behind.to_global(sample)
	actor.face_toward(Vector2(actor.position.x+100,actor.position.y))
	var global_after: Vector2 = behind.to_global(sample)
	check(signf(behind.transform.x.x) != sign_before,"facing mirrors the trail transform basis")
	check(absf((global_before.x-actor.position.x)+(global_after.x-actor.position.x)) < 0.05,"facing mirrors trail sample positions around the actor")
	actor.face_toward(Vector2(actor.position.x-100,actor.position.y))
	actor.set_pose("slash")
	actor._process(0.012)
	var early_bounds := _mesh_bounds(behind)
	actor._process(0.043)
	check(actor.trail_frame_index("slash") == 2,"second visible frame maps to manifest index two")
	var late_bounds := _mesh_bounds(behind)
	check(late_bounds.size.x > early_bounds.size.x+1.0,"frame slices advance the trail head per frame")
	actor._process(0.06)
	check(not actor.pipeline_playing,"one-shot trail playback ends")
	check(_all_meshes_hidden(actor),"ended playback hides and clears trail meshes")
	actor.set_pose("slash")
	actor._process(0.012)
	check(_visible_mesh_count(actor) > 0,"re-entering an attack rebuilds trail meshes")
	actor.free()
	_remove_fixture(path)
	PipelineCatalogScript.clear_preview()


func _mesh_vertices(renderer: Node2D) -> PackedVector2Array:
	var states: Dictionary = renderer.renderers
	for state_value in states.values():
		var state: Dictionary = state_value
		var mesh := state.get("mesh") as ArrayMesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		if vertices is PackedVector2Array and not vertices.is_empty():
			return vertices
	return PackedVector2Array()


func _index_count(renderer: Node2D) -> int:
	var states: Dictionary = renderer.renderers
	var total := 0
	for state_value in states.values():
		var state: Dictionary = state_value
		var mesh := state.get("mesh") as ArrayMesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array:
			total += indices.size()
	return total


func _mesh_bounds(renderer: Node2D) -> Rect2:
	var vertices := _mesh_vertices(renderer)
	if vertices.is_empty():
		return Rect2()
	var minimum := vertices[0]
	var maximum := vertices[0]
	for point in vertices:
		minimum.x = minf(minimum.x,point.x)
		minimum.y = minf(minimum.y,point.y)
		maximum.x = maxf(maximum.x,point.x)
		maximum.y = maxf(maximum.y,point.y)
	return Rect2(minimum,maximum-minimum)


func _all_meshes_hidden(actor: Node) -> bool:
	for renderer_value in [actor.trail_adapter.behind,actor.trail_adapter.front]:
		if not is_instance_valid(renderer_value):
			continue
		for state_value in renderer_value.renderers.values():
			var node := state_value.get("node") as MeshInstance2D
			var mesh := state_value.get("mesh") as ArrayMesh
			if node != null and node.visible:
				return false
			if mesh != null and mesh.get_surface_count() > 0:
				return false
	return true


func _visible_mesh_count(actor: Node) -> int:
	var count := 0
	for renderer_value in [actor.trail_adapter.behind,actor.trail_adapter.front]:
		if not is_instance_valid(renderer_value):
			continue
		for state_value in renderer_value.renderers.values():
			var node := state_value.get("node") as MeshInstance2D
			var mesh := state_value.get("mesh") as ArrayMesh
			if node != null and node.visible and mesh != null and mesh.get_surface_count() > 0:
				count += 1
	return count


func _test_attack_pose_wait() -> void:
	var profile := _visual_profile("wait_actor",{
		"idle":[_frame(IDLE_TEXTURE,[1,0,0,1,0,0],0.1,true)],
		"slash":[
			_frame(IDLE_TEXTURE,[1,0,0,1,0,0],0.02,false),
			_frame(MOVE_TEXTURE,[1,0,0,1,0,0],0.02,false),
		],
	})
	var path := _write_preview("wait",{"wait_actor":profile})
	var resolver := Resolver.new()
	var visual := resolver.resolve({"id":"preview_wait","combatVisualId":"wait_actor"},{})
	var actor := Actor.new()
	add_child(actor)
	actor.setup_enemy(visual,Vector2(100,300),-1.0)
	var stage := Stage.new()
	add_child(stage)
	actor.set_pose("slash")
	check(is_equal_approx(actor.pipeline_pose_total_duration(),0.04),"attack sequence reports its total duration")
	await stage._await_pipeline_pose(actor)
	check(actor.pipeline_pose_elapsed_time() >= 0.035,"attack presentation waits for the full pipeline sequence")
	actor.free()
	_dispose_stage(stage)
	_remove_fixture(path)
	PipelineCatalogScript.clear_preview()


func _dispose_stage(stage: Node) -> void:
	for key in ["world","actors_root","sound","combat_audio"]:
		var node = stage.get(key)
		if is_instance_valid(node) and node is Node and node.get_parent() == null:
			node.free()
	stage.free()
