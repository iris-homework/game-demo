extends RefCounted
## Presentation-only fixtures preserve retired enemy/background checks.
## No production catalog reads this helper.
static func install() -> void:
	var definitions: Dictionary = JSON.parse_string('{"QA_MECH":{"id":"QA_MECH","eventId":"QA_MECH_EVENT","name":"机甲复仇","battleType":"normal","participants":["@player","gang"],"returnNodeByResult":{"win":"win_01","lose":"lose","surrender":"surrender"},"rules":null,"enemyStats":null,"placeId":"hive","prototypeProfileId":"attack_flow_v1","enemyIds":["mech_boss"]},"QA_PORT":{"id":"QA_PORT","eventId":"QA_PORT_EVENT","name":"港口追击 · 理查德","battleType":"normal","participants":["@player","richard"],"returnNodeByResult":{"win":"win_01","lose":"lose","surrender":"surrender"},"rules":null,"enemyStats":null,"placeId":"port","prototypeProfileId":"attack_flow_v1","enemyIds":["richard"]}}')
	for id in definitions:
		var battle: Dictionary = definitions[id]
		Game.battles[id] = battle
		var event: Dictionary = Game.events.E02.duplicate(true)
		event.id = battle.eventId
		event.placeId = battle.placeId
		event.unlockCondition = {"flag":"qaPresentationOnly"}
		event.nodes.battle.battleId = id
		Game.events[event.id] = event
