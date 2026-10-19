extends RefCounted
## Presentation data only; damage text comes from the existing model preview.
const WIDTH := 324.0
const TEXT_WIDTH := WIDTH-36.0

static func describe(enemy: Dictionary, preview: String) -> Dictionary:
	var intent: Dictionary = enemy.get("intent",{})
	var amount := int(intent.get("amount",0))
	var kind := str(intent.get("type",""))
	var data := {"enemy":str(enemy.get("displayName","敌人")),"title":"特殊行动","value":preview,"unit":"","accent":Color("c7b1ec"),"summary":preview,"notes":[],"footer":"敌方回合执行"}
	match kind:
		"attack":
			var damage_text := preview.trim_prefix("攻击 ").replace(" ","")
			var damage := damage_text.split("×")[0].to_int()
			var hits := maxi(1,int(intent.get("hits",1)))
			data.title = "多段攻击" if hits>1 else "攻击"
			data.accent = Color("ff7894")
			data.value = damage_text
			data.unit = "每段伤害 × 次数" if hits>1 else "点伤害"
			data.summary = "将对你造成 %d 次伤害，每次 %d 点。" % [hits,damage] if hits>1 else "将对你造成 %d 点攻击伤害。" % damage
			data.notes.append({"title":"伤害预览","body":"预计合计 %d 点，先由格挡抵消。数值已计入当前伤害修正。" % (damage*hits)})
		"strength_allies":
			data.title = "强化同伴"
			data.accent = Color("f3c875")
			data.value = "+%d" % amount
			data.unit = "层力量 / 每名存活小弟"
			data.summary = "为每名存活的小弟增加 %d 层力量。" % amount
			data.notes.append({"title":"力量","body":"每层使每段基础攻击伤害 +1，持续至本场战斗结束。"})
		"pollution":
			data.title = "施加污染"
			data.accent = Color("b3df80")
			data.value = str(amount)
			data.unit = "层污染"
			data.summary = "对你施加 %d 层污染。" % amount
			data.notes.append({"title":"污染","body":"自身回合结束时，受到等于当前层数的伤害，再减少 1 层；先扣格挡，不触发追加污染或弹反。"})
		"vulnerable":
			data.title = "施加易伤"
			data.accent = Color("d6a2f2")
			data.value = str(amount)
			data.unit = "层易伤"
			data.summary = "对你施加 %d 层易伤。" % amount
			data.notes.append({"title":"易伤","body":"受到的攻击伤害增加 50%，不影响状态伤害；自身回合结束时减少 1 层，增幅不随层数叠加。"})
	if enemy.has("allyDeathIntentSequence"):
		var sequence: Array = enemy.allyDeathIntentSequence.get("sequence",[])
		var steps: PackedStringArray = []
		for action in sequence:
			match str(action.get("type","")):
				"attack": steps.append("攻击 %d" % int(action.get("amount",0)))
				"vulnerable": steps.append("易伤 %d" % int(action.get("amount",0)))
		var condition := "小弟已倒下，按以下顺序循环行动：" if enemy.get("intentPhase","") == "ally_death" else "完整回合开始时，若已有小弟死亡，则从攻击开始切换为："
		data.notes.append({"title":"行动变化","body":condition+"\n"+" → ".join(steps)})
	if int(enemy.get("attackPollution",0))>0:
		data.notes.append({"title":"攻击附带","body":"每段攻击实际扣血时，追加 %d 层污染；污染伤害不触发。" % int(enemy.attackPollution)})
	if int(enemy.get("deathPollution",0))>0:
		data.notes.append({"title":"死亡效果","body":"死亡时，对你施加 %d 层污染。" % int(enemy.deathPollution)})
	var lines := PackedStringArray([data.enemy+" · "+data.title,preview,data.summary])
	for note in data.notes: lines.append(note.title+"："+note.body)
	data.plain = "\n".join(lines)
	return data

static func text_line(parent: Node, text: String, font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = TEXT_WIDTH
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

static func build(data: Dictionary, font: Font) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "EnemyIntentTooltip"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.x = WIDTH
	var accent: Color = data.accent
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101722fa")
	style.border_color = Color(accent,0.55)
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.shadow_color = Color("05080fa6")
	style.shadow_size = 10
	style.shadow_offset = Vector2(0,5)
	box.add_theme_stylebox_override("panel",style)
	var bold := FontVariation.new()
	bold.base_font = font
	bold.variation_embolden = 0.75
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation",7)
	box.add_child(rows)
	text_line(rows,data.enemy+"  /  下次行动",font,13,Color("99aab9"))
	text_line(rows,data.title,bold,23,accent)
	text_line(rows,data.value,bold,32,Color("fff5e8"))
	if not data.unit.is_empty(): text_line(rows,data.unit,font,13,Color("b7c2ce"))
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(TEXT_WIDTH,1)
	rule.color = Color(accent,0.22)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(rule)
	text_line(rows,data.summary,font,16,Color("f1eee8"))
	for note in data.notes:
		var section := VBoxContainer.new()
		section.mouse_filter = Control.MOUSE_FILTER_IGNORE
		section.add_theme_constant_override("separation",2)
		rows.add_child(section)
		text_line(section,note.title,bold,14,accent)
		text_line(section,note.body,font,14,Color("bcc9d6"))
	text_line(rows,data.footer,font,12,Color("7c90a1"))
	return box
