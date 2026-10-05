extends DemoUI

func _ready() -> void:
	var e := Game.event_data()
	var complete: bool = Game.state.flags.get("week1Complete", false) and e.id == "E12"
	background("city", 0.53)
	chrome("事件结算")
	polygon(self,[Vector2(222,166),Vector2(1218,131),Vector2(1232,778),Vector2(238,813)],PINK)
	cut_panel(self, Vector2(231,147), Vector2(978,644), INK, CREAM,32)
	tag("WEEK 01 COMPLETE" if complete else "CASE CLOSED / " + e.id, Vector2(285,186), CYAN, 330)
	label(self, "第一周 · 落幕" if complete else "事件完成", Vector2(280,254), Vector2(873,95), 58)
	label(self, e.title, Vector2(285,373), Vector2(870,55), 28, PINK)
	var reward_ids: Array = e.get("rewardIds", [])
	var reward_text := "本次无奖励"
	if not reward_ids.is_empty():
		var parts: Array[String] = []
		for id in reward_ids:
			var r: Dictionary = Game.rewards.get(id, {})
			var claimed: bool = (e.id + ":" + id) in Game.state.claimedRewardIds
			parts.append(("已领取 · " if claimed else "可领取 · ") + str(r.get("name", id)))
		reward_text = "\n".join(parts)
	label(self, reward_text, Vector2(285,459), Vector2(860,85), 25)
	label(self, "奖励池与卡牌体系尚未配置。" if reward_ids.is_empty() else "领取记录与物品在同一检查点保存。", Vector2(286,551), Vector2(850,40), 17, MUTED)
	label(self, "第二周与第三周：内容待设计。可返回城市探索剩余支线。" if complete else "新的线索已更新到城市地图。进度已自动保存。", Vector2(286,615), Vector2(850,53), 20, CYAN)
	var rev := Game.revision
	button(self, "返回城市地图    →" if reward_ids.is_empty() else "领取并返回城市地图    →", Vector2(765,704), Vector2(390,59), func(): Game.claim_rewards(rev), true)
	fade_in()
