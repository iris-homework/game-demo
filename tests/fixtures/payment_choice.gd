extends RefCounted
# Generic payment/choice fixture. It is installed only in test memory and does
# not restore the retired E03 story, character, or encounter to the catalog.
const EVENT_ID := "QA_PAYMENT"
const BATTLE_ID := "QA_PAYMENT_BATTLE"

static func install(game: Node) -> void:
	var event: Dictionary = game.events.E02.duplicate(true)
	event.id = EVENT_ID
	event.title = "支付条件测试"
	event.placeId = "hive"
	event.description = "仅供检查支付条件和选择事务的内存夹具。"
	event.startNodeId = "intro_01"
	event.nodes.intro_01 = {"id":"intro_01", "text":"测试支付入口。", "next":"payment"}
	event.nodes.payment = {"id":"payment", "text":"请选择支付或战斗测试分支。", "choices":[
		{"id":"pay", "label":"支付 300 信用点", "next":"paid", "condition":{"creditsAtLeast":300}, "effects":[{"op":"spendCredits", "amount":300}]},
		{"id":"refuse", "label":"拒绝支付", "next":"battle", "condition":{}, "effects":[]}
	]}
	event.nodes.paid = {"id":"paid", "text":"测试支付已完成。", "next":"finish"}
	event.nodes.battle.battleId = BATTLE_ID
	game.events[EVENT_ID] = event
	var battle: Dictionary = game.battles.B02.duplicate(true)
	battle.id = BATTLE_ID
	battle.eventId = EVENT_ID
	battle.placeId = "hive"
	game.battles[BATTLE_ID] = battle

static func uninstall(game: Node) -> void:
	game.events.erase(EVENT_ID)
	game.battles.erase(BATTLE_ID)
