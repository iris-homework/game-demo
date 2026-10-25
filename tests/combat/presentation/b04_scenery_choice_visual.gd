extends Node
## Rendered menu input and training isolation; never writes adventure saves.
var app: Control
var output := "res://artifacts/qa/b04-scenery-choice-2026-10-18/render"
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	await get_tree().create_timer(0.15).timeout

func idle() -> void:
	var deadline := Time.get_ticks_msec()+20000
	await settle()
	while Game.battle_busy or Game.transition_locked:
		if Time.get_ticks_msec() > deadline:
			check(false,"Timed out waiting for battle/menu")
			get_tree().quit(1)
			return
		await get_tree().process_frame

func click(node: Control) -> void:
	check(is_instance_valid(node),"Required menu control exists")
	if not is_instance_valid(node): return
	var point := node.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		get_viewport().push_input(event,true)
		await get_tree().process_frame
	await settle()

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		get_viewport().push_input(event,true)
		await get_tree().process_frame
	await settle()

func shot(name_text: String) -> void:
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name_text+".png")) == OK,"Saved screenshot "+name_text)

func _ready() -> void:
	if not OS.get_environment("QA_OUT_DIR").is_empty(): output = OS.get_environment("QA_OUT_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	Game.state = Game.initial_state()
	var adventure: Dictionary = Game.state.duplicate(true)
	var battle_definitions: Dictionary = Game.battles.duplicate(true)
	Game.page = "menu"
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(0.6).timeout
	var choices := Game.training_scenery_choices()
	check(choices.size() == 13,"Default and twelve completed scenes are offered")
	check(choices.any(func(choice): return choice.id == "hospital"),"Laboratory battle background is offered")
	check(Game.set_b04_scenery_choice("alley"),"Completed alley can be selected")
	check(Game.set_b04_scenery_choice("bar"),"Midnight bar can be selected")
	Game.set_b04_scenery_choice("")
	check(not Game.set_b04_scenery_choice("invalid"),"Invalid scene cannot be selected")
	await click(app.view.training_toggle)
	check(app.view.training_open,"Training menu opens by input")
	await shot("01-menu-expanded")
	await click(app.view.training_scenery_button)
	check(is_instance_valid(app.view.scenery_dialog),"Scene picker opens by input")
	if not is_instance_valid(app.view.scenery_dialog):
		finish()
		return
	check(app.view.find_child("scenery_choice_alley",true,false) != null and app.view.find_child("scenery_choice_bar",true,false) != null,"Picker contains both new scene options")
	var bar_button: Control = app.view.find_child("scenery_choice_bar",true,false)
	check(bar_button.get_global_rect().end.y < app.view.scenery_cancel.get_global_rect().position.y,"Last row clears cancel button")
	check(app.view.find_child("training_B04",true,false).disabled,"B04 is blocked behind modal")
	await shot("02-scene-picker")
	await key(KEY_TAB)
	check(app.view.scenery_dialog.is_ancestor_of(get_viewport().gui_get_focus_owner()),"Keyboard focus remains inside picker")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.view.scenery_dialog) and Game.b04_scenery_choice.is_empty() and app.view.training_open,"Escape cancels only the picker without changing choice")
	await click(app.view.training_scenery_button)
	if not is_instance_valid(app.view.scenery_dialog):
		await shot("failure-picker-reopen")
		print("REOPEN STATE ",app.view.training_scenery_button.disabled," ",app.view.training_scenery_button.button_pressed," ",app.view.training_open," ",Game.battle_busy," ",Game.transition_locked)
		check(false,"Picker reopens after Escape")
		finish()
		return
	await click(app.view.find_child("scenery_choice_hive",true,false))
	check(Game.b04_scenery_choice == "hive" and app.view.training_scenery_button.text.contains("蜂巢"),"Selecting hive updates the menu button")
	await click(app.view.training_scenery_button)
	await click(app.view.find_child("scenery_cancel",true,false))
	check(Game.b04_scenery_choice == "hive","Cancel preserves previous selection")
	await click(app.view.find_child("training_B04",true,false))
	await idle()
	check(Game.training_mode and Game.training_scenery_place_id == "hive","B04 consumes the chosen session background")
	check(app.view.stage.scenery.texture == Game.texture("hive_battle_simplified"),"B04 displays selected image")
	check(app.view.battle.placeId == battle_definitions.B04.placeId and Game.battles == battle_definitions,"Scene choice never mutates encounter or story place")
	check(not Game.set_b04_scenery_choice("garden"),"Selection cannot change during active training")
	await shot("03-b04-hive")
	Game.finish_training("win")
	await idle()
	check(Game.state == adventure and Game.training_scenery_place_id.is_empty(),"Leaving B04 restores adventure and clears active override")
	check(Game.b04_scenery_choice == "hive","Menu preference persists for this session")
	await click(app.view.training_toggle)
	await click(app.view.training_scenery_button)
	await click(app.view.find_child("scenery_choice_default",true,false))
	await click(app.view.find_child("training_B04",true,false))
	await idle()
	check(is_instance_valid(app.view.stage.scenery) and app.view.stage.scenery.texture == Game.texture("alley_battle_simplified"),"Default B04 uses the new alley illustration")
	check(is_equal_approx(app.view.actor_offset.y,44.0),"Original default character placement is preserved")
	await shot("04-b04-default")
	Game.finish_training("win")
	await idle()
	check(Game.set_b04_scenery_choice("bar"),"Midnight bar is selectable after returning")
	Game.start_training("B04")
	await idle()
	check(Game.training_scenery_place_id == "bar" and app.view.stage.scenery.texture == Game.texture("bar_battle_simplified"),"B04 displays the new midnight bar")
	await shot("05-b04-bar")
	Game.finish_training("win")
	await idle()
	check(Game.set_b04_scenery_choice("garden"),"Another completed scene is selectable")
	Game.start_training("B11")
	await idle()
	check(Game.training_scenery_place_id.is_empty(),"B04 preference does not leak into B11")
	var b11_asset: String = Game.assets[Game.place_data(app.view.battle.placeId).backgroundAssetId].battleAssetId
	check(app.view.stage.scenery.texture == Game.texture(b11_asset),"B11 keeps its own scene")
	Game.finish_training("win")
	await idle()
	check(Game.state == adventure and Game.battles == battle_definitions,"Adventure and encounter definitions remain intact")
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path),"No preview save files were written")
	finish()

func finish() -> void:
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"messages":failures,"syntheticInput":true,"physicalInput":false},"\t"))
	print("B04 SCENERY CHOICE: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
