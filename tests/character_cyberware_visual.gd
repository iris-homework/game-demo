extends "res://tests/interaction_visual.gd"

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame

func open_battle(id: String) -> void:
	Game.new_game(id)
	await idle()
	Game.state.targetId = "richard"
	Game.state.activeEventId = "E04"
	Game.state.currentPlaceId = "alley"
	Game.enter_node("battle")
	await idle()

func _ready() -> void:
	Game.save_enabled = false
	output = ProjectSettings.globalize_path("res://artifacts/qa/character-cyberware-2026-10-11/roles_")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	var subset: Dictionary = Game.player_characters.noren.duplicate(true)
	subset.cyberwareIds = ["test_cyberware_05", "test_cyberware_02"]
	Game.player_characters.qa_subset = subset
	Game.characters.qa_subset = Game.characters.noren.duplicate(true)
	Game.characters.qa_subset.name = "科技子集测试角色"
	var empty: Dictionary = subset.duplicate(true)
	empty.cyberwareIds = []
	Game.player_characters.qa_empty = empty
	Game.characters.qa_empty = Game.characters.noren.duplicate(true)
	Game.characters.qa_empty.name = "无科技测试角色"
	await open_battle("qa_subset")
	var view = app.view
	verify(view.cyberware_button.text.contains("2/2"), "HUD uses role's two cyberware cards")
	await click(view.cyberware_button.get_rect().get_center())
	var overlay = view.pile_overlay
	verify(is_instance_valid(overlay) and overlay.card_buttons.size() == 2, "Only role's selected cards are rendered")
	verify(view.model.cyberware_cards()[0].id == "test_cyberware_05" and view.model.cyberware_cards()[1].id == "test_cyberware_02", "UI follows role's configured order")
	await key(KEY_3)
	verify(view.model.next_attack_bonus == 0, "Unassigned third shortcut has no effect")
	await key(KEY_1)
	verify(view.model.used_cyberware == ["test_cyberware_05"] and overlay.card_buttons[0].disabled, "First shortcut activates assigned fifth catalog item")
	await key(KEY_2)
	verify(view.model.next_attack_bonus == 2 and overlay.card_buttons[1].disabled, "Second assigned card stacks existing effect")
	view.activate_cyberware("test_cyberware_01")
	verify(view.model.next_attack_bonus == 2, "Unassigned catalog card cannot activate")
	await motion(Vector2(80,180))
	await shot("subset")
	await key(KEY_ESCAPE)
	verify(not is_instance_valid(view.pile_overlay) and view.cyberware_button.text.contains("0/2"), "Closing retains role-specific cooldown count")
	await open_battle("qa_empty")
	view = app.view
	verify(view.cyberware_button.text.contains("0/0"), "Empty role has no implicit six-card loadout")
	await click(view.cyberware_button.get_rect().get_center())
	overlay = view.pile_overlay
	verify(is_instance_valid(overlay) and overlay.card_buttons.is_empty(), "Empty role still opens informative overlay")
	var found_empty_text := false
	for child in overlay.get_children():
		if child is Label and child.text == "当前角色没有可激活科技":
			found_empty_text = true
	verify(found_empty_text, "Empty overlay explains missing loadout")
	await key(KEY_1)
	await key(KEY_6)
	verify(view.model.next_attack_bonus == 0 and view.model.used_cyberware.is_empty(), "Empty role shortcuts cannot activate shared catalog")
	await motion(Vector2(80,180))
	await shot("empty")
	await key(KEY_ESCAPE)
	verify(not is_instance_valid(view.pile_overlay), "Empty overlay exits normally")
	await open_battle("noren")
	view = app.view
	await click(view.cyberware_button.get_rect().get_center())
	verify(view.pile_overlay.card_buttons.size() == 6 and view.cyberware_button.text.contains("6/6"), "Noren's six-card loadout remains intact after other roles")
	await motion(Vector2(80,180))
	await shot("noren")
	for id in ["qa_subset", "qa_empty"]:
		Game.player_characters.erase(id)
		Game.characters.erase(id)
	print("CHARACTER CYBERWARE VISUAL: %d checks, %d failures; %s" % [checks, failures, output])
	get_tree().quit(0 if failures == 0 else 1)
