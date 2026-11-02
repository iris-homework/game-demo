extends Node
## Exercise the real presentation stage with supplied hit results; no model or RNG calls.
const Stage = preload("res://scripts/combat/test_stage.gd")
const GunBurst = preload("res://scripts/combat/gun_burst_fx.gd")
const AttackConfig = preload("res://enemy_asset_pipeline/runtime/pipeline_attack_config.gd")
const CONTACT_CLIPS := {
	"bite":"res://assets/audio/combat/enemy_reference/monster_bite_lucasduff_467701.mp3",
	"hit":"res://assets/audio/combat/enemy_reference/impact_strong_punch_mixkit_2155.mp3",
}
var checks := 0
var failures: Array[String] = []
var stage: Control
var cues: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
var muzzle_frames: Array[int] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func fixture(profile: String = "gang_henchman", count: int = 1, preview_profile: bool = false) -> void:
	stage = Stage.new()
	add_child(stage)
	var resolver := EnemyVisualResolver.new()
	var visuals: Array[EnemyVisualResolver.Visual] = []
	for i in count:
		var enemy_id := "preview_"+profile if preview_profile else "audio_%d" % i
		visuals.append(resolver.resolve({"id":enemy_id,"combatVisualId":profile}, {}))
	stage.setup(577.0, visuals)
	cues.clear()
	contacts.clear()
	muzzle_frames.clear()
	stage.combat_audio.cue_played.connect(record_cue)
	stage.world.child_entered_tree.connect(record_effect)

func record_cue(cue: String) -> void:
	var actor = stage.active_attacker
	cues.append({"cue":cue,"frame":Engine.get_process_frames(),"phase":stage.phase,
		"pose":actor.pose if is_instance_valid(actor) else "",
		"player_position":stage.player.position,"player_alpha":stage.player.modulate.a})

func record_effect(node: Node) -> void:
	if node.get_script() == GunBurst and node.mode == "muzzle":
		muzzle_frames.append(Engine.get_process_frames())

func record_hit(hit: Dictionary, index: int) -> void:
	contacts.append({"hit":hit.duplicate(true),"index":index,"frame":Engine.get_process_frames(),
		"cue_count":cues.size(),"phase":stage.phase,"pose":stage.active_attacker.pose,
		"has_impact_stream":stage.sound.stream != null,"impact_playing":stage.sound.playing})

func hit(damage: int = 5, blocked: int = 0, killed: bool = false) -> Dictionary:
	return {"damage":damage,"blocked":blocked,"hpAfter":0 if killed else 95,"killed":killed}

func destroy_stage() -> void:
	check(await preload("res://scripts/combat/audio_cleanup.gd").release(stage, get_tree()), "Stage audio playback references drain before disposal")
	stage.queue_free()
	await get_tree().process_frame
	stage = null

func test_melee(style: String, blocked: int = 0, lethal: bool = false) -> void:
	fixture()
	var hits := [hit(0 if blocked else 5, blocked, lethal),hit(),hit()]
	var before := hits.duplicate(true)
	await stage.attack(stage.player,stage.enemies[0],style,hits,record_hit)
	var expected := 1 if lethal else 3
	var label := "%s blocked=%d lethal=%s" % [style,blocked,lethal]
	check(cues.size() == expected,label+" emits exactly one slash per executed segment")
	check(contacts.size() == expected,label+" preserves contact count and death truncation")
	check(hits == before,label+" leaves supplied model hit results untouched")
	for i in cues.size():
		check(cues[i].cue == "slash" and cues[i].pose == style,label+" sound begins in attack pose")
		check(i < contacts.size() and contacts[i].cue_count == i+1,label+" cue precedes matching contact")
	check(stage.sound.stream != null,label+" retains original impact player")
	if lethal: check(not stage.enemies[0].alive,label+" marks dead defender")
	await destroy_stage()

