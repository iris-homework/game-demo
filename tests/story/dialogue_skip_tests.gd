extends Node
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = "user://dialogue_skip_test.json"
	Game.meta_path = "user://dialogue_skip_meta.json"
	# Compare every authored dialogue starting point with ordinary Continue.
	for event_id in Game.events:
		for node_id in Game.events[event_id].nodes:
			var node: Dictionary = Game.events[event_id].nodes[node_id]
			if node.get("type", "dialogue") in ["battle", "finish"]: continue
			Game.state = Game.initial_state()
			Game.state.activeEventId = event_id
			Game.state.currentPlaceId = Game.events[event_id].placeId
			Game.state.targetId = "richard"
			Game.enter_node(node_id)
			var initial: Dictionary = Game.state.duplicate(true)
			var refresh_rng_state := Game.event_refresh_rng.state
			# Compare the two routes with identical deck/reward and refresh draws.
			seed(9341)
			var guard := 0
			while Game.state.currentScene == "dialogue" and Game.node_data().get("choices", []).is_empty() and Game.node_data().has("next") and guard < 100:
				Game.advance(Game.revision)
				guard += 1
			check(guard < 100, "Authored path terminates: " + event_id + ":" + node_id)
			var expected: Dictionary = Game.state.duplicate(true)
			Game.state = initial
			Game.page = "dialogue"
			Game.event_refresh_rng.state = refresh_rng_state
			seed(9341)
			Game.skip_dialogue(Game.revision)
			check(Game.state == expected, "Skip matches Continue: " + event_id + ":" + node_id)
	Game.new_game()
	var rev := Game.revision
	var initial: Dictionary = Game.state.duplicate(true)
	Game.skip_dialogue(rev - 1)
	check(Game.state == initial, "Stale request rejected")
	Game.transition_locked = true
	Game.skip_dialogue(rev)
	check(Game.state == initial, "Transition lock respected")
	Game.transition_locked = false
	Game.battle_busy = true
	Game.skip_dialogue(rev)
	check(Game.state == initial, "Battle lock respected")
	Game.battle_busy = false
	Game.menu()
	Game.skip_dialogue(Game.revision)
	check(Game.state == initial, "Hidden dialogue does not skip from menu")
	Game.resume()
	Game.skip_dialogue(Game.revision)
	check(Game.state.activeNodeId == "contract" and Game.state.choiceHistory.is_empty(), "Opening stops at contract without choosing")
	initial = Game.state.duplicate(true)
	Game.skip_dialogue(rev)
	Game.skip_dialogue(Game.revision)
	check(Game.state == initial, "Double click and choice-node skip are harmless")
	Game.choose(2, Game.revision)
	Game.skip_dialogue(Game.revision)
	check(Game.state.currentScene == "result" and "E01" in Game.state.completedEventIds, "Selected branch finishes normally")
	Game.claim_rewards(Game.revision)
	preload("res://tests/fixtures/payment_choice.gd").install(Game)
	Game.state.refreshedEventIds = ["QA_PAYMENT"]
	Game.start_event("QA_PAYMENT")
	Game.skip_dialogue(Game.revision)
	check(Game.state.activeNodeId == "payment" and Game.state.credits == int(Game.config.initialCredits), "Payment choice preserved")
	check(not Game.choose(0, Game.revision), "Insufficient funds still reject payment")
	Game.choose(1, Game.revision)
	Game.skip_dialogue(Game.revision)
	check(Game.state.currentScene == "battle", "Refusal starts battle")
	Game.battle_exit("win", Game.revision)
	Game.skip_dialogue(Game.revision)
	check(Game.state.currentScene == "result" and Game.state.credits == int(Game.config.initialCredits) and Game.has_battle_reward() and Game.reward_credits_status() == "pending", "Victory skip offers unpaid reward once")
	initial = Game.state.duplicate(true)
	Game.skip_dialogue(Game.revision)
	check(Game.state == initial, "Result skip cannot duplicate reward")
	# Malformed cycles must not hang; fixtures are only in memory.
	Game.events["E01"].nodes["skip_cycle"] = {"next":"skip_cycle"}
	Game.state = Game.initial_state()
	Game.state.activeEventId = "E01"
	Game.enter_node("skip_cycle")
	rev = Game.revision
	Game.skip_dialogue(rev)
	check(Game.revision == rev, "Cycle stops without repeating node")
	Game.events["E01"].nodes.erase("skip_cycle")
	print("DIALOGUE SKIP: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
