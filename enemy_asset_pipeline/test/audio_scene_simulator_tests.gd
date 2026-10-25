extends Node
const Lab := preload("res://enemy_asset_pipeline/audio_scene_simulator.tscn")
var output := OS.get_environment("QA_OUT_DIR")
var lab: Control
var checks := 0
var failures: Array[String] = []
var cues: Array[String] = []
var played_paths: Dictionary = {}
var visual := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("AUDIO LAB: "+message)

func settle() -> void:
	var deadline := Time.get_ticks_msec()+15000
	while lab.route_busy or lab.route_queued or Game.battle_busy:
		if Time.get_ticks_msec() > deadline:
			check(false,"scene settles before timeout")
			return
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

func capture(name_value: String) -> void:
	if not visual: return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name_value+".png")) == OK,"capture "+name_value)

func check_dialogue_pitch(role: String, pitch: float) -> void:
	lab.bank.stop_all()
	lab.hooks.revealed = 0
	lab.view.text_label.visible_characters = 3
	lab.hooks._process(0)
	check(lab.hooks._dialogue_role() == role, "authored speaker is classified as " + role)
	var actual := -1.0
	for player in lab.bank.get_children():
		if player is AudioStreamPlayer and player.is_playing(): actual = player.pitch_scale
	check(is_equal_approx(actual, pitch), "revealed dialogue uses the actual voice pitch for " + role)

func press(button: Button) -> void:
	if not visual:
		button.pressed.emit()
		return
	var frame: Control = lab.viewport.get_parent()
	var point: Vector2 = frame.get_global_transform()*button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion,true)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event,true)
		await get_tree().process_frame

