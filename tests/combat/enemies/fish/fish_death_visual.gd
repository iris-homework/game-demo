extends "res://tests/combat/cards/noren_cards_visual.gd"
const Rules = preload("res://tests/combat/enemies/fish/fish_rules_tests.gd")
var rules := Rules.new()
var kill_contacts: Array = []

func on_phase(phase: String) -> void:
	if phase == "impact" and app.view.stage.active_attacker == app.view.stage.player:
		kill_contacts.append([app.view.shown_enemies[0].hp, app.view.shown_player_pollution])

func install_fish() -> void:
	var m: CombatModel = rules.fish_fixture()
	Game.commit_combat(m)
	app.swap_view()
	await idle()
	app.view.stage.phase_changed.connect(on_phase)
	kill_contacts.clear()

func _ready() -> void:
	output = "res://artifacts/qa/enemy-round-death-2026-10-19/fish-death/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = "user://fish_death_visual_unused.json"
	Game.meta_path = "user://fish_death_visual_meta_unused.json"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B11")
	await idle()
	await install_fish()
	var view: Control = app.view
	check(view.targets[0].tooltip_text.contains("死亡时，向角色施加 3 层污染"), "Death passive tooltip is visible")
	view.model.enemies[0].hp = 6
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.refresh_enemy_hud()
	view.commit()
	view.select_card("card_000")
	check(view.model.buffs.count(view.model,"pollution") == 0 and view.shown_player_pollution == 0,"Lethal preview never applies pollution")
	await view.play_selected(0)
	await idle()
	check(kill_contacts == [[0,3]], "Lethal card contact shows three stacks immediately: " + str(kill_contacts))
	check(view.model.buffs.count(view.model,"pollution") == 3 and view.shown_player_pollution == 3,"Card death model and display agree")
	check(not view.stage.enemies[0].alive and view.stage.enemies[1].alive,"Only killed fish retires")
	await shot("card-kill-pollution-three")
	await install_fish()
	view = app.view
	view.model.enemies[0].hp = 1
	view.model.parry = 2
	view.model.block = 6
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.refresh_resources()
	view.refresh_enemy_hud()
	view.commit()
	await view.end_turn_pressed()
	await idle()
	check(kill_contacts == [[0,3]], "Parry death displays three before second fish acts: " + str(kill_contacts))
	check(view.shown_player_pollution == 6 and view.model.buffs.count(view.model,"pollution") == 6,"Parry death plus second fish intent totals six")
	await shot("parry-kill-pollution-six")
	await install_fish()
	view = app.view
	view.model.enemies[0].hp = 1
	view.model.enemies[0].intent = {"type":"wait","amount":0}
	view.model.buffs.apply(view.model,"pollution",1,0)
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.refresh_enemy_hud()
	view.commit()
	await view.end_turn_pressed()
	await idle()
	check(not view.stage.enemies[0].alive and view.shown_enemies[0].hp == 0,"Pollution lethal tick retires fish")
	check(view.shown_player_pollution == 6 and view.model.buffs.count(view.model,"pollution") == 6,"Status death effect displayed before normal continuation")
	await shot("status-kill-pollution-six")
	Game.finish_training("win")
	check(Game.state.currentHp == 100 and not Game.training_mode,"Training restores adventure")
	rules.fixtures.free()
	rules.free()
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("FISH DEATH VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
