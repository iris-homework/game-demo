extends Node
## Bad authored data must never reach an actor.
const Resolver = preload("res://scripts/combat/enemy_visual_resolver.gd")
const Actor = preload("res://scripts/combat/pose_actor.gd")
const Stage = preload("res://scripts/combat/test_stage.gd")
const Pipeline = preload("res://enemy_asset_pipeline/runtime/pipeline_catalog.gd")
var checks := 0
var failures := 0

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func actor_for(visual: Resolver.Visual):
	var actor := Actor.new()
	add_child(actor)
	actor.setup_enemy(visual,Vector2(20,30),-1)
	return actor

func current_content() -> void:
	for id in Game.enemy_visuals.catalog:
		var visual := Game.enemy_combat_visual({"combatVisualId":id})
		check(visual.id == id and visual.diagnostics.is_empty(), "Current profile validates: "+id)
		for pose in Game.enemy_visuals.catalog[id].poses:
			check(visual.poses.get(pose) is Texture2D, "Current pose loads: "+id+"/"+pose)
	for id in Game.enemy_catalog:
		var enemy: Dictionary = Game.enemy_catalog[id]
		var resolved := Game.enemy_combat_visual(enemy)
		check(resolved.id == enemy.combatVisualId and resolved.diagnostics.is_empty(), "Explicit reference without fallback: "+id)
		var rendered = actor_for(resolved)
		for pose in resolved.poses:
			rendered.set_pose(pose)
			check(rendered.kind == enemy.combatVisualId and rendered.sprite.texture == resolved.poses[pose], "Enemy actor uses its configured texture: "+id+"/"+pose)
		rendered.free()
		var legacy := enemy.duplicate(true)
		legacy.erase("combatVisualId")
		var before := legacy.duplicate(true)
		check(Game.enemy_combat_visual(legacy).id == enemy.combatVisualId and legacy == before, "Legacy resolution is read-only: "+id)
	for id in Game.battles:
		Game.state = Game.initial_state()
		Game.state.battleId = id
		Game.initialize_combat()
		var snapshot: Dictionary = Game.state.combat.duplicate(true)
		check(Game.valid_combat(snapshot), "New snapshot validates: "+id)
		check(snapshot.enemies[0].combatVisualId == Game.enemy_catalog[snapshot.enemies[0].id].combatVisualId, "New snapshot carries reference: "+id)
		snapshot.enemies[0].erase("combatVisualId")
		var before := snapshot.duplicate(true)
		var restored := CombatModel.new()
		restored.restore(snapshot)
		check(Game.valid_combat(snapshot) and restored.snapshot() == before, "Old snapshot restores without migration: "+id)
		var actor = actor_for(Game.enemy_combat_visual(restored.enemies[0]))
		check(actor.sprite.texture != null and snapshot == before, "Old snapshot renders without mutation: "+id)
		actor.free()

func published_content() -> void:
	# Use the production catalog directly, never the workbench's path repair helper.
	for id in Pipeline.get_profiles():
		var raw := Pipeline.get_profile(id)
		var visual := Game.enemy_combat_visual({"id":"preview_"+id,"combatVisualId":id})
		check(visual.id == id and visual.pipeline_active and visual.diagnostics.is_empty(), "Published profile resolves without fallback: "+id)
		var actor = actor_for(visual)
		for pose in raw.poses:
			actor.set_pose(pose)
			check(actor.pose == pose and actor.sprite.texture != null, "Published actor pose renders: "+id+"/"+pose)
		if not str(raw.get("hitEffectTexture", "")).is_empty():
			check(visual.hit_effect_texture != null and visual.hit_effect_texture.resource_path == raw.hitEffectTexture, "Published hit effect retains its own binding: "+id)
		actor.free()

