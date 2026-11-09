extends Node
## Real battle scene and rendering; invokes UI commands, no physical-input claim.
const FORCE := "emergency_forcefield"
const MAG := "folding_magazine"
const CLEAN := "purification_filter"
const PHASE := "phase_plating"
const RECYCLE := "recycling_protocol"
const COUNTER := "counter_calibrator"
var checks := 0
var failures: Array[String] = []
var output := ""
var view: Control

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("TECHNOLOGY BATTLE VISUAL: " + message)

func settle(seconds: float = 0.15) -> void:
	await get_tree().create_timer(seconds).timeout

func idle() -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while Game.battle_busy or Game.transition_locked or (is_instance_valid(view) and not view.initialized):
		await get_tree().process_frame
		if Time.get_ticks_msec() > deadline:
			check(false,"Battle UI settles within deadline")
			get_tree().quit(1)
			return
	await get_tree().process_frame

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await settle()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name+".png"))

func start(technologies: Array, card_ids: Array) -> void:
	if is_instance_valid(view):
		view.queue_free()
		await get_tree().process_frame
	Game.battle_busy = false
	Game.transition_locked = false
	Game.training_mode = false
	Game.state = Game.initial_state()
	Game.state.ownedCyberwareIds = technologies.duplicate()
	Game.state.equippedCyberwareIds = technologies.duplicate()
	Game.state.deck = ["noren_45"]
	Game.state.battleId = "B02"
	Game.state.activeEventId = "E02"
	Game.state.activeNodeId = "battle"
	Game.state.currentPlaceId = "junkyard"
	Game.state.currentScene = "battle"
	Game.page = "battle"
	Game.initialize_combat()
	var m := CombatModel.new()
	m.restore(Game.state.combat)
	for id in card_ids:
		for uid in m.draw_pile.duplicate():
			if m.instances[uid] == id:
				m.draw_pile.erase(uid)
				m.hand.append(uid)
				break
	m.opening_draw_done = true
	Game.state.combat = m.snapshot()
	view = load("res://scenes/battle.tscn").instantiate()
	add_child(view)
	await idle()
	check(view.cards.size() == view.model.hand.size(),"Battle shows every deterministic opening hand card")

func hand_uid(id: String) -> String:
	for uid in view.model.hand:
		if view.model.instances[uid] == id: return uid
	return ""

func activate(id: String) -> void:
	view.show_cyberware()
	check(is_instance_valid(view.pile_overlay),"Technology UI opens before activation: "+id)
	view.activate_cyberware(id)
	var committed: Dictionary = view.model.snapshot()
	await idle()
	check(view.model.snapshot() == committed and Game.state.combat == committed,"Activation animation preserves one committed result: "+id)
	check(not is_instance_valid(view.pile_overlay),"Successful activation returns to battle: "+id)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://unused_technology_battle_visual.json"
	Game.meta_path = "user://unused_technology_battle_meta.json"
	output = OS.get_environment("QA_OUT_DIR")
	if not output.is_absolute_path() or not "qa" in OS.get_user_data_dir().to_lower():
		push_error("Technology battle visual requires isolated QA directory")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var large := "--large" in OS.get_cmdline_user_args()
	get_window().size = Vector2i(1600,1000) if large else Vector2i(1280,800)
	await start([FORCE,MAG,CLEAN,PHASE],["noren_04","noren_01"])
	view.show_cyberware()
	await shot("01-active-technology-overlay")
	view.close_pile()
	await activate(FORCE)
	check(view.model.block == 10 and view.shown_player_block == 10,"Forcefield immediately updates real block HUD")
	await activate(MAG)
	check(view.model.ammo == 5 and view.shown_player_ammo == 5,"Magazine immediately updates real five-round ammo HUD")
	view.model.buffs.apply(view.model,"pollution",9)
	view.model.buffs.apply(view.model,"weak",3)
	view.model.buffs.apply(view.model,"vulnerable",2)
	await view.commit()
	await shot("02-before-cleanse")
	await activate(CLEAN)
	check(view.shown_player_pollution == 0 and view.shown_player_weak == 0 and not view.shown_player_buffs.has("vulnerable") and view.shown_player_block == 10,"Cleanse removes all shown debuffs and retains block")
	view.show_cyberware()
	check(view.pile_overlay.state_labels[2].text.contains("999"),"Filter overlay displays actual 999-turn remaining cooldown")
	await shot("03-filter-cooldown-999")
	view.close_pile()
	await start([PHASE,RECYCLE,COUNTER,"dimensional_pocket"],["noren_45","noren_04","noren_01"])
	var uid := hand_uid("noren_04")
	view.select_card(uid)
	await view.play_selected(-1)
	await idle()
	check(view.model.stance == "ranged" and view.model.block == 10 and view.shown_player_block == 10,"Actual switch card updates form and plating block once")
	uid = hand_uid("noren_45")
	var hand_before: int = view.model.hand.size()
	view.select_card(uid)
	await view.play_selected(-1)
	await idle()
	check(view.model.hand.size() == hand_before+2 and view.cards.size() == view.model.hand.size() and view.model.exhaust_pile.has(uid),"Calculation plus protocol draws three visible cards and exhausts original")
	uid = hand_uid("noren_01")
	var hp_before: int = view.model.enemies[0].hp
	view.select_card(uid)
	await view.play_selected(0)
	await idle()
	check(hp_before-view.model.enemies[0].hp == 12 and view.model.technology_turn_state.firstAttackUsed,"Guarded ranged direct strike deals (6+2)*1.5 once in actual battle UI")
	check(Game.state.combat == view.model.snapshot() and view.model.technology_turn_state.values().all(func(value): return value == true),"All three passives remain committed after complete presentation")
	view.show_cyberware()
	await shot("04-passives-after-trigger")
	view.close_pile()
	view.queue_free()
	await get_tree().process_frame
	await settle(0.3)
	print("TECHNOLOGY BATTLE VISUAL: %d checks, %d failures" % [checks,failures.size()])
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physicalInput":false,"scope":"real battle UI commands and screenshots"},"\t"))
	get_tree().quit(0 if failures.is_empty() else 1)
