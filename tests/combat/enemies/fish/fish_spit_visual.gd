extends "res://tests/combat/cards/noren_cards_visual.gd"
const Spit = preload("res://scripts/combat/pollution_spit_fx.gd")
const Rules = preload("res://tests/combat/enemies/fish/fish_rules_tests.gd")
var rules := Rules.new()
var flights := 0
var splashes := 0
var contacts := 0
var scenario := "opening"
var before_contact := 0
var flight_snapshot: Dictionary = {}

func capture(name: String) -> void:
	if DisplayServer.get_name() != "headless": await shot(name)

func on_effect(node: Node) -> void:
	if node.get_script() != Spit: return
	if node.flight_time > 0: flights += 1
	else: splashes += 1
	check(Game.battle_busy,"Spit starts while combat input is locked")
	check(node.target_actor == app.view.stage.player,"Green water targets the player")
	check(node.start.distance_to(app.view.stage.world.to_local(app.view.stage.active_attacker.sprite.to_global(Vector2(150,610)))) < 0.1,"Liquid starts at transformed fish mouth")
	node.impacted.connect(func(): contacts += 1)
	if scenario == "opening" and node.flight_time > 0:
		await get_tree().create_timer(0.14).timeout
		await capture("01-green-water-flight")

func on_phase(value: String) -> void:
	var view = app.view
	if value == "spit_flight":
		before_contact = view.shown_player_pollution
		flight_snapshot = view.model.snapshot()
		check(view.stage.active_attacker.pose == "bite","Fish holds open-mouth pose while spitting")
		for actor in [view.stage.active_attacker,view.stage.player]:
			check(view.stage.get_global_rect().has_point(view.stage.contact(actor)),"Spitting fish and target both remain in frame")
	if value == "spit_impact":
		check(view.shown_player_pollution == before_contact+3,"Active pollution display advances on green-water contact")
		check(view.model.snapshot() == flight_snapshot,"Flight and contact do not apply model effects twice")
		check(view.stage.player.pose in ["damaged","gun_damaged"],"Player uses stance-specific hit pose")
		if scenario == "opening":
			await get_tree().create_timer(0.07).timeout
			await capture("02-green-water-splash")

func connect_view() -> void:
	app.view.stage.world.child_entered_tree.connect(on_effect)
	app.view.stage.phase_changed.connect(on_phase)
	flights = 0
	splashes = 0
	contacts = 0

func fixture() -> void:
	Game.commit_combat(rules.fish_fixture())
	app.swap_view()
	await idle()
	connect_view()

func cleared() -> void:
	await get_tree().process_frame
	check(get_tree().get_nodes_in_group("pollution_spit_fx").is_empty(),"All green-water nodes released before next interaction")
	check(not Game.battle_busy,"Combat unlocks after effects and next hand")
	for actor in app.view.stage.actors_root.get_children():
		if actor.alive: check(actor.modulate == Color.WHITE and actor.sprite.modulate == Color.WHITE,"No residual green tint or hidden survivor")

func _ready() -> void:
	output = "res://artifacts/qa/enemy-round-death-2026-10-19/fish-spit/"+("headless/" if DisplayServer.get_name() == "headless" else "render/")
	DirAccess.make_dir_recursive_absolute(output)
	Game.save_enabled = false
	Game.save_path = "user://fish_spit_unused.json"
	Game.meta_path = "user://fish_spit_meta_unused.json"
	Game.state = Game.initial_state()
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(2))
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B11")
	await idle()
	connect_view()
	await app.view.end_turn_pressed()
	check(flights == 1 and splashes == 1 and contacts == 2,"Opening: one bite splash and one active spit, each contacts once")
	check(app.view.model.player_hp == 94 and app.view.shown_player_pollution == 5,"Opening damage and three-stack intent")
	await cleared()
	await capture("03-next-turn")
	scenario = "multihit"
	flights = 0
	splashes = 0
	contacts = 0
	await app.view.end_turn_pressed()
	check(flights == 0 and splashes == 3 and contacts == 3,"Each damaging segment gets one splash; status tick gets none")
	check(app.view.model.player_hp == 79 and app.view.shown_player_pollution == 10,"Second turn damage and stacks reflect three-stack intent")
	await cleared()
	scenario = "blocked"
	await fixture()
	app.view.model.block = 100
	app.view.refresh_resources()
	app.view.commit()
	await app.view.end_turn_pressed()
	check(flights == 1 and splashes == 0 and contacts == 1,"Fully blocked bite has no pollution splash; active spit still plays")
	check(app.view.model.player_hp == 100 and app.view.shown_player_pollution == 3,"Active status bypasses block without direct damage")
	await cleared()
	scenario = "ranged"
	await fixture()
	app.view.model.stance = "ranged"
	app.view.stage.player.set_combat_stance("ranged")
	app.view.model.enemies[0].intent = {"type":"pollution","amount":3}
	app.view.shown_enemies = app.view.model.enemies.duplicate(true)
	# The second fish spits from the player's left, exercising mirrored mouth anchoring.
	app.view.stage.enemies[1].position.x = 200
	app.view.refresh_resources()
	app.view.commit()
	await app.view.end_turn_pressed()
	check(flights == 2 and splashes == 0 and contacts == 2,"Both fish actively spit, including a mirrored source")
	check(app.view.model.player_hp == 100 and app.view.shown_player_pollution == 6,"Status-only spits do not inflict immediate damage")
	check(app.view.stage.player.pose == "gun_idle","Ranged player returns to armed idle")
	await cleared()
	scenario = "death"
	await fixture()
	app.view.model.enemies[0].hp = 6
	app.view.shown_enemies = app.view.model.enemies.duplicate(true)
	app.view.refresh_enemy_hud()
	app.view.commit()
	app.view.select_card("card_000")
	await app.view.play_selected(0)
	check(flights == 0 and splashes == 0 and contacts == 0,"Death pollution never spawns green-water effects")
	check(app.view.shown_player_pollution == 3 and not app.view.stage.enemies[0].alive,"Death still applies three stacks exactly once")
	await cleared()
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false},"\t"))
	rules.fixtures.free()
	rules.free()
	print("FISH SPIT: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
