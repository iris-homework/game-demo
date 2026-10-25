extends Node
const OUT := "res://artifacts/qa/black-market-2026-10-23/"
var checks := 0
var failures: Array = []
var app: Control

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		push_error(detail)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		get_viewport().push_input(event,true)
	await settle()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Game.save_enabled = false
	Game.save_path = OUT+"ui-checkpoint.json"
	Game.meta_path = OUT+"ui-meta.json"
	Game.state = Game.initial_state()
	Game.state.credits = 2000
	Game.state.currentScene = "map"
	Game.page = "map"
	app = preload("res://scenes/main.tscn").instantiate()
	add_child(app)
	Game.visit("market")
	Game.skip_dialogue(Game.revision)
	await settle()
	var view = app.view
	check(view.get_script().resource_path.ends_with("black_market.gd"),"Map visit routes to the real shop")
	check(view.get_node_or_null("return_map") != null,"Shop has a city-map exit")
	check(Game.texture("black_market_shop") != null,"Generated shop background imported")
	var scenery: Control = view.get_node("black_market_art")
	check(scenery.get_child_count() == 3,"Shop uses background portrait and counter layers")
	var portrait: TextureRect = scenery.get_node("black_market_shopkeeper")
	var backdrop: TextureRect = scenery.get_node("black_market_background")
	var counter: Polygon2D = scenery.get_node("black_market_counter")
	check(portrait.texture == Game.texture("black_market_shopkeeper") and portrait.texture != backdrop.texture,"Portrait resolves its independent texture")
	check(portrait.texture.get_width() >= portrait.size.x * 1.8 and portrait.texture.get_height() >= portrait.size.y * 1.8,"Portrait has native detail headroom at current display size")
	var portrait_image := portrait.texture.get_image()
	check(portrait_image.detect_alpha() != Image.ALPHA_NONE and portrait_image.get_pixel(0,0).a == 0,"Portrait has real transparency")
	check(counter.texture == backdrop.texture and counter.get_index() > portrait.get_index(),"Foreground reuses the exact background texture above the portrait")
	check(scenery.mouse_filter == Control.MOUSE_FILTER_IGNORE and portrait.modulate == Color.WHITE,"Art stays bright and does not capture shop input")
	check(view.stock.find_children("buy_slot_*","Button",true,false).size() == 9,"Nine purchase slots")
	var seen := []
	for i in 9:
		var slot: Dictionary = Game.black_market_state().slots[i]
		check(Game.card_catalog[slot.cardId].rarity != "C","No C merchandise %d" % i)
		var b: Button = view.stock.get_node("buy_slot_%d" % i)
		check(b.position.y == 440 if i < 5 else b.position.y == 760,"Two purchase rows %d" % i)
		check(b.get_rect().end.x <= 1394,"Slot stays within canvas %d" % i)
		seen.append(slot.cardId)
	check(seen.size() == 9,"Nine card IDs accessible")
	var original_credits: int = Game.state.credits
	view.open_purchase(0)
	await settle()
	check(is_instance_valid(view.modal),"Purchase opens confirmation")
	check(Game.state.credits == original_credits,"Opening confirmation does not buy")
	for b in view.stock.find_children("*","Button",true,false):
		check(b.disabled and b.focus_mode == Control.FOCUS_NONE,"Stock suspended under modal")
	check(view.modal.get_node("cancel_trade").has_focus(),"Cancel initially focused")
	for i in 5:
		await key(KEY_TAB)
		check(view.modal.is_ancestor_of(get_viewport().gui_get_focus_owner()),"Tab contained inside modal")
	await key(KEY_F1)
	check(not is_instance_valid(app.debug_panel),"F1 cannot overlap the trade modal")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(view.modal) and Game.page == "place","Esc dismisses modal without leaving shop")
	check(Game.state.credits == original_credits,"Esc leaves credits untouched")
	var bought: String = Game.black_market_state().slots[0].cardId
	var price: int = Game.black_market_state().slots[0].price
	view.open_purchase(0)
	view.modal.get_node("confirm_trade").pressed.emit()
	await settle()
	check(Game.state.credits == original_credits-price,"Confirm charges visible price")
	check(bought in Game.state.deck and Game.black_market_state().slots[0].sold,"Confirmed card added and slot sold")
	check(view.stock.get_node("buy_slot_0").disabled,"Sold slot disabled immediately")
	check(view.credits_label.text == str(Game.state.credits),"Shared HUD updates immediately")
	view.open_purchase(0)
	check(not is_instance_valid(view.modal),"Sold card cannot reopen confirmation")
	view.open_sell_picker()
	await settle()
	check(is_instance_valid(view.modal.get_node_or_null("sell_scroll")),"Sell picker contains scrolling real deck")
	var starting: String = Game.player_definition().startingDeck[0]
	var before_count: int = Game.owned_card_counts()[starting]
	var selling_credits: int = Game.state.credits
	var pick: Button = view.modal.find_child("sell_pick_"+starting,true,false)
	check(pick != null and not pick.disabled,"Starting card eligible to sell")
	pick.pressed.emit()
	await settle()
	check(is_instance_valid(view.modal.get_node_or_null("confirm_trade")),"Choosing owned card opens sell confirmation")
	check(int(Game.owned_card_counts()[starting]) == before_count,"Choosing does not remove card")
	view.modal.get_node("confirm_trade").pressed.emit()
	await settle()
	check(Game.owned_card_counts().get(starting,0) == before_count-1,"Sale removes exactly one real starting card")
	check(Game.state.credits == selling_credits+Game.market_sell_price(starting),"Sale grants quoted credits")
	check(view.stock.get_node("sell_card").disabled,"Sale area locks until restock")
	view.open_sell_picker()
	check(not is_instance_valid(view.modal),"Used sale cannot reopen picker")
	Game.apply_actions([{"op":"advanceDay","days":3}])
	Game.checkpoint()
	await settle()
	view = app.view
	check(Game.black_market_state().restockDay == 4,"Day four refresh happens before shop reopens")
	check(not view.stock.get_node("sell_card").disabled,"Restock reopens sale area")
	for i in 9: check(not Game.black_market_state().slots[i].sold,"Restock resets purchased and unpurchased slots")
	Game.state.credits = 0
	view.refresh_stock()
	for i in 9: check(view.stock.get_node("buy_slot_%d" % i).disabled,"Insufficient credits visibly disables purchase")
	await key(KEY_ESCAPE)
	check(Game.page == "map","Esc leaves shop for map")
	Game.visit("bar")
	await settle()
	check(app.view.get_script().resource_path.ends_with("place.gd"),"Other locations keep normal page")
	remove_child(app)
	app.queue_free()
	await settle()
	var result := {"checks":checks,"failures":failures,"rendered":false,"physicalInput":false}
	var file := FileAccess.open(OUT+"ui-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("MARKET UI: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
