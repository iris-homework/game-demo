extends Node
## Exercise the real presentation stage with supplied hit results; no model or RNG calls.
const Stage = preload("res://scripts/combat/test_stage.gd")
const GunBurst = preload("res://scripts/combat/gun_burst_fx.gd")
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

func fixture(profile: String = "finn", count: int = 1) -> void:
	stage = Stage.new()
	add_child(stage)
	var resolver := EnemyVisualResolver.new()
	var visuals: Array[EnemyVisualResolver.Visual] = []
	for i in count:
		visuals.append(resolver.resolve({"id":"audio_%d" % i,"combatVisualId":profile}, {}))
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
	contacts.append({"hit":hit.duplicate(true),"index":index,"frame":Engine.get_process_frames(),"cue_count":cues.size()})

func hit(damage: int = 5, blocked: int = 0, killed: bool = false) -> Dictionary:
	return {"damage":damage,"blocked":blocked,"hpAfter":0 if killed else 95,"killed":killed}

func destroy_stage() -> void:
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
	check(cues.is_empty(),"Fish bite override never plays blade or gunshot cues")
	check(stage.sound.stream != null,"Bite keeps its existing impact sound")
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

func test_return() -> void:
	fixture("finn",2)
	await stage.return_home()
	check(cues.is_empty(),"Everyone at home: silent return")
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
	check(cues.is_empty(),"Only dead actor remains displaced: silent return")
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
	var players := audio_players(controller)
	check(players.size() == 4,"Overlapping and repeated cues own independent players")
	check(first.size() == 1 and is_instance_valid(first[0]) and first[0].playing,"Later sounds do not stop the first slash")
	var longest := 0.0
	for player in players:
		check(player.playing and player.stream != null and player.stream.get_length() > 0.0,"Each concurrent player has nonempty playing audio")
		longest = maxf(longest,player.stream.get_length()/player.pitch_scale)
	stage.play_hit_sound(true)
	check(stage.sound.playing and audio_players(controller).size() == 4,"Existing impact can play alongside all action sounds")
	await get_tree().create_timer(longest+0.40).timeout
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
		var output := "res://artifacts/qa/combat-audio-2026-10-17/preview/output.wav"
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
	get_tree().create_timer(60.0).timeout.connect(func():
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
	await test_return()
	await test_playback_lifecycle()
	# Allow the audio thread to release the just-stopped voice before engine shutdown.
	await get_tree().create_timer(0.12).timeout
	check(Game.state == original_state and Game.revision == original_revision,"Presentation tests preserve adventure state and revision")
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path),"Presentation tests never create save files")
	print("COMBAT AUDIO TESTS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
