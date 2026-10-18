extends Node
## Rendered integration checks using real battle calls and synthetic tool input.
var checks := 0
var failures := 0
var output := ""
var bench: Control
var completed := false
const Profiles = preload("res://tests/battle_background_profiles.gd")

func verify_background(message: String) -> void:
	var stage: Control = bench.view.stage
	var local: Rect2 = bench.backdrop.get_rect()
	var art := Rect2(bench.backdrop.to_global(local.position), local.size * bench.backdrop.global_scale)
	verify(art.encloses(stage.get_parent().get_global_rect()), "Background covers clip: " + message)

func on_phase(phase: String) -> void:
	if phase in ["impact", "light_flight"]:
		verify_background(phase)

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PREVIEW CHECK: " + message)

func settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw

func shot(filename: String) -> void:
	await settle()
	verify(get_viewport().get_texture().get_image().save_png(output + filename + ".png") == OK, "Screenshot " + filename)

func click_tool(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func verify_hand_trial() -> void:
	var original := preload("res://scripts/battle.gd").new()
	var count: int = bench.view.model.hand.size()
	for i in count:
		var card: CombatCard = bench.view.cards[bench.view.model.hand[i]]
		verify(card.home.is_equal_approx(original.hand_position(i, count) - Vector2(0, 60)), "Resting hand raised 60 pixels: " + str(i))
		verify(is_equal_approx(card.home_rotation, original.hand_rotation(i, count)) and is_equal_approx(card.home_scale, 0.75), "Resting fan rotation and scale retained: " + str(i))
	var middle := count / 2
	var uid: String = bench.view.model.hand[middle]
	var card: CombatCard = bench.view.cards[uid]
	var old_home: Vector2 = original.hand_position(middle, count)
	bench.view.set_process(false)
	card.hover(true)
	await settle(0.2)
	verify(card.position.is_equal_approx(old_home + Vector2(0, -140)), "Hovered card ends at original screen position")
	verify(card.scale.is_equal_approx(Vector2.ONE * 1.12) and is_zero_approx(card.rotation), "Hovered card keeps original enlargement and upright pose")
	await shot("10-hand-hover")
	bench.view.select_card(uid)
	await settle(0.2)
	verify(card.position.is_equal_approx(old_home + Vector2(0, -150)), "Selected card ends at original screen position")
	verify(card.scale.is_equal_approx(Vector2.ONE * 1.12) and is_zero_approx(card.rotation), "Selected card keeps original enlargement and upright pose")
	await shot("11-hand-selected")
	bench.view.cancel_selection()
	card.hover(false)
	await settle(0.2)
	verify(card.position.is_equal_approx(card.home), "Deselected card returns to raised resting fan")
	bench.view.set_process(true)
	var first: CombatCard = bench.view.cards[bench.view.model.hand[0]]
	var point: Vector2 = first.get_global_transform() * Vector2(25, 25)
	get_window().grab_focus()
	await get_tree().process_frame
	for attempt in 4:
		get_viewport().warp_mouse(point)
		await get_tree().create_timer(0.05).timeout
		if bench.view.get_global_mouse_position().distance_to(point) < 2.0: break
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = motion.position
	FileAccess.open(output + "hand-pointer.json", FileAccess.WRITE).store_string(JSON.stringify({"expected":str(point), "actual":str(bench.view.get_global_mouse_position()), "rest":str(first.home), "resolved":bench.view.hand_at_pointer(), "expectedUid":first.uid,"screen":str(DisplayServer.screen_get_size()),"window":str(get_window().position),"nativeMouse":str(DisplayServer.mouse_get_position()),"viewportTransform":str(get_viewport().get_final_transform())}, "\t"))
	verify(bench.view.hand_at_pointer() == first.uid, "Raised footprint resolves at viewport synthetic pointer")
	await click_tool(point)
	verify(bench.view.selected_uid == first.uid, "Raised resting footprint accepts synthetic click")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	verify(bench.view.selected_uid.is_empty() and bench.view.model.hand.size() == count, "Escape cancels selection without consuming raised card")
	# Leave the pointer outside the fan so later overview screenshots show rest.
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(600, 220)
	motion.global_position = motion.position
	get_viewport().warp_mouse(Vector2(600, 220))
	get_viewport().push_input(motion, true)
	await settle(0.2)
	original.free()

func verify_workspace() -> void:
	verify(bench.profiles.scenes.size() == 10, "Ten backgrounds including alley are available")
	await bench.rebuild(3)
	bench.view.stage.phase_changed.connect(on_phase)
	var before: Dictionary = bench.view.model.snapshot()
	var original_alley: Dictionary = bench.settings.duplicate(true)
	bench.sliders.x.value = 37
	verify(bench.profiles.is_dirty() and bench.profile_state.text.contains("有未保存修改"), "Dirty draft is visibly marked")
	verify(bench.switch_scene("harbor"), "Switch to harbor")
	bench.sliders.saturation.value = 0
	bench.sliders.contrast.value = 0
	bench.sliders.scale.value = 0.61
	bench.sliders.brightness.value = 1.07
	verify(bench.profiles.unsaved_count() == 2, "Drafts are independent per location")
	verify(bench.switch_scene("alley") and is_equal_approx(bench.settings.x, 37), "Switching back retains alley draft")
	bench.restore_settings()
	verify(bench.settings == original_alley and not bench.profiles.is_dirty(), "Restore saved alley recovers confirmed parameters")
	bench.switch_scene("harbor")
	var save_key := InputEventKey.new()
	save_key.keycode = KEY_S
	save_key.ctrl_pressed = true
	save_key.pressed = true
	Input.parse_input_event(save_key)
	await settle()
	verify(bench.profiles.has_saved() and not bench.profiles.is_dirty(), "Ctrl+S saves current location and clears its dirty flag")
	var reader := Profiles.new()
	verify(reader.initialize(bench.profile_path) and reader.current_id == "harbor", "Fresh loader reads saved current location")
	verify(reader.current().saturation == 0 and reader.current().contrast == 0, "Zero-valued color parameters survive disk roundtrip")
	verify(is_equal_approx(reader.current().scale, 0.61) and is_equal_approx(reader.current().brightness, 1.07), "Slider fractional values survive disk roundtrip")
	bench.sliders.x.value = 12
	bench.reset_settings()
	verify(bench.profiles.is_dirty() and bench.settings == bench.DEFAULTS, "Restore initial remains unsaved when it differs from saved profile")
	bench.restore_settings()
	verify(bench.settings.saturation == 0 and bench.settings.contrast == 0, "Restore saved restores last saved color parameters")
	# Use neutral initial profiles for image/camera inspection, without overwriting saves.
	for record in bench.profiles.scenes:
		verify(bench.switch_scene(record.id), "Switch " + record.id)
		bench.reset_settings()
		verify(bench.SAMPLE.resource_path == record.image, "Correct texture " + record.id)
		verify(bench.view.model.snapshot() == before, "Background switch preserves combat snapshot " + record.id)
		verify_background(record.id + " wide")
		await shot("catalog-" + record.id + "-wide")
		await bench.preview_camera(true)
		verify_background(record.id + " near")
		await shot("catalog-" + record.id + "-near")
		await bench.preview_camera(false)
	bench.switch_scene("daylight_court")
	bench.view.select_card(bench.view.model.hand[0])
	await bench.view.play_selected(1)
	verify_background("daylight farthest attack")
	await shot("catalog-daylight_court-attack")
	await bench.view.end_turn_pressed()
	bench.switch_scene("church")
	bench.view.select_card(bench.view.model.hand[0])
	await bench.view.play_selected(1)
	verify_background("church farthest attack")
	await shot("catalog-church-attack")
	await bench.view.end_turn_pressed()
	bench.switch_scene("alley")
	bench.reset_settings()
	# A pending draft protects close/quit, and dialog cancellation leaves it untouched.
	bench.sliders.x.value = 5
	bench.request_close()
	verify(bench.close_dialog.visible, "Closing with unsaved drafts asks before discarding")
	bench.close_dialog.hide()
	bench.restore_settings()
	# Return to the panel and exercise the actual navigation buttons.
	bench.controls.show()
	bench.hint.show()
	await settle()
	for action in bench.action_buttons:
		if action.text == "›":
			await click_tool(action.get_global_rect().get_center())
			break
	verify(bench.profiles.current_id == "daylight_court", "Synthetic next button switches background")
	await click_tool(bench.scene_picker.get_global_rect().get_center())
	await settle()
	var popup: PopupMenu = bench.scene_picker.get_popup()
	verify(popup.visible and popup.item_count == 10, "Scene dropdown opens with ten locations")
	# Route through OptionButton's popup signal so selection and UI stay in sync.
	popup.index_pressed.emit(9)
	popup.hide()
	await settle()
	verify(bench.profiles.current_id == "church" and bench.scene_picker.selected == 9, "Dropdown selection updates scene and selected row")
	await shot("12-workbench-tools")
	verify(bench.controls.get_global_rect().end.y < 790, "Expanded tool panel fits above hand")
	await bench.capture_current()
	var capture_path: String = bench.feedback.tooltip_text
	verify(FileAccess.file_exists(capture_path) and FileAccess.file_exists(capture_path.trim_suffix(".png") + ".json"), "Capture writes image and matching parameter sidecar")
	var capture_info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(capture_path.trim_suffix(".png") + ".json"))
	verify(capture_info.scene == "church" and capture_info.settings == bench.settings, "Capture records active location and parameters")
	verify(bench.controls.visible and bench.hint.visible and not bench.capturing, "Capture restores tool visibility")

