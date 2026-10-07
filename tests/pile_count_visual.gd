extends "res://tests/turn_banner_visual.gd"
## Counters follow visible transfers; all fixtures and snapshots stay in memory.
var count_history: Array[Vector2i] = []
func _process(_delta: float) -> void:
	if not is_instance_valid(app) or app.shown_page != "battle": return
	var view = app.view
	if not is_instance_valid(view.draw_count): return
	var pair := Vector2i(int(view.draw_count.text),int(view.discard_count.text))
	if count_history.is_empty() or count_history.back() != pair: count_history.append(pair)

func counts(view, draw: int, discard: int, description: String) -> void:
	verify(view.draw_count.text == str(draw) and view.discard_count.text == str(discard),description+" (actual %s/%s, expected %d/%d)" % [view.draw_count.text,view.discard_count.text,draw,discard])

func _ready() -> void:
	Game.save_enabled = false
	output = OS.get_temp_dir().path_join("midnight_count_")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.start_training("B04")
	await wait_banner("第1回合")
	var view = app.view
	counts(view,5,0,"Before opening draw all five cards are in deck")
	await idle()
	counts(view,0,0,"Opening hand removes exactly five cards")
	verify(count_history.has(Vector2i(4,0)) and count_history.has(Vector2i(1,0)),"Opening draw counter decreases during staggered flights")
	view.model.enemies[0].hp = 100
	view.model.enemies[0].maxHp = 100
	view.refresh_enemy_hud()
	view.select_card(view.model.hand[0])
	await view.play_selected(0)
	# Immediately end the turn while the played card is still in flight.
	view.end_turn_pressed()
	await wait_banner("敌方回合")
	await settle(0.65)
	counts(view,0,5,"Played card plus four cleanup cards all arrive during enemy banner")
	verify(view.model.turn == 1 and view.model.player_hp == 100,"Display transfers never resolve the model early")
	await shot("all_discarded")
	await idle()
	counts(view,0,0,"Full recycle and redraw leave both piles empty")
	verify(view.model.hand.size() == 5,"Recycle preserves the five-card hand")
	# Leave two cards in the draw pile: next draw must recycle partway through.
	for i in 2:
		var uid := "count_fixture_%d" % i
		view.model.instances[uid] = "test_attack"
		view.model.draw_pile.append(uid)
	view.refresh_counts()
	count_history.clear()
	view.end_turn_pressed()
	await wait_banner("敌方回合")
	await settle(0.65)
	counts(view,2,5,"Cleanup preserves undealt cards and counts each discard")
	await idle()
	counts(view,2,0,"Partial recycle leaves exactly two undealt cards")
	verify(count_history.has(Vector2i(1,5)) and count_history.has(Vector2i(4,0)),"Partial deal uses existing deck first then recycles only when exhausted")
	verify(count_history.all(func(pair): return pair.x >= 0 and pair.y >= 0),"Animated counters never become negative")
	verify(view.model.draw_pile.size() == 2 and view.model.hand.size() == 5,"Display agrees with partial recycle model")
	# Consecutive attacks overlap their visual tails.
	for i in 2:
		view.select_card(view.model.hand[0])
		await view.play_selected(0)
	await settle(0.5)
	counts(view,2,2,"Overlapping discard flights count each card once")
	view.show_pile("弃牌堆",view.model.discard_pile)
	verify(view.pile_overlay.displayed_uids.size() == int(view.discard_count.text),"Discard browser agrees with settled counter")
	view.close_pile()
	await shot("two_discarded")
	view.commit()
	app.swap_view()
	await idle()
	view = app.view
	counts(view,2,2,"Restoring snapshot initializes both counters correctly")
	# No recycling: an empty deck must leave the discard pile intact.
	view.model.profile.recycleDiscardWhenEmpty = false
	view.end_turn_pressed()
	await idle()
	counts(view,0,5,"Disabled recycling keeps discards while drawing only available cards")
	verify(view.model.hand.size() == 2,"Short draw preserves actual available hand size")
	print("PILE COUNT VISUAL: %d checks, %d failures; %s" % [checks,failures,output])
	get_tree().quit(0 if failures == 0 else 1)
