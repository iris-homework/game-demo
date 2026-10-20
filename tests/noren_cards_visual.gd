extends Node
var app: Control
var checks := 0
var failures := 0
var output := "res://artifacts/qa/noren-consolidation-2026-10-19/noren-visual/"

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func release_overlay_absent(view: Control) -> bool:
	for child in view.get_children():
		if child is Panel and child.z_index==5: return false
	for label in view.find_children("*","Label",true,false):
		if label.text.begins_with("点击释放") or label.text.begins_with("松手释放") or label.text.begins_with("拖到这里"): return false
	return true

func idle() -> void:
	var started := Time.get_ticks_msec()
	while Game.battle_busy or Game.transition_locked:
		await get_tree().process_frame
		if Time.get_ticks_msec()-started > 20000:
			push_error("Visual wait timed out")
			get_tree().quit(2)
			return
	await get_tree().process_frame
	await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+name+".png")

func key(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.ctrl_pressed = ctrl
		event.shift_pressed = shift
		event.keycode=code;event.pressed=down
		get_viewport().push_input(event,true)
		await get_tree().process_frame

func pointer(position: Vector2, pressed: int = -1) -> void:
	var event: InputEvent
	if pressed < 0:
		event = InputEventMouseMotion.new()
	else:
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed == 1
	event.position = get_viewport().get_final_transform() * position
	event.global_position = event.position
	Input.warp_mouse(event.position)
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame

func install_hand(numbers: Array, form: String = "melee") -> void:
	await idle()
	var rules: Dictionary=Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules,true)
	rules.deck=[]
	for number in numbers:rules.deck.append("noren_%02d" % int(number))
	for i in 12:rules.deck.append("noren_01")
	rules.shuffleInitialDeck=false
	var enemies: Array=[]
	for i in 3:
		enemies.append({"id":"visual_%d"%i,"displayName":"训练对手","maxHp":120,"battlePortraitAssetId":"","intentSequence":[{"type":"attack","amount":10,"hits":2}]})
	var m:=CombatModel.new()
	m.initialize("B04",100,100,rules,enemies,Game.card_catalog)
	m.stance=form;m.opening_draw_done=true
	for i in numbers.size():
		var uid:="card_%03d"%i
		m.draw_pile.erase(uid);m.hand.append(uid)
	Game.commit_combat(m)
	app.swap_view()
	await idle()

