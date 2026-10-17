extends "res://tests/noren_cards_visual.gd"

func wait_for_shift(actor: Node) -> bool:
	var started := Time.get_ticks_msec()
	while not is_instance_valid(actor.weapon_shift):
		await get_tree().process_frame
		if Time.get_ticks_msec()-started > 10000:
			check(false,"Stance transition started before timeout")
			return false
	return true

func exercise_card(number: int, before: String, after: String, check_input_lock: bool = false) -> void:
	await install_hand([number,1,2],before)
	var view = app.view
	var actor = view.stage.player
	var played_view = view.cards["card_000"]
	check(actor.combat_stance==before and actor.sprite.material==null and not is_instance_valid(actor.weapon_shift),"Restored stance has no arrival effect: %02d"%number)
	var target: Vector2 = view.stage.target_rect(0).get_center() if number in [9,10] else Vector2(720,420)
	await pointer(view.cards["card_000"].home+Vector2(68,110),1)
	await pointer(target)
	await pointer(target,0)
	if number in [9,10]:
		check(not is_instance_valid(actor.weapon_shift) and actor.combat_stance==before,"Attack starts in old stance before transition: %02d"%number)
	else:
		check(is_instance_valid(actor.weapon_shift) and is_instance_valid(played_view) and played_view.visible,"Stance effect starts while played card is still flying: %02d"%number)
	if not await wait_for_shift(actor): return
	var effect = actor.weapon_shift
	var committed: Dictionary = view.model.snapshot()
	check(view.model.stance==after and Game.battle_busy,"Model committed final stance while input stays locked")
	if number in [9,10]:
		check(view.shown_enemies[0].hp==view.model.enemies[0].hp and view.model.enemies[0].hp<120,"Attack damage is displayed before stance effect: %02d"%number)
	var phases: Array = [effect.phase]
	effect.phase_changed.connect(func(phase): phases.append(phase))
	if check_input_lock:
		await key(KEY_A,true,true)
		check(not is_instance_valid(app.card_console),"Existing busy lock blocks Ctrl+Shift+A during weapon transition")
		view.select_card("card_001");view.play_selected(0)
		check(view.model.snapshot()==committed,"Busy lock blocks a second card during weapon transition")
	var captured := ""
	var unchanged := true
	var stayed_busy := true
	while is_instance_valid(actor.weapon_shift):
		unchanged = unchanged and view.model.snapshot()==committed
		stayed_busy = stayed_busy and Game.battle_busy
		if effect.phase!=captured:
			captured=effect.phase
			await shot("card-%02d-%s-%s"%[number,before,captured])
		await get_tree().process_frame
	await idle()
	check(stayed_busy and (not is_instance_valid(played_view) or not played_view.visible),"Input stays locked through shift and card landing")
	check(unchanged and view.model.snapshot()==committed,"Effect never spends or applies card rewards again")
	check("glitch" in phases and "reveal" in phases,"Glitch precedes weapon reveal")
	check(actor.combat_stance==after and actor.pose==("gun_idle" if after=="ranged" else "idle"),"Final weapon matches final stance")
	check(actor.sprite.material==null and actor.sprite.get_child_count()==0 and not Game.battle_busy,"Effect restores material and removes all echoes")
	await shot("card-%02d-%s-done"%[number,before])

func pixels() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func sprite_region(actor: Node2D, picture: Image, region: Rect2) -> PackedByteArray:
	var transform := get_viewport().get_final_transform()
	var start: Vector2 = transform*actor.sprite.to_global(region.position)
	var end: Vector2 = transform*actor.sprite.to_global(region.end)
	return picture.get_region(Rect2i(Rect2(start,end-start).abs())).get_data()

func detail_fixture() -> void:
	app.hide()
	var fixture := Node2D.new()
	add_child(fixture)
	var actor = preload("res://scripts/combat/pose_actor.gd").new()
	fixture.add_child(actor)
	actor.setup_player(Vector2(780,775),-1.0)
	actor.scale=Vector2.ONE*5.0
	var original_material := CanvasItemMaterial.new()
	actor.sprite.material=original_material
	await get_tree().process_frame
	var baseline := await pixels()
	var sword_baseline := baseline
	await shot("detail-sword-before")
	actor.transition_combat_stance("ranged")
	var effect = actor.weapon_shift
	effect.set_process(false)
	effect._process(0.075)
	await get_tree().process_frame
	var during := await pixels()
	# Updated requirement: the effect must now cover head, torso, hands and legs.
	for region in [Rect2(600,250,160,200),Rect2(680,500,110,160),Rect2(580,1100,110,90)]:
		check(sprite_region(actor,baseline,region)!=sprite_region(actor,during,region),"Full-body glitch covers original sprite region: "+str(region))
	check(baseline.get_region(Rect2i(20,20,60,60)).get_data()==during.get_region(Rect2i(20,20,60,60)).get_data(),"Character glitch leaves the background unchanged")
	await shot("detail-sword-out")
	effect._process(effect.OUT_TIME-effect.elapsed+0.012)
	check(is_zero_approx(effect.materials[0].get_shader_parameter("visibility")) and is_zero_approx(effect.materials[0].get_shader_parameter("intensity")),"Pose swap stays fully hidden even when a frame overshoots the boundary")
	await get_tree().process_frame
	await shot("detail-hidden-swap")
	effect._process(0.04)
	await get_tree().process_frame
	await shot("detail-gun-glitch")
	effect._process(0.25)
	await get_tree().process_frame
	await shot("detail-gun-reveal")
	effect._process(0.30)
	await get_tree().process_frame
	check(actor.sprite.material==original_material and not is_instance_valid(actor.weapon_shift),"Normal completion restores a pre-existing material")
	await shot("detail-gun-done")
	await actor.transition_combat_stance("ranged")
	check(not is_instance_valid(actor.weapon_shift),"Setting the same stance never replays effect")
	baseline=await pixels()
	actor.transition_combat_stance("melee")
	effect=actor.weapon_shift
	effect.set_process(false)
	effect._process(0.075)
	await get_tree().process_frame
	during=await pixels()
	for region in [Rect2(445,798,25,15),Rect2(690,718,30,20)]:
		check(sprite_region(actor,baseline,region)!=sprite_region(actor,during,region),"Full-body glitch covers hands: "+str(region))
	await shot("detail-gun-out")
	effect._process(0.10)
	await get_tree().process_frame
	await shot("detail-sword-glitch")
	effect._process(0.25)
	await get_tree().process_frame
	await shot("detail-sword-reveal")
	effect._process(0.30)
	await get_tree().process_frame
	await shot("detail-sword-done")
	check((await pixels()).get_data()==sword_baseline.get_data(),"Reverse transition restores every original rendered pixel")
	actor.set_combat_stance("ranged")
	actor.transition_combat_stance("melee")
	await get_tree().process_frame
	actor.set_combat_stance("ranged")
	await get_tree().process_frame
	await get_tree().create_timer(0.65).timeout
	check(actor.combat_stance=="ranged" and actor.sprite.material==original_material and actor.sprite.get_child_count()==0,"Instant restore cancels active effect without a late pose swap")
	for reaction in ["retreat","block","damaged"]:
		actor.set_combat_stance("ranged")
		actor.set_pose(reaction)
		await get_tree().process_frame
		await shot("detail-new-"+reaction)
	actor.set_combat_stance("ranged")
	actor.transition_combat_stance("melee")
	actor.queue_free()
	await get_tree().process_frame
	check(not is_instance_valid(actor),"Freeing actor during transition cleans up safely")
	fixture.queue_free()
	app.show()