func configured_attack_effects() -> void:
	for id in ["fish", "robot", "gang", "gang_henchman"]:
		var visual := Game.enemy_combat_visual(Game.enemy_catalog[id])
		var stage := Stage.new()
		add_child(stage)
		var visuals: Array[Resolver.Visual] = [visual]
		stage.setup(533,visuals)
		var contacts := {"count":0}
		await stage.attack(stage.enemies[0],stage.player,"pierce",[{"damage":1,"blocked":0,"killed":false}],func(_hit,_index):
			contacts.count += 1
			if id == "fish":
				var effects := get_tree().get_nodes_in_group("bite_hit_fx")
				check(stage.enemies[0].pose == "bite_close" and effects.size() == 1, "Fish contact uses bite pose and one bite effect")
				if effects.size() == 1:
					check(effects[0].texture.resource_path == "res://assets/combat_test/12a_fish/fish_bite_hit_fx.png", "Fish bite uses the relocated fish effect")
			elif id == "robot":
				var beams := get_tree().get_nodes_in_group("palm_laser_fx")
				check(stage.enemies[0].pose == "laser" and beams.size() == 1, "Robot contact uses laser pose and one palm beam")
				if beams.size() == 1:
					check(beams[0].start.distance_to(stage.world.to_local(stage.enemies[0].sprite.to_global(stage.enemies[0].laser_muzzle))) < 0.01, "Robot beam originates from its calibrated palm")
			else:
				var matching := 0
				for effect in stage.world.get_children():
					if effect.get_script() == Stage.NeonSlash and effect.mode == "pierce": matching += 1
				check(stage.enemies[0].pose == "pierce" and matching == 1, "Gang contact retains its pierce effect: "+id))
		check(contacts.count == 1, "Configured attack presents exactly one hit: "+id)
		await stage.return_home()
		stage.queue_free()
		await get_tree().process_frame

func fallback_order() -> void:
	var resolver := Resolver.new()
	var enemies := {"fish":{"combatVisualId":"fish"}}
	for bad_id in ["old_fish", null, 42, ""]:
		var snapshot := {"id":"fish","combatVisualId":bad_id}
		var before := snapshot.duplicate(true)
		var visual := resolver.resolve(snapshot,enemies)
		check(visual.id == "fish" and not visual.diagnostics.is_empty(), "Invalid stored reference uses current enemy: "+str(bad_id))
		check(snapshot == before, "Fallback never rewrites stored reference: "+str(bad_id))
	check(resolver.resolve({"id":"fish","combatVisualId":"gang_henchman"},enemies).id == "gang_henchman", "Valid stored reference retains precedence")
	for retired in ["finn", "Finn", "fallback_finn"]:
		var snapshot := {"id":"fish", "combatVisualId":retired}
		var before := snapshot.duplicate(true)
		check(resolver.resolve(snapshot,enemies).id == "fish" and snapshot == before, "Retired stored art uses current art without changing snapshot: "+retired)
		check(resolver.resolve({"combatVisualId":retired},{}).id == "unillustrated", "Retired art without current replacement stays unillustrated: "+retired)
	check(resolver.resolve({"id":"fish"},enemies).id == "fish", "Absent stored field uses current catalog")
	check(resolver.resolve({"id":"missing"},{}).id == "unillustrated", "Unknown enemy has no character art")
	resolver.catalog["broken"] = {"id":"broken"}
	check(resolver.resolve({"id":"fish","combatVisualId":"broken"},enemies).id == "fish", "Broken stored profile uses current valid profile")
	check(resolver.resolve({"id":"fish"},{"fish":{"combatVisualId":"broken"}}).id == "unillustrated", "Broken current profile has no character art")
	resolver.catalog.clear()
	var emergency := resolver.resolve({"id":"missing"},{})
	var actor = actor_for(emergency)
	for pose in ["idle","move","block","damaged","pierce"]:
		actor.set_pose(pose)
		check(actor.pose == "idle" and actor.sprite.texture == null, "Broken final catalog stays unillustrated for pose: "+pose)
	check(emergency.id == "unillustrated" and emergency.target_bounds.size.x > 0, "Emergency visual has usable targeting")
	actor.free()