func test_ranged(blocked: int = 0, lethal: bool = false, routed: bool = false) -> void:
	fixture()
	stage.player.set_combat_stance("ranged")
	var hits := [hit(0 if blocked else 5,blocked,lethal),hit(),hit()]
	var before := hits.duplicate(true)
	if routed:
		await stage.attack(stage.player,stage.enemies[0],"shoot",hits,record_hit)
	else:
		await stage.ranged_attack(stage.player,stage.enemies[0],hits,record_hit)
	var expected := 1 if lethal else 3
	var label := "shoot blocked=%d lethal=%s routed=%s" % [blocked,lethal,routed]
	check(cues.size() == expected,label+" emits one gunshot per executed segment")
	check(contacts.size() == expected and muzzle_frames.size() == expected,label+" contacts and muzzle flashes match shots")
	check(hits == before,label+" preserves supplied results")
	for i in cues.size():
		check(cues[i].cue == "shoot" and cues[i].pose == "shoot",label+" uses shooting pose and cue")
		check(i < muzzle_frames.size() and cues[i].frame == muzzle_frames[i],label+" gunshot and muzzle flash share a frame")
		check(i < contacts.size() and cues[i].frame == contacts[i].frame,label+" gunshot and impact share a frame")
	check(stage.sound.stream != null,label+" retains impact player separately")
	if lethal: check(not stage.enemies[0].alive,label+" marks dead defender")
	await destroy_stage()

func test_bite_and_invalid_attacks() -> void:
	fixture("fish")
	await stage.attack(stage.enemies[0],stage.player,"pierce",[hit(),hit()],record_hit)
	check(contacts.size() == 2,"Fish override executes both bite contacts")
	check(cues.size() == 2 and cues[0].cue == "bite" and cues[1].cue == "bite", "Fish bite override replaces pierce with one bite sample per contact")
	check(stage.sound.stream == null,"Unblocked bite sample replaces the procedural impact")
	await destroy_stage()
	fixture()
	stage.enemies[0].alive = false
	await stage.attack(stage.player,stage.enemies[0],"slash",[hit()],record_hit)
	await stage.ranged_attack(stage.player,stage.enemies[0],[hit()],record_hit)
	check(cues.is_empty() and contacts.is_empty(),"Dead defender produces no attack sounds or contacts")
	stage.enemies[0].alive = true
	stage.player.alive = false
	await stage.attack(stage.player,stage.enemies[0],"slash",[hit()],record_hit)
	await stage.ranged_attack(stage.player,stage.enemies[0],[hit()],record_hit)
	check(cues.is_empty() and contacts.is_empty(),"Dead attacker produces no attack sounds or contacts")
	await destroy_stage()

# Parse the same contract as published actions; never write a catalog or fixture file.
func install_authored_hit(actor: Node2D, style: String = "hit", strike_pose: String = "hit") -> void:
	var problems: Array[String] = []
	var parsed := AttackConfig.parse({style:{"type":"hit", "movement":"approach",
		"windupPose":"idle", "strikePose":strike_pose, "recoveryPose":"idle",
		"windup":0.04, "impactDelay":0.02, "recovery":0.04, "flightTime":0.0,
		"muzzle":[0,0], "contact":[0,-62],
		"muzzleTexture":"", "projectileTexture":"", "impactTexture":""}}, actor.poses, actor.pose_aliases, problems)
	check(problems.is_empty() and parsed.has(style),"In-memory authored hit uses a legal parsed action")
	actor.pipeline_attacks = parsed

func test_contact_route(profile: String, cue: String, authored: bool, blocked: int = 0, lethal: bool = false, pose_name: String = "", segments: int = 2) -> void:
	# preview_luggage_lurker selects the real published profile, independent of encounter bindings.
	fixture(profile,1,true)
	var actor: Node2D = stage.enemies[0]
	if authored and cue == "hit": install_authored_hit(actor)
	check(actor.kind == profile,profile+" resolves its actual visual profile")
	check(actor.pipeline_attacks.has(cue) == authored,profile+" exercises the intended ordinary/authored branch")
	var hits := [hit(0 if blocked else 5,blocked,lethal)]
	if segments > 1: hits.append(hit(0 if blocked else 5,blocked))
	var before := hits.duplicate(true)
	# The intent still says pierce; profile overrides select bite/hit presentation.
	await stage.attack(actor,stage.player,"pierce",hits,record_hit)
	var expected := 1 if lethal else segments
	var expected_pose := pose_name if not pose_name.is_empty() else ("bite_close" if cue == "bite" else "hit")
	expected_pose = actor.pose_aliases.get(expected_pose,expected_pose)
	var label := "%s authored=%s blocked=%d lethal=%s" % [profile,authored,blocked,lethal]
	check(cues.size() == expected,label+" emits exactly one corresponding sample per executed segment")
	check(contacts.size() == expected,label+" preserves contact count and lethal truncation")
	check(hits == before,label+" leaves supplied hit results untouched")
	for i in contacts.size():
		check(contacts[i].hit == hits[i] and contacts[i].index == i,label+" reveals each supplied result once in order")
		check(contacts[i].has_impact_stream == (blocked > 0),
			label+" keeps a separate metallic block transient and avoids doubled ordinary impacts")
		if blocked: check(contacts[i].impact_playing,label+" metallic block feedback is playing at contact")
	for i in cues.size():
		check(cues[i].cue == cue,label+" routes the resolved attack rather than requested pierce")
		check(cues[i].pose == expected_pose,label+" sample occurs in the contact pose")
		check(i < contacts.size() and cues[i].frame == contacts[i].frame and contacts[i].cue_count == i+1,
			label+" sample precedes its callback in the same frame")
		if authored:
			check(cues[i].phase == "impact" and i < contacts.size() and contacts[i].phase == "impact",
				label+" authored sample and callback occur in impact phase")
	check(stage.sound.bus == "SFX",label+" metallic feedback stays on SFX")
	if lethal: check(not stage.player.alive,label+" retires the defender before a second segment")
	await destroy_stage()

