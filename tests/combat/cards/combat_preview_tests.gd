extends Node
## Preview is read-only: checking a card must not spend buffs, alter a pile,
## resolve combat, or advance the random sequence used by the next shuffle.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func fixture(ids: Array = [1], form: String = "melee", count: int = 1) -> CombatModel:
	var rules: Dictionary = Game.prototype_rules.duplicate(true)
	rules.merge(Game.noren_rules, true)
	rules.shuffleInitialDeck = false
	rules.deck = []
	for number in ids: rules.deck.append("noren_%02d" % int(number))
	for i in 12: rules.deck.append("noren_01")
	var enemies: Array = []
	for i in count:
		enemies.append({"id":"preview_%d" % i,"displayName":"靶子%d" % i,"maxHp":1000,"battlePortraitAssetId":"","intentSequence":[{"type":"attack","amount":10,"hits":1}]})
	var m := CombatModel.new()
	m.initialize("B04", 100, 100, rules, enemies, Game.card_catalog)
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
	m.card_catalog.noren_35.cardText="造成1点伤害，共4次。"
	m.card_catalog.noren_35.description=m.card_catalog.noren_35.cardText
	return m

func preview_text(m: CombatModel, target: int = 0, extra: int = -1, uid: String = "card_000") -> String:
	var before := m.snapshot()
	var result: Dictionary = m.card_preview(uid, target, extra)
	check(m.snapshot() == before, "%s preview leaves snapshot unchanged" % m.card(uid).get("name", uid))
	check(result.get("text") is String and result.get("effects") is Array, "Preview public result schema")
	var numbers := RegEx.new()
	numbers.compile("[0-9]+(?:[／–][0-9]+)*")
	var original: String = m.card(uid).get("cardText", m.card(uid).get("description", ""))
	check(numbers.sub(normalize_dynamic_damage(result.cardText), "#", true) == numbers.sub(original, "#", true), "Card face preserves authored rules besides explicit dynamic-hit damage")
	check(numbers.sub(normalize_dynamic_damage(result.description), "#", true) == numbers.sub(m.card(uid).get("description", ""), "#", true), "Tooltip preserves authored rules besides explicit dynamic-hit damage")
	return str(result.get("text", ""))

