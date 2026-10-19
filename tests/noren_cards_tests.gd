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

func four_hit_fixture(form: String = "melee") -> CombatModel:
	var m:=fixture([35],form)
	m.card_catalog.noren_35.effects=[{"type":"damage","amount":1,"hits":4}]
	return m

func play(m: CombatModel, index: int = 0, target: int = 0, discard: String = "", extra: int = 0) -> Dictionary:
	return m.play_card("card_%03d" % index,target,discard,extra)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://noren_cards_qa.json"
	Game.meta_path = "user://noren_cards_meta_qa.json"
	check(Game.card_catalog.size() == 40,"40 definitions")
	var before_catalog := Game.card_catalog.duplicate(true)
	var browser_cards := Game.library_cards()
	var expected_order := [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,18,19,21,25,27,28,31,32,34,35,37,39,16,17,20,22,24,29,30,33,38,23,26,36,40]
	check(browser_cards.map(func(c): return int(c.number))==expected_order,"Catalogue follows C B A S and original number within each rarity")
	browser_cards[0].name="copy only"
	check(Game.card_catalog==before_catalog,"Display sorting and returned edits leave definitions unchanged")
	check(Game.card_display_before({"id":"legacy2"},{"id":"legacy10"}),"Unranked legacy cards retain natural ID fallback")
	var rarities := {"C":0,"B":0,"A":0,"S":0}
	for definition in Game.card_catalog.values(): rarities[definition.rarity] += 1
	check(rarities == {"C":4,"B":23,"A":9,"S":4},"Rarity distribution")
	Game.state = Game.initial_state()
	check(Game.state.deck.is_empty(),"No nonstarter owned on new adventure")
	check(Game.owned_card_counts() == {"noren_01":4,"noren_02":4,"noren_03":1,"noren_04":1},"Exact initial ownership")
	var base_damage := {1:6,9:8,13:8,14:5,16:8,17:12,19:5,20:9,21:7,25:12,26:30,27:5,28:6,29:10,35:6,37:5,38:4}
	var ranged_damage := {1:9,9:12,13:12,14:8,16:12,17:18,19:8,20:42,21:11,25:18,26:66,27:8,28:10,29:15,35:9,37:8,38:6}
	var blocks := {2:5,4:4,6:4,11:7,31:4,32:10,33:10}
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
			check(("card_000" in m.exhaust_pile) == (number in [5,8,12,15,22,23,34,36,40]),label+" exhaust/power destination")
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
	check(m.enemies[0].bleed == 8,"Deepen doubles only on wounded melee target")
	m = fixture([27,35],"ranged")
	play(m)
	check(m.enemies[0].bleed == 1,"Ranged new bleed is applied after all hits, halved")
	var result := play(m,1)
	check(result.damage == 10 and m.enemies[0].bleed == 0,"Ranged segments consume existing bleed once each")
	m = four_hit_fixture("ranged"); m.enemies[0].bleed = 5
	result = play(m)
	check(result.damage == 22 and result.hits.size() == 4 and m.enemies[0].bleed == 1,"Four shots: 2*4 + 5+4+3+2, one ammo")
	check(m.ammo == 1,"Multi-hit spends one ammo")
	m = fixture([37],"ranged"); m.enemies[0].bleed = 5
	result = play(m)
	check(result.damage == 17 and result.hits.size() == 1 and m.enemies[0].bleed==3,"Hunt triggers bleed exactly twice after one hit")
	m = fixture([37],"ranged"); m.enemies[0].bleed = 4
	check(play(m).damage == 15 and m.enemies[0].bleed==2,"Hunt no longer requires a bleed threshold")
	m = fixture([38],"ranged",3)
	for enemy in m.enemies: enemy.bleed = 4
	result = play(m)
	check(result.damage == 30 and result.hits.size() == 3 and m.ammo == 1,"AoE spends one ammo and triggers each target bleed")
	check(m.enemies.all(func(e): return e.bleed == 5),"AoE new bleed applied after every hit")
	m = fixture([39]);m.enemies[0].bleed = 4
	result = play(m)
	check(m.block == 0 and result.drawn.size() == 3,"Tracking draws a third card on starting bleed threshold")
	m = fixture([15,35],"ranged")
	play(m);result = play(m,1)
	check(result.hits[0].attackDamage == 9 and result.hits[1].attackDamage == 3,"First-segment buff before multiplier; round each segment")
	m = fixture([23,35,13],"ranged")
	play(m);result = play(m,1)
	check(result.hits.map(func(h): return h.damage)==[4,4,4],"Ranged mastery doubles all segments")
	check(play(m,2).damage == 16,"Ranged mastery applies to subsequent attacks")
	m = fixture([40,34,30]);play(m);play(m,1)
	check(m.enemies[0].bleed == 4,"Dissection adds one on first single-target melee application")
	play(m,2)
	check(m.enemies[0].bleed == 10,"Dissection does not repeat")
	m = fixture([40,34],"ranged");play(m);play(m,1)
	check(m.enemies[0].bleed == 2 and not m.dissection_used,"Dissection not triggered in ranged")
	m = fixture([40,40]);play(m)
	var before := m.snapshot()
	check(not play(m,1).is_empty() and m.powers==["dissection"] and m.exhaust_pile.size()==2 and m.energy==1,"Duplicate ability leaves cycle and pays cost without stacking")
	m = fixture([21],"ranged"); m.ammo=1
	check(play(m).damage == 15 and m.ammo == 0,"Last bullet checks prepayment ammo")
	m = fixture([25],"ranged");m.enemies[0].hp = 500
	check(play(m).damage == 27,"Execution includes exactly 50 percent")
	m = fixture([25],"ranged");m.enemies[0].hp = 501
	check(play(m).damage == 18,"Execution excludes above threshold")
	for bullets in [1,2,10]:
		m=fixture([20],"ranged");m.ammo=bullets
		result=play(m)
		check(result.damage==14*(1+bullets) and result.hits.size()==1+bullets and m.ammo==0,"Barrage spends all bullets and adds one segment per bullet")
	m=fixture([26],"ranged");m.ammo=2
	check(play(m).damage==66 and m.ammo==1,"Finisher adds fourteen base damage in ranged without extra ammo")
	m = fixture([20],"ranged");m.ammo=2;before=m.snapshot()
	check(play(m,0,0,"",2).is_empty() and m.snapshot()==before,"Extra ammo fails atomically")
	m = fixture([16],"ranged");m.enemies[0].block=100
	check(play(m).damage==0 and m.enemies[0].block==88,"Backstep Slash ranged damage obeys block")
	m = fixture([16]);m.enemies[0].block=100
	check(play(m).damage==0 and m.enemies[0].block==92,"Melee Backstep Slash obeys block")
	m = fixture([4,1,3,1]);play(m)
	check(m.stance=="ranged" and m.stance_discount and m.block==4,"Enter ranged grants attack discount")
	check(m.card_cost("card_001")==0,"Discount reflected in actual cost")
	result=play(m,1)
	check(result.damage==9 and m.energy==2 and not m.stance_discount,"Discount consumed once")
	result=play(m,2)
	check(m.stance=="melee" and result.drawn.size()==2 and m.parry==1 and m.block==4,"Enter melee draws two and Close In grants parry without block")
	m = fixture([3]);result=play(m)
	check(result.drawn.is_empty() and m.parry==1 and m.block==0,"Same stance grants parry without block or entry draw")
	for layers in [1,2,3]:
		m=fixture([3]);m.parry=layers;result=play(m)
		check(m.parry==mini(3,layers+1) and result.drawn.is_empty(),"Close In adds one parry up to the three-layer limit")
	m=fixture([8],"ranged");result=play(m)
	check(m.stance=="melee" and result.drawn.size()==2,"Emergency shift shares the two-card melee entry reward")
	m=fixture([3],"ranged")
	m.discard_pile.assign(m.draw_pile);m.draw_pile.clear()
	result=play(m)
	check(result.drawn.size()==2 and not "card_000" in result.drawn and Game.valid_combat(m.snapshot()),"Melee entry recycles discard without redrawing its resolving card")
	for available in [0,1]:
		m=fixture([3],"ranged")
		m.draw_pile.resize(available);m.discard_pile.clear()
		result=play(m)
		check(result.drawn.size()==available and m.parry==1,"Melee entry draws only available cards")
	m=fixture([10]);result=play(m)
	check(result.damage==0 and m.ammo==4 and m.stance=="ranged" and m.stance_discount,"Quick Reload grants ammo then switches as a skill")
	m=fixture([9],"ranged");result=play(m)
	check(result.damage==12 and m.ammo==1 and m.stance=="melee" and result.drawn.size()==2,"Cut-in attacks ranged then enters melee and draws two")
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
	m=fixture([17]);m.ammo=9;play(m)
	check(m.ammo==10,"Ammo cap applies to normal and extra gains")
	m=fixture([14]);play(m);check(m.enemies[0].weak==1,"Melee butt applies weak")
	m=fixture([11],"ranged");play(m);check(m.enemies[0].weak==1 and m.block==7,"Ranged steady targets enemy")
	m=fixture([31,32,33]);play(m);m.energy=3;play(m,1);m.energy=3;play(m,2)
	check(m.parry==3,"New Counter Stance adds one charge up to the three-layer cap")
	m.enemies[0].intent={"type":"attack","amount":10,"hits":3}
	m.enemies[0].weak=2;m.block=100;m.stance="ranged"
	result=m.end_turn()
	check(result.attacks[0].hits.size()==3 and m.player_hp==100,"Block absorbs weakened enemy segments")
	check(result.attacks[0].counters.size()==1 and result.attacks[0].counters[0].damage==12,"Parry uses weakened pre-block total once per attack")
	check(m.parry==2 and m.enemies[0].bleed==0 and m.ammo==3,"One parry consumes one charge and gains one ammo without bleed")
	check(m.block==0 and m.energy==3 and m.turn==2 and m.hand.size()==5,"New turn clears own block and draws five")
	m=fixture([19]);m.enemies[0].weak=999;play(m)
	check(m.enemies[0].weak==999,"Weak caps at 999")
	m=fixture([1]);m.enemies[0].hp=1
	check(play(m).outcome=="win","Natural victory")
	m=fixture([1]);m.player_hp=1
	check(m.end_turn().outcome=="lose","Natural defeat")
	# Parry charges govern future attacks, never multiply one counter.
	for form in ["melee","ranged"]:
		for layers in [0,1,2,3]:
			for initial_ammo in [0,9,10]:
				m=fixture([1],form);m.parry=layers;m.ammo=initial_ammo;m.block=999
				m.enemies[0].intent={"type":"attack","amount":4,"hits":3}
				m.enemies[0].bleed=5;m.powers=["dissection"]
				result=m.end_turn()
				var counters: Array=result.attacks[0].counters
				check(counters.size()==(1 if layers>0 else 0),"Single/multi-charge parry triggers once per multi-hit attack")
				check(m.ammo==mini(10,initial_ammo+(1 if layers>0 else 0)) and m.parry==maxi(0,layers-1),"Parry charges and ammo obey caps in both stances")
				check(m.enemies[0].bleed==5 and not m.dissection_used,"Parry neither applies nor consumes bleed")
				if layers>0:
					check(counters[0].damage==6 and counters[0].ammoAfter==m.ammo,"Parry returns half of pre-block multi-hit total and captures ammo")
	m=fixture([1],"melee",3);m.parry=3;m.ammo=0;m.block=999
	result=m.end_turn()
	check(result.attacks.all(func(a): return a.counters.size()==1) and m.ammo==3 and m.parry==0,"Three charges respond once to each of three enemies")
	m=fixture([1]);m.parry=3;m.ammo=0;m.enemies[0].hp=1
	result=m.end_turn()
	check(result.outcome=="win" and result.attacks[0].counters.size()==1 and m.ammo==1 and m.parry==2,"Lethal counter still gains exactly one ammo")
	m=fixture([1]);m.parry=2;m.buffs.apply(m,"parry",5)
	check(m.parry==3,"Parry gains clamp to global three-layer cap")
	m.buffs.apply(m,"parry",10,-1,{"fill":true})
	check(m.parry==3,"Parry fill also respects global cap")
	m.ammo=10
	var ten_saved: Dictionary=JSON.parse_string(JSON.stringify(m.snapshot()))
	check(Game.valid_combat(ten_saved),"Ten ammo and three parry charges validate")
	var ten_restored:=CombatModel.new();ten_restored.restore(ten_saved)
	check(ten_restored.ammo==10 and ten_restored.parry==3 and ten_restored.profile.ammoCap==10,"New resource limits survive JSON restore")
	ten_saved.norenState.ammo=11
	check(not Game.valid_combat(ten_saved),"Eleven ammo rejected")
	ten_saved.norenState.ammo=10;ten_saved.norenState.parry=4
	check(not Game.valid_combat(ten_saved),"Four parry charges rejected")
	m=fixture([1]);m.profile.ammoCap=6;m.ammo=6;m.gain_ammo(1)
	check(m.ammo==6 and Game.valid_combat(m.snapshot()),"Existing explicit six-ammo snapshot remains valid and capped")
	# Melee automatic ammo follows executed segments, with shared AoE segments counted once.
	for number in [28,35]:
		m=fixture([number]);m.ammo=0;result=play(m)
		var expected_segments: int=3 if number==35 else 2
		check(result.hits.size()==expected_segments and m.ammo==expected_segments,"Melee multi-hit grants one ammo per executed segment")
		check(result.hits.map(func(h): return h.ammoAfter)==range(1,expected_segments+1),"Each melee hit captures its ammo count")
	m=four_hit_fixture();m.ammo=8;result=play(m)
	check(m.ammo==10 and result.hits.map(func(h): return h.ammoAfter)==[9,10,10,10],"Per-hit gains stop at ten ammo")
	m=four_hit_fixture();m.ammo=0;m.enemies[0].hp=2;result=play(m)
	check(result.hits.size()==2 and m.ammo==2,"Lethal second hit does not grant unexecuted third and fourth ammo")
	m=four_hit_fixture();m.ammo=0;m.enemies[0].hp=2;m.enemies[0].block=2;result=play(m)
	check(result.hits.size()==4 and m.ammo==4 and result.hits[0].damage==0,"Blocked segments still grant ammo before later lethal damage")
	m=four_hit_fixture("ranged");m.ammo=6;result=play(m)
	check(result.hits.size()==4 and m.ammo==5,"Ranged multi-hit still spends only one ammo")
	m=fixture([38],"melee",3);m.ammo=0;result=play(m)
	check(result.hits.size()==3 and m.ammo==1,"Single AoE segment grants one ammo across three targets")
	m=fixture([38],"melee",3);m.ammo=0
	m.card_catalog.noren_38.effects=[{"type":"damage","amount":1,"hits":4}]
	m.enemies[0].hp=1;m.enemies[1].hp=3;result=play(m)
	check(result.hits.size()==8 and m.ammo==4,"Multi-hit AoE counts four shared segments despite unequal early deaths")
	m=fixture([1]);m.ammo=0
	m.card_catalog.noren_01.effects=[{"type":"damage","amount":1},{"type":"damage","amount":1}]
	result=play(m)
	check(result.hits.size()==2 and m.ammo==2,"Separate damage effects each contribute their executed segment")
	m=fixture([10]);m.ammo=0;result=play(m)
	check(result.hits.is_empty() and m.ammo==2 and m.stance=="ranged","Quick Reload is a skill with two ammo and no attack gain")
	m=fixture([9],"ranged");m.ammo=2;result=play(m)
	check(m.ammo==1 and m.stance=="melee","Ranged attack then melee switch does not retroactively grant ammo")
	m=fixture([20],"ranged");m.ammo=10;m.enemies[0].hp=1;result=play(m)
	check(result.hits.size()==1 and m.ammo==0,"Barrage pays all ten bullets even when first segment kills")
	m=fixture([20],"ranged");m.ammo=0;before=m.snapshot()
	check(play(m).is_empty() and m.snapshot()==before,"Empty-ammo Barrage fails before paying energy")
	# Newly authored abilities and conditional effects.
	m=fixture([36,35],"ranged");m.ammo=6;m.enemies[0].bleed=5
	play(m);result=play(m,1)
	check(m.powers==["persistent_bleed"] and result.damage==24 and m.enemies[0].bleed==5 and m.ammo==5,"Deep Wound preserves bleed on every ranged segment")
	m=fixture([37]);m.enemies[0].bleed=5;result=play(m)
	check(result.damage==14 and result.hits.size()==1 and m.enemies[0].bleed==3 and m.ammo==3,"Hunt explicitly triggers two bleed ticks in melee")
	m=fixture([36,37]);m.enemies[0].bleed=5;play(m);result=play(m,1)
	check(result.damage==15 and m.enemies[0].bleed==5,"Deep Wound also preserves both explicit Hunt ticks")
	m=fixture([23,26],"ranged");play(m);m.energy=3
	check(play(m,1).damage==88,"Ranged mastery changes Finisher66 into88")
	m=fixture([23,37],"ranged");m.enemies[0].bleed=5;play(m)
	check(play(m,1).damage==19 and m.enemies[0].bleed==3,"Ranged mastery doubles body damage but never bleed")
	m=fixture([24,35,1],"ranged");play(m);result=play(m,1)
	check(result.hits.map(func(h): return h.attackDamage)==[12,12,12] and m.buffs.count(m,"next_hit_damage")==0,"Weakpoint Lock applies six base damage to each segment of one attack")
	check(play(m,2).damage==9,"Per-hit bonus is consumed by the first attack only")
	m=fixture([24,35],"ranged");play(m);m.turn_damage_bonus=4;result=play(m,1)
	check(result.hits.map(func(h): return h.attackDamage)==[18,12,12],"First-segment and every-segment bonuses compose independently")
	m=fixture([24]);play(m);m.end_turn()
	check(m.buffs.count(m,"next_hit_damage")==0,"Unused per-hit bonus expires at turn end")
	m=fixture([39]);m.enemies[0].bleed=2
	check(play(m).drawn.size()==2 and m.block==0,"Tracking below three bleed draws only two")
	m=fixture([39]);m.enemies[0].bleed=3
	check(play(m).drawn.size()==3 and m.block==0,"Tracking includes exactly three bleed and draws a third")
	m=fixture([16]);result=play(m)
	check(result.damage==8 and result.drawn.size()==2 and m.energy==2,"Backstep Slash costs one and draws two in melee")
	m=fixture([16],"ranged");result=play(m)
	check(result.damage==12 and result.drawn.is_empty(),"Backstep Slash does not draw in ranged")
	m=fixture([33]);result=play(m)
	check(m.block==10 and m.parry==1 and m.exhaust_pile.is_empty() and m.discard_pile==["card_000"],"Counter Stance grants10 block and1 parry without exhausting")
	m=fixture([1]);m.powers=["ranged_mastery","persistent_bleed"];m.buffs.apply(m,"next_hit_damage",6)
	var new_saved: Dictionary=JSON.parse_string(JSON.stringify(m.snapshot()))
	check(Game.valid_combat(new_saved),"New powers and per-hit bonus validate in JSON snapshot")
	var new_restored:=CombatModel.new();new_restored.restore(new_saved)
	check(new_restored.powers==m.powers and new_restored.buffs.count(new_restored,"next_hit_damage")==6,"New statuses survive exact restore")
	for bad_field in ["consumeAllAmmo","allAmmoHits","bleedTriggers","rangedBonus"]:
		m=fixture([20],"ranged")
		if bad_field=="consumeAllAmmo": m.card_catalog.noren_20[bad_field]="invalid"
		else: m.card_catalog.noren_20.effects[0][bad_field]="invalid"
		before=m.snapshot()
		check(play(m).is_empty() and m.snapshot()==before,"Invalid new parameter fails atomically: "+bad_field)
	# Persistent ownership, frozen battle, save validation and console errors.
	Game.state=Game.initial_state()
	Game.state.activeEventId="E04";Game.state.currentPlaceId="alley";Game.enter_node("battle")
	var frozen: Dictionary=Game.state.combat.duplicate(true)
	check(Game.console_command("addcard 深度伤口 2").begins_with("已添加"),"Console Chinese name")
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