func test_authored_type_routing() -> void:
	fixture("luggage_lurker",1,true)
	var actor: Node2D = stage.enemies[0]
	check(actor.pipeline_attacks.has("bite"),"Published luggage lurker supplies its authored bite")
	if actor.pipeline_attacks.has("bite"):
		# An explicitly selected action can retain a legacy pierce key and still be a bite.
		actor.pipeline_attacks["pierce"] = actor.pipeline_attacks.bite.duplicate(true)
		await stage.attack(actor,stage.player,"pierce",[hit()],record_hit)
		check(cues.size() == 1 and cues[0].cue == "bite","Authored bite type wins over a pierce action key without a slash layer")
		check(contacts.size() == 1 and stage.sound.stream == null,"Authored bite type replaces the procedural ordinary impact")
	await destroy_stage()
	for style in ["slash","pierce"]:
		fixture("noss_hand",1,true)
		install_authored_hit(stage.enemies[0],style)
		await stage.attack(stage.enemies[0],stage.player,style,[hit()],record_hit)
		check(cues.size() == 1 and cues[0].cue == "slash","Authored hit template preserves %s blade start cue" % style)
		if cues.size() == 1:
			check(cues[0].phase == "strike","Authored %s slash cue still begins at strike" % style)
		check(contacts.size() == 1 and contacts[0].cue_count == 1 and stage.sound.stream != null,
			"Authored %s blade contact preserves its procedural impact without a blunt sample" % style)
		await destroy_stage()

func test_mouse_routes() -> void:
	var enemies: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies/enemies.json"))
	var resolver := EnemyVisualResolver.new()
	for id in ["mutant_mouse","mutant_mouse_second"]:
		check(enemies.has(id),id+" is present in the formal enemy catalog")
		if not enemies.has(id): continue
		var visual := resolver.resolve(enemies[id],enemies)
		check(visual.id == "mutant_mouse",id+" uses the mouse profile in actual encounter resolution")
		fixture("mutant_mouse",1,true)
		var hits := [hit(),hit(0,10)]
		var before := hits.duplicate(true)
		await stage.attack(stage.enemies[0],stage.player,"pierce",hits,record_hit)
		check(cues.size() == 2 and contacts.size() == 2,id+" executes two slash cues and contacts")
		check(hits == before,id+" preserves supplied damage and block results")
		for i in cues.size():
			check(cues[i].cue == "slash" and cues[i].pose == "pierce",id+" uses slash audio with the existing lunge pose")
			check(i < contacts.size() and cues[i].frame <= contacts[i].frame and contacts[i].cue_count == i+1,
				id+" plays one slash per segment before its normal or blocked contact")
		check(stage.sound.stream != null,id+" retains separate contact and block feedback")
		await destroy_stage()
	fixture("mutant_mouse",1,true)
	install_authored_hit(stage.enemies[0],"pierce","pierce")
	await stage.attack(stage.enemies[0],stage.player,"pierce",[hit()],record_hit)
	check(cues.size() == 1 and cues[0].cue == "slash" and cues[0].pose == "pierce",
		"Authored mouse hit template keeps pierce motion and uses the slash cue")
	check(contacts.size() == 1 and stage.sound.stream != null,"Authored mouse retains its ordinary impact transient")
	if cues.size() == 1 and contacts.size() == 1:
		check(cues[0].phase == "strike" and cues[0].frame <= contacts[0].frame,"Authored mouse slash starts at strike before contact")
	await destroy_stage()

