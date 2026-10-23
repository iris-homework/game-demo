extends "res://tests/combat/cards/noren_cards_visual.gd"
## Headless presentation and lifecycle contracts; no screenshots or pointer helpers.
const FX_PATH := "res://scripts/combat/exhaust_fx.gd"
const DISCARD_PATH := "res://scripts/combat/discard_fx.gd"
var observed: Array = []
var discarded: Array = []
var tracked: Dictionary = {}
var cases: Array = []
var composition_ok := true
var ownership_ok := true
var input_disabled := true
var selected_highlight := true
var progress_ok := true
var local_motion := true
var saw_dissolve := false
var max_progress := 0.0
var effect_refs: Array = []
var card_refs: Array = []
var viewport_refs: Array = []

func reset_observations() -> void:
	observed.clear()
	discarded.clear()
	tracked.clear()
	effect_refs.clear()
	card_refs.clear()
	viewport_refs.clear()
	composition_ok = true
	ownership_ok = true
	input_disabled = true
	selected_highlight = true
	progress_ok = true
	local_motion = true
	saw_dissolve = false
	max_progress = 0.0

func sample_effects(view: Control) -> void:
	for effect in get_tree().get_nodes_in_group("card_exhaust_fx"):
		var card: CombatCard = effect.card
		if not is_instance_valid(card):
			ownership_ok = false
			continue
		var id := effect.get_instance_id()
		if not tracked.has(id):
			observed.append(card.uid)
			tracked[id] = {"origin":effect.global_position,"progress":-1.0}
			effect_refs.append(weakref(effect))
			card_refs.append(weakref(card))
			var captures := effect.find_children("*","SubViewport",true,false)
			var sprites := effect.find_children("*","Sprite2D",true,false)
			var owns_full_card := false
			var displays_capture := false
			for capture in captures:
				viewport_refs.append(weakref(capture))
				owns_full_card = owns_full_card or capture.is_ancestor_of(card)
				for sprite in sprites:
					displays_capture = displays_capture or (sprite.texture is ViewportTexture and sprite.texture == capture.get_texture() and sprite.material is ShaderMaterial)
			composition_ok = composition_ok and owns_full_card and displays_capture
		ownership_ok = ownership_ok and effect.get_script().resource_path == FX_PATH and view.is_ancestor_of(effect) and effect.is_ancestor_of(card)
		input_disabled = input_disabled and not card.enabled and card.mouse_filter == Control.MOUSE_FILTER_IGNORE and card.card_button.mouse_filter == Control.MOUSE_FILTER_IGNORE
		selected_highlight = selected_highlight and card.selected
		var progress: float = effect.progress
		progress_ok = progress_ok and progress >= 0.0 and progress <= 1.0 and progress >= float(tracked[id].progress)
		tracked[id].progress = progress
		max_progress = maxf(max_progress,progress)
		saw_dissolve = saw_dissolve or (progress > 0.05 and progress < 0.95)
		local_motion = local_motion and effect.global_position.distance_to(tracked[id].origin) <= 140.0
	for child in view.get_children():
		var script = child.get_script()
		if script == null or script.resource_path != DISCARD_PATH: continue
		if is_instance_valid(child.card) and not child.card.uid in discarded:
			discarded.append(child.card.uid)

func pile_integrity(model: CombatModel) -> bool:
	var all_uids: Array = []
	all_uids.append_array(model.hand)
	all_uids.append_array(model.draw_pile)
	all_uids.append_array(model.discard_pile)
	all_uids.append_array(model.exhaust_pile)
	var unique := {}
	for uid in all_uids:
		if unique.has(uid): return false
		unique[uid] = true
	return unique.size() == model.instances.size()

