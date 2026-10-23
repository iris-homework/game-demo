extends Node
const Icons = preload("res://scripts/technology_icons.gd")
const OUTPUT := "res://artifacts/qa/passive-technologies-2026-10-24/icons"
var checks := 0
var failures: Array[String] = []
var original_state: Dictionary
var original_revision := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("TECHNOLOGY ICONS: " + message)

func stage(page: String = "map") -> void:
	Game.save_enabled = false
	Game.save_path = OUTPUT.path_join("checkpoint-test.json")
	Game.meta_path = OUTPUT.path_join("meta-test.json")
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.state = Game.initial_state()
	Game.state.currentScene = page
	Game.state.currentPlaceId = "mall" if page == "place" else "bar"
	Game.state.credits = 2000
	Game.page = page
	original_state = Game.state.duplicate(true)
	original_revision = Game.revision

func unchanged(label: String) -> void:
	check(Game.state == original_state and Game.revision == original_revision, label)

func check_icon(view: TextureRect, id: String, dimensions: Vector2, context: String) -> void:
	check(is_instance_valid(view), context + " icon node exists")
	if not is_instance_valid(view): return
	check(view.visible and view.texture == Icons.texture_for(id) and view.get_meta("technology_id") == id, context + " resolves correct shared texture by ID")
	check(view.size == dimensions and view.mouse_filter == Control.MOUSE_FILTER_IGNORE, context + " has intended art size and does not intercept input")
	var parent := view.get_parent() as Control
	check(Rect2(Vector2.ZERO,parent.size).encloses(view.get_rect()), context + " icon fits parent bounds")
	for sibling in parent.get_children():
		if sibling is Label and sibling.visible and not sibling.text.is_empty():
			check(not sibling.get_rect().intersects(view.get_rect()), context + " illustration does not overlap text: " + sibling.text)

