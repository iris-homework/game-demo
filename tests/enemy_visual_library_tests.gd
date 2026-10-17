extends Node
## Presentation references must work for new battles and old, unmodified snapshots.
const Actor = preload("res://scripts/combat/pose_actor.gd")
var checks := 0
var failures := 0

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://enemy_visual_library_test.json"
	Game.meta_path = "user://enemy_visual_library_meta_test.json"
	for id in Game.enemy_visual_catalog:
		var profile: Dictionary = Game.enemy_visual_catalog[id]
		check(profile.id == id and profile.poses.has("idle"), "Visual profile identity and idle: "+id)
		check(profile.targetRect.size() == 4 and profile.targetRect[2] > 0 and profile.targetRect[3] > 0, "Positive target area: "+id)
		for pose in profile.poses:
			var entry: Dictionary = profile.poses[pose]
			check(ResourceLoader.exists(entry.texture) and load(entry.texture) is Texture2D, "Pose texture loads: "+id+"/"+pose)
			check(entry.anchor.size() == 2 and entry.scale > 0, "Pose calibration: "+id+"/"+pose)
		for alias in profile.poseAliases:
			check(profile.poses.has(profile.poseAliases[alias]), "Alias resolves to a pose: "+id+"/"+alias)
		if profile.attackStyleOverride == "bite":
			check(profile.poses.has("bite") and profile.poses.has("bite_close") and load(profile.hitEffectTexture) is Texture2D, "Bite has windup, contact and effect assets")
	for id in Game.enemy_catalog:
		var enemy: Dictionary = Game.enemy_catalog[id]
		check(Game.enemy_visual_catalog.has(enemy.combatVisualId), "Explicit visual reference: "+id)
		var legacy := enemy.duplicate(true)
		legacy.erase("combatVisualId")
		var before := legacy.duplicate(true)
		check(Game.enemy_combat_visual_id(legacy) == enemy.combatVisualId and legacy == before, "Legacy resolution leaves enemy unchanged: "+id)
	for id in Game.battles:
		Game.state = Game.initial_state()
		Game.state.battleId = id
		Game.initialize_combat()
		var snapshot: Dictionary = Game.state.combat.duplicate(true)
		check(Game.valid_combat(snapshot), "New combat snapshot validates: "+id)
		check(snapshot.enemies[0].combatVisualId == Game.enemy_catalog[snapshot.enemies[0].id].combatVisualId, "New battle carries configured visual: "+id)
		snapshot.enemies[0].erase("combatVisualId")
		var before := snapshot.duplicate(true)
		check(Game.valid_combat(snapshot), "Old snapshot needs no migration: "+id)
		var actor := Actor.new()
		add_child(actor)
		actor.setup(Game.enemy_combat_visual_id(snapshot.enemies[0]),Vector2(20,30),-1)
		check(actor.sprite.texture != null and snapshot == before, "Old battle renders without mutating snapshot: "+id)
		actor.free()
	# A new profile ID and an unrelated enemy ID must work without name-based code.
	Game.enemy_visual_catalog["qa_biter"] = Game.enemy_visual_catalog.fish.duplicate(true)
	Game.enemy_visual_catalog.qa_biter.id = "qa_biter"
	Game.enemy_catalog["qa_enemy"] = {"combatVisualId":"qa_biter"}
	var custom := Actor.new()
	add_child(custom)
	custom.setup(Game.enemy_combat_visual_id({"id":"qa_enemy"}),Vector2.ZERO,-1)
	check(custom.kind == "qa_biter" and custom.attack_style_override == "bite", "Data selects bite for a new enemy and visual ID")
	check(custom.target_bounds == Rect2(-80,-122,152,134) and custom.hit_effect_texture != null, "Data selects body target and hit effect")
	custom.set_pose("block")
	check(custom.pose == "idle", "New profile inherits configured guard alias")
	custom.free()
	check(Game.enemy_combat_visual_id({"id":"fish","combatVisualId":"finn"}) == "finn", "Explicit snapshot visual wins over catalog fallback")
	Game.enemy_visual_catalog.erase("qa_biter")
	Game.enemy_catalog.erase("qa_enemy")
	check(Game.enemy_combat_visual_id({"id":"unknown_qa"}) == "finn", "Missing mapping falls back safely with diagnostic")
	check(Game.enemy_combat_visual_id({"id":"fish","combatVisualId":null}) == "finn", "Malformed optional visual cannot crash old-save rendering")
	print("ENEMY VISUAL LIBRARY: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
