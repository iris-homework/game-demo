extends Node
const OUT := "res://artifacts/qa/passive-technologies-2026-10-24/shop-ui/"
var checks := 0
var failures: Array = []
var app: Control

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		push_error(detail)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		get_viewport().push_input(event,true)
	await settle()

func export_layout(node: Node, items: Array) -> void:
	# Layout evidence from real controls; a browser preview is not a Godot screenshot.
	if node is Control and node.visible:
		var r: Rect2 = node.get_global_rect()
		var item := {"type":node.get_class(),"x":r.position.x,"y":r.position.y,"w":r.size.x,"h":r.size.y}
		if node is Label or node is Button:
			item.text = node.text
			item.fontSize = node.get_theme_font_size("font_size")
			item.color = "#"+node.get_theme_color("font_disabled_color" if node is Button and node.disabled else "font_color").to_html()
			item.align = node.horizontal_alignment if node is Label else node.alignment
			item.valign = node.vertical_alignment if node is Label else 1
		if node is ColorRect: item.fill = "#"+node.color.to_html()
		if node is Panel or node is Button:
			var stylebox = node.get_theme_stylebox("panel" if node is Panel else "disabled" if node.disabled else "normal")
			if stylebox is StyleBoxFlat:
				item.fill = "#"+stylebox.bg_color.to_html()
				item.border = "#"+stylebox.border_color.to_html()
		if node is TextureRect and node.texture:
			item.image = ProjectSettings.globalize_path(node.texture.resource_path)
			item.cover = node.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if item.has("text") or item.has("fill") or item.has("image"): items.append(item)
	for child in node.get_children(): export_layout(child,items)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Game.save_enabled = false
	Game.save_path = OUT+"ui-checkpoint.json"
	Game.meta_path = OUT+"ui-meta.json"
	Game.state = Game.initial_state()
	Game.state.credits = 1000
	Game.state.currentScene = "map"
	Game.page = "map"
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.visit("mall")
	await settle()
	var view = app.view
	var layout: Array = []
	export_layout(view,layout)
	var layout_file := FileAccess.open(OUT+"layout.json",FileAccess.WRITE)
	layout_file.store_string(JSON.stringify(layout,"\t"))
	layout_file.close()
	check(view.get_script().resource_path.ends_with("technology_shop.gd"),"Real main routes mall to shop")
	check(Game.texture("woss_mall_shop") != null,"Mall background imported")
	check(view.stock.find_children("buy_slot_*","Button",true,false).size() == 6,"All six implemented technologies offered")
	for i in 6:
		var tile: Panel = view.stock.get_node("technology_tile_%d" % i)
		check(tile.position == Vector2(484+(i%3)*304,202+floori(float(i)/3)*302),"Three columns and two rows %d" % i)
		check(tile.get_rect().end.x <= 1380 and tile.get_rect().end.y <= 786,"Tile fits storefront %d" % i)
		for child in tile.get_children():
			if child is TextureRect: check(child.texture != null,"Product icon available %d" % i)
			if child is Label: check(child.get_rect().end.x <= tile.size.x and child.get_rect().end.y <= 238,"Product labels stay above button %d" % i)
	for i in range(3,6):
		check(not view.stock.get_node("buy_slot_%d" % i).disabled,"Unowned passive technology can be purchased")
		view.open_purchase(i)
		check(is_instance_valid(view.modal),"Passive technology opens purchase confirmation")
		view.close_modal()
		check(Game.state.credits == 1000,"Cancel passive purchase preserves money")
	for i in 3:
		check(view.stock.get_node("buy_slot_%d" % i).disabled,"Default character already owns existing technology")
	view.open_purchase(0)
	check(not is_instance_valid(view.modal),"Starter technology cannot be bought twice")
	# Isolated purchase fixture; production defaults and saves remain unchanged.
	Game.state.ownedCyberwareIds = []
	Game.state.equippedCyberwareIds = []
	view.refresh_stock()
	view.open_purchase(0)
	await settle()
	check(is_instance_valid(view.modal),"Purchase opens modal for unowned technology")
	check(Game.state.credits == 1000,"Opening modal does not spend")
	check(view.modal.get_node("cancel_trade").has_focus(),"Cancel has initial focus")
	for b in view.stock.find_children("*","Button",true,false):
		check(b.disabled and b.focus_mode == Control.FOCUS_NONE,"Background purchases suspended")
	for i in 5:
		await key(KEY_TAB)
		check(view.modal.is_ancestor_of(get_viewport().gui_get_focus_owner()),"Focus trapped in modal")
	await key(KEY_F1)
	check(not is_instance_valid(app.debug_panel),"Modal blocks debug overlay")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(view.modal) and Game.page == "place","Escape cancels before exiting")
	check(Game.state.credits == 1000,"Cancellation preserves money")
	view.open_purchase(0)
	view.modal.get_node("confirm_trade").pressed.emit()
	await settle()
	check(Game.state.credits == 850,"Confirm charges configured price once")
	check(Game.owned_cyberware_ids().has("dimensional_pocket"),"Purchased technology owned")
	check(not Game.equipped_cyberware_ids().has("dimensional_pocket"),"Purchase does not silently equip")
	check(view.stock.get_node("buy_slot_0").disabled,"Owned purchase disabled")
	check(view.credits_label.text == "850","HUD balance refreshed")
	view.open_purchase(0)
	check(not is_instance_valid(view.modal),"Owned offer cannot reopen")
	Game.state.credits = 0
	view.refresh_stock()
	for b in view.stock.find_children("buy_slot_*","Button",true,false):
		check(b.disabled,"Insufficient funds disable purchase")
	Game.state.credits = 1000
	view.refresh_stock()
	view.open_purchase(1)
	Game.revision += 1
	view.modal.get_node("confirm_trade").pressed.emit()
	await settle()
	check(Game.state.credits == 1000 and not Game.owned_cyberware_ids().has("accelerated_clock"),"Stale confirmation cannot transact")
	await key(KEY_ESCAPE)
	check(Game.page == "map","Escape exits shop to map")
	Game.visit("mall")
	await settle()
	check(app.view.stock.get_node("buy_slot_0").disabled,"Re-entry preserves ownership")
	app.view.get_node("return_map").pressed.emit()
	await settle()
	check(Game.page == "map","Exit button returns to map")
	Game.visit("market")
	await settle()
	check(app.view.get_script().resource_path.ends_with("black_market.gd"),"Black-market routing retained")
	app.queue_free()
	await settle()
	var report := {"checks":checks,"failures":failures,"headless":true,"physicalInput":false,"pixelReview":false}
	var file := FileAccess.open(OUT+"ui-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("TECHNOLOGY_SHOP_UI_RESULT "+JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
