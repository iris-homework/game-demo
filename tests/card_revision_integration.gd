extends "res://tests/noren_cards_visual.gd"

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://card_revision_unused.json"
	Game.meta_path = "user://card_revision_meta_unused.json"
	Game.state = Game.initial_state()
	output = "res://artifacts/qa/current-integration-2026-10-20/card-revision-window/"
	DirAccess.make_dir_recursive_absolute(output)
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	for number in [4,11,19]:
		await install_hand([number])
		var view = app.view
		view.select_card("card_000")
		view.play_selected(0)
		await idle()
		match number:
			4: check(view.model.block == 6 and view.model.stance == "ranged" and view.shown_player_block == 6,"Pull Away gives six block in model and HUD")
			11: check(view.model.block == 8 and view.model.ammo == 3 and view.shown_player_block == 8,"Hold Ground gives eight block and melee ammo")
			19: check(view.model.enemies[0].hp == 113 and view.model.enemies[0].weak == 2 and view.shown_enemies[0].weak == 2,"Suppressive Fire deals seven and applies two weakness in model and HUD")
	await install_hand([12,2,1,23])
	var view = app.view
	var before: Dictionary = view.model.snapshot().duplicate(true)
	view.select_card("card_000")
	view.play_selected(-1)
	check(is_instance_valid(view.pile_overlay) and view.pile_overlay.options.map(func(item): return item.value) == ["card_001","card_002","card_003"],"Picker includes skill, attack and power, excluding resolving card")
	check(view.pile_overlay.heading == "选择消耗另一张手牌" and view.model.snapshot() == before,"Picker describes exhaustion and opens without mutation")
	await shot("01-exhaust-any-card-picker")
	view.close_pile()
	check(view.selected_uid == "card_000" and view.model.snapshot() == before,"Cancel leaves card selected and all resources untouched")
	view.play_selected(-1)
	view.pile_overlay.picked.emit("card_001")
	var committed: Dictionary = view.model.snapshot().duplicate(true)
	await idle()
	check(view.model.exhaust_pile == ["card_001"] and view.model.discard_pile == ["card_000"],"Selected skill exhausted; Dismantle itself goes to discard")
	check(view.model.ammo == 4 and view.model.energy == 3 and view.model.hand == ["card_002","card_003"],"Dismantle gains two ammo once at zero energy cost")
	check(view.cards.size() == 2 and not view.cards.has("card_001") and not view.cards.has("card_000"),"Both retired hand visuals disappear and remaining hand realigns")
	check(view.model.snapshot() == committed and Game.state.combat == committed,"Animations do not repeat model or snapshot changes")
	await shot("02-selected-skill-exhausted")
	for other in [23,12]:
		await install_hand([12,other])
		view = app.view
		view.select_card("card_000")
		view.play_selected(-1)
		view.pile_overlay.picked.emit("card_001")
		await idle()
		check(view.model.exhaust_pile == ["card_001"] and view.model.discard_pile == ["card_000"] and view.model.powers.is_empty() and view.model.ammo == 4,"Can exhaust power or duplicate instance without playing its effects")
	await install_hand([12])
	view = app.view
	before = view.model.snapshot().duplicate(true)
	view.select_card("card_000")
	check(view.selected_uid.is_empty() and not is_instance_valid(view.pile_overlay) and view.model.snapshot() == before,"Only Dismantle in hand cannot select itself or mutate state")
	Game.finish_training("lose")
	await idle()
	check(Game.state == Game.initial_state() and not Game.training_mode,"Training restores original adventure")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false},"\t"))
	print("CARD REVISION INTEGRATION: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