func observe_completion(view: Control, committed: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	var unchanged := true
	var unique_zones := true
	while Game.battle_busy or Game.transition_locked or not get_tree().get_nodes_in_group("card_exhaust_fx").is_empty():
		sample_effects(view)
		unchanged = unchanged and view.model.snapshot() == committed
		unique_zones = unique_zones and pile_integrity(view.model)
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > 20000:
			check(false,"Exhaust presentation timed out")
			get_tree().quit(2)
			return
	await get_tree().process_frame
	check(unchanged and view.model.snapshot() == committed,"Presentation never mutates the committed combat snapshot")
	check(unique_zones and pile_integrity(view.model),"Every card instance remains in exactly one of the four model zones")

func exercise(title: String, expected_exhaust: Array, expected_discard: Array, picked_uid: String = "") -> void:
	var view: Control = app.view
	reset_observations()
	view.select_card("card_000")
	view.play_selected(-1)
	if not picked_uid.is_empty():
		check(is_instance_valid(view.pile_overlay) and not Game.battle_busy,title + ": choosing the other card does not resolve the play early")
		check(observed.is_empty() and get_tree().get_nodes_in_group("card_exhaust_fx").is_empty(),title + ": no dissolve before the choice commits")
		view.pile_overlay.picked.emit(picked_uid)
	sample_effects(view)
	check(Game.battle_busy,title + ": committed card holds the busy lock")
	check(observed == expected_exhaust,title + ": only exhausted cards receive the new effect")
	check(discarded == expected_discard,title + ": ordinary discarded cards keep the discard effect")
	var committed: Dictionary = view.model.snapshot()
	view.select_card("card_001")
	view.play_selected(0)
	view.end_turn_pressed()
	check(view.model.snapshot() == committed,title + ": busy lock rejects repeated play and end turn")
	for uid in expected_exhaust:
		check(uid in view.model.exhaust_pile and not uid in view.model.discard_pile and not uid in view.model.hand and not uid in view.model.draw_pile,title + ": exhausted instance enters only the exhaust pile")
	for uid in expected_discard:
		check(uid in view.model.discard_pile and not uid in view.model.exhaust_pile,title + ": ordinary instance enters only the discard pile")
	await observe_completion(view,committed)
	check(observed == expected_exhaust,title + ": no duplicate exhaust effect appears during playback")
	check(composition_ok,title + ": the full original card is captured by a viewport and displayed on a sprite")
	check(ownership_ok and input_disabled,title + ": effect owns its card and disables all card input")
	if not expected_exhaust.is_empty():
		check(selected_highlight,title + ": exhausted card keeps its selected highlight during the effect")
	check(progress_ok and local_motion,title + ": dissolve progresses monotonically near its original position")
	if not expected_exhaust.is_empty():
		check(saw_dissolve and max_progress >= 0.95,title + ": dissolve passes through intermediate values and reaches completion")
	check(get_tree().get_nodes_in_group("card_exhaust_fx").is_empty(),title + ": effect leaves its group after finishing")
	check(effect_refs.all(func(reference): return reference.get_ref() == null) and card_refs.all(func(reference): return reference.get_ref() == null) and viewport_refs.all(func(reference): return reference.get_ref() == null),title + ": effect, original card and capture viewport are released")
	check(view.cards.size() == view.model.hand.size(),title + ": hand views match committed hand")
	cases.append({"case":title,"exhaust_effects":observed.duplicate(),"discard_effects":discarded.duplicate(),"maximum_dissolve_progress":max_progress})

func teardown_mid_effect() -> void:
	await install_hand([5,1])
	var view: Control = app.view
	reset_observations()
	view.select_card("card_000")
	view.play_selected(-1)
	var started := Time.get_ticks_msec()
	while max_progress < 0.15 and not get_tree().get_nodes_in_group("card_exhaust_fx").is_empty():
		sample_effects(view)
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > 3000: break
	check(not effect_refs.is_empty() and max_progress > 0.0 and max_progress < 1.0,"Mid-page teardown starts with a live dissolving card")
	var committed: Dictionary = view.model.snapshot()
	var model: CombatModel = view.model
	# Force the same view replacement path used by routing, without physical input.
	Game.page = "menu"
	app.swap_view()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(view) and get_tree().get_nodes_in_group("card_exhaust_fx").is_empty(),"Page replacement releases the battle view and active effect")
	check(effect_refs.all(func(reference): return reference.get_ref() == null) and card_refs.all(func(reference): return reference.get_ref() == null) and viewport_refs.all(func(reference): return reference.get_ref() == null),"Page replacement frees the captured card and viewport immediately")
	check(model.snapshot() == committed,"Mid-effect teardown preserves already committed model state")
	Game.battle_busy = false
	# Let any remaining cosmetic callbacks reach their original deadline.
	await get_tree().create_timer(1.0).timeout
	check(get_tree().get_nodes_in_group("card_exhaust_fx").is_empty(),"No delayed callback recreates the destroyed effect")

func _ready() -> void:
	output = "res://artifacts/qa/exhaust-fx-2026-10-23/"
	Game.save_enabled = false
	Game.save_path = "user://exhaust_fx_unused.json"
	Game.meta_path = "user://exhaust_fx_meta_unused.json"
	DirAccess.make_dir_recursive_absolute(output)
	Game.state = Game.initial_state()
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Game.start_training("B04")
	await idle()
	await install_hand([5,1])
	check(app.view.model.card("card_000").get("exhaust",false),"Self-exhaust case uses the real catalog exhaust flag")
	await exercise("05 补弹",["card_000"],[])
	await install_hand([23,1],"ranged")
	check(app.view.model.card("card_000").type == "power","Power case uses a real power card")
	await exercise("23 弱点瞄准",["card_000"],[])
	check(app.view.model.powers.has("ranged_mastery"),"Power resolves once and persists after its card dissolves")
	await install_hand([12,1,13,2])
	await exercise("12 拆卸弹药",["card_002"],["card_000"],"card_002")
	check(app.view.model.ammo == 4,"Dismantle grants its actual ammo once")
	await install_hand([2,1])
	await exercise("02 普通弃牌",[],["card_000"])
	await install_hand([5,1])
	# Reject a genuine exhaust card by freezing its energy cost above available energy.
	app.view.model.card_catalog.noren_05.cost = 1
	app.view.model.energy = 0
	app.view.commit()
	reset_observations()
	var before: Dictionary = app.view.model.snapshot()
	app.view.select_card("card_000")
	app.view.play_selected(-1)
	await get_tree().process_frame
	sample_effects(app.view)
	check(app.view.model.snapshot() == before and not Game.battle_busy and observed.is_empty(),"Rejected exhaust card has no effect and spends no resources")
	await teardown_mid_effect()
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path),"Headless checks never write save or meta files")
	var result := {"checks":checks,"failures":failures,"headless":true,"cases":cases,"limitations":["No rendered-image or human visual review","No physical input or normal menu-exit flow; forced routing tests view lifecycle"]}
	var file := FileAccess.open(output + "result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("EXHAUST FX: %d checks, %d failures" % [checks,failures])
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
