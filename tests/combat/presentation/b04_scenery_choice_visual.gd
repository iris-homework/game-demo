extends Node
## Former scenery-picker regression now verifies fixed week-one battle backgrounds.
## Headless scene-state checks only; no screenshot or physical-input acceptance.
const FORMAL_BATTLES := {"robot":"B02", "gang":"B04", "fish":"B11", "pruning_hound":"B13", "powerline_repairman":"B14", "beacon_jellyfish":"B15", "dancer_duet":"B16"}
var output := ""
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("FIXED TRAINING SCENERY: " + message)

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("Require absolute QA_OUT_DIR and isolated user directory containing QA")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.state.currentHp = 43
	Game.state.credits = 123
	var adventure: Dictionary = Game.state.duplicate(true)
	var battle_definitions: Dictionary = Game.battles.duplicate(true)
	var enemy_definitions: Dictionary = Game.enemy_catalog.duplicate(true)
	Game.page = "menu"
	Engine.time_scale = 8.0
	for id in FORMAL_BATTLES:
		# A developer preview may leave an override; public training must reset it.
		Game.training_scenery_place_id = "bar"
		Game.start_enemy_training(id)
		check(Game.training_mode and Game.page == "battle", "Week-one practice starts: " + id)
		if not Game.training_mode: continue
		var view: Control = preload("res://scenes/battle.tscn").instantiate()
		add_child(view)
		var deadline := Time.get_ticks_msec() + 20000
		while (not view.initialized or Game.battle_busy) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(view.initialized and not Game.battle_busy, "Actual battle finishes initial draw: " + id)
		var formal: Dictionary = battle_definitions[FORMAL_BATTLES[id]]
		check(view.battle.placeId == formal.placeId and Game.state.currentPlaceId == formal.placeId and Game.training_scenery_place_id.is_empty(), "Actual view uses fixed formal place: " + id)
		var place_asset: String = Game.place_data(formal.placeId).backgroundAssetId
		var stage_asset: String = Game.assets.get(place_asset, {}).get("battleAssetId", "")
		var stage_definition: Dictionary = Game.assets.get(stage_asset, {})
		var expected_texture: Texture2D = Game.texture(stage_asset) if stage_definition.get("battleEnabled", true) else null
		if expected_texture != null:
			check(is_instance_valid(view.stage.scenery) and view.stage.scenery.texture == expected_texture, "Stage uses formal battle background texture: " + id)
		else:
			check(not is_instance_valid(view.stage.scenery), "Unillustrated formal place uses standard floor fallback: " + id)
		var offset: Array = stage_definition.get("actorOffset", Game.assets.get(place_asset, {}).get("battleActorOffset", [0, 0]))
		check(view.actor_offset == view.ACTOR_OFFSET + Vector2(offset[0], offset[1]), "Formal background retains authored actor placement: " + id)
		check(view.stage.enemies.size() == formal.enemyIds.size(), "Actual stage has whole formal formation: " + id)
		for index in formal.enemyIds.size():
			var definition: Dictionary = enemy_definitions[formal.enemyIds[index]]
			var visual = Game.enemy_combat_visual(definition)
			check(view.stage.enemies[index].kind == visual.id and view.model.enemies[index].id == definition.id, "Stage resolves formal actor identity: " + id + " slot " + str(index))
		await preload("res://scripts/combat/audio_cleanup.gd").release(view, get_tree())
		view.queue_free()
		await get_tree().process_frame
		Game.menu()
		check(Game.state == adventure and not Game.training_mode and Game.training_scenery_place_id.is_empty(), "Exit restores adventure and clears preview override: " + id)
		check(Game.battles == battle_definitions and Game.enemy_catalog == enemy_definitions, "Formal definitions remain unchanged: " + id)
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "No adventure save was written")
	Engine.time_scale = 1.0
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures.size(), "messages":failures, "headless":true, "physicalInput":false}, "\t"))
	print("FIXED_TRAINING_SCENERY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
