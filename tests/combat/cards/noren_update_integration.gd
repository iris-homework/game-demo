extends "res://tests/combat/cards/noren_cards_visual.gd"
const Fixtures=preload("res://tests/combat/cards/noren_cards_tests.gd")

func _ready() -> void:
	Game.save_enabled=false
	Game.save_path="user://noren_update_integration_unused.json"
	Game.meta_path="user://noren_update_integration_meta_unused.json"
	output="res://artifacts/qa/noren-consolidation-2026-10-19/window/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state=Game.initial_state()
	Game.state.deck=["noren_40","noren_08","noren_13"]
	Game.page="menu"
	var adventure: Dictionary=Game.state.duplicate(true)
	var catalog: Dictionary=Game.card_catalog.duplicate(true)
	var order: Array=Game.library_cards().map(func(c): return c.id)
	app=preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await idle()
	Game.open_card_library()
	await idle()
	app.view.owned_only=false
	app.view.refresh_library()
	await get_tree().create_timer(0.35).timeout
	check(app.view.definitions.map(func(c): return c.id)==order and order.size()==40,"Actual all-cards library loads forty definitions in C B A S order")
	check(app.view.definitions.slice(0,4).all(func(c): return c.rarity=="C") and app.view.definitions.slice(36).all(func(c): return c.rarity=="S"),"C cards lead and S cards end the library")
	check(Game.state==adventure and Game.card_catalog==catalog,"Library ordering leaves adventure and catalogue unchanged")
	await shot("library-c-b")
	app.view.scroll.scroll_vertical=int(app.view.scroll.get_v_scroll_bar().max_value)
	await get_tree().create_timer(0.2).timeout
	await shot("library-a-s")
	app.view.close_library()
	await idle()
	app.open_card_console()
	await idle()
	check(app.card_console.card_buttons.keys()==order,"Actual console uses the same rarity order")
	check(Game.state==adventure,"Opening console does not add any cards")
	await shot("console-cbas")
	app.close_card_console()
	Game.start_training("B04")
	await idle()
	var frozen: Dictionary=app.view.model.snapshot()
	check(frozen.profile.ammoCap==10,"Fresh battle loads ten-ammo cap")
	check(frozen.cardCatalog.noren_03.effects.size()==2 and frozen.cardCatalog.noren_03.effects[0].type=="parry" and int(frozen.cardCatalog.noren_03.effects[0].amount)==1 and frozen.cardCatalog.noren_03.effects[1].type=="stance" and frozen.cardCatalog.noren_03.effects[1].value=="melee","Fresh battle loads revised Close In definition")
	check(app.view.resources_label.text.ends_with("2 / 10"),"Fresh battle HUD shows loaded ammo configuration")
	Game.open_current_deck()
	await idle()
	var expected_deck: Array=["noren_01","noren_02","noren_03","noren_04","noren_08","noren_13","noren_40"]
	check(is_instance_valid(app.deck_browser) and app.deck_browser.definitions.map(func(c): return c.id)==expected_deck,"Frozen current deck also follows C B A S")
	await shot("current-deck-cbas")
	app.close_current_deck()
	check(app.view.model.snapshot()==frozen and Game.state.combat==frozen,"Browsing never changes real draw order or frozen battle state")
	var fixtures:=Fixtures.new()
	var m:=fixtures.fixture([3],"ranged")
	var result: Dictionary=fixtures.play(m)
	check(m.parry==1 and m.block==0 and result.drawn.size()==2,"Loaded Close In grants parry and two-card melee entry")
	m=fixtures.fixture([35]);m.ammo=2;result=fixtures.play(m)
	check(m.ammo==5 and result.hits.size()==3,"Loaded new triple attack gains ammo per segment")
	m=fixtures.fixture([1]);m.parry=3;m.ammo=9
	var counters: Array=m.buffs.after_enemy_attack(m,0,12)
	check(counters.size()==1 and counters[0].damage==6 and m.ammo==10 and m.parry==2 and m.enemies[0].bleed==0,"Loaded parry uses one charge, half damage and one ammo without bleed")
	fixtures.free()
	Game.menu();await idle()
	check(Game.state==adventure and not Game.training_mode,"Integration training restores adventure")
	app.queue_free();app=null
	await get_tree().process_frame
	await get_tree().process_frame
	print("NOREN UPDATE INTEGRATION: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
