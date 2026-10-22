extends DemoUI
var checks := 0
var failures := 0
var output := "res://artifacts/qa/noren-fixed-cards-2026-10-22/integration/visual"
var fixture_examples := false
var content: Control
const EXAMPLES := {13: "重弹射击", 29: "撕裂斩", 6: "战术补弹", 26: "终结弹"}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func shot(filename: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(filename + ".png")) == OK, "Saved " + filename)

func reset_content(title: String) -> void:
	if is_instance_valid(content): content.free()
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	label(content, title, Vector2(30, 18), Vector2(1380, 50), 25)

func card_at(number: int, point: Vector2, card_scale: float, dynamic: bool = false) -> CombatCard:
	var definition: Dictionary = Game.card_catalog["noren_%02d" % number]
	var card := CombatCard.new()
	card.allow_zoom_preview = false
	card.setup(definition.id, definition, true)
	if fixture_examples:
		var path := ProjectSettings.globalize_path("res://../卡牌游戏美术资源/卡牌/固定排版模板_v1/outputs/examples/noren_%02d_%s_旧插画套模板.png" % [number, EXAMPLES[number]])
		var image := Image.load_from_file(path)
		check(image != null, "Fixture example loads")
		card.face_texture = ImageTexture.create_from_image(image)
		card.face_font = load("res://assets/fonts/NotoSerifCJKsc-Bold.otf")
	check(card.face_texture != null, "Artwork is present: " + definition.id)
	card.position = point
	card.pivot_offset = Vector2.ZERO
	card.scale = Vector2.ONE * card_scale
	content.add_child(card)
	if dynamic:
		var rules: Dictionary = Game.prototype_rules.duplicate(true)
		rules.merge(Game.noren_rules, true)
		rules.deck = [definition.id]
		rules.shuffleInitialDeck = false
		var model := CombatModel.new()
		model.initialize("B04", 100, 100, rules, [{"id": "preview", "displayName": "靶子", "maxHp": 1000, "intentSequence": []}], Game.card_catalog)
		model.stance = "ranged"
		model.turn_discount = 1
		model.next_attack_bonus = 3
		model.draw_pile.clear()
		model.hand = ["card_000"]
		card.show_preview(model.card_preview("card_000", 0))
		card.show_cost(model.card_cost("card_000"))
	return card

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("FIXED CARD FACE VISUAL: skipped; this build's headless driver has no rendered viewport. No screenshots or visual pass claimed.")
		get_tree().quit(2)
		return
	fixture_examples = "--fixture-examples" in OS.get_cmdline_user_args()
	if not OS.get_environment("QA_OUT_DIR").is_empty(): output = OS.get_environment("QA_OUT_DIR")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	Game.save_enabled = false
	Game.save_path = "user://fixed_card_face_visual.json"
	Game.meta_path = "user://fixed_card_face_visual_meta.json"
	Game.state = Game.initial_state()
	rect(self, Vector2.ZERO, Vector2(1440, 900), Color("111523"))
	var prefix := "UI测试夹具（旧插画模板，不是本轮40张正式图）" if fixture_examples else "诺伦固定卡面 · 正式资源"
	if not fixture_examples:
		for page in 5:
			reset_content(prefix + " · %d/5" % (page + 1))
			for index in 8:
				card_at(page * 8 + index + 1, Vector2(55 + (index % 4) * 345, 80 + (index / 4) * 395), 1.5)
			await shot("catalog-%02d" % (page + 1))
	reset_content(prefix + " · 上：原始卡面 / 下：远程、下次攻击+3、减费1")
	var index := 0
	var cards: Array[CombatCard] = []
	for number in EXAMPLES:
		card_at(number, Vector2(55 + index * 345, 80), 1.5)
		cards.append(card_at(number, Vector2(55 + index * 345, 490), 1.5, true))
		index += 1
	await shot("static-and-dynamic")
	var preview := cards[0]
	preview.allow_zoom_preview = true
	preview.show_zoom_preview()
	check(preview.zoom_card.effect_label.text == preview.effect_label.text, "Zoom keeps the same calculated rules")
	check(preview.zoom_card.cost_label.text == preview.cost_label.text, "Zoom keeps the same discounted cost")
	await shot("zoom")
	preview.hide_zoom_preview()
	await settle()
	print("FIXED CARD FACE VISUAL: %d checks, %d failures; fixture_examples=%s" % [checks, failures, fixture_examples])
	get_tree().quit(0 if failures == 0 else 1)