func unillustrated_combat() -> void:
	check(not Game.enemy_visuals.catalog.has("finn"), "Retired profile removed from catalog")
	check(not DirAccess.dir_exists_absolute("res://assets/combat_test/Finn"), "Retired asset directory removed")
	check(not FileAccess.file_exists("res://assets/combat_test/reference_idle/finn_idle.webp"), "Retired reference idle removed")
	var resolver := Resolver.new()
	# Even a previously valid catalog entry cannot reactivate retired art.
	resolver.catalog.finn = resolver.catalog.gang_henchman.duplicate(true)
	resolver.catalog.finn.id = "finn"
	check(resolver.resolve({"combatVisualId":"finn"},{}).poses.is_empty(), "Retired profile is blocked even when reintroduced in a catalog")
	for id in ["ike", "richard", "lumina", "psycho", "mech_boss"]:
		var enemy: Dictionary = Game.enemy_catalog[id]
		var before := enemy.duplicate(true)
		var visual := Game.enemy_combat_visual(enemy)
		check(visual.id == "unillustrated" and visual.poses.is_empty() and visual.diagnostics.is_empty(), "Former placeholder is explicitly unillustrated: "+id)
		var legacy := enemy.duplicate(true)
		legacy.combatVisualId = "finn"
		check(Game.enemy_combat_visual(legacy).poses.is_empty() and enemy == before, "Old placeholder snapshot stays unillustrated: "+id)
	var visual := resolver.resolve({"combatVisualId":"unillustrated"},{})
	var stage := Stage.new()
	add_child(stage)
	var visuals: Array[Resolver.Visual] = [visual]
	stage.setup(533,visuals)
	var enemy = stage.enemies[0]
	check(enemy.sprite.texture == null and enemy.target_bounds.has_point(Vector2(0,-60)), "Unillustrated enemy retains usable target bounds")
	var contacts := {"count":0}
	await stage.attack(stage.player,enemy,"slash",[{"damage":1,"blocked":0,"killed":false}],func(_hit,_index): contacts.count += 1)
	check(contacts.count == 1 and enemy.sprite.texture == null, "Player attack still hits the unillustrated target once")
	await stage.attack(enemy,stage.player,"pierce",[{"damage":1,"blocked":0,"killed":false}],func(_hit,_index): contacts.count += 1)
	check(contacts.count == 2 and enemy.sprite.texture == null, "Unillustrated enemy attack still hits once")
	await stage.return_home()
	check(enemy.position == enemy.home and enemy.sprite.texture == null, "Unillustrated enemy returns without restoring art")
	stage.queue_free()
	await get_tree().process_frame

func malformed_profiles() -> void:
	var resolver := Resolver.new()
	var original: Dictionary = resolver.catalog.fish.duplicate(true)
	var mutations: Dictionary = {
		"missing rect":func(p): p.erase("targetRect"),
		"short rect":func(p): p.targetRect = [0],
		"wrong rect type":func(p): p.targetRect = "0,0,100,100",
		"zero width":func(p): p.targetRect[2] = 0,
		"negative width":func(p): p.targetRect[2] = -10,
		"nonfinite rect":func(p): p.targetRect[0] = INF,
		"vector width underflow":func(p): p.targetRect[2] = 1e-50,
		"missing poses":func(p): p.erase("poses"),
		"wrong poses type":func(p): p.poses = [],
		"missing idle":func(p): p.poses.erase("idle"),
		"invalid pose object":func(p): p.poses.idle = null,
		"short anchor":func(p): p.poses.idle.anchor = [2],
		"wrong anchor type":func(p): p.poses.idle.anchor = "2,3",
		"nonfinite anchor":func(p): p.poses.idle.anchor[0] = NAN,
		"vector anchor overflow":func(p): p.poses.idle.anchor[0] = 1e300,
		"zero scale":func(p): p.poses.idle.scale = 0,
		"negative scale":func(p): p.poses.idle.scale = -1,
		"wrong scale type":func(p): p.poses.idle.scale = "0.12",
		"nonfinite scale":func(p): p.poses.idle.scale = INF,
		"vector scale overflow":func(p): p.poses.idle.scale = 1e300,
		"vector scale underflow":func(p): p.poses.idle.scale = 1e-50,
		"missing texture":func(p): p.poses.idle.texture = "res://assets/qa_missing.png",
		"non-texture resource":func(p): p.poses.idle.texture = "res://tests/combat/enemies/enemy_visual_library_tests.tscn",
		"invalid texture value":func(p): p.poses.idle.texture = null,
		"invalid alias object":func(p): p.poseAliases = [],
		"missing alias target":func(p): p.poseAliases.block = "absent",
		"invalid alias value":func(p): p.poseAliases.block = 3,
		"unknown attack style":func(p): p.attackStyleOverride = "teleport",
		"invalid attack style":func(p): p.attackStyleOverride = 1,
		"bite missing contact pose":func(p): p.poses.erase("bite_close"),
		"bite missing effect":func(p): p.hitEffectTexture = "",
		"missing effect texture":func(p): p.hitEffectTexture = "res://assets/qa_missing.png",
		"non-texture effect":func(p): p.hitEffectTexture = "res://tests/combat/enemies/enemy_visual_library_tests.tscn",
		"invalid effect value":func(p): p.hitEffectTexture = [],
		"shoot missing pose":func(p): p.attackStyleOverride = "shoot",
		"mismatched profile id":func(p): p.id = "wrong"
	}
	for label in mutations:
		var profile := original.duplicate(true)
		profile.id = "qa_broken"
		mutations[label].call(profile)
		resolver.catalog.qa_broken = profile
		var visual := resolver.resolve({"combatVisualId":"qa_broken"},{})
		check(visual.id == "unillustrated" and not visual.diagnostics.is_empty(), "Invalid profile rejected as a whole: "+label)
		var actor = actor_for(visual)
		actor.set_pose("damaged")
		check(actor.sprite.texture == null and actor.attack_style_override.is_empty() and actor.hit_effect_texture == null, "No partial bad profile reaches actor: "+label)
		actor.free()

