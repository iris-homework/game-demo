extends RefCounted
## Test-only path repair for the user's numbered asset folders. Authored files stay intact.
const IDLE_ART := {
	"warden_shield":["01a_warden_shield/warden_shield_idle.png","巡界盾手"],
	"scavenger_hooker":["02b_scavenger_hooker/scavenger_hooker_idle.png","拾荒钩客"],
	"chip_broker":["04b_chip_broker/chip_broker_idle.png","筹码掮客"],
	"mutant_mouse":["05a_mutant_mouse/mutant_mouse.png","爬墙线鼠"],
	"luggage_lurker":["06b_luggage_lurker/luggage_lurker_idle.png","行李潜伏客"],
	"penitent_ascetic":["07b_penitent_ascetic/penitent_ascetic_idle.png","赎罪苦修者"],
	"rogue_drone":["08b_rogue_drone/rogue_drone_idle.png","失控配送蜂"],
	"pruning_hound":["10a_pruning_hound/pruning_hound_idle.png","修枝猎犬"],
	"powerline_repairman":["11a_powerline_repairman/powerline_repairman_idle.png","输电抢修工"],
	"beacon_jellyfish":["13b_beacon_jellyfish/beacon_jellyfish_idle.png","信标水母"]
}
const MOVED := {"fish":"12a_fish","robot":"02b_robot","gang_boss":"03b_gang_boss","gang_henchman":"03a_gang_henchman"}

static func prepare() -> void:
	# The resolver is process-local; no production JSON, resource or scene is edited.
	var catalog: Dictionary = Game.enemy_visuals.catalog.duplicate(true)
	for id in catalog:
		for pose in catalog[id].get("poses",{}).values():
			pose.texture = _current_path(str(pose.texture))
		if not str(catalog[id].get("hitEffectTexture","")).is_empty():
			catalog[id].hitEffectTexture = _current_path(str(catalog[id].hitEffectTexture))
	for id in IDLE_ART:
		var path := "res://assets/combat_test/"+str(IDLE_ART[id][0])
		if not ResourceLoader.exists(path): continue
		var texture := load(path) as Texture2D
		if texture == null: continue
		var bounds := texture.get_image().get_used_rect()
		if bounds.size.y <= 0: continue
		catalog[id] = {"id":id,"targetRect":[-65,-145,130,155],"sourceFacing":"left","poses":{"idle":{"texture":path,"anchor":[bounds.position.x+bounds.size.x*0.5,bounds.end.y],"scale":140.0/bounds.size.y}}}
	Game.enemy_visuals.catalog = catalog

static func _current_path(path: String) -> String:
	for old in MOVED:
		var prefix := "res://assets/combat_test/"+str(old)+"/"
		if path.begins_with(prefix):
			var candidate := "res://assets/combat_test/"+str(MOVED[old])+"/"+path.trim_prefix(prefix)
			if ResourceLoader.exists(candidate): return candidate
	return path
