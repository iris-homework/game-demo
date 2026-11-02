extends DemoUI
## Shared visual layout for story pages and in-battle encounter dialogue.
const STORY_RED := Color("ff393e")
const STORY_WHITE := Color("f4f2ef")

func dialogue_portraits(shown: Dictionary, speaker_id: String, speaker_side: String) -> void:
	var speaker := Game.resolve_character_id(speaker_id)
	portrait(shown.left, "left", speaker_side == "left" and Game.resolve_character_id(shown.left) == speaker, 173, 642)
	portrait(shown.right, "right", speaker_side == "right" and Game.resolve_character_id(shown.right) == speaker, 173, 642)

func dialogue_text(text: String) -> Label:
	var body := label(self, text, Vector2(330,706), Vector2(1004,118), 25, STORY_WHITE)
	body.name = "DialogueText"
	body.add_theme_constant_override("line_spacing", 8)
	return body

func dialogue_hint(text: String) -> Label:
	var hint := label(self, text, Vector2(330,842), Vector2(650,26), 13, MUTED)
	hint.name = "DialogueHint"
	return hint

func dialogue_panel(speaker: String) -> void:
	# Solid reading panel and a shared horizontal cap for the rising left graphics.
	rect(self, Vector2(0,650), Vector2(1440,250), Color.BLACK)
	# Two rising red rails frame the lower-right corner; the center stays open.
	_dialogue_polygon([Vector2(1025,900),Vector2(1440,786),Vector2(1440,839),Vector2(1214,900)], STORY_RED)
	_dialogue_polygon([Vector2(1047,900),Vector2(1440,792),Vector2(1440,832),Vector2(1190,900)], Color.BLACK)
	_dialogue_polygon([Vector2(1320,801),Vector2(1440,767),Vector2(1440,783),Vector2(1320,817)], STORY_RED)
	# Left slopes are clipped at y=650; keep the long underline and short bottom stripe.
	_dialogue_polygon([Vector2(0,708),Vector2(242.20,650),Vector2(275.60,650),Vector2(0,716)], STORY_RED)
	_dialogue_polygon([Vector2(0,716),Vector2(275.60,650),Vector2(380,650),Vector2(380,676),Vector2(0,767)], Color.BLACK)
	_dialogue_polygon([Vector2(0,767),Vector2(486.85,650),Vector2(511.81,650),Vector2(0,773)], STORY_RED)
	_dialogue_polygon([Vector2(0,779),Vector2(260,717),Vector2(260,804),Vector2(0,866)], STORY_RED)
	_dialogue_polygon([Vector2(0,877),Vector2(170,836),Vector2(170,844),Vector2(0,885)], STORY_RED)
	var speaker_name := Game.display_name(speaker) if not speaker.is_empty() else "场景"
	var name_font := FontVariation.new()
	name_font.base_font = base_font
	name_font.variation_embolden = 0.65
	name_font.spacing_glyph = 2
	var speaker_label := label(self, speaker_name, Vector2(20,708), Vector2(222,49), 27, STORY_WHITE)
	speaker_label.name = "SpeakerName"
	speaker_label.add_theme_font_override("font", name_font)
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speaker_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	speaker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	speaker_label.rotation = -0.20
	# Center both lines on the red plaque's local axis, using the original fonts.
	var brand_center := Vector2(130,791.5)
	var brand_angle := Vector2(260,-62).angle() # Match the plaque edge exactly.
	var title := label(self, "午夜委托", brand_center + Vector2(-110,-30).rotated(brand_angle), Vector2(220,30), 21, Color.BLACK)
	title.add_theme_font_override("font", name_font)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.rotation = brand_angle
	var subtitle := label(self, "MIDNIGHT COMMISSION", brand_center + Vector2(-110,3).rotated(brand_angle), Vector2(220,22), 13, Color.BLACK)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	subtitle.rotation = brand_angle

func _dialogue_polygon(points: Array, color: Color) -> Polygon2D:
	var shape := polygon(self, points, color)
	shape.antialiased = true
	return shape

