extends Node
## Run in an isolated project/user directory. All state and payment fixtures are unsaved.
const App := preload("res://scenes/main.tscn")
const Cleanup := preload("res://scripts/combat/audio_cleanup.gd")
var app: Control
var checks := 0
var failures: Array[String] = []
var cues: Array[String] = []
var output := OS.get_environment("QA_OUT_DIR")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("FORMAL AUDIO: " + message)

func settle() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Game.transition_locked or Game.battle_busy:
		if Time.get_ticks_msec() > deadline:
			check(false, "formal page settles before timeout")
			break
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

func clear_audio() -> void:
	app.audio_player.stop_all()
	cues.clear()

func fresh(page: String, place: String = "bar") -> void:
	Game.state = Game.initial_state("noren")
	Game.state.currentPlaceId = place
	Game.state.currentScene = page
	Game.page = page
	Game.revision += 1
	Game.transition_locked = false
	Game.battle_busy = false
	Game.training_mode = false
	Game.pending_save_kind = ""

func check_voice(role: String, pitch: float) -> void:
	clear_audio()
	app.audio_hooks.revealed = 0
	app.view.text_label.visible_characters = 3
	app.audio_hooks._process(0)
	check(app.audio_hooks._dialogue_role() == role, "formal speaker role is " + role)
	var actual := -1.0
	for player in app.audio_player.get_children():
		if player is AudioStreamPlayer and player.is_playing(): actual = player.pitch_scale
	check(cues.has("dialogue_blip") and is_equal_approx(actual, pitch), "formal dialogue plays the expected pitch for " + role)

