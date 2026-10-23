extends Control
## Transparent inspection region; battle input and rules stay with their owners.
var tooltip_data: Dictionary = {}
var stance := ""
var capacity := -1

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE

func configure(form: String, ammo_cap: int) -> void:
	if stance == form and capacity == ammo_cap: return
	stance = form
	capacity = ammo_cap
	tooltip_data = {
		"enemy":"诺伦", "node_name":"StanceTooltip", "eyebrow":"诺伦 / 专属机制",
		"title":"战斗形态", "accent":Color("64ffe1"),
		"value":"近战" if stance == "melee" else "远程", "unit":"当前形态",
		"summary":"切换形态，交替补充弹药与强化攻击。",
		"notes":[
			{"title":"近战 · 回弹与抽牌","body":"每实际打出一段攻击恢复 1 发弹药，上限 %d 发；群体攻击同一段只恢复 1 发。切入近战时抽 2 张牌。" % capacity},
			{"title":"远程 · 耗弹与增伤","body":"通常每张攻击牌消耗 1 发弹药，弹药不足时无法攻击。攻击本体伤害通常为近战的 1.5 倍，卡牌与能力可进一步修正。切入远程时，下一张攻击牌的能量费用 -1。"}
		],
		"footer":"只有实际切换形态才触发切入奖励；特殊耗弹以卡牌说明为准。"
	}
	var lines := PackedStringArray(["诺伦 · 当前形态："+tooltip_data.value])
	for note in tooltip_data.notes: lines.append(note.title+"："+note.body)
	lines.append(tooltip_data.footer)
	tooltip_text = "\n".join(lines)

func _make_custom_tooltip(_text: String) -> Object:
	return preload("res://scripts/combat/intent_tooltip.gd").build(tooltip_data,get_theme_font("font")) if not tooltip_data.is_empty() else null