func _ready() -> void:
	output = "res://artifacts/qa/battle-background-preview-2026-10-16/%d/" % DisplayServer.window_get_size().x
	var arguments := OS.get_cmdline_user_args()
	var output_index := arguments.find("--output-dir")
	if output_index >= 0 and output_index + 1 < arguments.size():
		output = arguments[output_index + 1].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(120).timeout.connect(func():
		if not completed:
			push_error("PREVIEW CHECK timed out")
			get_tree().quit(2))
	bench = preload("res://tests/battle_background_preview.tscn").instantiate()
	bench.profile_path = output + "profiles.json"
	verify(DirAccess.copy_absolute(Profiles.DEFAULT_PATH, bench.profile_path) == OK, "QA uses isolated profile copy")
	# The user may save any starting location; this check begins with alley poses.
	# Normalize only the isolated copy, retaining all saved location parameters.
	var qa_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bench.profile_path))
	qa_profile.last_scene = "alley"
	FileAccess.open(bench.profile_path, FileAccess.WRITE).store_string(JSON.stringify(qa_profile, "\t"))
	add_child(bench)
	while not bench.ready_for_preview: await get_tree().process_frame
	verify(not Game.save_enabled and Game.training_mode, "Saving disabled; memory-only training")
	verify(Game.save_path.ends_with("battle_background_preview_unused.json"), "Accidental direct save has test-only path")
	verify(Game.training_backup.is_empty() and Game.state.combat.enemies.size() == 1, "Adventure not loaded")
	verify(bench.view.model.enemies.size() == 1 and bench.view.model.enemies[0].hp == 20, "Single 20HP test enemy")
	var stage: Control = bench.view.stage
	stage.phase_changed.connect(on_phase)
	verify(bench.settings == {"scale":0.53, "x":0.0, "y":-61.0, "brightness":1.05, "saturation":1.15, "contrast":0.92, "fade_start":610.0, "fade_strength":0.94, "rear_edge_ratio":0.46}, "User approved background parameters retained")
	verify_background("single wide")
	bench.sliders.y.value = 0
	var clip_rect: Rect2 = stage.get_parent().get_global_rect()
	var wall_point: Vector2 = bench.backdrop.to_global(bench.CAMERA_PADDING + Vector2(0, bench.SAMPLE.get_height() * bench.settings.rear_edge_ratio))
	verify(absf((wall_point.y - clip_rect.position.y) / clip_rect.size.y - 0.46) < 0.01, "Wide framing matches 46 percent building / 54 percent ground guide")
	bench.reset_settings()
	verify(is_equal_approx(bench.backdrop.material.get_shader_parameter("contrast"), 0.92), "Moderate contrast applied to artwork only")
	verify(stage.size == Vector2(1440, 420) and is_equal_approx(stage.player.home.x, 405), "Original camera dimensions and foot positions retained")
	verify(bench.backdrop.get_parent() == stage.world, "Artwork follows real battle camera")
	verify(not stage.world.get_child(1).visible and stage.world.get_child(0) == bench.backdrop, "Only instance floor hidden; sample behind actors")
	verify(stage.get_parent().clip_contents and not stage.clip_contents, "Extended clip contains artwork below HUD")
	verify(bench.controls.get_global_rect().end.y < 790, "Tool panel fits above hand")
	await shot("01-tools-single")
	for key in bench.sliders:
		var slider: HSlider = bench.sliders[key]
		slider.value = slider.min_value
		verify(is_equal_approx(bench.settings[key], slider.min_value), "Slider updates " + key)
	bench.reset_settings()
	verify(bench.settings == bench.DEFAULTS, "Reset restores all parameters")
	verify(is_equal_approx(bench.backdrop.material.get_shader_parameter("brightness"), bench.settings.brightness), "Brightness applied to artwork shader")
	var original_point: Vector2 = bench.backdrop.position
	bench.sliders.x.value = 80
	bench.sliders.y.value += 30
	verify(bench.backdrop.position.is_equal_approx(original_point + Vector2(80, 30)), "Artwork offset does not move feet")
	verify(stage.player.position == stage.player.home, "Fit settings leave actors untouched")
	bench.reset_settings()
	await click_tool(bench.guides_toggle.get_global_rect().get_center())
	verify(bench.guides.visible and bench.view.selected_uid.is_empty(), "Synthetic checkbox click toggles guides without battle input")
	await shot("02-guides")
	bench.guides_toggle.button_pressed = false
	# Exercise Tab through the input dispatcher, not just a visibility assignment.
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	await settle()
	verify(not bench.controls.visible and not bench.hint.visible, "Tab hides tools and hint")
	await shot("03-clean-single-wide")
	await verify_hand_trial()
	var snapshot: Dictionary = bench.view.model.snapshot()
	var fixed_ui: Rect2 = bench.view.end_button.get_global_rect()
	await bench.preview_camera(true)
	verify_background("single static near")
	verify(stage.zoom > 1.0 and bench.view.model.snapshot() == snapshot, "Near preview changes camera without combat mutation")
	for actor in stage.actors_root.get_children():
		verify(stage.get_parent().get_global_rect().has_point(stage.contact(actor)), "Static near preview retains standing actors")
	verify(bench.view.end_button.get_global_rect() == fixed_ui, "UI stays fixed during preview zoom")
	await shot("04-single-near")
	await bench.preview_camera(false)
	verify(is_equal_approx(stage.zoom, 1), "Wide preview restores camera")
	bench.view.select_card(bench.view.model.hand[0])
	await bench.view.play_selected(0)
	verify(bench.view.model.enemies[0].hp == 19 and not Game.battle_busy, "Real card and attack complete once")
	await shot("05-real-attack-near")
	await bench.view.end_turn_pressed()
	verify(bench.view.model.turn == 2 and bench.view.model.player_hp == 99, "Real enemy turn completes")
	verify(stage.player.position == stage.player.home and stage.enemies[0].position == stage.enemies[0].home, "Actors return to original feet")
	await bench.rebuild(3)
	stage = bench.view.stage
	stage.phase_changed.connect(on_phase)
	verify_background("three wide")
	verify(stage.enemies.size() == 3 and bench.view.model.enemies.size() == 3, "Three enemy rebuild uses production stage")
	verify(not Game.battle_busy and Game.save_enabled == false, "Rebuild retains save isolation")
	await shot("06-three-wide")
	await bench.preview_camera(true)
	verify_background("three static near")
	for actor in stage.actors_root.get_children():
		verify(stage.get_parent().get_global_rect().has_point(stage.contact(actor)), "Three-lane near preview retains actors")
	await shot("07-three-near")
	await bench.preview_camera(false)
	bench.view.select_card(bench.view.model.hand[0])
	await bench.view.play_selected(2)
	verify(bench.view.model.enemies[2].hp == 19, "Front depth lane receives real attack")
	bench.view.select_card(bench.view.model.hand[0])
	await bench.view.play_selected(1)
	verify(bench.view.model.enemies[1].hp == 19, "Farthest right enemy receives real attack")
	verify_background("farthest right attack")
	await shot("09-farthest-right-near")
	await bench.view.end_turn_pressed()
	verify(bench.view.model.player_hp == 97 and bench.view.model.hand.size() == 5, "Three enemies attack and next hand deals")
	for actor in stage.actors_root.get_children():
		verify(actor.position == actor.home, "Depth actor returns home")
	await shot("08-three-returned")
	# A finished training battle remains in this bench, never routes to story/menu.
	bench.view.model.enemies[0].hp = 1
	bench.view.model.enemies[1].hp = 0
	bench.view.model.enemies[2].hp = 0
	bench.view.select_card(bench.view.model.hand[0])
	await bench.view.play_selected(0)
	verify(bench.finished and Game.page == "battle" and Game.training_mode, "Victory stays in preview")
	await bench.rebuild(1)
	verify(not bench.finished and bench.view.model.enemies[0].hp == 20, "Rebuild after victory")
	bench.view.finish("surrender")
	verify(bench.finished and not bench.view.initialized and Game.training_mode, "Surrender freezes battle inside bench")
	await bench.rebuild(1)
	verify(bench.view.initialized and not bench.finished, "Rebuild after surrender")
	var previous_view_id: int = bench.view.get_instance_id()
	await click_tool(Vector2(1310, 181))
	while bench.rebuilding or not bench.ready_for_preview: await get_tree().process_frame
	verify(bench.view.get_instance_id() != previous_view_id and bench.view.initialized, "Top rebuild button stays in isolated bench")
	await verify_workspace()
	verify(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "No test save or meta file created")
	completed = true
	FileAccess.open(output + "result.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false,"syntheticToolKeyboard":true,"battleCalls":"real view methods"}, "\t"))
	print("BACKGROUND PREVIEW: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
