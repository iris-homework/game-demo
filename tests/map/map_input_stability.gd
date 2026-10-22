extends "res://tests/map/map_zoom_visual.gd"

func _ready() -> void:
	output_dir = "res://artifacts/qa/map-input-fix-2026-10-11/stability"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--output-dir" and i + 1 < args.size(): output_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	Game.save_enabled = false
	Game.save_path = output_dir.path_join("checkpoint.json")
	Game.meta_path = output_dir.path_join("meta.json")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await stage()
	var view = app.view
	await motion(view.get_marker_center("church"))
	await settle(0.2)
	check(view._hovered_id == "church", "initial pointer hover")
	view._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await settle(0.2)
	check(view._hovered_id.is_empty() and not view.markers.church.is_hovered(), "focus loss clears hover and keeps it cleared")
	view._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await motion(view.get_marker_center("hive"))
	await settle(0.2)
	check(view._hovered_id == "hive", "focus return uses fresh pointer")
	app.toggle_debug()
	await settle(0.2)
	check(view._hovered_id.is_empty(), "debug overlay clears underlying hover")
	await click(view.get_marker_center("bar"))
	check(view.selected_id.is_empty(), "debug overlay blocks selection")
	app.toggle_debug()
	await motion(view.get_marker_center("church"))
	view.show_weeks()
	await settle(0.2)
	check(view._hovered_id.is_empty(), "week modal clears underlying hover")
	await press_escape()
	await click(view.get_marker_center("hive"))
	check(view.selected_id == "hive", "click works after closing modal")
	await motion(view.detail.get_global_rect().get_center())
	await settle(0.2)
	check(view._hovered_id.is_empty(), "detail does not leave stale hover on covered map")
	view.close_detail()
	for zoom in [1.0, 1.5]:
		for cycle in range(3):
			for place in Game.places:
				view.close_detail()
				view.set_map_zoom(1.0)
				view.set_map_zoom(zoom, view.get_marker_center(place.id))
				await motion(view.get_marker_center(place.id))
				await settle(0.18)
				check(view._hovered_id == place.id and view.markers[place.id].is_hovered(), "hover %s zoom %.1f cycle %d" % [place.id, zoom, cycle])
				await click(view.get_marker_center(place.id))
				check(view.selected_id == place.id, "click %s zoom %.1f cycle %d" % [place.id, zoom, cycle])
	view.close_detail()
	view.set_map_zoom(1.0)
	view.set_map_zoom(1.1)
	var magnify := InputEventMagnifyGesture.new()
	magnify.position = Vector2(700,700)
	magnify.factor = 1.2
	dispatch_input(magnify)
	await get_tree().process_frame
	check(is_equal_approx(view.zoom_level, 1.32), "one magnify gesture applies exactly once")
	magnify.factor = 2.0
	dispatch_input(magnify)
	await get_tree().process_frame
	check(is_equal_approx(view.zoom_level, 1.5), "magnify clamps to 150 percent")
	var before: Vector2 = view._pan
	var pan := InputEventPanGesture.new()
	pan.position = Vector2(700,700)
	pan.delta = Vector2.ONE
	dispatch_input(pan)
	await get_tree().process_frame
	check(view._pan.distance_to(before - Vector2(24,24)) < 0.01, "one pan gesture applies exactly once")
	await shot("final-input-state")
	FileAccess.open(output_dir.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(input_records,"\t"))
	print("MAP INPUT STABILITY: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
