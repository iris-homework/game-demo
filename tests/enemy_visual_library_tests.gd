extends Node
## Bad authored data must never reach an actor.
const Resolver = preload("res://scripts/combat/enemy_visual_resolver.gd")
const Actor = preload("res://scripts/combat/pose_actor.gd")
const Stage = preload("res://scripts/combat/test_stage.gd")
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
			check(visual.poses[pose] is Texture2D, "Current pose loads: "+id+"/"+pose)
	for id in Game.enemy_catalog:
		var enemy: Dictionary = Game.enemy_catalog[id]
		check(Game.enemy_combat_visual(enemy).id == enemy.combatVisualId, "Explicit reference: "+id)
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

func fallback_order() -> void:
	var resolver := Resolver.new()
	var enemies := {"fish":{"combatVisualId":"fish"}}
	for bad_id in ["old_fish", null, 42, ""]:
		var snapshot := {"id":"fish","combatVisualId":bad_id}
		var before := snapshot.duplicate(true)
		var visual := resolver.resolve(snapshot,enemies)
		check(visual.id == "fish" and not visual.diagnostics.is_empty(), "Invalid stored reference uses current enemy: "+str(bad_id))
		check(snapshot == before, "Fallback never rewrites stored reference: "+str(bad_id))
	check(resolver.resolve({"id":"fish","combatVisualId":"finn"},enemies).id == "finn", "Valid stored reference retains precedence")
	check(resolver.resolve({"id":"fish"},enemies).id == "fish", "Absent stored field uses current catalog")
	check(resolver.resolve({"id":"missing"},{}).id == "finn", "Unknown enemy uses validated Finn")
	resolver.catalog["broken"] = {"id":"broken"}
	check(resolver.resolve({"id":"fish","combatVisualId":"broken"},enemies).id == "fish", "Broken stored profile uses current valid profile")
	check(resolver.resolve({"id":"fish"},{"fish":{"combatVisualId":"broken"}}).id == "finn", "Broken current profile uses Finn")
	resolver.catalog.finn = null
	var emergency := resolver.resolve({"id":"missing"},{})
	var actor = actor_for(emergency)
	for pose in ["idle","move","block","damaged","pierce"]:
		actor.set_pose(pose)
		check(actor.pose == "idle" and actor.sprite.texture != null, "Broken final catalog still has a visible safe pose: "+pose)
	check(emergency.id == "fallback_finn" and emergency.target_bounds.size.x > 0, "Emergency visual has usable targeting")
	actor.free()

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
		"non-texture resource":func(p): p.poses.idle.texture = "res://tests/enemy_visual_library_tests.tscn",
		"invalid texture value":func(p): p.poses.idle.texture = null,
		"invalid alias object":func(p): p.poseAliases = [],
		"missing alias target":func(p): p.poseAliases.block = "absent",
		"invalid alias value":func(p): p.poseAliases.block = 3,
		"unknown attack style":func(p): p.attackStyleOverride = "teleport",
		"invalid attack style":func(p): p.attackStyleOverride = 1,
		"bite missing contact pose":func(p): p.poses.erase("bite_close"),
		"bite missing effect":func(p): p.hitEffectTexture = "",
		"missing effect texture":func(p): p.hitEffectTexture = "res://assets/qa_missing.png",
		"non-texture effect":func(p): p.hitEffectTexture = "res://tests/enemy_visual_library_tests.tscn",
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
		check(visual.id == "finn" and not visual.diagnostics.is_empty(), "Invalid profile rejected as a whole: "+label)
		var actor = actor_for(visual)
		actor.set_pose("damaged")
		check(actor.sprite.texture != null and actor.attack_style_override.is_empty() and actor.hit_effect_texture == null, "No partial bad profile reaches actor: "+label)
		actor.free()

func catalog_loading() -> void:
	var path := "user://qa_invalid_enemy_visuals.json"
	for text in ["{", "[]", "null"]:
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var resolver := Resolver.new(path)
		check(resolver.resolve({},{}).id == "fallback_finn" and not resolver.load_error.is_empty(), "Broken catalog file falls back: "+text)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(Resolver.new(path).resolve({},{}).id == "fallback_finn", "Missing catalog file falls back")

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
	fallback_order()
	malformed_profiles()
	catalog_loading()
	await identity_and_isolation()
	print("ENEMY VISUAL LIBRARY: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