func test_contact_dead_and_death_silence(profile: String, authored_hit: bool = false) -> void:
	fixture(profile,1,true)
	var actor: Node2D = stage.enemies[0]
	if authored_hit: install_authored_hit(actor)
	actor.alive = false
	await stage.attack(actor,stage.player,"pierce",[hit()],record_hit)
	check(cues.is_empty() and contacts.is_empty(),profile+" dead attacker produces no sample or contact")
	actor.alive = true
	stage.player.alive = false
	await stage.attack(actor,stage.player,"pierce",[hit()],record_hit)
	check(cues.is_empty() and contacts.is_empty(),profile+" dead defender produces no sample or contact")
	stage.player.alive = true
	await stage.retire_actor(actor)
	check(cues.is_empty() and contacts.is_empty(),profile+" retirement adds no bite/hit/death cue")
	await destroy_stage()

func test_contact_resources() -> void:
	fixture()
	check(AudioServer.get_bus_index("SFX") >= 0,"Contact samples have a real SFX bus")
	for cue in CONTACT_CLIPS:
		var stream: AudioStream = stage.combat_audio.CLIPS.get(cue)
		check(stream != null and stream.resource_path == CONTACT_CLIPS[cue],cue+" binds the exact accepted MP3")
		if stream == null: continue
		check(stream is AudioStreamMP3 and stream.get_length() > 0.0,cue+" loads as a nonempty MP3 stream")
		var start_offset: float = stage.combat_audio.START_OFFSETS.get(cue,0.0)
		check(is_equal_approx(start_offset,0.38 if cue == "bite" else 0.04) and start_offset < stream.get_length(),
			cue+" starts after its leading silence within the original source")
		var playback := stream.instantiate_playback()
		check(playback != null,cue+" creates a real decoder")
		if playback == null: continue
		playback.start()
		var peak := 0.0
		# Decode the source instead of trusting metadata or the presence of imported bytes.
		for _chunk in ceili(stream.get_length()*AudioServer.get_mix_rate()/4096.0)+1:
			var samples := playback.mix_audio(1.0,4096)
			for sample in samples: peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		playback.stop()
		check(peak > 0.0001,cue+" decodes into non-silent PCM samples")
	await destroy_stage()

func test_return() -> void:
	fixture("gang_henchman",2)
	await stage.return_home()
	check(cues.size() == 1 and cues[0].cue == "snap","Stationary survivors share one return snap")
	cues.clear()
	stage.player.position += Vector2(150,15)
	var departure: Vector2 = stage.player.position
	await stage.return_home()
	check(cues.size() == 1 and cues[0].cue == "snap","Single living return plays one finger snap")
	if cues.size() == 1:
		check(cues[0].phase == "return_light" and cues[0].player_position == departure and cues[0].player_alpha > 0.99,"Snap occurs at initial vanish before relocation/fade")
	check(stage.player.position == stage.player.home,"Single return finishes at home")
	cues.clear()
	stage.player.position += Vector2(100,10)
	stage.enemies[0].position += Vector2(-100,-10)
	stage.enemies[1].position += Vector2(-150,20)
	stage.enemies[1].alive = false
	var dead_position: Vector2 = stage.enemies[1].position
	await stage.return_home()
	check(cues.size() == 1 and cues[0].cue == "snap","Several living actors return with one shared snap")
	check(stage.player.position == stage.player.home and stage.enemies[0].position == stage.enemies[0].home,"All living displaced actors arrive home")
	check(stage.enemies[1].position == dead_position and not stage.enemies[1].alive,"Dead displaced actor does not return")
	cues.clear()
	await stage.return_home()
	check(cues.size() == 1 and cues[0].cue == "snap","Stationary survivors still return while dead actor stays excluded")
	cues.clear()
	stage.player.alive = false
	stage.enemies[0].alive = false
	await stage.return_home()
	check(cues.is_empty(),"No living actors: silent return")
	await destroy_stage()

func audio_players(node: Node) -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = []
	for child in node.get_children():
		if child is AudioStreamPlayer: players.append(child)
	return players

