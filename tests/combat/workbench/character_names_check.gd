extends Node
## Naming QA for both workbenches. Headless runs skip only the screenshot.

const Names = preload("res://tests/combat/workbench/workbench_character_names.gd")

var bench: Control
var checks := 0
var failures: Array[String] = []
var output := ""
var started := 0
var done := false


func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _process(_delta: float) -> void:
	if started > 0 and Time.get_ticks_msec()-started > 120000:
		verify(false,"QA watchdog: timed out")
		finish()


func unlock(node: Control) -> void:
	var deadline := Time.get_ticks_msec()+30000
	while node.tools_locked():
		if Time.get_ticks_msec() > deadline:
			verify(false,"Workbench did not unlock")
			return
		await get_tree().process_frame
	await get_tree().process_frame


func has_label(root: Node, wanted: String) -> bool:
	if root is Label and root.text == wanted:
		return true
	for child in root.get_children():
		if has_label(child,wanted):
			return true
	return false


func choice_name(id: String) -> String:
	for choice in bench.enemy_choices:
		if choice.id == id:
			return str(choice.name)
	return ""


func check_helpers() -> void:
	var catalog := Names.names()
	verify(Names.name_for_visual("warden_shield") == "01a_warden_shield","warden_shield uses its real folder")
	verify(Names.name_for_visual("robot") == "02b_robot","robot uses its real folder")
	verify(Names.name_for_visual("fish") == "12a_fish","fish uses its real folder")
	verify(Names.name_for_visual("noren") == "noren","noren stays lower-case")
	verify(Names.name_for_visual("finn") == "finn","Finn folder displays finn")
	verify(Names.name_for_visual("Finn") == "finn","Mixed-case finn lookup is lower-case")
	verify(Names.name_for_visual("Robot") == "02b_robot","Mixed-case robot lookup finds its folder")
	verify(Names.name_for_visual("visual:FINN") == "finn","Prefixed mixed-case lookup is lower-case")
	verify(Names.name_for_visual("unknown_model") == "unknown_model","unknown visual keeps its ASCII id")
	verify(Names.name_for_visual("Unknown_Model") == "unknown_model","unknown visual also lowers its id")
	verify(Names.visual_id_from_directory("02B_ROBOT") == "robot","Numbered prefix lookup is lower-case")
	verify(Names.display_name_from_directory("01A_WARDEN_SHIELD") == "01a_warden_shield","Numbered display is lower-case")
	verify(Names.is_skipped_directory("reference") and Names.is_skipped_directory("reference_idle") and Names.is_skipped_directory("REFERENCE-finn") and not Names.is_skipped_directory("noren"),"reference directories are skipped")
	verify(Names.is_role_id("warden_shield") and not Names.is_role_id("bad name") and not Names.is_role_id("Reference"),"role ids match the web pattern")
	verify(not catalog.has("reference_idle"),"reference_idle is skipped")
	verify(catalog.has("noren") and catalog.has("finn"),"noren and finn are always mapped")
	for visual in catalog:
		var label := str(catalog[visual])
		verify(Names.is_ascii(label),"Folder name is ASCII: "+label)
		verify(label == label.to_lower(),"Folder name is lower-case: "+label)
		verify(not str(visual).begins_with("reference"),"Reference folder is not mapped: "+str(visual))
		verify(Names.visual_id_from_directory(label) == str(visual),"Folder round-trip: "+label)


func check_choices(tag: String) -> void:
	verify(bench.enemy_picker.item_count == bench.enemy_choices.size(),tag+" picker keeps every choice")
	var counts: Dictionary = {}
	for index in bench.enemy_choices.size():
		var choice: Dictionary = bench.enemy_choices[index]
		var label := str(choice.name)
		var id := str(choice.id)
		counts[id] = int(counts.get(id,0))+1
		verify(Names.is_ascii(label),tag+" choice is ASCII: "+label)
		verify(label == label.to_lower(),tag+" choice is lower-case: "+label)
		verify(not label.contains("·") and not label.contains("素材预览") and not label.contains("制作配置"),tag+" choice has no role suffix: "+label)
		verify(bench.enemy_picker.get_item_text(index) == label,tag+" picker text matches: "+label)
		verify(not bench.enemy_picker.get_item_tooltip(index).is_empty(),tag+" tooltip keeps source id: "+id)
	for id in Game.enemy_catalog:
		verify(int(counts.get(id,0)) == 1,tag+" formal enemy kept once: "+str(id))
	verify(choice_name("fish") == "12a_fish" and choice_name("fish_second") == "12a_fish",tag+" repeated fish choices both kept")
	verify(choice_name("gang_henchman") == "03a_gang_henchman" and choice_name("gang_henchman_second") == "03a_gang_henchman",tag+" repeated henchman choices both kept")
	verify(choice_name("ike") == "finn" and choice_name("richard") == "finn" and choice_name("lumina") == "finn" and choice_name("psycho") == "finn" and choice_name("mech_boss") == "finn",tag+" all Finn placeholders share finn")
	verify(choice_name("robot") == "02b_robot",tag+" robot label")


