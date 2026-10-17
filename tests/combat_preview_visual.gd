extends Node
const Fixtures = preload("res://tests/noren_cards_tests.gd")
var app: Control
var helper: Node
var checks := 0
var failures := 0
var output := "res://artifacts/qa/combat-preview-2026-10-17/"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func idle() -> void:
	var started := Time.get_ticks_msec()
	while Game.battle_busy or Game.transition_locked:
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > 20000:
			push_error("Preview visual timeout")
			get_tree().quit(2)
			return
	await get_tree().process_frame

func shot(filename: String) -> void:
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + filename + ".png")

func install(ids: Array, form: String = "ranged") -> void:
	var m: CombatModel = helper.fixture(ids, form, 2)
	m.energy = 10
	m.ammo = 6
	m.enemies[0].hp = 500
	m.enemies[0].bleed = 5
	m.enemies[0].weak = 2
	m.enemies[0].block = 100
	m.enemies[1].hp = 1000
	m.enemies[1].bleed = 0
	m.block = 100
	m.turn_damage_bonus = 4
	Game.commit_combat(m)
	app.swap_view()
	await idle()

func aim_at(index: int) -> void:
	var view = app.view
	view.update_target_rects()
	var point: Vector2 = view.targets[index].get_global_rect().get_center()
	Input.warp_mouse(get_viewport().get_final_transform() * point)
	await get_tree().process_frame
	view._process(0.0)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	Game.save_enabled = false
	Game.save_path = "user://preview_visual_unused.json"
	Game.meta_path = "user://preview_visual_meta_unused.json"
	helper = Fixtures.new()
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	await install([25, 36, 20, 39, 31])
	var view = app.view
	check(view.cards.card_000.effect_label.text.contains("24–33"), "Unselected execute shows target-dependent range")
	check(view.targets[0].tooltip_text.contains("攻击 8"), "Enemy intent includes weakness and ignores player block")
	view.select_card("card_000")
	await aim_at(0)
	check(view.hovered_target == 0 and view.cards.card_000.effect_label.text.contains("造成33点伤害"), "Aim updates execute against half-HP target")
	await shot("battle-execute-target")
	await aim_at(1)
	check(view.hovered_target == 1 and view.cards.card_000.effect_label.text.contains("造成24点伤害"), "Changing target updates damage")
	view.cancel_selection()
	view.select_card("card_001")
	await aim_at(0)
	check(view.cards.card_001.effect_label.text == "造成8／2／2／2点伤害，共4次。", "Multi-hit face updates existing damage only, without extra bleed or ammo lines")
	await shot("battle-multihit-bleed")
	view.cancel_selection()
	view.select_card("card_003")
	await aim_at(0)
	check(view.cards.card_003.effect_label.text == view.cards.card_003.data.cardText, "Satisfied block condition retains correct printed number")
	await aim_at(1)
	check(view.cards.card_003.effect_label.text == view.cards.card_003.data.cardText.replace("获得4点格挡", "获得0点格挡"), "Target changes update only the existing block number")
	view.cancel_selection()
	view.select_card("card_002")
	view.play_selected(0)
	check(view.pile_overlay.options.size() == 3, "Extra ammo picker retains three choices")
	for i in 3:
		check(view.pile_overlay.options[i].text.contains("造成%d点伤害" % (21 + i * 6)), "Ammo choice shows final damage %d" % i)
	await shot("ammo-choices")
	view.close_pile()
	view.cancel_selection()
	view.show_cyberware()
	view.activate_cyberware(view.model.cyberware_cards()[0].id)
	view.close_pile()
	check(view.cards.card_002.effect_label.text.contains("23–35"), "Technology activation refreshes hand immediately")
	view.show_pile("抽牌堆", view.model.draw_pile)
	var pile_card: CombatCard = view.pile_overlay.grid.get_child(0).get_child(0)
	check(pile_card.effect_label.text.contains("17点伤害"), "Pile cards use current bonuses and ranged multiplier")
	await shot("pile-preview")
	view.close_pile()
	view.model.turn_discount = 1
	view.commit()
	check(view.cards.card_002.cost_label.text == "费用 1", "Hand still shows discounted cost")
	var frozen: Dictionary = view.model.snapshot()
	Game.open_current_deck()
	await get_tree().process_frame
	var deck_cards: Array = app.deck_browser.card_views
	check(deck_cards.size() == 6, "Current battle deck includes all six card types")
	for card in deck_cards:
		check(card.effect_label.text == card.data.get("cardText", card.data.description), "Library shows original effect: " + card.data.name)
		check(card.cost_label.text == "费用 %d" % int(card.data.cost), "Library shows original cost: " + card.data.name)
		check(card.card_button.tooltip_text == card.data.description, "Library shows original tooltip: " + card.data.name)
	check(view.model.snapshot() == frozen, "Library browsing preserves combat state")
	await shot("library-original-values")
	# Independent rendered matrix checks all 40 cards in both forms, with buffs.
	if is_instance_valid(app.deck_browser): app.close_current_deck()
	view.select_card("card_002")
	var played_card: CombatCard = view.cards.card_002
	view.play_selected(0, "", 2)
	check(played_card.effect_label.text.contains("造成35点伤害"), "Retiring card retains chosen ammo and consumed buff values")
	check(played_card.cost_label.text == "费用 1", "Retiring card retains the cost actually paid before discount consumption")
	await idle()
	check(view.cards.card_001.effect_label.text == "造成2点伤害，共4次。", "Remaining hand refreshes damage while retaining authored hit count")
	view.show_pile("弃牌堆", view.model.discard_pile)
	var discarded_card: CombatCard = view.pile_overlay.grid.get_child(0).get_child(0)
	check(discarded_card.effect_label.text.contains("造成15–27点伤害"), "Discard pile continues to show calculated ranged damage")
	await shot("discard-calculated-values")
	view.close_pile()
	await install([19], "ranged")
	view = app.view
	view.model.enemies[0].hp = 1
	view.model.enemies[0].block = 0
	view.model.enemies[0].bleed = 0
	Game.commit_combat(view.model)
	app.swap_view()
	await idle()
	view = app.view
	view.select_card("card_000")
	await aim_at(0)
	check(view.cards.card_000.effect_label.text.contains("施加1层虚弱"), "Lethal attack still displays potential weakness layers")
	await shot("lethal-target-potential-status")
	view.cancel_selection()
	for form in ["melee", "ranged"]:
		for page in 4:
			var board := Control.new()
			board.z_index = 200
			view.add_child(board)
			view.rect(board, Vector2.ZERO, Vector2(1440,900), Color("07080c"))
			view.label(board, "当前效果预览 · " + form + " · %d/4" % (page + 1), Vector2(40,30), Vector2(1200,50), 30)
			for i in 10:
				var m: CombatModel = helper.fixture([page * 10 + i + 1], form)
				m.turn_damage_bonus = 4
				m.ammo = 5
				m.parry = 2
				m.powers = ["high_pressure", "dissection"]
				m.enemies[0].bleed = 5
				var card := CombatCard.new()
				card.setup("card_000", m.card("card_000"), true)
				card.position = Vector2(55 + (i % 5) * 278, 125 + (i / 5) * 350)
				card.scale = Vector2.ONE * 1.35
				card.pivot_offset = Vector2.ZERO
				board.add_child(card)
				card.show_preview(m.card_preview("card_000", 0))
				card.show_cost(m.card_cost("card_000"))
				var size: Vector2 = card.base_font.get_multiline_string_size(card.effect_label.text, HORIZONTAL_ALIGNMENT_LEFT, card.effect_label.size.x, card.effect_label.get_theme_font_size("font_size"), -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
				check(size.y <= card.effect_label.size.y, "%s %s dynamic text fits" % [form, card.data.name])
			await shot("cards-%s-%d" % [form, page + 1])
			board.queue_free()
			await get_tree().process_frame
	print("COMBAT PREVIEW VISUAL: %d checks, %d failures" % [checks, failures])
	helper.free()
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