func _ready() -> void:
	Game.save_enabled=false
	Game.save_path="user://noren_visual_unused.json"
	Game.meta_path="user://noren_visual_meta_unused.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suffix="):output += arg.trim_prefix("--suffix=")+"-"
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	Game.state=Game.initial_state()
	app=preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.open_card_library()
	await get_tree().process_frame
	check(app.view.card_views.size()==4,"Owned library has only four initial types")
	await shot("owned")
	app.view.owned_only=false;app.view.refresh_library()
	await get_tree().process_frame
	check(app.view.card_views.size()==40,"All forty cards rendered")
	for card in app.view.card_views:
		check(card.rarity_color()==CombatCard.RARITY_COLORS[card.data.rarity],card.data.name+" rarity color")
		for node in card.get_children():
			if node is Label:
				check(node.position.y+node.size.y<=230.5,card.data.name+" text fits card")
	await shot("catalogue-top")
	app.view.scroll.scroll_vertical=int(app.view.scroll.get_v_scroll_bar().max_value)
	await get_tree().process_frame
	await shot("catalogue-bottom")
	await key(KEY_A,true,true)
	check(is_instance_valid(app.card_console) and app.view.process_mode==Node.PROCESS_MODE_DISABLED,"Ctrl+Shift+A opens console and suspends base view")
	app.card_console.submit("addcard 深度伤口 2")
	app.card_console.submit("owned")
	check(Game.state.deck==["noren_36","noren_36"],"Console UI adds only requested owned copies")
	await shot("console")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.card_console) and app.view.process_mode!=Node.PROCESS_MODE_DISABLED,"Escape closes console and restores view")
	Game.menu();Game.start_training("B04")
	await idle()
	await install_hand([4,1,3,7,31])
	var view=app.view
	await pointer(view.cards["card_000"].home+Vector2(68,110),1)
	await pointer(Vector2(720,420))
	check(release_overlay_absent(view) and not view.aim.visible,"Self skill has no release rectangle, instruction or enemy aim")
	await pointer(Vector2(720,420),0)
	await idle()
	check(view.model.block==4 and view.model.stance=="ranged" and view.model.energy==2,"Self skill resolves from center drag release")
	check(view.cards.size()==view.model.hand.size(),"Hand views match after skill")
	check(view.stage.player.pose=="gun_idle","Ranged stance switches gun portrait")
	view.select_card("card_001");view.play_selected(0)
	await idle()
	check(view.model.enemies[0].hp==111 and view.model.energy==2,"Ranged attack uses discount and correct damage")
	view.select_card("card_002");view.play_selected(-1)
	await idle()
	check(view.model.stance=="melee" and view.cards.size()==view.model.hand.size(),"Stance entry draw creates a live card view")
	await shot("combat-melee")
	await install_hand([20,26,36,38,34],"ranged")
	view=app.view;view.model.ammo=3
	view.select_card("card_000")
	var frozen: Dictionary=view.model.snapshot()
	await key(KEY_ESCAPE)
	check(view.model.snapshot()==frozen and view.selected_uid.is_empty() and not is_instance_valid(view.pile_overlay),"Canceling an unplayed full-ammo attack spends nothing")
	view.select_card("card_000");view.play_selected(0)
	check(not is_instance_valid(view.pile_overlay) and Game.battle_busy,"Full-ammo attack commits directly without an extra-ammo picker")
	check(view.model.enemies[0].hp==64 and view.model.ammo==0 and view.model.energy==1,"Three ammo produce four ranged hits and spend all three ammo once")
	frozen=view.model.snapshot()
	await idle()
	check(view.model.snapshot()==frozen,"Full-ammo attack presentation never repeats damage, ammo or energy spending")
	await shot("all-ammo-attack")
	view.select_card("card_004");view.play_selected(0)
	await idle()
	check(view.model.exhaust_pile.size()==1 and view.cards.size()==view.model.hand.size(),"Exhaust leaves hand and has no discard duplicate")
	await shot("combat-ranged")
	await install_hand([26,1,2],"ranged")
	view=app.view
	view.select_card("card_000");view.play_selected(0)
	check(not is_instance_valid(view.pile_overlay) and view.model.enemies[0].hp==54 and view.model.ammo==1,"Finisher deals sixty-six damage and spends one normal ammo without a picker")
	frozen=view.model.snapshot()
	await idle()
	check(view.model.snapshot()==frozen,"Finisher presentation preserves the single committed resolution")
	await install_hand([23,36,35],"ranged")
	view=app.view;view.model.ammo=3
	view.select_card("card_000");view.play_selected(-1)
	await idle()
	view.select_card("card_001");view.play_selected(-1)
	await idle()
	check(view.model.powers.has("ranged_mastery") and view.model.powers.has("persistent_bleed") and view.model.exhaust_pile.size()==2,"Both new persistent powers activate and leave the card loop")
	view.model.enemies[0].bleed=5
	view.select_card("card_002");view.play_selected(0)
	frozen=view.model.snapshot()
	await idle()
	check(view.model.enemies[0].hp==93 and view.model.enemies[0].bleed==5 and view.model.ammo==2,"Three shots use double body damage while all three bleed triggers preserve five layers")
	check(view.model.snapshot()==frozen,"Powered multi-hit playback leaves committed buffs and damage unchanged")
	await shot("persistent-powers")
	await install_hand([12,1,13,2,7])
	view=app.view;view.select_card("card_000");view.play_selected(-1)
	check(view.pile_overlay.options.size()==4,"Dismantle lists every other hand instance")
	await shot("exhaust-picker")
	view.pile_overlay.picked.emit("card_002")
	await idle()
	check("card_002" in view.model.exhaust_pile and "card_000" in view.model.discard_pile and not view.cards.has("card_002") and view.model.ammo==4,"Chosen card exhausted, Dismantle discarded; cards synchronized")
	view.select_card("card_004");view.play_selected(-1)
	await idle()
	check(view.cards.size()==view.model.hand.size() and view.model.hand.size()==4,"Draw two card updates playable hand")
	await install_hand([33,1,2])
	view=app.view;view.select_card("card_000");view.play_selected(-1)
	await idle()
	view.end_turn_pressed()
	await idle()
	check(view.model.turn==2 and view.model.parry==0 and view.model.enemies.map(func(e): return e.hp)==[110,120,120] and view.model.player_hp==50,"Single parry counters only the first attack; ten block and all three enemy attacks resolve once")
	check(view.cards.size()==5 and view.model.energy==3 and view.model.block==0,"Turn refresh creates five playable cards")
	await shot("parry-next-turn")
	# Already-drawn empty formal hand does not refill on rebuilding the scene.
	view.model.discard_pile.append_array(view.model.hand);view.model.hand.clear()
	view.commit();app.swap_view();await idle()
	check(app.view.model.hand.is_empty(),"Resume never draws an extra opening hand")
	Game.finish_training("lose");await idle()
	Game.state=Game.initial_state()
	Game.state.targetId="richard"
	Game.state.activeEventId="E04";Game.state.currentPlaceId="alley"
	Game.enter_node("battle");await idle()
	Game.battle_exit("win",Game.revision);await idle()
	var steps:=0
	while Game.state.currentScene=="dialogue" and steps<100:
		if Game.node_data().has("next"):Game.advance(Game.revision)
		else:Game.choose(0,Game.revision)
		steps+=1
	check(Game.has_battle_reward(),"Formal victory reaches reward after authored dialogue")
	if not Game.has_battle_reward():
		get_tree().quit(1)
		return
	Game.state.battleReward.options=["noren_20","noren_23","noren_38"]
	app.swap_view();await get_tree().process_frame
	app.view.reward_view.open_picker()
	await get_tree().create_timer(0.4).timeout
	await shot("formal-reward")
	check(app.view.reward_view.option_buttons.size()==3,"Three formal reward cards displayed")
	await key(KEY_2)
	check(Game.state.battleReward.status=="claimed" and Game.state.deck==["noren_23"],"Keyboard claims formal reward exactly once")
	print("NOREN VISUAL: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
