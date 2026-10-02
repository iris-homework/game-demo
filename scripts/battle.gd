extends DemoUI
## Replace this scene's internals with card combat; preserve enter/exit contract.
var expected_revision: int
var battle: Dictionary

func _ready() -> void:
	enter({"battleId":Game.state.battleId,"eventId":Game.state.activeEventId})

func enter(params: Dictionary) -> void:
	expected_revision = Game.revision
	battle = Game.battles[params.battleId]
	background(Game.place_data(Game.state.currentPlaceId).backgroundAssetId, 0.64)
	chrome("战斗接口")
	tag("DEVELOPMENT / 流程验证", Vector2(60,114), PINK, 330)
	label(self, battle.name, Vector2(58,176), Vector2(1120,78), 52)
	panel(self, Vector2(60,297), Vector2(815,485), Color("1a1524ee"), Color("695071"))
	label(self, "战斗规则待设计", Vector2(98,326), Vector2(730,70), 38)
	label(self, "当前为独立战斗占位页。\n选择模拟结果，检查剧情的不同返回路径。", Vector2(101,424), Vector2(711,85), 23, MUTED)
	var names: Array[String] = []
	for id in battle.participants: names.append(Game.display_name(id))
	label(self, "参战角色\n" + " / ".join(names), Vector2(101,545), Vector2(710,100), 22, CREAM)
	label(self, "卡牌 · 费用 · 初始牌组 · 敌人数值\n待正式设计后接入此模块", Vector2(101,681), Vector2(710,80), 18, MUTED)
	label(self, "模拟战斗结果", Vector2(940,315), Vector2(430,51), 26)
	button(self, "胜利    →", Vector2(940,408), Vector2(430,74), func(): exit_battle("win"), true).disabled = not Game.config.developmentMode
	button(self, "失败    →", Vector2(940,509), Vector2(430,74), func(): exit_battle("lose")).disabled = not Game.config.developmentMode
	button(self, "投降    →", Vector2(940,610), Vector2(430,74), func(): exit_battle("surrender")).disabled = not Game.config.developmentMode
	label(self, "失败与投降仅记录结果，\n后续剧情和惩罚规则待补。", Vector2(941,716), Vector2(430,73), 18, MUTED)
	fade_in()

func exit_battle(result: String) -> void:
	Game.battle_exit(result, expected_revision)
