extends Node
## Presentation randomization and one real four-hit card; no saves or physical input.
const Battle = preload("res://scripts/battle.gd")
var app: Control
var checks := 0
var failures := 0
var impact_poses: Array[String] = []
var committed_snapshot: Dictionary = {}
var selected_style := ""
var expected_rng_state := 0

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func idle() -> void:
	var started := Time.get_ticks_msec()
	while Game.battle_busy or Game.transition_locked:
		await get_tree().process_frame
		if Time.get_ticks_msec()-started > 20000:
			push_error("Random melee playback timed out")
			get_tree().quit(2)
			return
	await get_tree().process_frame
	await get_tree().process_frame

func selector_checks() -> void:
	var view = Battle.new()
	var melee := {"stance":"melee","hits":[{"damage":1}]}
	Game.training_mode = false
	view.melee_animation_rng.seed = 20261018
	var first: Array[String] = []
	for i in 512:
		first.append(view.choose_player_attack_style({},melee))
	view.melee_animation_rng.seed = 20261018
	var repeated: Array[String] = []
	for i in 512:
		repeated.append(view.choose_player_attack_style({},melee))
	check(first == repeated,"Fixed local seed reproduces all 512 motion choices")
	check(first.has("slash") and first.has("pierce"),"Seeded sample includes both melee motions")
	check(first.all(func(style): return style in ["slash","pierce"]),"Unspecified melee uses only supported motions")
	seed(6192026)
	var expected_global: Array[int] = []
	for i in 8: expected_global.append(randi())
	seed(6192026)
	for i in 512: view.choose_player_attack_style({},melee)
	var actual_global: Array[int] = []
	for i in 8: actual_global.append(randi())
	check(actual_global == expected_global,"Visual choice leaves global random stream untouched")
	var before: int = view.melee_animation_rng.state
	check(view.choose_player_attack_style({}, {"stance":"melee","hits":[]}) == "slash","No-hit card keeps harmless default motion")
	check(view.melee_animation_rng.state == before,"No-hit card consumes no local random draw")
	check(view.choose_player_attack_style({"animation":"pierce"},melee) == "pierce","Explicit authored pierce is preserved")
	check(view.choose_player_attack_style({"animation":"slash"},melee) == "slash","Explicit authored slash is preserved")
	check(view.melee_animation_rng.state == before,"Explicit motion consumes no local random draw")
	Game.training_mode = true
	view.preview_attack_style = "pierce"
	check(view.choose_player_attack_style({"animation":"slash"},melee) == "pierce","Training manual preview overrides authored motion")
	view.preview_attack_style = "slash"
	check(view.choose_player_attack_style({},melee) == "slash","Training preview can force slash")
	check(view.choose_player_attack_style({"animation":"pierce"},{"stance":"ranged","hits":[{}]}) == "shoot","Ranged stance wins over authored and manual melee choices")
	check(view.melee_animation_rng.state == before,"Manual and ranged overrides consume no local random draw")
	Game.training_mode = false
	view.melee_animation_rng.seed = 20261018
	var formal: Array[String] = []
	for i in 512: formal.append(view.choose_player_attack_style({},melee))
	check(formal == first,"Formal combat ignores retained preview setting and follows seeded random sequence")
	view.free()

func install_multihit_hand() -> void:
	await idle()
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules,true)
	rules.deck = ["noren_36"]
	for i in 12: rules.deck.append("noren_01")
	rules.shuffleInitialDeck = false
	var enemies: Array = [{"id":"random_motion_target","displayName":"动作测试对手","maxHp":120,"battlePortraitAssetId":"","intentSequence":[{"type":"attack","amount":1}]}]
	var model := CombatModel.new()
	model.initialize("B04",100,100,rules,enemies,Game.card_catalog)
	model.stance = "melee"
	model.opening_draw_done = true
	model.draw_pile.erase("card_000")
	model.hand.append("card_000")
	Game.commit_combat(model)
	app.swap_view()
	await idle()

func on_phase(phase: String) -> void:
	if phase != "impact": return
	var view = app.view
	impact_poses.append(view.stage.player.pose)
	check(view.stage.player.pose == selected_style,"Every hit keeps the card's single selected motion")
	check(view.melee_animation_rng.state == expected_rng_state,"Further hits consume no additional motion choices")
	check(view.model.snapshot() == committed_snapshot,"Hit presentation leaves resolved model snapshot unchanged")
	check(Game.state.combat == committed_snapshot,"Hit presentation leaves committed snapshot unchanged")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://random_melee_qa_unused.json"
	Game.meta_path = "user://random_melee_qa_meta_unused.json"
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	selector_checks()
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	await install_multihit_hand()
	var view = app.view
	view.preview_attack_style = ""
	view.melee_animation_rng.seed = 271828
	var reference := RandomNumberGenerator.new()
	reference.seed = 271828
	selected_style = "slash" if reference.randi_range(0,1) == 0 else "pierce"
	expected_rng_state = reference.state
	view.stage.phase_changed.connect(on_phase)
	check(view.model.card("card_000").id == "noren_36","Real battle uses existing four-hit card")
	view.select_card("card_000")
	view.play_selected(0)
	committed_snapshot = Game.state.combat.duplicate(true)
	check(Game.battle_busy,"Real card enters locked presentation after model resolution")
	check(view.model.enemies[0].hp == 116 and view.model.energy == 1,"Four-hit card resolves damage and cost exactly once before playback")
	check(view.melee_animation_rng.state == expected_rng_state,"One card consumes exactly one local motion choice")
	await idle()
	check(impact_poses.size() == 4,"All four real card hits reach impact")
	check(view.model.snapshot() == committed_snapshot and Game.state.combat == committed_snapshot,"Complete presentation preserves committed combat state")
	check(view.melee_animation_rng.state == expected_rng_state,"Complete multi-hit card consumes no extra motion choices")
	check(view.stage.phase == "idle","Real battle returns to idle after all hits")
	var output := "res://artifacts/qa/random-melee-2026-10-18/"
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"impacts":impact_poses,"physicalInput":false,"scope":"seeded selector and real four-hit card presentation; save disabled"},"\t"))
	print("RANDOM MELEE: %d checks, %d failures" % [checks,failures])
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
