extends Node
## Pure logic and UI structure checks; no window, pointer input or formal saves.
var checks := 0
var failures: Array[String] = []
var notices: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("CLINIC: " + message)

func reset(hp: int = 50, credits: int = 150, max_hp: int = 100) -> void:
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.state.currentHp = hp
	Game.state.maxHp = max_hp
	Game.state.credits = credits
	Game.page = "map"
	Game.transition_locked = false
	Game.battle_busy = false
	notices.clear()

func rejected(place_id: String, message: String) -> void:
	var before := JSON.stringify(Game.state)
	var revision := Game.revision
	check(not Game.heal_at(place_id), message + " rejected")
	check(before == JSON.stringify(Game.state) and revision == Game.revision, message + " preserves entire state and revision")

func verify_button(button: Button, expected_price: int, disabled: bool, context: String) -> void:
	check(button != null, context + " button exists")
	if button == null: return
	check(button.text.contains("%d 信用点" % expected_price) if expected_price > 0 else button.text.contains("免费"), context + " price displayed")
	check(button.text.contains("30%"), context + " percentage displayed")
	check(button.disabled == disabled, context + " availability displayed")
	check(button.tooltip_text.contains("最大生命值"), context + " basis explained")
	check(button.icon == DemoUI.CREDIT_ICON if expected_price > 0 else button.icon == null, context + " paid-service icon")

func verify_views(credits: int, hp: int, disabled: bool, context: String) -> void:
	reset(hp, credits)
	var map_view = load("res://scenes/map.tscn").instantiate()
	add_child(map_view)
	var content: Dictionary = map_view._card_content("clinic")
	check(content.healing_service.credits_cost == 150 and content.healing_service.can_heal != disabled, context + " map consumes shared query")
	map_view._build_detail("clinic")
	check(map_view.get_detail_button("heal_place") == null, context + " map defers healing to service page")
	check(map_view.get_detail_button("enter_place") != null, context + " clinic has direct service entry")
	remove_child(map_view)
	map_view.queue_free()
	Game.state.currentScene = "place"
	Game.state.currentPlaceId = "clinic"
	Game.page = "place"
	var place_view = load("res://scenes/place.tscn").instantiate()
	add_child(place_view)
	verify_button(place_view.find_child("heal_place", true, false), 150, disabled, context + " place")
	var hint: Label = place_view.find_child("healing_hint", true, false)
	var back: Button = place_view.find_child("return_map", true, false)
	check(hint != null and back != null and not hint.get_rect().intersects(back.get_rect()), context + " two-line service hint clears return button")
	remove_child(place_view)
	place_view.queue_free()
	await get_tree().process_frame

