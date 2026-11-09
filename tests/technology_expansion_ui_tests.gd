extends Node
## Catalog paging, actual trade indices, long text and per-turn badges in isolated QA.
const Icons = preload("res://scripts/technology_icons.gd")
const NEW_IDS := ["emergency_forcefield","folding_magazine","purification_filter","phase_plating","recycling_protocol","counter_calibrator"]
var checks := 0
var failures: Array[String] = []
var output := ""
var captures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("TECHNOLOGY EXPANSION UI: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await settle()
	RenderingServer.force_draw()
	var path := output.path_join(name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK,"GPU capture " + name)
	captures.append(path)

func fits(parent: Control, context: String) -> void:
	for child in parent.get_children():
		if child is Label:
			check(child.get_rect().end.y <= parent.size.y and child.get_rect().end.x <= parent.size.x, context + " text stays within card: " + child.text)
			check(child.get_line_count()*child.get_line_height() <= child.size.y, context + " text fits allocated height: " + child.text)

func _ready() -> void:
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("Requires isolated QA user directory and absolute QA_OUT_DIR")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = true
	Game.save_path = output.path_join("catalog-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	Game.state = Game.initial_state()
	Game.state.currentScene = "place"
	Game.state.currentPlaceId = "mall"
	Game.state.credits = 2000
	Game.page = "place"
	var before: Dictionary = Game.state.duplicate(true)
	var shop = preload("res://scenes/technology_shop.tscn").instantiate()
	add_child(shop)
	await settle()
	check(Icons.ids().size() == 12 and Game.technology_shop_offers().size() == 12,"Twelve real technologies share the archive and shop")
	check(shop.stock.get_node("previous_page").disabled and not shop.stock.get_node("next_page").disabled,"First page has correct navigation")
	await shot("shop-page-1")
	shop.stock.get_node("next_page").pressed.emit()
	await settle()
	check(shop.page_index == 1 and not shop.stock.get_node("previous_page").disabled and shop.stock.get_node("next_page").disabled,"Second page has correct navigation")
	check(Game.state == before,"Paging has no adventure side effects")
	for i in range(6,12):
		var tile: Control = shop.stock.get_node("technology_tile_%d" % i)
		check(tile.get_node("technology_icon").get_meta("technology_id") == NEW_IDS[i-6],"Second page uses absolute offer index " + str(i))
		check(not shop.stock.get_node("buy_slot_%d" % i).disabled,"Each new technology is purchasable")
		fits(tile,"Shop " + NEW_IDS[i-6])
		shop.open_purchase(i)
		check(is_instance_valid(shop.modal),"Each new technology opens its own confirmation")
		for b in shop.find_children("*","Button",true,false):
			if not shop.modal.is_ancestor_of(b): check(b.disabled and b.focus_mode == Control.FOCUS_NONE,"Modal suspends background navigation and purchases")
		shop.change_page(-1)
		check(shop.page_index == 1,"Modal blocks page changes")
		shop.close_modal()
	await shot("shop-page-2")
	shop.open_purchase(8)
	await shot("purification-confirmation")
	shop.close_modal()
	shop.open_purchase(11)
	shop.modal.get_node("confirm_trade").pressed.emit()
	await settle()
	check(Game.state.credits == 1875 and Game.owned_cyberware_ids() == ["counter_calibrator"] and Game.equipped_cyberware_ids() == ["counter_calibrator"],"Second-page purchase acquires selected technology, charges once and auto equips")
	check(shop.page_index == 1 and shop.stock.get_node("buy_slot_11").disabled,"Purchase retains page and disables correct absolute offer")
	check(Game.load_game() and Game.owned_cyberware_ids() == ["counter_calibrator"],"Second-page purchase persists through actual isolated save reload")
	shop.queue_free()
	await settle()
	Game.state.ownedCyberwareIds = Icons.ids()
	Game.state.equippedCyberwareIds = NEW_IDS.slice(0,4)
	Game.state.currentScene = "map"
	Game.page = "map"
	var loadout = preload("res://scripts/technology_loadout.gd").new()
	add_child(loadout)
	await settle()
	check(loadout.technology_buttons.size() == 12 and loadout.slot_buttons.size() == 4,"All twelve owned technologies retain four equipped slots")
	for id in Icons.ids(): fits(loadout.technology_buttons[id],"Loadout " + id)
	var scroll: ScrollContainer = loadout.find_children("*","ScrollContainer",true,false)[0]
	scroll.scroll_vertical = 100000
	await settle()
	check(scroll.scroll_vertical > 0,"Owned list scrolls to additional technology rows")
	await shot("loadout-last-row")
	loadout.queue_free()
	await settle()
	Game.page = "cyberware"
	before = Game.state.duplicate(true)
	var meta_before: Dictionary = Game.meta_profile.duplicate(true)
	var archive = preload("res://scenes/cyberware.tscn").instantiate()
	add_child(archive)
	await settle()
	await shot("archive-page-1")
	archive.change_page(1)
	await settle()
	for id in NEW_IDS: fits(archive.catalog.get_node("archive_" + id),"Archive " + id)
	check(Game.state == before and Game.meta_profile == meta_before,"Archive paging remains read only")
	await shot("archive-page-2")
	archive.queue_free()
	await settle()
	Game.state.currentScene = "battle"
	Game.page = "battle"
	Game.state.battleId = "B02"
	Game.state.equippedCyberwareIds = NEW_IDS.slice(2,6)
	Game.initialize_combat()
	var model := CombatModel.new()
	model.restore(Game.state.combat)
	var view = preload("res://scripts/combat/cyberware_view.gd").new()
	view.setup(model)
	add_child(view)
	await settle()
	for b in view.card_buttons: fits(b,"Battle technology")
	for i in range(1,4): check(view.state_labels[i].text == "本回合待触发" and view.card_buttons[i].disabled,"New passive shows unused per-turn opportunity and cannot manually activate")
	check(model.activate_cyberware("purification_filter") and model.cyberware_cooldown("purification_filter") == 999,"Purification filter uses requested real 999 cooldown")
	model.technology_turn_state = {"stanceBlockUsed":true,"exhaustDrawUsed":true,"firstAttackUsed":true}
	var model_before := model.snapshot()
	view.refresh()
	for i in range(1,4): check(view.state_labels[i].text == "本回合已结算","New passive shows spent opportunity")
	check(model.snapshot() == model_before,"Per-turn status display never mutates model")
	await shot("battle-new-passives-and-cleanse-cooldown")
	view.queue_free()
	await settle()
	Game.save_enabled = false
	var report := {"checks":checks,"failures":failures,"captures":captures,"physicalInput":false,"scope":"Real controls, pagination, absolute-index trade/save/reload, modal isolation, owned scroll, text geometry, passive status; GPU captures only when display is available"}
	var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("TECHNOLOGY EXPANSION UI: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
