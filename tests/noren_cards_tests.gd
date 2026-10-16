extends Node
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func fixture(ids: Array = [1], form: String = "melee", count: int = 1) -> CombatModel:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules,true)
	rules.shuffleInitialDeck = false
	rules.deck = []
	for number in ids: rules.deck.append("noren_%02d" % int(number))
	for i in 12: rules.deck.append("noren_01")
	var enemies: Array = []
	for i in count:
		enemies.append({"id":"qa_%d" % i,"displayName":"靶子","maxHp":1000,"battlePortraitAssetId":"","intentSequence":[{"type":"attack","amount":10,"hits":1}]})
	var m := CombatModel.new()
	m.initialize("B04",100,100,rules,enemies,Game.card_catalog)
	m.stance = form
	m.opening_draw_done = true
	for i in ids.size():
		var uid := "card_%03d" % i
		m.draw_pile.erase(uid)
		m.hand.append(uid)
	return m

func play(m: CombatModel, index: int = 0, target: int = 0, discard: String = "", extra: int = 0) -> Dictionary:
	return m.play_card("card_%03d" % index,target,discard,extra)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://noren_cards_qa.json"
	Game.meta_path = "user://noren_cards_meta_qa.json"
	check(Game.card_catalog.size() == 40,"40 definitions")
	var rarities := {"C":0,"B":0,"A":0,"S":0}
	for definition in Game.card_catalog.values(): rarities[definition.rarity] += 1
	check(rarities == {"C":4,"B":22,"A":10,"S":4},"Rarity distribution")
	Game.state = Game.initial_state()
	check(Game.state.deck.is_empty(),"No nonstarter owned on new adventure")
	check(Game.owned_card_counts() == {"noren_01":4,"noren_02":4,"noren_03":1,"noren_04":1},"Exact initial ownership")
	var base_damage := {1:6,9:5,10:5,13:8,14:5,16:13,17:12,19:5,20:10,21:7,25:12,26:20,27:5,28:6,29:10,35:6,36:4,37:4,38:4}
	var ranged_damage := {1:9,9:8,10:8,13:12,14:8,16:20,17:18,19:8,20:15,21:11,25:18,26:30,27:8,28:10,29:15,35:10,36:8,37:6,38:6}
	var blocks := {2:5,3:6,4:4,6:4,11:7,31:4,32:10,33:6}
	for form in ["melee","ranged"]:
		for number in range(1,41):
			var m := fixture([number,1],form)
			var result := play(m,0,0,"card_001" if number == 12 else "")
			var label := "%02d %s" % [number,form]
			check(not result.is_empty(),label+" playable")
			if result.is_empty(): continue
			check(result.damage == (base_damage if form == "melee" else ranged_damage).get(number,0),label+" exact damage")
			check(m.energy == 3-int(Game.card_catalog["noren_%02d" % number].cost),label+" exact cost")
			check(m.block == blocks.get(number,0),label+" block")
			check(("card_000" in m.exhaust_pile) == (number in [5,8,12,15,22,23,33,34,40]),label+" exhaust/power destination")
			check(not "card_000" in m.hand and not "card_000" in m.draw_pile,label+" played card cannot redraw itself")
			check(Game.valid_combat(m.snapshot()),label+" snapshot valid")
			var saved_state: Dictionary=JSON.parse_string(JSON.stringify(m.snapshot()))
			var restored_state:=CombatModel.new()
			restored_state.restore(saved_state)
			check(JSON.parse_string(JSON.stringify(restored_state.snapshot()))==saved_state,label+" exact JSON restore")
	# Exact status and state-dependent branches.
	var m := fixture([27,28,29,30,34])
	play(m)
	check(m.enemies[0].bleed == 2,"Melee applies full bleed")
	m.energy = 3
	play(m,3)
	check(m.enemies[0].bleed == 6,"Deepen doubles only on wounded melee target")
	m = fixture([27,35],"ranged")
	play(m)
	check(m.enemies[0].bleed == 1,"Ranged new bleed is applied after all hits, halved")
	var result := play(m,1)
	check(result.damage == 11 and m.enemies[0].bleed == 0,"Ranged segments consume existing bleed once each")
	m = fixture([36],"ranged"); m.enemies[0].bleed = 5
	result = play(m)
	check(result.damage == 22 and result.hits.size() == 4 and m.enemies[0].bleed == 1,"Four shots: 2*4 + 5+4+3+2, one ammo")
	check(m.ammo == 1,"Multi-hit spends one ammo")
	m = fixture([37],"ranged"); m.enemies[0].bleed = 5
	result = play(m)
	check(result.damage == 21 and result.hits.size() == 2,"Hunt checks starting bleed and fires twice")
	m = fixture([37],"ranged"); m.enemies[0].bleed = 4
	check(play(m).hits.size() == 1,"Hunt threshold excludes four")
	m = fixture([38],"ranged",3)
	for enemy in m.enemies: enemy.bleed = 4
	result = play(m)
	check(result.damage == 30 and result.hits.size() == 3 and m.ammo == 1,"AoE spends one ammo and triggers each target bleed")
	check(m.enemies.all(func(e): return e.bleed == 4),"AoE new bleed applied after every hit")
	m = fixture([39]);m.enemies[0].bleed = 4
	result = play(m)
	check(m.block == 4 and result.drawn.size() == 2,"Tracking draws two and checks start-of-card bleed")
	m = fixture([15,35],"ranged")
	play(m);result = play(m,1)
	check(result.hits[0].attackDamage == 11 and result.hits[1].attackDamage == 5,"First-segment buff before multiplier; round each segment")
	m = fixture([23,35,13],"ranged")
	play(m);result = play(m,1)
	check(result.hits[0].damage == 9 and result.hits[1].damage == 5,"Pressure once on first segment")
	check(play(m,2).damage == 12,"Pressure does not repeat in turn")
	m = fixture([40,34,30]);play(m);play(m,1)
	check(m.enemies[0].bleed == 3,"Dissection adds one on first single-target melee application")
	play(m,2)
	check(m.enemies[0].bleed == 7,"Dissection does not repeat")
	m = fixture([40,34],"ranged");play(m);play(m,1)
	check(m.enemies[0].bleed == 1 and not m.dissection_used,"Dissection not triggered in ranged")
	m = fixture([40,40]);play(m)
	var before := m.snapshot()
	check(not play(m,1).is_empty() and m.powers==["dissection"] and m.exhaust_pile.size()==2 and m.energy==1,"Duplicate ability leaves cycle and pays cost without stacking")
	m = fixture([21],"ranged"); m.ammo=1
	check(play(m).damage == 15 and m.ammo == 0,"Last bullet checks prepayment ammo")
	m = fixture([25],"ranged");m.enemies[0].hp = 500
	check(play(m).damage == 27,"Execution includes exactly 50 percent")
	m = fixture([25],"ranged");m.enemies[0].hp = 501
	check(play(m).damage == 18,"Execution excludes above threshold")
	for extra in 3:
		m = fixture([20],"ranged");m.ammo=6
		check(play(m,0,0,"",extra).damage == roundi((10+extra*4)*1.5) and m.ammo == 5-extra,"Overload optional ammo %d" % extra)
	m = fixture([26],"ranged");m.ammo=2
	check(play(m,0,0,"",1).damage == 39 and m.ammo == 0,"Finisher optional bullet")
	m = fixture([20],"ranged");m.ammo=2;before=m.snapshot()
	check(play(m,0,0,"",2).is_empty() and m.snapshot()==before,"Extra ammo fails atomically")
	m = fixture([16],"ranged");m.enemies[0].block=100
	check(play(m).damage==20 and m.enemies[0].block==100,"Ranged piercing ignores block")
	m = fixture([16]);m.enemies[0].block=100
	check(play(m).damage==0 and m.enemies[0].block==87,"Melee piercing obeys block")
	m = fixture([4,1,3,1]);play(m)
	check(m.stance=="ranged" and m.stance_discount and m.block==4,"Enter ranged grants attack discount")
	check(m.card_cost("card_001")==0,"Discount reflected in actual cost")
	result=play(m,1)
	check(result.damage==9 and m.energy==2 and not m.stance_discount,"Discount consumed once")
	result=play(m,2)
	check(m.stance=="melee" and result.drawn.size()==1,"Enter melee draws one")
	m = fixture([3]);result=play(m)
	check(result.drawn.is_empty(),"No entry reward when stance unchanged")
	m=fixture([10]);result=play(m)
	check(result.damage==5 and m.ammo==3 and m.stance=="ranged" and m.stance_discount,"Retreat attack uses old melee stance then switches")
	m=fixture([9],"ranged");result=play(m)
	check(result.damage==8 and m.ammo==1 and m.stance=="melee" and result.drawn.size()==1,"Cut-in attacks ranged then enters melee")
	m=fixture([22,1]);play(m);m.stance_discount=true
	check(m.card_cost("card_001")==0,"Multiple reductions floor at zero")
	m.end_turn()
	check(m.turn_discount==0 and m.stance_discount,"Turn discount expires; stance reward persists")
	m=fixture([1],"ranged");m.ammo=0;before=m.snapshot()
	check(play(m).is_empty() and m.snapshot()==before,"No-ammo attack fails atomically")
	m=fixture([1]);m.energy=0;before=m.snapshot()
	check(play(m).is_empty() and m.snapshot()==before,"No-energy attack fails atomically")
	m=fixture([1]);before=m.snapshot()
	check(play(m,0,4).is_empty() and m.snapshot()==before,"Invalid enemy fails atomically")
	m=fixture([12,2]);before=m.snapshot()
	check(play(m,0,0,"card_001").is_empty() and m.snapshot()==before,"Dismantle cannot discard a skill")
	m=fixture([12,1]);result=play(m,0,0,"card_001")
	check(m.ammo==4 and m.discard_pile==["card_001"] and m.exhaust_pile==["card_000"],"Dismantle exact chosen instance")
	m=fixture([17]);m.ammo=5;play(m)
	check(m.ammo==6,"Ammo cap applies to normal and extra gains")
	m=fixture([14]);play(m);check(m.enemies[0].weak==1,"Melee butt applies weak")
	m=fixture([11],"ranged");play(m);check(m.enemies[0].weak==1 and m.block==7,"Ranged steady targets enemy")
	m=fixture([31,32,33]);play(m);m.energy=3;play(m,1);m.energy=3;play(m,2)
	check(m.parry==2,"Parry limits never add beyond two")
	m.enemies[0].intent={"type":"attack","amount":10,"hits":3}
	m.enemies[0].weak=2;m.block=100;m.stance="ranged"
	result=m.end_turn()
	check(result.attacks[0].hits.size()==3 and m.player_hp==100,"Block absorbs weakened enemy segments")
	check(result.attacks[0].counters.size()==2 and result.attacks[0].counters[0].damage==6,"Parry uses weakened pre-block total once per attack")
	check(m.parry==1 and m.enemies[0].bleed==2,"Each parry layer adds unhalved bleed; consumes one layer")
	check(m.block==0 and m.energy==3 and m.turn==2 and m.hand.size()==5,"New turn clears own block and draws five")
	m=fixture([19]);m.enemies[0].weak=5;play(m)
	check(m.enemies[0].weak==5,"Weak caps at five")
	m=fixture([1]);m.enemies[0].hp=1
	check(play(m).outcome=="win","Natural victory")
	m=fixture([1]);m.player_hp=1
	check(m.end_turn().outcome=="lose","Natural defeat")
	# Persistent ownership, frozen battle, save validation and console errors.
	Game.state=Game.initial_state()
	Game.state.activeEventId="E04";Game.state.currentPlaceId="alley";Game.enter_node("battle")
	var frozen: Dictionary=Game.state.combat.duplicate(true)
	check(Game.console_command("addcard 短点连射 2").begins_with("已添加"),"Console Chinese name")
	check(Game.console_command("addcard 23").begins_with("已添加"),"Console number")
	check(Game.console_command("addcard noren_40").begins_with("已添加"),"Console ID")
	check(Game.owned_card_counts().get("noren_36")==2 and Game.state.combat==frozen,"Adds owned copies without mutating running battle")
	var deck: Array=Game.state.deck.duplicate()
	for command in ["addcard 不存在","addcard 41","addcard 1 0","addcard 1 -2","addcard 1 1.5","addcard 1 100","addcard 1 2 extra"]:
		Game.console_command(command)
		check(Game.state.deck==deck,"Invalid command atomic: "+command)
	Game.initialize_combat()
	check(Game.state.combat.instances.size()==14,"Next battle includes owned additions")
	m=CombatModel.new();m.restore(Game.state.combat);m.draw_cards()
	m.stance="ranged";m.ammo=4;m.parry=2;m.block=11;m.stance_discount=true
	Game.commit_combat(m)
	check(Game.save_game() and Game.load_game(),"Formal save roundtrip")
	check(Game.state.combat.norenState.parry==2 and Game.state.combat.norenState.block==11,"Combat state restored")
	var malformed: Dictionary=Game.state.combat.duplicate(true);malformed.norenState.ammo=99
	check(not Game.valid_combat(malformed),"Reject corrupt ammo")
	malformed=Game.state.combat.duplicate(true);malformed.norenState.exhaustPile.append(malformed.hand[0])
	check(not Game.valid_combat(malformed),"Reject duplicate exhausted instance")
	var original: Dictionary=Game.state.duplicate(true)
	Game.start_training("B04")
	check(Game.state.combat.instances.size()==14,"Training copies owned cards")
	check(Game.console_command("addcard 23").begins_with("演练"),"Training cannot alter adventure ownership")
	Game.finish_training("lose")
	check(Game.state==original,"Training restores adventure exactly")
	var legacy=Game.read_data("prototype/combat.json")
	m=CombatModel.new();m.initialize("B04",100,100,legacy,[Game.enemy_catalog[Game.battles.B04.enemyIds[0]]]);m.draw_cards()
	check(m.play_card(m.hand[0],0).damage==1,"Legacy snapshots retain old rules")
	check(Game.valid_combat(m.snapshot()),"Legacy snapshot valid")
	Game.state=Game.initial_state();Game.save_enabled=true
	check(Game.console_command("addcard 23").begins_with("已添加"),"Console writes an isolated checkpoint")
	Game.state={}
	check(Game.load_game() and Game.state.deck==["noren_23"],"Console ownership survives actual disk reload")
	var valid_path:=Game.save_path
	Game.save_path="user://missing_noren_qa_dir/checkpoint.json"
	check(Game.console_command("addcard 36").begins_with("添加失败") and Game.state.deck==["noren_23"],"Console save failure rolls ownership back")
	Game.save_path=valid_path;Game.save_enabled=false
	for name in ["checkpoint.json","checkpoint.json.bak"]:
		var path: String="res://artifacts/qa/noren-cards-2026-10-16/save-backup/"+name
		if FileAccess.file_exists(path):
			check(Game.valid_save(Game.migrate_save(JSON.parse_string(FileAccess.get_file_as_string(path)))),"Actual pre-change save copy remains loadable: "+name)
	for path in [Game.save_path,Game.save_path+".bak",Game.save_path+".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("NOREN CARDS: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
