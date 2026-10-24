extends Node
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("AUDIO WORKBENCH: "+message)

func _ready() -> void:
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(2))
	var bench := preload("res://enemy_asset_pipeline/workbench.tscn").instantiate()
	add_child(bench)
	while bench.rebuilding: await get_tree().process_frame
	await get_tree().process_frame
	check(bench.audio_bank.entries.size() >= 76,"formal F6 workbench discovers every candidate")
	check(bench.audio_hooks.view == bench.view,"original combat workbench receives candidate feedback")
	var original_state: Dictionary = Game.state.duplicate(true)
	var original_model: Dictionary = bench.view.model.snapshot()
	var original_revision: int = Game.revision
	bench.open_audio_lab()
	while not is_instance_valid(bench.audio_lab.view) or bench.audio_lab.route_busy: await get_tree().process_frame
	check(bench.process_mode == Node.PROCESS_MODE_DISABLED,"background workbench input is paused during scene simulation")
	check(Game.state.activeEventId == "E01" and not Game.training_mode,"real dialogue fixture replaces only temporary session state")
	await bench.audio_lab.open_scenario("market")
	var lab: Control = bench.audio_lab
	var price: int = Game.black_market_state().slots[0].price
	check(Game.buy_market_card(0,Game.revision),"real trade succeeds inside the workbench lab")
	check(Game.state.credits == 2000-price,"trade changes only fixture credits")
	await lab.close_preview()
	await get_tree().process_frame
	check(bench.audio_lab == null and bench.process_mode != Node.PROCESS_MODE_DISABLED,"closing returns to the usable original workbench")
	check(Game.state == original_state and Game.revision == original_revision,"workbench state and revision restore exactly")
	check(bench.view.model.snapshot() == original_model,"underlying combat model remains unchanged")
	check(bench.audio_hooks.view == bench.view,"combat audio observer reattaches after close")
	check(bench.view.card_aim_started.get_connections().size() == 1,"returning does not duplicate card audio connections")
	check(not Game.save_enabled and Game.training_mode,"workbench save isolation and training mode restore")
	bench.open_audio_lab()
	while not is_instance_valid(bench.audio_lab.view) or bench.audio_lab.route_busy: await get_tree().process_frame
	bench.profiles[bench.selected_place]["audio_test_dirty"] = true
	await bench.request_close()
	check(bench.audio_lab == null,"window-close routing first restores the lab session")
	check(bench.close_dialog.visible,"original dirty-map confirmation remains usable after leaving the lab")
	check(Game.state == original_state,"window-close routing also preserves original workbench state")
	bench.close_dialog.hide()
	await preload("res://scripts/combat/audio_cleanup.gd").release(bench,get_tree())
	bench.free()
	print("AUDIO_WORKBENCH_TESTS checks=%d failures=%d" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
