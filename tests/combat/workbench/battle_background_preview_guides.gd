extends Node2D
## Guides follow actual feet and the artwork horizon through the stage camera.
var stage: Control
var ground_start := 0.5
var focused_actor: Node2D
var attack_key := ""

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(stage): return
	for actor in stage.actors_root.get_children():
		var foot := to_local(actor.global_position)
		draw_line(foot-Vector2(35,0),foot+Vector2(35,0),Color("64ffe1"),2)
		draw_line(foot-Vector2(0,10),foot+Vector2(0,10),Color("64ffe1"),2)
	if is_instance_valid(stage.scenery):
		var bounds: Rect2 = stage.scenery.get_global_rect()
		var y := bounds.position.y+bounds.size.y*ground_start
		draw_line(to_local(Vector2(0,y)),to_local(Vector2(1440,y)),Color("ffc982"),2)
	if not is_instance_valid(focused_actor): return
	var config: Dictionary = focused_actor.pipeline_attacks.get(attack_key, {})
	if config.is_empty(): return
	var origin := to_local(focused_actor.sprite.to_global(config.muzzle))
	draw_circle(origin, 6, Color("ffe082"), false, 2, true)
	var defender: Node2D = stage.player if focused_actor != stage.player else (stage.enemies[0] if not stage.enemies.is_empty() else null)
	if not is_instance_valid(defender): return
	var target := to_local(defender.to_global(config.contact))
	draw_circle(target, 7, Color("ff87b8"), false, 2, true)
	draw_dashed_line(origin, target, Color(1, 0.7, 0.8, 0.5), 1, 7, true)
