extends Control
## Fixed enemy readout matching the player's top status bar.
var hp := 0
var max_hp := 1
var block := 0
var hp_label: Label
const DIMENSIONS := Vector2(328,68)
const TRACK := Rect2(18,44,170,12)

func _init() -> void:
	size = DIMENSIONS
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func text_label(text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.position = at
	result.size = dimensions
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	return result

func setup(enemy: Dictionary, number: int, font: Font) -> void:
	add_theme_font_override("font",font)
	hp = int(enemy.hp)
	max_hp = maxi(1,int(enemy.maxHp))
	block = int(enemy.get("block",0))
	var title := "%02d  %s" % [number,enemy.displayName]
	var name_label := text_label(title,Vector2(18,4),Vector2(198,26),19,Color("f5f3eb"))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = title
	hp_label = text_label("%d / %d" % [hp,max_hp],Vector2(196,32),Vector2(126,28),16,Color("f5f3eb"))
	var state := "已击败" if hp <= 0 else ("格挡 %d" % block if block > 0 else "")
	var status := text_label(state,Vector2(218,7),Vector2(98,22),13,Color("6dcaff") if hp > 0 else Color("a7b0be"))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,DIMENSIONS),Color("070e19ee"))
	draw_rect(Rect2(0,67,DIMENSIONS.x,1),Color("2f6178"))
	draw_rect(TRACK,Color("805071"))
	draw_rect(TRACK.grow(-1),Color("382333"))
	draw_rect(Rect2(Vector2(20,46),Vector2(166*clampf(float(hp)/max_hp,0,1),8)),Color("ff3158"))