func export_layout(root: Node, filename: String) -> void:
	var rows := []
	collect_layout(root,rows)
	var file := FileAccess.open(OUTPUT.path_join(filename + "-layout.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(rows,"\t")); file.close()

func collect_layout(node: Node, items: Array) -> void:
	# Hidden ancestors stop traversal, including empty-slot images.
	if node is Control and not node.is_visible_in_tree(): return
	if node is Control:
		var r: Rect2 = node.get_global_rect()
		var item := {"name":str(node.name),"type":node.get_class(),"x":r.position.x,"y":r.position.y,"w":r.size.x,"h":r.size.y}
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
			item.technology_id = node.get_meta("technology_id", "")
		if item.has("text") or item.has("fill") or item.has("image"): items.append(item)
	for child in node.get_children(): collect_layout(child,items)

func test_resolver() -> void:
	check(Icons.ids() == ["dimensional_pocket","accelerated_clock","backup_energy","money_chip","healing_chip","swift_chip"], "single mapping contains all six real technologies")
	for id in Icons.ids():
		var texture := Icons.texture_for(id)
		check(texture != null and texture.get_width() > 0 and texture.get_height() > 0, "real PNG loads: " + id)
		check(not Game.cyberware_definition(id).has("icon"), "ID resolver supports existing definitions without icon field: " + id)
	for id in ["", "UNKNOWN", "test_cyberware_01"]:
		check(Icons.texture_for(id) == null, "unmapped ID does not reuse another technology art: " + id)

func test_shop() -> void:
	stage("place")
	var shop = preload("res://scenes/technology_shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	var offers := Game.technology_shop_offers()
	check(offers.size() == 6 and offers.all(func(offer): return offer.price == 150), "shop lists six offers at 150")
	for i in 6:
		var tile: Control = shop.stock.get_node("technology_tile_%d" % i)
		check_icon(tile.get_node("technology_icon"),offers[i].id,Vector2(112,100),"shop " + offers[i].id)
		check(shop.stock.get_node("buy_slot_%d" % i).disabled == (i < 3), "only starter-owned offers disabled")
	unchanged("opening shop does not alter state")
	export_layout(shop,"shop")
	Game.state.ownedCyberwareIds = []
	Game.state.equippedCyberwareIds = []
	shop.refresh_stock()
	var before := Game.state.duplicate(true)
	var rev := Game.revision
	shop.open_purchase(0)
	check_icon(shop.modal.get_node("technology_icon"),offers[0].id,Vector2(174,174),"purchase confirmation")
	export_layout(shop,"shop_confirmation")
	shop.close_modal()
	check(Game.state == before and Game.revision == rev, "opening and cancelling purchase does not change state")
	shop.queue_free()
	await get_tree().process_frame

func test_loadout() -> void:
	stage()
	var view = preload("res://scripts/technology_loadout.gd").new()
	add_child(view)
	await get_tree().process_frame
	var ids := Game.equipped_cyberware_ids()
	for id in ids:
		check_icon(view.technology_buttons[id].get_node("technology_icon"),id,Vector2(96,96),"owned list " + id)
	for i in ids.size():
		check_icon(view.slot_buttons[i].get_node("technology_icon"),ids[i],Vector2(60,60),"equipped " + ids[i])
	check(not view.slot_buttons[3].get_node("technology_icon").visible and view.slot_buttons[3].disabled, "empty equipment slot has no visible icon")
	unchanged("opening loadout does not alter state")
	export_layout(view,"loadout")
	Game.save_enabled = true
	view.remove_slot(0)
	check(Game.equipped_cyberware_ids() == ids.slice(1), "unequip still commits selected order")
	check_icon(view.slot_buttons[0].get_node("technology_icon"),ids[1],Vector2(60,60),"shifted equipped slot")
	check(not view.slot_buttons[2].get_node("technology_icon").visible, "freed equipment slot clears prior icon")
	view.toggle_technology(ids[0])
	check(Game.equipped_cyberware_ids() == ids.slice(1) + [ids[0]], "equip still appends to next free slot")
	check_icon(view.slot_buttons[2].get_node("technology_icon"),ids[0],Vector2(60,60),"newly equipped slot")
	var saved := Game.state.duplicate(true)
	check(Game.load_game() and JSON.parse_string(JSON.stringify(Game.state)) == JSON.parse_string(JSON.stringify(saved)), "equipment changes persist to isolated save")
	view.queue_free()
	await get_tree().process_frame

func test_battle() -> void:
	stage("battle")
	Game.state.battleId = "B02"
	Game.initialize_combat()
	original_state = Game.state.duplicate(true)
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	var before := model.snapshot()
	var view = preload("res://scripts/combat/cyberware_view.gd").new()
	view.setup(model)
	add_child(view)
	await get_tree().process_frame
	for i in model.cyberware_cards().size():
		check_icon(view.card_buttons[i].get_node("technology_icon"),model.cyberware_cards()[i].id,Vector2(112,112),"battle " + str(i))
		check(view.card_buttons[i].size.y == 340, "battle card has enough illustration and text space")
	check(model.snapshot() == before, "opening technology panel preserves frozen combat")
	unchanged("opening battle panel does not change adventure")
	export_layout(view,"battle")
	var activations := []
	view.activation_requested.connect(func(id): activations.append(id); model.activate_cyberware(id); view.refresh())
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	view._input(key)
	check(activations == ["dimensional_pocket"] and model.cyberware_cooldown("dimensional_pocket") == 3, "numeric shortcut still activates technology once")
	check(view.card_buttons[0].disabled and view.state_labels[0].text.contains("3"), "activated technology remains disabled with actual cooldown")
	check(view.card_buttons[0].get_node("technology_icon").modulate.a < 1.0, "cooling technology art visually dims")
	view._input(key)
	check(activations.size() == 1, "disabled technology cannot retrigger shortcut")
	unchanged("panel activation signal does not directly commit adventure state")
	view.queue_free()
	await get_tree().process_frame
	model.profile.cyberware.cards = [Game.cyberware_definition("test_cyberware_01").duplicate(true)]
	model.profile.playerCyberwareIds = ["test_cyberware_01"]
	view = preload("res://scripts/combat/cyberware_view.gd").new()
	view.setup(model)
	add_child(view)
	await get_tree().process_frame
	check(not view.card_buttons[0].get_node("technology_icon").visible, "legacy snapshot placeholder remains unillustrated without borrowing real art")
	view.queue_free()
	await get_tree().process_frame

func test_archive() -> void:
	stage("menu")
	var meta: Dictionary = Game.meta_profile.duplicate(true)
	var view = preload("res://scenes/cyberware.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	for id in Icons.ids():
		check_icon(view.get_node("archive_" + id).get_node("technology_icon"),id,Vector2(120,120),"archive " + id)
	unchanged("archive only displays technologies without ownership or equipment changes")
	check(Game.meta_profile == meta and view.get_node("return_menu") is Button, "archive keeps meta untouched and retains menu return")
	export_layout(view,"archive")
	view.queue_free()
	await get_tree().process_frame


func test_passive_display() -> void:
	stage()
	var passives := ["money_chip","healing_chip","swift_chip"]
	Game.state.ownedCyberwareIds.append_array(passives)
	Game.state.equippedCyberwareIds = passives + ["backup_energy"]
	var loadout = preload("res://scripts/technology_loadout.gd").new()
	add_child(loadout)
	await get_tree().process_frame
	check(loadout.technology_buttons.size() == 6 and loadout.slot_buttons.size() == 4,"six owned technologies retain four equipped slots")
	for id in passives:
		check_icon(loadout.technology_buttons[id].get_node("technology_icon"),id,Vector2(96,96),"passive loadout " + id)
		var badges: Array = loadout.technology_buttons[id].find_children("*","Label",false,false)
		check(badges.any(func(l): return l.text == "被动 · 自动生效"),"passive loadout shows automatic label: " + id)
	loadout.queue_free()
	await get_tree().process_frame
	Game.state.currentScene = "battle"
	Game.state.activeEventId = "E02"
	Game.state.battleId = "B02"
	Game.initialize_combat()
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	var view = preload("res://scripts/combat/cyberware_view.gd").new()
	view.setup(model)
	add_child(view)
	await get_tree().process_frame
	var before := model.snapshot()
	var activations := []
	view.activation_requested.connect(func(id): activations.append(id); model.activate_cyberware(id); view.refresh())
	for i in 3:
		check_icon(view.card_buttons[i].get_node("technology_icon"),passives[i],Vector2(112,112),"passive battle " + passives[i])
		check(view.card_buttons[i].disabled and view.state_labels[i].text == "被动 · 无需激活","passive cannot activate")
		check(view.card_buttons[i].get_node("technology_icon").modulate == Color.WHITE,"passive art remains bright")
		check(not view.card_buttons[i].tooltip_text.contains("冷却"),"passive has no cooldown tooltip")
		view.card_buttons[i].pressed.emit()
		var key := InputEventKey.new()
		key.keycode = KEY_1 + i
		key.pressed = true
		view._input(key)
	check(activations.is_empty() and model.snapshot() == before,"passive click signals and shortcuts cannot mutate combat")
	check(view.status_label.text.contains("1 项主动科技"),"available counter excludes passives")
	export_layout(view,"passive_battle")
	view.card_buttons[3].pressed.emit()
	check(activations == ["backup_energy"] and model.cyberware_cooldown("backup_energy") == 3,"fourth active technology remains usable beside passives")
	view.queue_free()
	await get_tree().process_frame
	Game.state.currentScene = "result"
	Game.page = "result"
	Game.state.battleReward = {"status":"pending","credits":1000,"battleId":"B02","battleType":"normal"}
	Game.state.battlePassiveReward = {"eventId":"E02","battleId":"B02","credits":30,"healing":5}
	var state_before := Game.state.duplicate(true)
	var reward = preload("res://scripts/reward.gd").new()
	add_child(reward)
	await get_tree().process_frame
	var labels: Array = reward.find_children("passive_reward_summary","Label",true,false)
	check(labels.size() == 1 and labels[0].text.contains("+30 信用点") and labels[0].text.contains("+5 生命"),"reward displays actual passive proceeds")
	check(Game.state == state_before,"viewing passive settlement never grants reward again")
	export_layout(reward,"passive_reward")
	reward.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	stage()
	test_resolver()
	await test_shop()
	await test_loadout()
	await test_battle()
	await test_archive()
	await test_passive_display()
	Game.save_enabled = false
	var report := {"checks":checks,"failures":failures,"scope":"headless shared textures, all five display contexts, layout bounds and no text overlaps, loadout save, combat shortcut/cooldown and read-only archive; no rendered pixel or physical-input verification"}
	var file := FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("TECHNOLOGY ICONS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