func _ready() -> void:
	if output.is_empty(): output = "user://formal-audio-evidence"
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(110).timeout.connect(func(): push_error("FORMAL AUDIO TIMEOUT"); get_tree().quit(2))
	Game.save_enabled = false
	Game.save_path = "user://formal-audio-checkpoint.json"
	Game.meta_path = "user://formal-audio-meta.json"
	fresh("dialogue")
	app = App.instantiate()
	add_child(app)
	await settle()
	app.audio_player.cue_played.connect(func(cue: String, _path: String): cues.append(cue))
	check(not app.audio_player.has_method("scan"), "formal player has no developer-library scanner")
	check(app.audio_player._registered_streams.size() == 18, "formal player registers exactly the selected eighteen assets")
	for cue in app.audio_player.bindings:
		var path: String = app.audio_player.bindings[cue]
		check(path.is_empty() or path.begins_with("res://assets/audio/game/"), "formal binding stays in published assets: " + cue)
		if not path.is_empty():
			var stream: AudioStream = app.audio_player._load_stream(path)
			check(stream != null and stream.get_length() > 0.0, "formal imported asset decodes: " + cue)
	for cue in ["reward", "transition", "turn_start", "victory", "defeat", "energy"]:
		check(app.audio_player.bindings[cue].is_empty() and not app.audio_player.play_cue(cue), "removed formal feedback stays silent: " + cue)
	check_voice("npc", 1.0)
	app.view.advance()
	app.view.advance()
	await settle()
	check(Game.state.activeNodeId == "intro_02", "real dialogue advancement routes through Main")
	check_voice("noren", 0.88)
	Game.enter_node("contract")
	await settle()
	check_voice("narrator", 1.0)
	clear_audio()
	app.view.select(0)
	await settle()
	check("money_chip" in Game.owned_cyberware_ids() and cues.has("ui_click"), "real story selection grants its chip and plays one choice click")

	fresh("place", "mall")
	Game.state.credits = 1000
	app.swap_view()
	await settle()
	var offers: Array = Game.technology_shop_offers()
	var swift := -1
	for i in offers.size():
		if offers[i].id == "swift_chip": swift = i
	check(swift >= 0 and int(offers[swift].price) == 150, "formal Swift Chip price is still 150")
	var balance: int = Game.state.credits
	clear_audio()
	app.view.open_purchase(swift)
	await get_tree().process_frame
	await get_tree().process_frame
	var confirm: Button = app.view.modal.get_node("confirm_trade")
	confirm.pressed.emit()
	await get_tree().process_frame
	check(Game.state.credits == balance - 150 and "swift_chip" in Game.owned_cyberware_ids(), "formal purchase uses real payment and ownership rules")
	check(cues.has("ui_click") and cues.has("trade_success"), "formal shop confirmation and trade feedback are connected")
	clear_audio()
	Game.notice.emit("信用点不足。")
	check(cues.has("ui_error"), "formal rejection toast plays its error feedback")

	fresh("battle", "alley")
	Game.state.activeEventId = "E04"
	Game.state.activeNodeId = "battle"
	Game.state.battleId = "B04"
	Game.state.deck = ["noren_07", "noren_12", "noren_20"]
	seed(20261025)
	Game.initialize_combat()
	Game.changed.emit()
	await settle()
	check(app.shown_page == "battle" and app.view.initialized, "formal battle loads through Main's actual page transition")
	var action_cues: Array[String] = []
	app.view.stage.combat_audio.cue_played.connect(func(cue: String): action_cues.append(cue))
	check(not "snap" in app.view.stage.combat_audio.muted_cues, "formal return snap remains enabled")
	app.view.model.ammo = 10
	Game.commit_combat(app.view.model)
	var attack := ""
	for uid in app.view.model.hand:
		if app.view.model.card(uid).get("type") == "attack": attack = uid; break
	check(not attack.is_empty(), "formal battle fixture has a playable attack")
	clear_audio()
	if not attack.is_empty():
		app.view.select_card(attack, false)
		check(cues.has("card_select"), "formal card selection plays its cue")
		await app.view.play_selected(0)
		await settle()
		check(cues.has("card_play") and not attack in app.view.model.hand, "committed formal card play has presentation feedback")
	app.view.model.discard_pile.append_array(app.view.model.hand)
	app.view.model.hand.clear()
	app.view.model.energy = 0
	for card in app.view.cards.values(): card.free()
	app.view.cards.clear()
	Game.commit_combat(app.view.model)
	clear_audio()
	var turn: int = app.view.model.turn
	app.view.end_button.pressed.emit()
	await settle()
	check(app.view.model.turn > turn, "empty-hand formal end-turn completes real enemy actions")
	check(not cues.has("energy") and not cues.has("turn_start") and not cues.has("ui_click"), "formal round reset has none of the removed extra feedback")
	check(action_cues.count("snap") == 1 and (action_cues.has("slash") or action_cues.has("shoot")), "formal return plays exactly one snap while attack audio remains active")

	fresh("map")
	app.swap_view()
	await settle()
	app.open_current_deck()
	await get_tree().process_frame
	await get_tree().process_frame
	check(is_instance_valid(app.deck_browser), "formal read-only deck overlay opens")
	clear_audio()
	var close_control: BaseButton = app.deck_browser.close_button
	if close_control != null:
		close_control.pressed.emit()
		check(not cues.is_empty(), "formal root-level overlay buttons receive feedback")
	else: check(false, "read-only deck exposes its close control")
	app.close_current_deck()
	for page in ["result", "defeat"]:
		fresh(page)
		clear_audio()
		app.swap_view()
		await settle()
		check(not cues.has("victory") and not cues.has("defeat") and not cues.has("reward") and not cues.has("transition"), "formal terminal page stays quiet: " + page)
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "formal-audio fixture never writes adventure saves")
	check(await Cleanup.release(app, get_tree()), "formal audio drains before disposal")
	app.free()
	await get_tree().process_frame
	var report := {"checks": checks, "failures": failures, "scope": "formal Main with native imported streams; no preview session or price overrides"}
	var file := FileAccess.open(output.path_join("formal-result.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("FORMAL_AUDIO_TESTS checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