func verify_laboratory_views() -> void:
	reset()
	var map_view = load("res://scenes/map.tscn").instantiate()
	add_child(map_view)
	var content: Dictionary = map_view._card_content("hospital")
	check(not content.has_service and content.healing_service.is_empty(), "laboratory map query has no healing service")
	map_view._build_detail("hospital")
	check(map_view.get_detail_button("enter_place") == null, "empty nonresident laboratory has no visit action")
	check(map_view.get_detail_button("heal_place") == null, "laboratory map has no healing action")
	remove_child(map_view)
	map_view.queue_free()
	Game.state.currentScene = "place"
	Game.state.currentPlaceId = "hospital"
	Game.page = "place"
	var place_view = load("res://scenes/place.tscn").instantiate()
	add_child(place_view)
	check(place_view.find_child("heal_place", true, false) == null, "laboratory place has no healing action")
	check(place_view.find_child("healing_hint", true, false) == null, "laboratory place has no healing hint")
	check(place_view.find_child("return_map", true, false) != null, "laboratory place retains return action")
	rejected("hospital", "laboratory place treatment")
	remove_child(place_view)
	place_view.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	Game.save_enabled = false
	var evidence_dir := ProjectSettings.globalize_path("res://artifacts/qa/clinic-credits-2026-10-23/payment-test-files")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	Game.save_path = evidence_dir.path_join("checkpoint.json")
	Game.meta_path = evidence_dir.path_join("meta.json")
	Game.notice.connect(func(message: String): notices.append(message))
	reset()
	var clinic: Dictionary = Game.healing_service("clinic")
	check(clinic.credits_cost == 150 and is_equal_approx(clinic.percent, 0.3), "authored clinic price and rate")
	check(Game.healing_service("hospital").is_empty(), "laboratory has no healing service")
	var before := JSON.stringify(Game.state)
	Game.healing_service("clinic")
	check(before == JSON.stringify(Game.state), "service query is read only")
	var day: int = Game.state.currentDay
	var place: String = Game.state.currentPlaceId
	var revision := Game.revision
	check(Game.heal_at("clinic"), "exactly 150 pays for treatment")
	check(Game.state.currentHp == 80 and Game.state.credits == 0, "30 HP and 150 credits commit together")
	check(Game.revision == revision + 1 and Game.state.currentDay == day and Game.state.currentPlaceId == place, "one checkpoint preserves day and current location")
	check(notices.back().contains("150") and notices.back().contains("+30"), "success reports payment and actual healing")
	rejected("clinic", "second treatment without funds")
	check(notices.back().contains("不足"), "insufficient funds has explicit feedback")
	reset(50, 149)
	rejected("clinic", "149 credits")
	reset(50, 0)
	rejected("clinic", "zero credits")
	reset(100, 300)
	rejected("clinic", "full HP does not charge")
	check(notices.back().contains("已满"), "full HP has explicit feedback")
	reset(95, 150)
	check(Game.heal_at("clinic") and Game.state.currentHp == 100 and Game.state.credits == 0, "partial healing caps at max and costs one treatment")
	reset(50, 150, 105)
	check(Game.heal_at("clinic") and Game.state.currentHp == 82, "uses maximum HP with existing roundi rounding")
	reset(0, 300)
	check(Game.heal_at("clinic") and Game.heal_at("clinic") and Game.state.currentHp == 60 and Game.state.credits == 0, "each accepted treatment costs 150")
	reset(50, 0)
	rejected("hospital", "laboratory treatment at zero credits")
	reset(50, 300)
	rejected("hospital", "laboratory treatment with sufficient credits")
	reset(100, 300)
	rejected("hospital", "full HP laboratory treatment")
	reset()
	Game.transition_locked = true
	rejected("clinic", "transition lock")
	Game.transition_locked = false
	Game.battle_busy = true
	rejected("clinic", "battle lock")
	Game.battle_busy = false
	Game.state.currentScene = "dialogue"
	rejected("clinic", "dialogue page")
	reset()
	rejected("unknown", "unknown location")
	rejected("bar", "location without healing")
	var authored_service: Dictionary = Game.place_data("clinic").services[0]
	authored_service.creditsCost = 75
	authored_service.percent = 0.2
	check(Game.healing_service("clinic").label.contains("75") and Game.healing_service("clinic").label.contains("20%"), "query text follows configuration")
	check(Game.heal_at("clinic") and Game.state.currentHp == 70 and Game.state.credits == 75, "commit follows configuration")
	for bad_cost in [-1, 1.5, "150"]:
		authored_service.creditsCost = bad_cost
		rejected("clinic", "invalid price " + str(bad_cost))
	authored_service.creditsCost = 150
	authored_service.percent = 1.1
	rejected("clinic", "invalid healing rate")
	authored_service.percent = 0.3
	reset()
	Game.state.currentScene = "place"
	Game.page = "place"
	Game.state.currentPlaceId = "clinic"
	check(Game.heal_at("clinic"), "place route accepts treatment")
	check(Game.save_game(), "test-only save succeeds")
	Game.state = {}
	check(Game.load_game() and Game.state.currentHp == 80 and Game.state.credits == 0 and Game.state.currentPlaceId == "clinic", "paid treatment restores together")
	await verify_views(150, 50, false, "affordable")
	await verify_views(149, 50, true, "insufficient")
	await verify_views(300, 100, true, "full HP")
	await verify_laboratory_views()
	var report := {"checks":checks, "failures":failures, "scope":"headless logic and UI structure; no visual or physical-input acceptance"}
	var file := FileAccess.open(evidence_dir.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CLINIC PAYMENT: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