func _ready() -> void:
	if output.is_empty(): output = "res://artifacts/qa/audio-lab-2026-10-24"
	DirAccess.make_dir_recursive_absolute(output)
	visual = "--visual" in OS.get_cmdline_user_args()
	get_tree().create_timer(110).timeout.connect(func(): push_error("AUDIO LAB TIMEOUT"); get_tree().quit(2))
	Game.save_enabled = false
	Game.state = Game.initial_state("noren")
	Game.state.credits = 417
	Game.page = "menu"
	Game.revision = 29
	var previous_state: Dictionary = Game.state.duplicate(true)
	var previous_shop_rules: Dictionary = Game.technology_shop_rules.duplicate(true)
	var previous_save_path: String = Game.save_path
	var previous_meta_path: String = Game.meta_path
	var previous_rng: int = Game.event_refresh_rng.state
	lab = Lab.instantiate()
	# Start from defaults even when an earlier test saved a comparison plan.
	lab.config_path = ""
	add_child(lab)
	await settle()
	lab.config_path = output.path_join("bindings.json")
	check(not Game.save_enabled and not Game.training_mode,"formal pages run without saving or training purchase restrictions")
	check(Game.save_path.ends_with("audio_lab_unused_checkpoint.json"),"session uses an isolated checkpoint path")
	check(lab.bank.entries.size() >= 96,"all classified candidates including refreshed references are selectable")
	check(lab.bank.bindings.dialogue_blip.ends_with("dialogue_blip_cozy_soft_01.wav"),"dialogue simulation starts with the soft text candidate")
	check(lab.library_list.item_count == lab.bank.entries.size(),"library UI lists the complete candidate set")
	check(lab.view.get_script().resource_path == "res://scripts/dialogue.gd","dialogue reuses the production script")
	lab.bank.stop_all()
	lab.bank.cue_played.connect(func(cue: String, path: String):
		cues.append(cue)
		played_paths[cue] = path)
	lab.view.text_label.visible_characters = 3
	lab.hooks._process(0)
	check("dialogue_blip" in cues,"revealed dialogue text plays the selected blip")
	check_dialogue_pitch("npc", 1.0)
	lab.view.advance()
	check(lab.view.text_label.visible_characters == -1,"first dialogue click reveals the full line")
	lab.view.advance()
	await settle()
	check(Game.state.activeNodeId == "intro_02","production dialogue advances to the next authored node")
	check_dialogue_pitch("noren", 0.88)
	await capture("dialogue")
	Game.state.activeNodeId = "contract"
	await lab._show_page()
	await settle()
	check_dialogue_pitch("narrator", 1.0)
	await lab.open_scenario("choices")
	await settle()
	check(lab.view.choice_buttons.size() == 3,"real opening support choices are available")
	lab.view.select(0)
	await settle()
	check("money_chip" in Game.owned_cyberware_ids(),"a real dialogue choice grants its technology in the fixture")
	lab.bank.stop_all()
	await lab.open_scenario("mall")
	await settle()
	check(not played_paths.has("transition"),"real page change no longer plays transition feedback")
	check(lab.view.get_script().resource_path == "res://scripts/technology_shop.gd","mall reuses the production storefront")
	var offers: Array = Game.technology_shop_offers()
	var swift_index := -1
	for i in offers.size():
		if offers[i].id == "swift_chip": swift_index = i
	check(swift_index >= 0 and int(offers[swift_index].price) == 9999,"test-only Swift Chip price is 9999")
	if swift_index >= 0:
		var swift_button: Button = lab.view.stock.get_node("buy_slot_%d" % swift_index)
		check(swift_button.disabled and "9999" in swift_button.text and "不足" in swift_button.tooltip_text,"Swift Chip visibly shows an unaffordable test price")
		var credits_before_rejection: int = Game.state.credits
		var owned_before_rejection: Array = Game.owned_cyberware_ids().duplicate()
		check(not Game.buy_shop_technology(swift_index, Game.revision),"real payment rules reject the unaffordable test item")
		check(Game.state.credits == credits_before_rejection and Game.owned_cyberware_ids() == owned_before_rejection,"rejected test purchase changes neither credits nor ownership")
	var index := -1
	for i in offers.size():
		if not offers[i].id in Game.owned_cyberware_ids(): index = i; break
	check(index >= 0,"mall fixture offers a purchasable technology")
	if index >= 0:
		var credits: int = Game.state.credits
		lab.bank.stop_all()
		cues.clear()
		lab.view.open_purchase(index)
		await get_tree().process_frame
		await capture("mall-confirm")
		await press(lab.view.modal.get_node("confirm_trade"))
		await get_tree().process_frame
		check(Game.state.credits == credits-int(offers[index].price),"mall confirmation deducts the authored price once")
		check(offers[index].id in Game.owned_cyberware_ids(),"mall confirmation grants the technology")
		check("trade_success" in cues,"successful mall trade plays its result cue")
	await lab.open_scenario("market")
	await settle()
	check(lab.view.get_script().resource_path == "res://scripts/black_market.gd","black market reuses the production storefront")
	var market: Dictionary = Game.black_market_state()
	check(market.slots.size() == 9,"real black-market inventory is generated")
	var credits_before: int = Game.state.credits
	var bought_id: String = market.slots[0].cardId
	lab.view.open_purchase(0)
	await get_tree().process_frame
	await capture("market-confirm")
	await press(lab.view.modal.get_node("confirm_trade"))
	await get_tree().process_frame
	check(Game.state.credits == credits_before-int(market.slots[0].price),"black-market purchase charges its listed price")
	check(bought_id in Game.state.deck and Game.black_market_state().slots[0].sold,"purchased card enters the deck and stock becomes sold")
	var sell_price: int = Game.market_sell_price(bought_id)
	credits_before = Game.state.credits
	lab.view.open_confirmation(bought_id,true)
	await get_tree().process_frame
	await press(lab.view.modal.get_node("confirm_trade"))
	await get_tree().process_frame
	check(Game.state.credits == credits_before+sell_price,"selling applies the real recovery price")
	check(Game.black_market_state().soldCardUsed,"selling consumes the batch sell opportunity")
	lab.bank.stop_all()
	await lab.open_scenario("reward")
	await settle()
	check(not played_paths.has("victory"),"real result page no longer plays victory feedback")
	check(Game.has_battle_reward(),"reward fixture uses the production reward transaction")
	var reward: Control = lab.view.reward_view
	reward.open_picker()
	await get_tree().process_frame
	check(reward.option_buttons.size() == 3,"real reward picker displays three cards")
	await capture("reward")
	var reward_id: String = Game.state.battleReward.options[0]
	Game.choose_reward_card(reward_id,Game.revision)
	await settle()
	check(Game.state.battleReward.status == "claimed" and reward_id in Game.state.deck,"reward selection grants one real card")
	check(not played_paths.has("reward"),"event reward completion no longer plays reward feedback")
	# Keep this audio fixture reproducible, including the opening attack card.
	seed(20261025)
	await lab.open_scenario("battle")
	await settle()
	check(lab.view.get_script().resource_path == "res://scripts/battle.gd","combat uses the production battle view")
	check(lab.view.initialized and lab.view.model.hand.size() == 5,"real opening hand is playable")
	var stage_audio: Node = lab.view.stage.combat_audio
	var action_cues: Array[String] = []
	stage_audio.cue_played.connect(func(cue: String): action_cues.append(cue))
	check(not "snap" in stage_audio.muted_cues,"battle attachment keeps the return snap enabled")
	lab.view.model.energy = 1
	Game.commit_combat(lab.view.model)
	lab.hooks._process(0)
	lab.bank.stop_all()
	cues.clear()
	lab._refill()
	lab.hooks._process(0)
	check(lab.view.model.energy == 3 and lab.view.model.ammo == 10,"refill uses test resources only")
	check(not cues.has("energy"),"explicit energy recovery is also silent")
	var uid: String = lab.view.model.hand[0]
	lab.bank.stop_all()
	cues.clear()
	lab.view.select_card(uid,false)
	lab.hooks._process(0)
	check("card_select" in cues,"production selection drives the card cue")
	lab.view.cancel_selection()
	lab.hooks._process(0)
	check("card_deselect" in cues,"cancelled aiming drives the cancel cue")
	var card: CombatCard = lab.view.cards[uid]
	card.hover(true)
	lab.hooks._process(0)
	check("card_hover" in cues,"production card hover drives a hover cue")
	await capture("battle")
	var attack_uid := ""
	for candidate in lab.view.model.hand:
		if lab.view.model.card(candidate).get("type") == "attack": attack_uid = candidate; break
	check(not attack_uid.is_empty(),"fixture provides an attack card")
	if not attack_uid.is_empty():
		lab.bank.stop_all()
		cues.clear()
		lab.view.select_card(attack_uid,false)
		await lab.view.play_selected(0)
		await settle()
		check("card_play" in cues,"successful production card resolution plays its committed-card cue")
		check(not attack_uid in lab.view.model.hand,"the committed card actually leaves the hand")
	lab.view.show_pile("抽牌",lab.view.model.draw_pile)
	await get_tree().process_frame
	check(is_instance_valid(lab.view.pile_overlay),"production read-only pile can be inspected")
	lab.view.close_pile()
	# Reproduce ending a turn after every hand card and all energy are spent.
	lab.view.model.discard_pile.append_array(lab.view.model.hand)
	lab.view.model.hand.clear()
	lab.view.model.energy = 0
	for remaining_card in lab.view.cards.values(): remaining_card.free()
	lab.view.cards.clear()
	Game.commit_combat(lab.view.model)
	lab.hooks._process(0)
	lab.bank.stop_all()
	cues.clear()
	var previous_turn: int = lab.view.model.turn
	await press(lab.view.end_button)
	await settle()
	check(lab.view.model.turn > previous_turn,"production enemy actions finish and start the next round")
	check(not cues.has("energy"),"empty-hand turn end does not announce automatic energy refill")
	check(not cues.has("ui_click"),"end-turn button does not emit generic button feedback")
	check(not played_paths.has("turn_start"),"real round advance no longer plays turn-start feedback")
	check(action_cues.count("snap") == 1,"full enemy round plays exactly one return snap")
	check(action_cues.has("slash") or action_cues.has("shoot"),"ordinary attack sounds remain active")
	lab.hooks.attach(null)
	check(not "snap" in stage_audio.muted_cues,"detaching leaves the return snap enabled")
	stage_audio.muted_cues.append("snap")
	lab.hooks.attach(lab.view)
	lab.hooks.attach(null)
	check("snap" in stage_audio.muted_cues,"detaching preserves a mute that existed before attachment")
	stage_audio.muted_cues.erase("snap")
	lab.hooks.attach(lab.view)
	Game.page = "defeat"
	await lab._show_page()
	await settle()
	check(lab.view.get_script().resource_path == "res://scripts/defeat.gd" and not played_paths.has("defeat"),"defeat page also remains silent")
	await lab.open_scenario("map")
	await settle()
	check(lab.view.get_script().resource_path == "res://scripts/map.gd","map uses the production page")
	lab._open_deck()
	check(is_instance_valid(lab.modal) and lab.modal.current_deck_mode,"current-deck toolbar opens the real read-only browser")
	lab._close_modal()
	lab._open_loadout()
	check(is_instance_valid(lab.modal),"technology toolbar opens the real loadout editor")
	lab._close_modal()
	check(lab.bank.bind("dialogue_blip","res://assets/audio/incoming/dialogue/dialogue_blip_cozy_low_01.wav"),"the dialogue binding can switch to the new low text candidate")
	lab.bank.master_volume_db = -18
	check(lab.save_bindings(),"explicit save writes only the lab's separate audio plan")
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(lab.config_path))
	check(config.bindings.dialogue_blip.ends_with("dialogue_blip_cozy_low_01.wav"),"audio plan preserves the chosen candidate")
	await lab.close_preview()
	await get_tree().process_frame
	check(Game.state == previous_state and Game.page == "menu" and Game.revision == 29,"closing restores the complete pre-lab state and revision")
	check(Game.save_path == previous_save_path and Game.meta_path == previous_meta_path,"closing restores both checkpoint and meta paths")
	check(Game.technology_shop_rules == previous_shop_rules,"closing restores the original formal shop prices")
	check(Game.event_refresh_rng.state == previous_rng,"closing restores event-pool RNG state")
	check(not FileAccess.file_exists("user://audio_lab_unused_checkpoint.json") and not FileAccess.file_exists("user://audio_lab_unused_meta.json"),"simulation did not create checkpoints or metadata")
	var report := {"checks":checks,"failures":failures,"visual":visual,"scope":"program-driven production dialogue, choices, combat, shops, reward, modal, binding and state restoration"}
	var file := FileAccess.open(output.path_join("visual-result.json" if visual else "headless-result.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("AUDIO_SCENE_SIMULATOR_TESTS checks=%d failures=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