func observe_battle_poses(names: Array, prefix: String) -> Array:
	var seen: Array = []
	var started := Time.get_ticks_msec()
	while Game.battle_busy:
		var actor = app.view.stage.player
		if actor.pose in names and not actor.pose in seen:
			seen.append(actor.pose)
			check(actor.sprite.texture==actor.poses[actor.pose],"Live battle uses registered ranged texture: "+actor.pose)
			await shot(prefix+actor.pose)
		await get_tree().process_frame
		if Time.get_ticks_msec()-started > 20000:
			check(false,"Ranged action playback finishes before timeout")
			get_tree().quit(2)
			return seen
	await idle()
	return seen

func exercise_ranged_actions() -> void:
	print("RANGED QA: start")
	await install_hand([1,2],"ranged")
	var view = app.view
	var actor = view.stage.player
	var home: Vector2 = actor.position
	actor.position=view.stage.enemies[0].position-Vector2(130,0)
	view.select_card("card_000");view.play_selected(0)
	var seen := await observe_battle_poses(["retreat","shoot"],"ranged-")
	print("RANGED QA: attack finished")
	check(seen==["retreat","shoot"],"Close attack uses a ground retreat before the gun shot")
	check(view.model.enemies[0].hp==111 and view.model.ammo==1,"Ranged visual replacement preserves attack damage and ammo")
	check(actor.pose=="gun_idle" and actor.sprite.material==null,"Ranged attack returns to clean gun idle")
	view.model.block=5
	view.commit()
	view.refresh_resources()
	view.end_turn_pressed()
	print("RANGED QA: enemy turn started")
	seen=await observe_battle_poses(["gun_block","gun_damaged"],"ranged-enemy-")
	print("RANGED QA: enemy turn finished")
	check("gun_block" in seen and "gun_damaged" in seen,"Partial block followed by damage uses both new gun reactions")
	check(view.model.player_hp==45,"Enemy hits still resolve once through partial block")
	check(actor.pose=="gun_idle" and actor.combat_stance=="ranged" and actor.position.is_equal_approx(home),"Enemy turn and return effect preserve ranged stance and home anchor")
	await shot("ranged-next-turn")
	for stance in ["melee","ranged"]:
		actor.set_combat_stance(stance)
		for reaction in ["block","damaged"]:
			actor.set_pose(reaction)
			check(actor.pose==("gun_"+reaction if stance=="ranged" else reaction),"Reaction follows stance: "+stance+" / "+reaction)
	actor.set_combat_stance("ranged")

func _ready() -> void:
	var requested_size := Vector2i(1280,800)
	Game.save_enabled=false
	Game.save_path="user://weapon_shift_visual_unused.json"
	Game.meta_path="user://weapon_shift_visual_meta_unused.json"
	output="res://artifacts/qa/full-body-shift-2026-10-16/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suffix="):output+=arg.trim_prefix("--suffix=")+"-"
		if arg=="--large":requested_size=Vector2i(1600,1000)
		if arg.begins_with("--output-dir="):output=arg.trim_prefix("--output-dir=").trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state=Game.initial_state()
	app=preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(0.4).timeout
	get_window().mode=Window.MODE_WINDOWED
	get_window().size=requested_size
	await get_tree().create_timer(0.2).timeout
	var rendered := await pixels()
	print("WINDOW: ",get_window().size," RENDER: ",rendered.get_size())
	check(rendered.get_size()==requested_size,"Rendered output matches requested QA size")
	Game.start_training("B04")
	await idle()
	await exercise_card(4,"melee","ranged",true)
	await exercise_card(3,"ranged","melee")
	await exercise_card(8,"melee","ranged")
	await exercise_card(8,"ranged","melee")
	await exercise_card(9,"ranged","melee")
	await exercise_card(10,"melee","ranged")
	await detail_fixture()
	await exercise_ranged_actions()
	print("FULL BODY SHIFT: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
