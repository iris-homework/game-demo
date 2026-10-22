extends "res://tests/combat/interaction/interaction_visual.gd"
## Real rendered viewport, synthetic pointer input. Never writes adventure saves.
var mouse_mask := 0
var phases: Array[String] = []
var evidence := "res://artifacts/qa/combat-stage-2026-10-13"
var hit_frames: Array = []

func motion(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_viewport().get_final_transform()*pos
	event.global_position = event.position
	event.button_mask = mouse_mask
	Input.warp_mouse(event.position)
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame

func mouse(pos: Vector2, down: bool, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	mouse_mask = (1 << (which-1)) if down else 0
	var event := InputEventMouseButton.new()
	event.position = get_viewport().get_final_transform()*pos
	event.global_position = event.position
	event.button_index = which
	event.button_mask = mouse_mask
	event.pressed = down
	Input.parse_input_event(event)
	await get_tree().process_frame

func click(pos: Vector2, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await motion(pos)
	await mouse(pos,true,which)
	await mouse(pos,false,which)

func card_point(card: CombatCard) -> Vector2:
	return card.home+card.pivot_offset+((Vector2(30,45)-card.pivot_offset)*card.home_scale).rotated(card.home_rotation)

func on_phase(value: String) -> void:
	phases.append(value)
	if value == "impact":
		hit_frames.append({"shownHp":app.view.shown_player_hp,"enemyHp":app.view.shown_enemies[0].hp,"playerPose":app.view.stage.player.pose,"enemyPose":app.view.stage.enemies[0].pose})
		shot("impact_%02d" % hit_frames.size())
	if value == "light_flight":
		await settle(0.06)
		shot("return_light")

func wait_phase(value: String) -> void:
	var deadline := Time.get_ticks_msec()+4000
	while app.view.stage.phase != value:
		if Time.get_ticks_msec() > deadline:
			verify(false,"Timed out waiting for "+value)
			return
		await get_tree().process_frame

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://stage_visual_unused.json"
	Game.meta_path = "user://stage_visual_meta_unused.json"
	evidence += "/%d" % DisplayServer.window_get_size().x
	DirAccess.make_dir_recursive_absolute(evidence)
	output = evidence+"/"
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle(0.5)
	Game.start_training("B04")
	await idle()
	var view = app.view
	view.model.enemies[0].hp = 20
	view.model.enemies[0].maxHp = 20
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.commit()
	view.refresh_enemy_hud()
	view.stage.phase_changed.connect(on_phase)
	var end_rect: Rect2 = view.end_button.get_global_rect()
	var cyber_rect: Rect2 = view.cyberware_button.get_global_rect()
	verify(view.stage.zoom == 1 and view.model.hand.size() == 5,"Opening is wide with original five cards")
	await shot("01-wide")
	var uid: String = view.model.hand[0]
	var card: CombatCard = view.cards[uid]
	await click(card_point(card))
	verify(view.selected_uid == uid,"Existing point-select card input works")
	await click(view.stage.contact(view.stage.enemies[0]),MOUSE_BUTTON_RIGHT)
	verify(view.selected_uid.is_empty() and view.model.enemies[0].hp == 20,"Cancel keeps HP and hand")
	await motion(card_point(card))
	await mouse(card_point(card),true)
	await motion(view.stage.contact(view.stage.enemies[0]))
	verify(view.aim.locked,"Far-view target follows actor")
	await mouse(view.stage.contact(view.stage.enemies[0]),false)
	verify(Game.battle_busy and view.model.enemies[0].hp == 19,"Drag release resolves exactly once and locks")
	verify(view.shown_enemies[0].hp == 20,"Enemy displayed HP remains old before impact")
	view.play_selected(0)
	view.end_turn_pressed()
	view.show_pile("抽牌堆",view.model.draw_pile)
	verify(view.model.turn == 1 and view.model.hand.size() == 4 and not is_instance_valid(view.pile_overlay),"Action blocks duplicates, end turn and overlays")
	await wait_phase("impact")
	verify(view.shown_enemies[0].hp == 19 and view.stage.enemies[0].pose == "damaged","Damage pose and HP share the impact")
	await idle()
	verify(is_equal_approx(view.stage.zoom,1.485),"Player close view persists after action")
	verify(view.stage.player.position.distance_to(view.stage.player.home) > 100,"Attacker stays beside target")
	verify(view.end_button.get_global_rect() == end_rect and view.cyberware_button.get_global_rect() == cyber_rect,"Camera leaves UI geometry unchanged")
	verify(view.shown_discard_count == view.model.discard_pile.size(),"Discard display settles without double counting")
	await shot("02-near")
	uid = view.model.hand[0]
	view.preview_attack_style = "pierce"
	phases.clear()
	await click(card_point(view.cards[uid]))
	await motion(view.stage.contact(view.stage.enemies[0]))
	verify(view.aim.locked,"Close-view aiming follows transformed enemy")
	await click(view.stage.contact(view.stage.enemies[0]))
	await idle()
	verify(view.model.enemies[0].hp == 18 and not phases.has("approach"),"Same-target pierce skips another long dash")
	verify(view.stage.enemies[0].position.distance_to(view.stage.enemies[0].home) < 1,"Knockback does not accumulate")
	view.end_turn_pressed()
	await wait_phase("wide")
	verify(view.stage.player.position.distance_to(view.stage.player.home) > 100,"Player turn end does not return actors")
	await wait_phase("prepare")
	verify(view.shown_player_hp == 100 and view.model.player_hp == 99,"Enemy model resolves once but HUD waits for contact")
	await idle()
	verify(view.model.player_hp == 99 and view.shown_player_hp == 99 and view.hp_label.text == "99 / 100","Enemy hit updates displayed HP")
	verify(view.model.turn == 2 and view.model.hand.size() == 5,"Next turn deals once")
	verify(view.stage.player.position == view.stage.player.home and view.stage.enemies[0].position == view.stage.enemies[0].home and is_equal_approx(view.stage.zoom,1),"Enemy turn end returns both actors and camera")
	verify(view.stage.player.modulate == Color.WHITE,"Return restores opacity and tint")
	await shot("03-next-round")
	var state: Dictionary = view.model.snapshot()
	await view.preview_defense(false)
	verify(view.model.snapshot() == state and hit_frames[-1].playerPose == "block","Full-block preview uses guard and does not mutate rules")
	await view.preview_defense(true)
	verify(view.model.snapshot() == state and view.stage.player.pose == "idle","Partial-block preview finishes without rule mutation")
	# Real multi-hit results, not multiple calls to play_card().
	view.preview_attack_style = "slash"
	uid = view.model.hand[0]
	view.model.card_catalog[view.model.instances[uid]].effects = [{"type":"damage","amount":1},{"type":"damage","amount":2}]
	var before_hits := hit_frames.size()
	view.select_card(uid)
	await view.play_selected(0)
	verify(hit_frames.size() == before_hits+2 and view.model.enemies[0].hp == 15,"Two-effect attack has two contacts and one card consumption")
	verify(hit_frames[-2].enemyHp == 17 and hit_frames[-1].enemyHp == 15,"Multi-hit HUD exposes intermediate HP")
	# Restore ignores view positions and must not replay damage or draw.
	var hp: int = view.model.enemies[0].hp
	var count: int = view.model.hand.size()
	app.swap_view()
	await idle()
	view = app.view
	verify(view.model.enemies[0].hp == hp and view.model.hand.size() == count and view.stage.zoom == 1,"Snapshot restore has no extra hit or deal")
	view.stage.phase_changed.connect(on_phase)
	view.model.player_hp = 1
	view.shown_player_hp = 1
	view.commit()
	view.end_turn_pressed()
	await idle()
	verify(Game.page == "menu" and not Game.training_mode,"Lethal enemy hit completes training without new turn")
	# Natural player victory also waits for its last hit and exits.
	Game.start_training("B04")
	await idle()
	view = app.view
	view.model.enemies[0].hp = 1
	view.shown_enemies = view.model.enemies.duplicate(true)
	view.refresh_enemy_hud()
	view.select_card(view.model.hand[0])
	await view.play_selected(0)
	await idle()
	verify(Game.page == "menu" and not Game.battle_busy,"Lethal player hit completes and releases lock")
	FileAccess.open(output+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"hitFrames":hit_frames},"\t"))
	print("COMBAT STAGE VISUAL: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