func normalize_dynamic_damage(text: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("首段造成([0-9–]+)点伤害，后续每段造成[0-9–]+点伤害")
	return pattern.sub(text, "造成 $1 点伤害", true)

func test_barrage_first_hit_wording() -> void:
	for form in ["melee", "ranged"]:
		for bullets in [0, 1, 3, 10]:
			var m := fixture([20], form)
			m.ammo = bullets
			m.next_attack_bonus = 4
			m.energy = 10
			var before := m.snapshot()
			var preview := m.card_preview("card_000", 0)
			var expected := "首段造成20点伤害，后续每段造成14点伤害。" if form == "ranged" and bullets > 0 else ("造成 20 点伤害。" if form == "ranged" else "造成 13 点伤害。")
			check(preview.cardText.begins_with(expected), "Barrage card face distinguishes segment values: %s %d" % [form, bullets])
			check(preview.description.begins_with(expected), "Barrage tooltip distinguishes segment values: %s %d" % [form, bullets])
			check(preview.cardText.ends_with("总段数为 1 加打出前的弹药数。"), "Barrage keeps authored ammo count rule")
			check(m.snapshot() == before, "Barrage wording consumes no bonus, ammo or state")
			if form == "ranged" and bullets == 0: continue
			var played := m.play_card("card_000", 0)
			var expected_hits: int = bullets + 1 if form == "ranged" else 1
			check(played.hits.size() == expected_hits, "Barrage execution keeps declared segment count")
			check(played.hits[0].damage == (20 if form == "ranged" else 13), "Barrage actual first hit matches preview")
			if form == "ranged":
				check(played.hits.slice(1).all(func(hit): return hit.damage == 14), "Barrage subsequent actual hits match lower preview value")
	var m := fixture([20], "ranged", 2)
	m.ammo = 10
	m.next_attack_bonus = 4
	m.buffs.apply(m, "vulnerable", 1, 1)
	var preview := m.card_preview("card_000", -1)
	check(preview.cardText.begins_with("首段造成20–30点伤害，后续每段造成14–21点伤害。"), "Untargeted barrage keeps separate first/later vulnerability ranges")

func contains(actual: String, expected: String, label: String) -> void:
	check(expected in actual, "%s expected <%s>, got <%s>" % [label, expected, actual])

func test_read_only_catalog() -> void:
	check(Game.card_catalog.size() == 40, "All 40 formal cards are covered")
	for form in ["melee", "ranged"]:
		for number in range(1, 41):
			var m := fixture([number, 1], form, 3)
			m.next_attack_bonus = 3
			m.turn_damage_bonus = 4
			m.turn_discount = 1
			m.stance_discount = true
			m.powers = ["high_pressure", "dissection"]
			m.ammo = 6
			m.parry = 1
			m.enemies[0].bleed = 5
			m.enemies[1].bleed = 3
			m.enemies[1].hp = 500
			m.enemies[1].weak = 999
			m.enemies[2].hp = 0
			# Exhaust the draw pile so the comparison observes an actual shuffle.
			m.discard_pile = m.draw_pile.duplicate()
			m.draw_pile.clear()
			var initial := m.snapshot()
			var control := CombatModel.new()
			control.restore(initial)
			seed(170010 + number)
			var expected_draw: Array = control.draw_cards(5)
			var expected_random := randi()
			seed(170010 + number)
			for target in [-1, 0, 1]:
				var text := preview_text(m, target)
				check(not text.is_empty(), "%02d %s target %d gives text" % [number, form, target])
			for extra in range(m.extra_ammo_limit("card_000") + 1):
				preview_text(m, 0, extra)
			m.enemy_intent_text(m.enemies[1])
			check(m.snapshot() == initial, "%02d %s all previews strictly preserve snapshot" % [number, form])
			check(m.draw_cards(5) == expected_draw, "%02d %s previews preserve subsequent shuffle" % [number, form])
			check(randi() == expected_random, "%02d %s previews preserve global RNG sequence" % [number, form])

func test_numeric_effects() -> void:
	var m := fixture([1])
	contains(preview_text(m), "造成6点伤害。", "Melee base damage")
	m.stance = "ranged"
	contains(preview_text(m), "造成9点伤害。", "Ranged 1.5 multiplier")
	m = fixture([35], "ranged")
	contains(preview_text(m), "造成3×3点伤害。", "Round each 3 * 1.5 segment, not total")
	m.next_attack_bonus = 2
	m.turn_damage_bonus = 4
	contains(preview_text(m), "造成12＋3＋3点伤害。", "Technology and next damage apply only to first segment")
	m.enemies[0].block = 999
	m.enemies[0].hp = 1
	contains(preview_text(m), "造成12＋3＋3点伤害。", "Neither block nor remaining HP truncates displayed attacks")
	m = fixture([35], "ranged")
	m.powers = ["high_pressure"]
	contains(preview_text(m), "造成8＋3＋3点伤害。", "Unused pressure boosts first segment only")
	m.pressure_used = true
	contains(preview_text(m), "造成3×3点伤害。", "Used pressure does not boost again")
	m.stance = "melee"
	m.pressure_used = false
	contains(preview_text(m), "造成2×3点伤害。", "Pressure does not boost melee")
	m = four_hit_fixture( "ranged")
	m.enemies[0].bleed = 5
	var text := preview_text(m)
	contains(text, "造成2×4点伤害。", "Four individually rounded shots")
	contains(text, "裂伤追加5＋4＋3＋2点伤害。", "Bleed decreases independently each segment")
	m.enemies[0].hp = 1
	m.enemies[0].block = 100
	contains(preview_text(m), "裂伤追加5＋4＋3＋2点伤害。", "Bleed request preview ignores block and HP clipping")
	m = fixture([27], "ranged")
	text = preview_text(m)
	contains(text, "施加1层裂伤。", "Ranged bleed application halves")
	check(not "裂伤追加" in text, "New bleed is not retroactively used by this card's attack")
	m = fixture([30])
	m.powers = ["dissection"]
	contains(preview_text(m), "施加4层裂伤。", "Dissection adds to unwounded melee application")
	m.enemies[0].bleed = 1
	contains(preview_text(m), "施加7层裂伤。", "Wounded deepening then dissection")
	m.dissection_used = true
	contains(preview_text(m), "施加6层裂伤。", "Used dissection does not add a layer")
	m.stance = "ranged"
	m.dissection_used = false
	contains(preview_text(m), "施加2层裂伤。", "Ranged deepening has no wounded melee or dissection bonus")
	m = fixture([6])
	m.ammo = 9
	contains(preview_text(m), "获得1弹药。", "Ammo gain limited by remaining capacity")
	m.ammo = 10
	contains(preview_text(m), "获得0弹药。", "Full ammo gives zero actual gain")
	m = fixture([17])
	m.ammo = 9
	text = preview_text(m)
	contains(text, "回弹1。", "Melee automatic ammo precedes extra gain")
	contains(text, "获得0弹药。", "Extra card ammo sees capacity after automatic ammo")
	m.ammo = 8
	contains(preview_text(m), "获得1弹药。", "Extra card ammo partially fits after automatic ammo")
	m.ammo = 10
	contains(preview_text(m), "回弹0。", "Automatic ammo capped too")
	for number in [28,35]:
		m=fixture([number]);m.ammo=0
		contains(preview_text(m),"回弹%d。" % (3 if number==35 else 2),"Preview counts melee attack segments")
	m=four_hit_fixture();m.ammo=8
	contains(preview_text(m),"回弹2。","Per-hit ammo preview respects ten-cap")
	m=four_hit_fixture();m.ammo=0;m.enemies[0].hp=2
	contains(preview_text(m),"回弹2。","Melee ammo preview stops at lethal segment")
	m.enemies[0].block=2
	contains(preview_text(m),"回弹4。","Blocked segments count before lethal damage")
	m=fixture([38],"melee",3);m.ammo=0
	contains(preview_text(m,-1),"回弹1。","AoE ammo preview counts shared segment once")
	m.card_catalog.noren_38.effects=[{"type":"damage","amount":1,"hits":4}]
	m.enemies[0].hp=1;m.enemies[1].hp=3
	contains(preview_text(m,-1),"回弹4。","AoE ammo preview considers all targets even if one dies early")
	m=fixture([1]);m.ammo=0
	m.card_catalog.noren_01.effects=[{"type":"damage","amount":1},{"type":"damage","amount":1}]
	m.enemies[0].hp=1
	contains(preview_text(m),"回弹1。","Separate damage effects stop ammo on an already dead target")
	m=fixture([35],"ranged");m.buffs.apply(m,"next_hit_damage",6);m.turn_damage_bonus=4
	contains(preview_text(m),"造成18＋12＋12点伤害。","Every-hit and first-hit preview bonuses compose")
	m.powers=["ranged_mastery"]
	contains(preview_text(m),"造成24＋16＋16点伤害。","Mastery multiplier applies after all base bonuses")
	m=fixture([35],"ranged");m.powers=["persistent_bleed"];m.enemies[0].bleed=5
	contains(preview_text(m),"裂伤追加5×3点伤害。","Persistent bleed preview does not decay layers")
	m=fixture([37]);m.powers=["persistent_bleed"];m.enemies[0].bleed=5
	contains(preview_text(m),"裂伤追加5×2点伤害。","Melee Hunt explicitly triggers two persistent ticks")
	for number in [3, 31, 32, 33]:
		for layers in range(4):
			m = fixture([number])
			m.parry = layers
			var gained := mini(1,3-layers) if number == 3 else ((1 if layers == 0 else 0) if number == 31 else ((1 if layers < 2 else 0) if number == 32 else mini(1,3-layers)))
			contains(preview_text(m), "获得%d层弹反。" % gained, "Parry card %d at %d layers" % [number, layers])
	m = fixture([39], "melee", 3)
	m.enemies[0].bleed = 2
	m.enemies[1].bleed = 3
	m.enemies[2].bleed = 8
	m.enemies[2].hp = 0
	contains(preview_text(m, 0), "抽0张牌。", "Conditional third draw excludes two bleed")
	contains(preview_text(m, 1), "抽1张牌。", "Conditional third draw includes three bleed")
	contains(preview_text(m, -1), "抽0–1张牌。", "Untargeted third draw gives live target range")
	m = fixture([20], "ranged")
	for bullets in [1,2,3,10]:
		m.ammo=bullets
		text=preview_text(m)
		contains(text,"造成14×%d点伤害。" % (bullets+1),"Barrage preview adds base segment to every bullet")
		contains(text,"耗弹%d。" % bullets,"Barrage preview consumes all bullets")
		check(not "可选额外" in text,"Barrage has no optional ammo choice")
	m = fixture([26], "ranged")
	contains(preview_text(m),"造成66点伤害。","Finisher previews new base and ranged bonus")
	m.powers=["ranged_mastery"]
	contains(preview_text(m),"造成88点伤害。","Mastery changes Finisher multiplier to two")
	m = fixture([21], "ranged")
	m.ammo = 1
	contains(preview_text(m), "造成18点伤害。", "Last bullet uses prepayment ammo")
	m.ammo = 2
	contains(preview_text(m), "造成12点伤害。", "Postpayment last bullet does not qualify")
	m = fixture([25], "ranged", 3)
	m.enemies[0].hp = 501
	m.enemies[1].hp = 500
	m.enemies[2].hp = 0
	contains(preview_text(m, 0), "造成21点伤害。", "Execution excludes just above half health")
	contains(preview_text(m, 1), "造成33点伤害。", "Execution includes exactly half health")
	contains(preview_text(m, -1), "造成21–33点伤害。", "Execution unknown target range")
	m = fixture([37], "ranged", 2)
	m.enemies[0].bleed = 4
	m.enemies[1].bleed = 5
	contains(preview_text(m, 0), "造成9点伤害。", "Hunt uses one ranged attack body")
	contains(preview_text(m, 1), "造成9点伤害。", "Hunt never gains an extra body hit")
	contains(preview_text(m, 1), "裂伤追加5＋4点伤害。", "Hunt extra hit consumes next bleed amount")
	contains(preview_text(m, -1), "裂伤追加4–5＋3–4点伤害。", "Untargeted Hunt shows two bleed tick ranges")
	m = fixture([38], "ranged", 3)
	m.next_attack_bonus = 2
	m.enemies[0].bleed = 5
	m.enemies[1].bleed = 2
	m.enemies[2].bleed = 100
	m.enemies[2].hp = 0
	text = preview_text(m, -1)
	contains(text, "对每名敌人造成12点伤害。", "AoE first segment bonus applies to each live target")
	contains(text, "裂伤追加2–5点伤害。", "AoE bleed range excludes dead targets")
	contains(text, "对每名敌人施加2层裂伤。", "AoE ranged new bleed applied after attacks")
	m = fixture([11])
	text = preview_text(m)
	contains(text, "获得1弹药。", "Melee stance-specific ammo shown")
	check(not "虚弱" in text, "Inactive ranged skill effect omitted")
	m.stance = "ranged"
	text = preview_text(m)
	contains(text, "施加1层虚弱。", "Ranged stance-specific weakness shown")
	check(not "弹药" in text, "Inactive melee skill effect omitted")
	m.enemies[0].weak = 999
	contains(preview_text(m), "施加0层虚弱。", "Weak cap displayed as actual zero gain")
	m = fixture([3], "ranged")
	contains(preview_text(m), "切换至近战。抽2张牌。", "Stance entry draws two in preview")
	contains(preview_text(m), "获得1层弹反。", "Close In previews parry")
	for available in [0,1]:
		var limited := fixture([3], "ranged")
		limited.draw_pile.resize(available)
		limited.discard_pile.clear()
		contains(preview_text(limited), "切换至近战。抽%d张牌。" % available, "Melee entry preview respects available cards")
	m.stance = "melee"
	contains(preview_text(m), "保持当前形态。", "Same stance does not promise entry reward")
	m = fixture([7])
	m.draw_pile.clear()
	m.discard_pile.clear()
	contains(preview_text(m), "抽0张牌。", "Drawing cannot include resolving card or nonexistent cards")
	m = fixture([1])
	m.block = 999
	m.player_hp = 1
	for layers in [0, 1, 2, 999]:
		m.enemies[0].weak = layers
		m.enemies[0].intent = {"type":"attack", "amount":10, "hits":3}
		var before := m.snapshot()
		check(m.enemy_intent_text(m.enemies[0]) == ("攻击 10 ×3" if layers == 0 else "攻击 8 ×3"), "Enemy weakness %d previews per-hit rounding before block/HP" % layers)
		check(m.snapshot() == before, "Enemy intent display preserves snapshot")
	m.enemies[0].intent = {"type":"wait", "description":"蓄力"}
	check(m.enemy_intent_text(m.enemies[0]) == "蓄力", "Nonattack intent retains authored description")

func test_potential_status_and_conditional_wording() -> void:
	# Damage and status labels show potential values regardless of lethality.
	# Actual resolution must still skip status application to dead recipients.
	for number in [19, 27, 29]:
		for protected in [false, true]:
			var m := fixture([number], "melee")
			m.enemies[0].hp = 1
			m.enemies[0].block = 100 if protected else 0
			var before := m.snapshot()
			var preview := m.card_preview("card_000", 0)
			var status := "weak" if number == 19 else "bleed"
			var name := "虚弱" if number == 19 else "裂伤"
			var expected := 2 if number == 19 else 2 if number == 27 else 4
			check(m.snapshot() == before, "%d potential preview preserves live snapshot" % number)
			contains(preview.cardText, "施加%d层%s" % [expected, name], "%d card face retains potential layers even on lethal hit" % number)
			contains(str(preview.description).replace(" ", ""), "施加%d层%s" % [expected, name], "%d tooltip retains potential layers even on lethal hit" % number)
			contains(preview.cardText, "造成%d点伤害" % (14 if number == 29 else 8 if number == 19 else 6), "%d damage stays untruncated" % number)
			var result := m.play_card("card_000", 0)
			check(not result.is_empty(), "%d survival comparison executes a valid play" % number)
			check(int(m.enemies[0].get(status, 0)) == (expected if protected else 0), "%d actual status still skips dead targets" % number)
	# Ranged bleed can kill between the direct hit and the card's status effect.
	for number in [19, 27]:
		for protected in [false, true]:
			var m := fixture([number], "ranged")
			m.enemies[0].hp = 10
			m.enemies[0].bleed = 4
			m.enemies[0].block = 100 if protected else 0
			var before := m.snapshot()
			var preview := m.card_preview("card_000", 0)
			var status := "weak" if number == 19 else "bleed"
			var name := "虚弱" if number == 19 else "裂伤"
			var expected := 2 if number == 19 else 1
			check(m.snapshot() == before, "Ranged lethal bleed preview preserves live state")
			contains(preview.cardText, "施加%d层%s" % [expected, name], "Follow-up status preview ignores bleed lethality")
			contains(preview.cardText, "造成%d点伤害" % (12 if number == 19 else 9), "Direct damage remains before block and HP clipping")
			check(not m.play_card("card_000", 0).is_empty(), "Ranged comparison executes")
			check((m.enemies[0].hp > 0) == protected, "Ranged survival matches damage and bleed order")
			check(int(m.enemies[0][status]) == (expected if protected else 0) + (3 if number == 27 else 0), "Actual ranged status still skips targets killed by bleed")
	for number in [27, 29]:
		var m := fixture([number], "melee")
		m.enemies[0].hp = 1
		m.powers = ["dissection"]
		var before := m.snapshot()
		var expected := 3 if number == 27 else 5
		var preview := m.card_preview("card_000", 0)
		contains(preview.cardText, "施加%d层裂伤" % expected, "Lethal-hit preview includes dissection bonus")
		contains(str(preview.description).replace(" ", ""), "施加%d层裂伤" % expected, "Lethal-hit tooltip includes dissection bonus")
		check(m.snapshot() == before, "Potential preview never consumes dissection")
	for starting_bleed in [0, 1]:
		for used in [false, true]:
			var m := fixture([30], "melee")
			m.powers = ["dissection"]
			m.dissection_used = used
			m.enemies[0].bleed = starting_bleed
			var before := m.snapshot()
			var preview := m.card_preview("card_000", 0)
			var base := 3 if used else 4
			var wounded := 6 if used else 7
			var expected := "对一名敌人施加%d层裂伤。近身技：若目标在本牌使用前已有裂伤，改为施加%d层裂伤。" % [base, wounded]
			check(preview.cardText.replace("\n","").replace(" ","") == expected, "Deepening retains separate base and wounded branch values: "+preview.cardText)
			check(str(preview.description).replace(" ", "") == expected, "Deepening tooltip retains separate branch values")
			check(m.snapshot() == before, "Deepening branch preview preserves live snapshot")
		var ranged := fixture([30], "ranged")
		ranged.powers = ["dissection"]
		ranged.enemies[0].bleed = starting_bleed
		var before := ranged.snapshot()
		var preview := ranged.card_preview("card_000", 0)
		var expected := "对一名敌人施加2层裂伤。近身技：若目标在本牌使用前已有裂伤，改为施加6层裂伤。"
		check(preview.cardText.replace("\n","").replace(" ","") == expected, "Ranged deepening halves active base and preserves inactive melee wording: "+preview.cardText)
		check(str(preview.description).replace(" ", "") == expected, "Ranged deepening tooltip preserves inactive melee branch")
		check(ranged.snapshot() == before, "Ranged deepening preview preserves live snapshot")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://combat_preview_qa.json"
	Game.meta_path = "user://combat_preview_meta_qa.json"
	var exhaust_preview := fixture([12,2])
	var exhaust_before := exhaust_preview.snapshot()
	contains(preview_text(exhaust_preview), "消耗另一张手牌。", "Dismantle previews hand exhaustion")
	check(exhaust_preview.snapshot() == exhaust_before, "Dismantle preview never moves candidate cards")
	test_numeric_effects()
	test_barrage_first_hit_wording()
	test_read_only_catalog()
	test_potential_status_and_conditional_wording()
	var m := fixture([1])
	m.next_attack_bonus = 2
	check(m.card_preview("card_000").cardText == "造成8点伤害。", "Basic attack gains damage but no implicit ammo line")
	m = fixture([39], "melee", 2)
	m.enemies[1].bleed = 4
	check(m.card_preview("card_000", 0).cardText.replace(" ","").ends_with("额外抽0张牌。"), "Conditional third draw becomes zero below threshold: "+m.card_preview("card_000",0).cardText)
	check(m.card_preview("card_000", 1).cardText.replace(" ","").ends_with("额外抽1张牌。"), "Conditional third draw stays one above threshold: "+m.card_preview("card_000",1).cardText)
	m = fixture([6])
	m.ammo = 9
	check(m.card_preview("card_000").cardText == "获得1颗弹药和6点格挡。", "Only authored ammo and block numbers update")
	m = fixture([8])
	check(m.card_preview("card_000").cardText == m.card("card_000").cardText, "Stance card gets no implicit draw or discount text")
	m = fixture([33])
	m.parry = 1
	check(m.card_preview("card_000").cardText.replace(" ","").contains("1层弹反"), "New Counter Stance previews one gained charge: "+m.card_preview("card_000").cardText)
	print("COMBAT PREVIEW: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
