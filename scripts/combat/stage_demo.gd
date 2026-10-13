extends Node
## Launches the real game and its existing training flow, with memory-only endurance HP.
func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://combat_stage_demo_unused.json"
	Game.meta_path = "user://combat_stage_demo_meta_unused.json"
	var app := preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	while app.shown_page != "battle": await get_tree().process_frame
	var view = app.view
	while Game.battle_busy or Game.transition_locked: await get_tree().process_frame
	# Only this isolated entry duplicates the encounter, never the enemy catalog.
	var template: Dictionary = view.model.enemies[0].duplicate(true)
	view.model.enemies.clear()
	for i in 3:
		var enemy := template.duplicate(true)
		enemy.id = "depth_demo_%d" % i
		enemy.displayName = "训练对手"
		enemy.maxHp = 20
		enemy.hp = 20
		view.model.enemies.append(enemy)
	view.commit()
	app.swap_view()
	Game.notice.emit("纵深演练 · 三名对手 · F5 切换挥砍/突刺 · F6 格挡预览 · F7 破防预览")
