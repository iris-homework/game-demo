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
	view.model.enemies[0].maxHp = 20
	view.model.enemies[0].hp = 20
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.commit()
	view.refresh_enemy_hud()
	Game.notice.emit("动作演练 · F5 切换挥砍/突刺 · F6 格挡预览 · F7 破防预览")