func check_actor(actor: int, roster_key: String, model_id: String, visual: String, label: String) -> void:
	bench.selected_actor = actor
	bench._sync_actor_controls()
	verify(bench.roster[actor-1] == roster_key,"Roster key stays "+roster_key)
	verify(bench.actor_info.text == label,"Actor info shows "+label)
	verify(bench.enemy_picker.get_item_text(bench.enemy_picker.selected) == label,"Picker selection shows "+label)
	verify(bench.target_picker.get_item_text(0) == "目标：noren","Enemy target shows noren")
	var enemy: Dictionary = bench.view.model.enemies[actor-1]
	verify(str(enemy.id) == model_id,"Model id stays "+model_id)
	verify(str(enemy.combatVisualId) == visual,"Visual id stays "+visual)
	verify(str(enemy.displayName) == label,"Model display uses "+label)
	verify(bench.view.stage.enemies[actor-1].kind == visual,"Stage visual stays "+visual)
	var plate_title := ""
	for child in bench.view.enemy_summary_plates[actor-1].get_children():
		if child is Label and child.text.contains("  "):
			plate_title = child.text
	verify(plate_title.contains(label),"HUD title shows "+label)
	verify(bench.view.enemy_intents[actor-1].tooltip_text.begins_with(label+" · "),"Intent tooltip shows "+label)
	var snapshot: Dictionary = bench.view.model.snapshot()
	verify(snapshot.enemies[actor-1].id == model_id and snapshot.enemies[actor-1].combatVisualId == visual,"Snapshot keeps ids for "+label)
	var restored := CombatModel.new()
	restored.restore(snapshot)
	verify(restored.enemies[actor-1].id == model_id and restored.enemies[actor-1].combatVisualId == visual,"Snapshot round-trip keeps ids for "+label)
	verify(restored.snapshot() == snapshot,"Snapshot round-trip is unchanged for "+label)


func check_workbench() -> void:
	if Game.training_mode: Game.restore_training()
	var formal_before: Dictionary = Game.enemy_catalog.duplicate(true)
	bench = preload("res://tests/combat/workbench/battle_background_preview.tscn").instantiate()
	bench.profile_path = output.path_join("character_names_profiles.json")
	add_child(bench)
	await unlock(bench)
	verify(Game.enemy_catalog == formal_before,"Formal enemy catalog is unchanged")
	verify(bench.actor_tabs.get_tab_title(0) == "noren" and bench.actor_tabs.tab_count == 2,"Player tab shows noren")
	check_choices("Base workbench")
	bench.selected_actor = 0
	bench._sync_actor_controls()
	verify(bench.actor_info.text.begins_with("noren · "),"Player info shows noren")
	verify(bench.target_picker.get_item_text(0) == "目标：02b_robot","Player target shows 02b_robot")
	check_actor(1,"robot","robot","robot","02b_robot")
	var robot_before: Dictionary = Game.enemy_catalog["robot"].duplicate(true)
	var robot_copy: Dictionary = bench._enemy_definition("robot")
	verify(robot_copy.id == "robot" and robot_copy.combatVisualId == "robot" and robot_copy.displayName == "02b_robot","Test definition changes only the display name")
	verify(Game.enemy_catalog["robot"] == robot_before,"Formal robot definition is unchanged")
	await bench.change_roster("fish")
	await unlock(bench)
	check_actor(1,"fish","fish","fish","12a_fish")
	await bench.change_roster("fish_second")
	await unlock(bench)
	check_actor(1,"fish_second","fish_second","fish","12a_fish")
	await bench.change_roster("gang_henchman_second")
	await unlock(bench)
	check_actor(1,"gang_henchman_second","gang_henchman_second","gang_henchman","03a_gang_henchman")
	await bench.change_roster("ike")
	await unlock(bench)
	check_actor(1,"ike","ike","finn","finn")
	await bench.change_roster("visual:warden_shield")
	await unlock(bench)
	check_actor(1,"visual:warden_shield","preview_warden_shield","warden_shield","01a_warden_shield")
	verify(has_label(bench.view,"noren / 战斗"),"Battle status bar shows noren")
	verify(not has_label(bench.view,"诺伦 / 战斗"),"Battle status bar has no Chinese role name")
	verify(has_label(bench.view,"演练模式 · 不影响冒险") or has_label(bench.view,"noren / 形态与弹药"),"Battle top bar has an ASCII role label")
	verify(not has_label(bench.view,"诺伦 / 形态与弹药"),"Battle top bar has no Chinese role name")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		verify(get_viewport().get_texture().get_image().save_png(output.path_join("character-names.png")) == OK,"Screenshot saved")
	bench.queue_free()
	await get_tree().process_frame


func check_pipeline() -> void:
	var preview_path := "res://enemy_asset_pipeline/test/preview_catalog.json"
	if not FileAccess.file_exists(preview_path): return
	# The base workbench leaves training active; restore it before a second entry.
	if Game.training_mode: Game.restore_training()
	var pipe: Control = preload("res://enemy_asset_pipeline/workbench.tscn").instantiate()
	pipe.test_mode = true
	pipe.profile_path = output.path_join("character_names_pipeline_profiles.json")
	add_child(pipe)
	await unlock(pipe)
	await pipe._reload_pipeline(true)
	await unlock(pipe)
	bench = pipe
	check_choices("Pipeline workbench")
	verify(choice_name("visual:warden_shield") == "01a_warden_shield","Pipeline append uses the real folder")
	pipe.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	started = Time.get_ticks_msec()
	output = OS.get_environment("QA_OUT_DIR")
	if output.is_empty(): output = "res://tests/combat/workbench/runtime/qa"
	DirAccess.make_dir_recursive_absolute(output)
	check_helpers()
	await check_workbench()
	await check_pipeline()
	finish()


func finish() -> void:
	if done: return
	done = true
	started = 0
	var report := {"checks":checks,"failures":failures,"headless":DisplayServer.get_name()=="headless","scope":"character directory names in both workbenches"}
	var file := FileAccess.open(output.path_join("character_names_result.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"	"))
	print("CHARACTER NAMES QA: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
