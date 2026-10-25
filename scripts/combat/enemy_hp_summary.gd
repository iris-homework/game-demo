extends Control
## Fixed enemy readout matching the player's top status bar.
var hp := 0
var max_hp := 1
var block := 0
var hp_label: Label
const DIMENSIONS := Vector2(328,68)
const BOSS_DIMENSIONS := Vector2(600,68)
const TRACK := Rect2(18,44,170,12)
const BOSS_TRACK := Rect2(18,44,442,12)
var track := TRACK
var show_background := true

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

func setup(enemy: Dictionary, number: int, font: Font, boss: bool = false) -> void:
	add_theme_font_override("font",font)
	show_background = not boss
	size = BOSS_DIMENSIONS if boss else DIMENSIONS
	track = BOSS_TRACK if boss else TRACK
	hp = int(enemy.hp)
	max_hp = maxi(1,int(enemy.maxHp))
	block = int(enemy.get("block",0))
	var title: String = str(enemy.displayName) if boss else "%02d  %s" % [number,enemy.displayName]
	var name_label := text_label(title,Vector2(18,4),Vector2(size.x-130,26),19,Color("f5f3eb"))
	if boss:
		# Center over the health track, excluding the HP readout on the right.
		name_label.position.x = track.position.x
		name_label.size.x = track.size.x
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = title
	hp_label = text_label("%d / %d" % [hp,max_hp],Vector2(size.x-132,32),Vector2(126,28),16,Color("f5f3eb"))
	var state := "已击败" if hp <= 0 else ("格挡 %d" % block if block > 0 else "")
	var status := text_label(state,Vector2(size.x-110,7),Vector2(98,22),13,Color("6dcaff") if hp > 0 else Color("a7b0be"))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	queue_redraw()

func _draw() -> void:
	if show_background:
		draw_rect(Rect2(Vector2.ZERO,size),Color("070e19ee"))
		draw_rect(Rect2(0,67,size.x,1),Color("2f6178"))
	draw_rect(track,Color("805071"))
	draw_rect(track.grow(-1),Color("382333"))
	draw_rect(Rect2(Vector2(20,46),Vector2((track.size.x-4)*clampf(float(hp)/max_hp,0,1),8)),Color("ff3158"))
