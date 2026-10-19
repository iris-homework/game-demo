extends "res://tests/enemy_intent_tooltip_visual.gd"
## Actual player/enemy badge hovers using read-only display snapshots.

func tooltip_boxes() -> Array[Node]:
	return get_tree().root.find_children("CombatStatusTooltip","PanelContainer",true,false)

func badge(plate: Control, id: String) -> Control:
	for item in plate.badges:
		if item.metadata.get("buffId","") == id: return item
	return null

func _ready() -> void:
	get_tree().create_timer(45).timeout.connect(func():
		push_error("Buff tooltip QA timed out")
		get_tree().quit(2))
	Game.save_enabled = false
	Game.save_path = "user://buff_tooltip_unused.json"
	Game.meta_path = "user://buff_tooltip_meta_unused.json"
	output = "res://artifacts/qa/buff-tooltip-2026-10-20/hover/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	DisplayServer.window_move_to_foreground()
	await get_tree().create_timer(0.3).timeout
	var view = app.view
	var buffs = view.model.buffs
	buffs.apply(view.model,"parry",2)
	buffs.apply(view.model,"pollution",3)
	buffs.apply(view.model,"high_pressure",1)
	buffs.apply(view.model,"strength",2,0)
	buffs.apply(view.model,"weak",2,0)
	view.shown_player_parry = view.model.parry
	view.shown_player_pollution = buffs.count(view.model,"pollution")
	view.shown_player_buffs = view.model.buff_state.duplicate(true)
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.refresh_player_plate()
	view.refresh_enemy_hud()
	view.update_target_rects()
	var before: Dictionary = view.model.snapshot().duplicate(true)
	await hover_tip(badge(view.player_plate,"parry"),"01-player-parry","每次消耗 1 层")
	await hover_tip(badge(view.player_plate,"pollution"),"02-player-pollution","再减少 1 层")
	await hover_tip(badge(view.enemy_plates[0],"strength"),"03-enemy-strength","不会随回合减少")
	await hover_tip(badge(view.enemy_plates[0],"weak"),"04-enemy-weak","固定降低 25%")
	await hover_tip(badge(view.player_plate,"high_pressure"),"05-persistent-ability","本回合：待触发")
	check(view.model.snapshot() == before,"Hovering buffs leaves model and stacks unchanged")
	check(badge(view.player_plate,"parry").metadata.category == "positive" and badge(view.enemy_plates[0],"weak").metadata.category == "negative","Positive and negative labels use authored metadata")
	# Rebuilding the displayed badges must use the latest layer count.
	buffs.apply(view.model,"weak",1,0)
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.refresh_enemy_hud()
	view.update_target_rects()
	await hover_tip(badge(view.enemy_plates[0],"weak"),"06-updated-weak","3 层")
	check(badge(view.enemy_plates[0],"weak").amount == 3,"Updated stack count reaches badge and tooltip")
	# Read a badge with a card selected; moving across it must not clear selection.
	var uid: String = view.model.hand[0]
	view.select_card(uid)
	before = view.model.snapshot().duplicate(true)
	await hover_tip(badge(view.player_plate,"parry"),"07-selected-card-buff","一次敌方攻击结束后")
	check(view.selected_uid == uid and view.model.snapshot() == before,"Buff tooltip preserves selected card and combat resources")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false,"syntheticPointerInput":true},"\t"))
	print("BUFF TOOLTIP VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