func test_playback_lifecycle() -> void:
	fixture()
	var recorder := AudioEffectRecord.new()
	var recording := AudioServer.get_driver_name() != "Dummy"
	var effect_index := AudioServer.get_bus_effect_count(0)
	if recording:
		recorder.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(0,recorder)
		recorder.set_recording_active(true)
	var controller: Node = stage.combat_audio
	controller.play_cue("slash")
	var first: Array[AudioStreamPlayer] = audio_players(controller)
	check(first.size() == 1 and first[0].playing,"Slash starts a real audio player")
	controller.play_cue("shoot")
	controller.play_cue("snap")
	controller.play_cue("slash")
	controller.play_cue("bite")
	controller.play_cue("hit")
	controller.play_cue("bite")
	var players := audio_players(controller)
	check(players.size() == 7,"Overlapping and repeated slash/shoot/snap/bite/hit cues own independent players")
	check(first.size() == 1 and is_instance_valid(first[0]) and first[0].playing,"Later sounds do not stop the first slash")
	var longest := 0.0
	for player in players:
		check(player.playing and player.stream != null and player.stream.get_length() > 0.0,"Each concurrent player has nonempty playing audio")
		check(player.bus == "SFX","Each independent action voice uses SFX")
		longest = maxf(longest,player.stream.get_length()/player.pitch_scale)
	stage.play_hit_sound(true)
	check(stage.sound.playing and audio_players(controller).size() == 7,"Existing impact can play alongside all action sounds")
	# MP3 completion follows the real audio thread, even when --fixed-fps makes
	# scene timers advance much faster. Observe natural completion, never stop it.
	var completion_deadline := Time.get_ticks_msec()+int((longest+1.0)*1000.0)
	while not audio_players(controller).is_empty() and Time.get_ticks_msec() < completion_deadline:
		OS.delay_msec(1)
		await get_tree().process_frame
	check(audio_players(controller).is_empty(),"All transient players free themselves after natural completion")
	if recording:
		recorder.set_recording_active(false)
		var capture: AudioStreamWAV = recorder.get_recording()
		AudioServer.remove_bus_effect(0,effect_index)
		var peak := 0
		var clipped := 0
		var samples := capture.data
		for offset in range(0,samples.size(),2):
			var sample := absi(samples.decode_s16(offset))
			peak = maxi(peak,sample)
			if sample >= 32767: clipped += 1
		check(peak > 100,"Actual device mix contains non-silent samples")
		check(clipped == 0,"Concurrent cues and impact produce no full-scale clipped samples")
		var output := "res://artifacts/qa/noren-consolidation-2026-10-19/combat-audio/output.wav"
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		check(capture.save_to_wav(output) == OK,"Actual mix capture is saved")
		print("AUDIO MIX driver=%s peak=%d clipped=%d seconds=%.3f path=%s" % [AudioServer.get_driver_name(),peak,clipped,capture.get_length(),output])
	controller.play_cue("shoot")
	var exiting := audio_players(controller)
	check(exiting.size() == 1 and exiting[0].playing,"Exit cleanup starts with active playback")
	await destroy_stage()
	check(not is_instance_valid(controller),"Removing stage releases its audio controller")
	for player in exiting: check(not is_instance_valid(player),"Removing stage releases active audio player")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://combat_audio_unused.json"
	Game.meta_path = "user://combat_audio_meta_unused.json"
	var original_state: Dictionary = Game.state.duplicate(true)
	var original_revision: int = Game.revision
	print("AUDIO DRIVER: "+AudioServer.get_driver_name())
	get_tree().create_timer(120.0).timeout.connect(func():
		push_error("Combat audio tests timed out")
		get_tree().quit(2))
	await test_melee("slash")
	await test_melee("pierce",10)
	await test_melee("slash",0,true)
	await test_ranged()
	await test_ranged(10)
	await test_ranged(0,true)
	await test_ranged(0,false,true)
	await test_bite_and_invalid_attacks()
	for route in [{"profile":"fish","cue":"bite","authored":false},
		{"profile":"luggage_lurker","cue":"bite","authored":true},
		{"profile":"noss_hand","cue":"hit","authored":false},
		{"profile":"noss_hand","cue":"hit","authored":true}]:
		await test_contact_route(route.profile,route.cue,route.authored)
		await test_contact_route(route.profile,route.cue,route.authored,10)
		await test_contact_route(route.profile,route.cue,route.authored,0,true)
	await test_authored_type_routing()
	await test_mouse_routes()
	for profile in ["fish","luggage_lurker","noss_hand","mutant_mouse"]:
		await test_contact_dead_and_death_silence(profile)
	await test_contact_dead_and_death_silence("noss_hand",true)
	await test_contact_resources()
	await test_return()
	await test_playback_lifecycle()
	# Allow the audio thread to release the just-stopped voice before engine shutdown.
	await get_tree().create_timer(0.12).timeout
	check(Game.state == original_state and Game.revision == original_revision,"Presentation tests preserve adventure state and revision")
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path),"Presentation tests never create save files")
	print("COMBAT AUDIO TESTS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
