extends Node
## Run with --headless --verbose and inspect engine teardown as well as checks.
## This preload alone reproduces the original full-project script graph leak.
const CardLibraryScript := preload("res://scripts/card_library.gd")
const Catalog := preload("res://enemy_asset_pipeline/runtime/pipeline_catalog.gd")
const RuntimeProfile := preload("res://enemy_asset_pipeline/runtime/pipeline_runtime_profile.gd")
const TEXTURE := "res://assets/combat_test/03a_gang_henchman/gang_henchman_idle.png"

var checks := 0
var failures := 0


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PIPELINE CLEANUP: " + title)


func _ready() -> void:
	Game.save_enabled = false
	_test_catalog()
	for iteration in 3:
		var released := _create_and_release_profile()
		for index in released.size():
			check(released[index].get_ref() == null, "profile graph released %d/%d" % [iteration, index])
		_test_retained_frame()
	var problems: Array[String] = []
	check(RuntimeProfile.parse({}, "empty", problems) != null, "empty optional pipeline remains valid")
	check(RuntimeProfile.parse({"id": "wrong"}, "expected", problems) == null, "invalid id still rejected")
	check(not problems.is_empty(), "invalid profile reports diagnostics")
	# Deliberately leave the normal catalog cache populated. No exit-time cache
	# clearing: the engine must release the static script graph on its own.
	check(not Catalog.get_profiles().is_empty(), "populated catalog survives until shutdown")
	print("RESOURCE_PIPELINE_CLEANUP_TESTS checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _test_catalog() -> void:
	check(CardLibraryScript != null, "real card-library dependency graph loaded")
	var preview_before := Catalog.preview_path_override
	var published_before := Catalog.published_path_override
	var revision_before := Catalog.revision()
	Catalog.set_published_path(Catalog.PUBLISHED_PATH)
	check(Catalog.revision() == revision_before + 1, "published setter increments revision once")
	check(Catalog.published_path_override == Catalog.PUBLISHED_PATH, "published override getter forwards state")
	Catalog.preview_path_override = ""
	check(Catalog.preview_path_override == "", "preview override property setter remains supported")
	var profiles := Catalog.get_profiles()
	check(not profiles.is_empty(), "published profiles load")
	var bindings := Catalog.get_bindings()
	var original_bindings := bindings.duplicate(true)
	bindings["cleanup_copy"] = "missing"
	check(Catalog.get_bindings() == original_bindings, "binding copy cannot mutate cache")
	var profile_id := String(profiles.keys()[0])
	var original := Catalog.get_profile(profile_id)
	profiles[profile_id]["label"] = "changed copy"
	check(Catalog.get_profile(profile_id) == original, "nested profile copies cannot mutate cache")
	var catalog_copy := Catalog.get_catalog()
	catalog_copy.clear()
	check(not Catalog.get_catalog().is_empty(), "catalog copy cannot erase cache")
	check(not Catalog.get_profile_source(profile_id).is_empty(), "profile source retained")
	for enemy_id in original_bindings:
		check(Catalog.get_bound_profile_id(enemy_id, "missing") == String(original_bindings[enemy_id]), "binding resolves cached profile")
	check(Catalog.get_bound_profile_id("cleanup_missing", "fallback") == "fallback", "unknown binding preserves fallback")
	check(not Catalog.refresh_if_changed(), "unchanged populated catalog avoids reload")
	check(Catalog.revision() == revision_before + 1, "unchanged lookup preserves revision")
	Catalog.published_path_override = published_before
	Catalog.preview_path_override = preview_before
	Catalog.reload()
	check(Catalog.published_path_override == published_before, "published override restores through property")
	check(Catalog.preview_path_override == preview_before, "preview override restores through property")
	check(Catalog.get_profile(profile_id) == original, "normal reload retains published profile")


func _raw_profile() -> Dictionary:
	return {
		"id": "cleanup_probe", "sourceFacing": "right",
		"pipelineFrames": {"idle": [{
			"texture": TEXTURE, "transform": [1, 0, 0, 1, 3, 4], "duration": 0.125,
			"attachments": [{"texture": TEXTURE, "offset": [5, 6], "layer": "below"}],
		}]},
	}


func _create_and_release_profile() -> Array:
	var problems: Array[String] = []
	var profile = RuntimeProfile.parse(_raw_profile(), "cleanup_probe", problems)
	check(profile != null and problems.is_empty(), "frame and attachment profile parses")
	if profile == null:
		return []
	check(profile.get_script() == RuntimeProfile, "parse returns concrete runtime profile")
	check(profile.id == "cleanup_probe" and profile.has_pipeline, "parsed identity and flags retained")
	check(profile.source_facing == 1.0, "source facing retained")
	var frame = profile.frames.idle[0]
	var attachment = frame.attachments[0]
	check(frame.texture != null and attachment.texture != null, "frame and attachment textures loaded")
	check(frame.transform.origin == Vector2(3, 4) and frame.duration == 0.125, "frame timing and transform retained")
	check(attachment.offset == Vector2(5, 6) and attachment.layer_order == -1.0, "attachment transform retained")
	return [weakref(profile), weakref(frame), weakref(attachment)]


func _test_retained_frame() -> void:
	var holder: Array = []
	var refs := _retain_frame_only(holder)
	check(refs[0].get_ref() == null, "caller-held frame does not keep its profile alive")
	check(refs[1].get_ref() != null and refs[2].get_ref() != null, "caller ownership keeps frame and attachment alive")
	holder.clear()
	check(refs[1].get_ref() == null and refs[2].get_ref() == null, "releasing last frame owner releases attachments")


func _retain_frame_only(holder: Array) -> Array:
	var problems: Array[String] = []
	var profile = RuntimeProfile.parse(_raw_profile(), "cleanup_probe", problems)
	var frame = profile.frames.idle[0]
	holder.append(frame)
	return [weakref(profile), weakref(frame), weakref(frame.attachments[0])]
