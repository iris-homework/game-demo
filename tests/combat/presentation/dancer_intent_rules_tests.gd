extends Node
## Headless display-state checks: no window, input, or formal save writes.
class DisplayProbe extends "res://scripts/battle.gd":
	func refresh_enemy_hud() -> void: pass
	func refresh_player_plate() -> void: pass

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DANCER DISPLAY: " + message)

func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(func(): get_tree().quit(2))
	Game.save_enabled = false
	Game.save_path = "user://dancer_display_unused.json"
	Game.meta_path = "user://dancer_display_meta_unused.json"
	var tooltip = preload("res://scripts/combat/intent_tooltip.gd")
	var weak_enemy := {"displayName":"白舞者","intent":{"type":"weak","amount":2}}
	var data: Dictionary = tooltip.describe(weak_enemy,"虚弱 2")
	check(data.title == "施加虚弱" and data.value == "2", "weak intent has explicit title and stacks")
	check(data.plain.contains("降低 25%") and data.plain.contains("自身回合结束"), "weak tooltip explains modifier and lifetime")
	var heal_enemy := {"displayName":"白舞者","intent":{"type":"heal_ally","amount":10,"targetIds":["dancer_black"]}}
	data = tooltip.describe(heal_enemy,"治疗 10")
	check(data.title == "治疗同伴" and data.value == "+10", "heal intent shows positive healing amount")
	check(data.plain.contains("黑舞者") and data.plain.contains("不会复活"), "heal tooltip names the black dancer and prevents revival")
	var reinforcement := {"displayName":"黑舞者","intent":{"type":"strength_allies","amount":2,"targetIds":["dancer_white"]}}
	data = tooltip.describe(reinforcement,"强化 +2")
	check(data.title == "强化同伴" and data.value == "+2" and data.plain.contains("存活的白舞者") and not data.plain.contains("小弟"), "reinforcement tooltip names living white instead of gang henchmen")
	data = tooltip.describe({"displayName":"黑舞者","intent":{"type":"attack","amount":10,"onHitWeak":2}},"攻击 10")
	check(data.plain.contains("2 层虚弱") and data.plain.contains("即使攻击被格挡"), "attack tooltip includes unconditional post-attack weakness")
	var font := ThemeDB.fallback_font
	for intent in [weak_enemy.intent,heal_enemy.intent,reinforcement.intent]:
		var icon = preload("res://scripts/combat/enemy_intent.gd").new()
		icon.setup(intent,"测试",font)
		check(icon.value_label.text == ("2" if intent.type == "weak" else ("+10" if intent.type == "heal_ally" else "+2")), "new intent icon keeps a numeric value")
		icon.free()
	var view := DisplayProbe.new()
	view.model = CombatModel.new()
	view.model.initialize("display",100,100,{"ruleset":"noren_v1","deck":[]},[
		{"id":"dancer_black","displayName":"黑舞者","maxHp":90,"intentSequence":[{"type":"attack","amount":20}]},
		{"id":"dancer_white","displayName":"白舞者","maxHp":90,"intentSequence":[{"type":"weak","amount":2}]}
	])
	view.model.enemies[0].hp = 65
	view.model.buffs.apply(view.model,"soul_link",2,1)
	var connection_badges: Array = view.model.buffs.enemy_badges(view.model.enemies[1]).filter(func(b): return b.buffId == "soul_link")
	check(connection_badges.size() == 1 and connection_badges[0].count == 2, "connection badge exposes both initial layers")
	var badge = preload("res://scripts/combat/status_badge.gd").new()
	badge.setup(connection_badges[0].id,connection_badges[0].count,Color(connection_badges[0].color),connection_badges[0].description,connection_badges[0])
	check(badge.symbol == "soul_link" and badge.amount == 2 and badge.metadata.buffId == "soul_link", "double-ring badge retains connection identity and stack count")
	badge.free()
	view.shown_enemies = view.model.enemies.duplicate(true)
	var original := view.model.snapshot()
	view.apply_shown_heal({"type":"heal","source":1,"target":0,"amount":10,"hpAfter":75})
	check(view.shown_enemies[0].hp == 75, "healing updates the displayed target HP")
	check(view.model.snapshot() == original, "healing presentation never reapplies authoritative healing")
	view.apply_shown_status({"target":1,"buffId":"block","stacksAfter":10})
	check(view.shown_enemies[1].block == 10, "soul-link block uses the displayed block field")
	view.apply_shown_status({"target":0,"buffId":"strength","stacksAfter":2})
	check(view.shown_enemies[0].buffs.strength == 2, "soul-link strength uses extra buff state")
	view.apply_shown_status({"target":-1,"buffId":"weak","stacksAfter":2})
	check(view.shown_player_weak == 2, "weakness applies at the display event boundary")
	var weak_badges: Array = view.model.buffs.player_badges(view.model,0,0,{},view.shown_player_weak).filter(func(b): return b.buffId == "weak")
	check(weak_badges.size() == 1 and weak_badges[0].count == 2, "weak badge uses the display state while the resolved model differs")
	view.apply_shown_status({"target":-1,"buffId":"weak","stacksAfter":1})
	check(view.shown_player_weak == 1, "weakness decay updates the shown player value")
	view.apply_shown_status({"target":1,"buffId":"weak","stacksAfter":1})
	check(view.shown_enemies[1].weak == 1, "enemy weakness updates its canonical display field")
	view.model.instances.preview = "preview"
	view.model.hand.append("preview")
	view.model.card_catalog.preview = {"id":"preview","name":"黑卡","type":"skill","cost":1,"target":"self","description":"使白舞者失去1层灵魂连接。","effects":[{"type":"remove_soul_link","amount":1,"enemyId":"dancer_white"}]}
	original = view.model.snapshot()
	var preview: Dictionary = view.model.card_preview("preview")
	check(preview.text == "使白舞者失去1层灵魂连接。", "black-card preview resolves the named opposing dancer")
	check(preview.effects[0].values == [1], "black-card preview limits removal to one of two layers")
	check(view.model.snapshot() == original, "black-card preview preserves every live card and status")
	view.model.buffs.clear(view.model,"soul_link",1)
	preview = view.model.card_preview("preview")
	check(preview.text == "使白舞者失去0层灵魂连接。", "preview shows no removal once the connection is gone")
	view.model.enemies[1].hp = 0
	preview = view.model.card_preview("preview")
	check(preview.effects[0].values == [0], "preview does not remove a dead dancer's connection")
	view.model.instances.attack = "attack"
	view.model.hand.append("attack")
	view.model.card_catalog.attack = {"id":"attack","name":"QA attack","type":"attack","cost":0,"target":"enemy","effects":[{"type":"damage","amount":10}]}
	view.model.buffs.apply(view.model,"weak",2)
	preview = view.model.card_preview("attack",0)
	check(preview.effects.filter(func(e): return e.type == "damage")[0].values == [8], "player weakness rounds melee preview damage once")
	view.model.stance = "ranged"
	preview = view.model.card_preview("attack",0)
	check(preview.effects.filter(func(e): return e.type == "damage")[0].values == [11], "ranged preview combines stance and weakness before rounding")
	view.model.instances.suppress = "suppress"
	view.model.hand.append("suppress")
	view.model.card_catalog.suppress = {"id":"suppress","name":"QA suppress","type":"skill","cost":0,"target":"enemy","effects":[{"type":"weak","amount":2}]}
	preview = view.model.card_preview("suppress",0)
	check(preview.effects[0].enemy and preview.effects[0].values == [2], "existing weak card effects still preview against enemies")
	view.free()
	print("DANCER INTENT DISPLAY: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
