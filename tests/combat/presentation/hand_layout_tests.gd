extends "res://tests/combat/cards/noren_cards_visual.gd"
## Headless geometry, hit lookup and card poses; no system pointer movement.
const CORNERS := [Vector2.ZERO,Vector2(180,0),Vector2(180,230),Vector2(0,230)]

func exposed_point(view: Control, index: int) -> Vector2:
	var card: CombatCard = view.cards[view.model.hand[index]]
	for y in [2,8,24,50,90]:
		for x in [2,10,25,50,90,140,178]:
			var point := card.get_global_transform()*Vector2(x,y)
			if not Rect2(210,0,1020,900).has_point(point): continue
			var covered := false
			for j in range(index+1,view.model.hand.size()):
				var later: CombatCard = view.cards[view.model.hand[j]]
				if Rect2(Vector2.ZERO,later.size).has_point(later.get_global_transform().affine_inverse()*point):
					covered = true
					break
			if not covered: return point
	return Vector2.INF

func check_rest(view: Control, count: int) -> void:
	check(view.cards.size() == count,"All hand instances have views: %d" % count)
	var left := INF
	var right := -INF
	for i in count:
		var card: CombatCard = view.cards[view.model.hand[i]]
		check(card.scale.is_equal_approx(Vector2.ONE*1.056),"Hand card uses the additional ten-percent resting size")
		check(card.position.is_equal_approx(card.home) and is_equal_approx(card.rotation,card.home_rotation),"Resting pose matches layout after dealing/reflow")
		for corner in CORNERS:
			var point: Vector2 = card.get_global_transform()*corner
			left = minf(left,point.x)
			right = maxf(right,point.x)
			check(point.x >= 218.0-0.01 and point.x <= 1222.0+0.01,"Rotated corners leave a margin beside side controls")
		check((card.get_global_transform()*Vector2(90,0)).y < 900.0 and (card.get_global_transform()*Vector2(90,230)).y > 900.0,"Cards retain the partially submerged bottom edge")
		if count > 1 and i != (count-1)/2.0:
			var inward_index := i+1 if i < (count-1)/2.0 else i-1
			var neighbour: CombatCard = view.cards[view.model.hand[inward_index]]
			var inward_corner := Vector2(180,0) if i < (count-1)/2.0 else Vector2.ZERO
			var corner_in_neighbour := neighbour.get_global_transform().affine_inverse()*(card.get_global_transform()*inward_corner)
			check(corner_in_neighbour.y >= -3.0,"Inward upper corners do not spike above neighbouring cards")
		if i > 0:
			var previous: CombatCard = view.cards[view.model.hand[i-1]]
			var chord := card.home-previous.home
			check(is_equal_approx(chord.angle(),(card.home_rotation+previous.home_rotation)/2.0),"Card tilt follows the shared layout arc")
	check(is_equal_approx((left+right)/2.0,720.0),"The complete hand stays centered")

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://hand_layout_unused.json"
	Game.meta_path = "user://hand_layout_meta_unused.json"
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	for count in [1,5,7,10,20,40]:
		var numbers: Array = []
		numbers.resize(count)
		numbers.fill(1)
		await install_hand(numbers)
		var view: Control = app.view
		# The headless display has no desktop pointer. Exercise the same hit lookup
		# explicitly and prevent automatic hover from replacing the requested pose.
		view.set_process(false)
		for card in view.cards.values(): card.allow_zoom_preview = false
		await get_tree().create_timer(0.2).timeout
		check(is_equal_approx(view.hand_position(0,1).y,748.0),"Hand baseline is raised by twelve pixels")
		check_rest(view,count)
		var before: Dictionary = view.model.snapshot()
		var points: Array[Vector2] = []
		for i in count: points.append(exposed_point(view,i))
		for i in count:
			check(points[i] != Vector2.INF,"Every card has an exposed, onscreen selection area")
			if points[i] == Vector2.INF: continue
			check(view.hand_at_point(points[i]) == view.model.hand[i],"Overlapping fan picks the visible card instance")
			var card: CombatCard = view.cards[view.model.hand[i]]
			card.hover(true)
			await get_tree().create_timer(0.18).timeout
			check(card.hovered and absf(card.rotation) < 0.01,"Hover lifts and straightens the intended card")
			for corner in CORNERS:
				check(Rect2(0,0,1440,900).has_point(card.get_global_transform()*corner),"Hovered card fits completely in the viewport")
			view.select_card(view.model.hand[i],false)
			await get_tree().create_timer(0.18).timeout
			check(view.selected_uid == card.uid,"An exposed card can still be selected")
			for corner in CORNERS:
				check(Rect2(0,0,1440,900).has_point(card.get_global_transform()*corner),"Selected attack fits completely in the viewport")
			view.cancel_selection()
			card.hover(false)
			await get_tree().create_timer(0.18).timeout
		check(view.model.snapshot() == before,"Layout, hover, selection and cancel preserve all combat state")
		if count == 10:
			view.model.draw_cards(2)
			await view.deal_hand(true)
			view.arrange_hand()
			await get_tree().create_timer(0.2).timeout
			check_rest(view,12)
			var retired_uid: String = view.model.hand.pop_front()
			view.model.discard_pile.append(retired_uid)
			view.cards[retired_uid].queue_free()
			view.cards.erase(retired_uid)
			view.arrange_hand()
			await get_tree().create_timer(0.2).timeout
			check_rest(view,11)
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("HAND LAYOUT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