func catalog_loading() -> void:
	var path := "user://qa_invalid_enemy_visuals.json"
	for text in ["{", "[]", "null"]:
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var resolver := Resolver.new(path)
		check(resolver.resolve({},{}).id == "unillustrated" and not resolver.load_error.is_empty(), "Broken catalog file falls back: "+text)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(Resolver.new(path).resolve({},{}).id == "unillustrated", "Missing catalog file falls back")

func identity_and_isolation() -> void:
	var resolver := Resolver.new()
	var profile: Dictionary = resolver.catalog.fish.duplicate(true)
	profile.id = "noren"
	resolver.catalog.noren = profile
	var before := resolver.catalog.duplicate(true)
	var visual := resolver.resolve({"combatVisualId":"noren"},{})
	check(visual.id == "noren" and visual.diagnostics.is_empty(), "Enemy profile may share a player name")
	check(resolver.catalog == before, "Resolver never mutates authored catalog")
	var other := resolver.resolve({"combatVisualId":"noren"},{})
	other.pose_aliases.block = "damaged"
	check(visual.pose_aliases.block == "idle", "Resolved mutable maps are independent")
	resolver.catalog.clear()
	var actor = actor_for(visual)
	check(not actor.is_player and actor.sprite.texture.resource_path.ends_with("fish_idle.png"), "Named noren enemy uses its configured fish art")
	actor.set_combat_stance("ranged")
	check(actor.pose == "idle" and actor.weapon_shift == null, "Enemy name cannot enable player stance machinery")
	actor.free()
	var player := Actor.new()
	add_child(player)
	player.setup_player(Vector2.ZERO,1)
	player.set_combat_stance("ranged")
	check(player.is_player and player.pose == "gun_idle", "Player retains explicit ranged identity")
	player.free()
	# Rendering needs no raw catalog after resolution.
	var stage := Stage.new()
	add_child(stage)
	var visuals: Array[Resolver.Visual] = [visual]
	stage.setup(533,visuals)
	var hits := {"count":0,"contactPose":""}
	await stage.attack(stage.enemies[0],stage.player,"pierce",[{"damage":1,"blocked":0,"killed":false}],func(_hit,_i):
		hits.count += 1
		hits.contactPose = stage.enemies[0].pose)
	check(hits.count == 1 and hits.contactPose == "bite_close", "Named noren enemy still bites and calls hit once")
	check(is_equal_approx(stage.last_hit_stop,0.095), "Enemy identity retains original bite hit stop")
	await stage.return_home()
	check(stage.enemies[0].position == stage.enemies[0].home and stage.enemies[0].pose == "idle", "Name collision does not affect return animation")
	stage.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://enemy_visual_library_test.json"
	Game.meta_path = "user://enemy_visual_library_meta_test.json"
	current_content()
	published_content()
	await configured_attack_effects()
	fallback_order()
	await unillustrated_combat()
	malformed_profiles()
	catalog_loading()
	await identity_and_isolation()
	print("ENEMY VISUAL LIBRARY: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
