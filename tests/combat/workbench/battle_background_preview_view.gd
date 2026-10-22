extends "res://scripts/battle.gd"
## Test-only battle presentation. Story exits, saving and permanent card edits stay outside.
signal preview_finished(result: String)

const TEST_HAND_LIMIT := 20
const TEST_UID_PREFIX := "preview_"
const PREVIEW_ACTIONS := ["move", "hit", "slash", "pierce", "shoot", "laser", "bite", "block", "damaged", "attack"]
const PREVIEW_ATTACK_ACTIONS := ["hit", "slash", "pierce", "shoot", "laser", "bite", "attack"]

var preview_busy := false
var preview_paused := false
var preview_speed := 1.0
var _preview_finished := false
var _next_preview_uid := 1
var _time_scale_owned := false
var _previous_time_scale := 1.0


func enter(params: Dictionary) -> void:
	super.enter(params)
	# The shared battle view adds its top tag after chrome(); rename it for the test UI.
	for child in get_children():
		if child is Label and child.text.begins_with("诺伦 / "):
			child.text = "noren / " + child.text.trim_prefix("诺伦 / ")


func chrome(section: String, show_days: bool = true) -> void:
	super.chrome(section, show_days)
	# The shared status bar prints the player's Chinese name; this test view uses
	# the assets/combat_test folder name for every character label.
	for child in get_children():
		if child is Label and child.text.begins_with("诺伦 / "):
			child.text = "noren / " + child.text.trim_prefix("诺伦 / ")
	# The production chrome exits training and restores the adventure. A workbench
	# owns its lifetime, so only the parent may close or rebuild this battle view.
	for child in get_children():
		if child is Button and child.text in ["退出演练", "菜单"]:
			for connection in child.pressed.get_connections().duplicate():
				var callback: Callable = connection.callable
				if callback.is_valid(): child.pressed.disconnect(callback)
			child.text = "关闭测试台"
			child.pressed.connect(_request_parent_close)


func finish(result: String) -> void:
	if _preview_finished: return
	_preview_finished = true
	preview_busy = false
	preview_paused = false
	_restore_time_scale()
	cancel_selection()
	if is_instance_valid(aim): aim.visible = false
	_disable_test_controls()
	Game.battle_busy = false
	preview_finished.emit(result)


func set_busy(value: bool) -> void:
	super.set_busy(value)
	# A late animation callback must not make the finished sample playable again.
	if _preview_finished: _disable_test_controls()


func show_debug_results() -> void:
	if not _can_edit_model() or preview_busy: return
	cancel_selection()
	var parent_node := get_parent()
	if is_instance_valid(parent_node) and parent_node.has_method("rebuild"):
		parent_node.call("rebuild")


func _input(event: InputEvent) -> void:
	# Input is global in Godot. Tool and modal geometry must never reach battle
	# selection or aiming while the parent still receives its own GUI events.
	if _parent_modal_open() or _parent_tools_locked(): return
	if event is InputEventMouse and _parent_tool_contains(event.position): return
	if event is InputEventKey and _preview_keyboard_blocked(): return
	super._input(event)


func _unhandled_key_input(event: InputEvent) -> void:
	if _parent_modal_open() or _parent_tools_locked(): return
	if _preview_keyboard_blocked(): return
	super._unhandled_key_input(event)


func get_actor(index: int) -> Node2D:
	if not is_instance_valid(stage): return null
	if index == 0: return stage.player as Node2D
	var enemy_index := index - 1
	if enemy_index < 0 or enemy_index >= stage.enemies.size(): return null
	return stage.enemies[enemy_index] as Node2D


func available_poses(index: int) -> Array[String]:
	var result: Array[String] = []
	var actor := get_actor(index)
	if actor == null: return result
	for key in actor.poses:
		if not key is String: continue
		var texture = actor.poses[key]
		var calibration = actor.calibrations.get(key, [])
		if texture is Texture2D and texture.get_width() > 0 and texture.get_height() > 0 \
				and calibration is Array and calibration.size() == 2:
			result.append(key)
	result.sort()
	return result


func set_preview_pose(index: int, pose: String) -> bool:
	if not _can_edit_model(): return false
	var actor := get_actor(index)
	if actor == null or not pose in available_poses(index): return false
	actor.set_pose(pose)
	return true


func set_preview_stance(stance: String) -> bool:
	if not _can_edit_model() or stance not in ["melee", "ranged"]: return false
	var player := get_actor(0)
	if player == null: return false
	# Deliberately bypass change_stance(): switching presentation must not draw
	# cards, apply discounts, spend ammo or resolve a card effect.
	model.stance = stance
	player.set_combat_stance(stance)
	refresh_resources()
	refresh_card_previews()
	_commit_unsaved()
	return true


func preview_action(index: int, action: String, target: int = -1) -> bool:
	if not _can_start_preview_action(): return false
	var normalized := action.to_lower()
	if not normalized in PREVIEW_ACTIONS: return false
	var actor := get_actor(index)
	if actor == null or not actor.alive or not _actor_has_hp(index): return false
	var resolved_target := target
	var resolved_style := ""
	if normalized in PREVIEW_ATTACK_ACTIONS:
		resolved_style = _resolved_preview_style(index, normalized)
		if resolved_style.is_empty() or not _preview_style_supported(index, resolved_style): return false
		if resolved_target < 0: resolved_target = _default_attack_target(index)
		if not _valid_attack_target(index, resolved_target): return false

	_previous_time_scale = Engine.time_scale
	_time_scale_owned = true
	Engine.time_scale = _previous_time_scale * preview_speed
	preview_busy = true
	set_busy(true)
	await _perform_preview_action(index, normalized, resolved_target, resolved_style)
	if is_instance_valid(stage): reset_preview_poses()
	_end_preview_action()
	return true


func pause_preview(value: bool) -> void:
	if value == preview_paused: return
	if value:
		if not _time_scale_owned:
			_previous_time_scale = Engine.time_scale
			_time_scale_owned = true
		Engine.time_scale = 0.0
		preview_paused = true
	else:
		preview_paused = false
		Engine.time_scale = _previous_time_scale * preview_speed


func reset_preview_poses() -> void:
	if not is_instance_valid(stage): return
	if stage.camera_tween and stage.camera_tween.is_running(): stage.camera_tween.kill()
	stage.active_attacker = null
	stage.active_defender = null
	stage.shake = Vector2.ZERO
	stage.shake_time = 0.0
	stage.shake_duration = 0.0
	stage.impact_zoom = 1.0
	stage.zoom = 1.0
	stage.focus_x = 720.0
	stage.focus_y = stage.floor_y - 35.0
	var player := stage.player as Node2D
	if is_instance_valid(player):
		player.position = player.home
		player.alive = int(model.player_hp) > 0
		player.visible = player.alive
		player.modulate = Color.WHITE
		player.sprite.modulate = Color.WHITE
		player.set_combat_stance(model.stance if model.is_noren() else "melee")
	for i in stage.enemies.size():
		var actor: Node2D = stage.enemies[i]
		var hp := int(model.enemies[i].get("hp", 0))
		actor.position = actor.home
		actor.alive = hp > 0
		actor.visible = actor.alive
		actor.modulate = Color.WHITE
		actor.sprite.modulate = Color.WHITE
		actor.set_pose("idle")
	stage.set_phase("idle")
	stage.call("_update_camera")


func replace_test_hand(ids: Array) -> bool:
	if not _can_edit_model() or ids.size() > TEST_HAND_LIMIT: return false
	var card_ids: Array[String] = []
	for raw_id in ids:
		if not raw_id is String: return false
		var card_id := str(raw_id)
		if not _card_definition_exists(card_id): return false
		card_ids.append(card_id)
	for uid in model.hand.duplicate(): _purge_instance(str(uid))
	model.hand.clear()
	for card_id in card_ids:
		var uid := _new_test_uid()
		model.instances[uid] = card_id
		model.hand.append(uid)
	_rebuild_hand_views()
	_commit_unsaved()
	return true


func add_test_card(id: String) -> bool:
	if not _can_edit_model() or model.hand.size() >= TEST_HAND_LIMIT: return false
	if not _card_definition_exists(id): return false
	var uid := _new_test_uid()
	model.instances[uid] = id
	model.hand.append(uid)
	_rebuild_hand_views()
	_commit_unsaved()
	return true


func remove_test_card(uid: String) -> bool:
	if not _can_edit_model() or not uid in model.hand: return false
	_purge_instance(uid)
	_rebuild_hand_views()
	_commit_unsaved()
	return true


func preview_energy(amount: int) -> bool:
	if not _can_edit_model() or amount < 0: return false
	model.energy = amount
	_commit_unsaved()
	return true


func refill_test_resources() -> bool:
	if not _can_edit_model(): return false
	model.energy = maxi(1, int(model.profile.get("energyPerTurn", 3)))
	model.ammo = maxi(0, int(model.profile.get("ammoCap", 10)))
	_commit_unsaved()
	return true


func _perform_preview_action(index: int, action: String, target: int, style: String) -> void:
	var actor := get_actor(index)
	if actor == null: return
	match action:
		"hit", "slash", "pierce", "shoot", "laser", "bite", "attack":
			await _perform_preview_attack(index, actor, target, style)
		"move":
			actor.set_pose("move")
			await _wait_for_preview(0.04)
			var direction := -1.0 if actor.position.x >= 720.0 else 1.0
			var duration: float = stage.travel_duration(actor,96.0) if not actor.pipeline_motion.is_empty() else 0.26
			await stage.move_actor(actor, actor.position + Vector2(direction * 96.0, 0.0), duration)
			await _wait_for_preview(0.10)
			await stage.return_home()
		"block", "damaged":
			actor.set_pose(action)
			await _wait_for_preview(maxf(0.45,actor.pipeline_pose_remaining()))


func _perform_preview_attack(index: int, actor: Node2D, target: int, style: String) -> void:
	var defender := get_actor(target)
	if defender == null: return
	# Synthetic hits drive only the existing presentation path. They never enter
	# CombatModel, so HP, block, statuses, energy and ammo remain untouched.
	var hits: Array = [{"target":target, "damage":0, "blocked":0, "hpAfter":_actor_hp(target), "killed":false}]
	var no_effect := func(_hit: Dictionary, _hit_index: int) -> void: pass
	var saved_override: String = str(actor.attack_style_override)
	# Noren has no authored override; clearing it here still guarantees that the
	# workbench's selected slash/pierce/shoot survives future profile changes.
	if index == 0 or actor.pipeline_attacks.has(style): actor.attack_style_override = ""
	await stage.attack(actor, defender, style, hits, no_effect)
	if is_instance_valid(actor): actor.attack_style_override = saved_override
	await _wait_for_preview(0.06)
	await stage.return_home()


func _resolved_preview_style(index: int, action: String) -> String:
	if action != "attack": return action
	if index == 0:
		if model.stance == "ranged" and "shoot" in available_poses(index): return "shoot"
		if preview_attack_style in ["slash", "pierce"] and preview_attack_style in available_poses(index):
			return preview_attack_style
		return "slash" if "slash" in available_poses(index) else "pierce"
	var actor := get_actor(index)
	if actor != null and not actor.attack_style_override.is_empty():
		return actor.attack_style_override
	for candidate in ["hit", "pierce", "slash", "shoot", "bite", "laser"]:
		if _preview_style_supported(index, candidate): return candidate
	return ""


func _preview_style_supported(index: int, style: String) -> bool:
	if not style in ["hit", "slash", "pierce", "shoot", "laser", "bite"]: return false
	var actor := get_actor(index)
	if actor == null: return false
	if actor.pipeline_attacks.has(style): return true
	if not style in available_poses(index): return false
	# Enemies only advertise the action their own visual profile can perform.
	if index > 0:
		if not actor.attack_style_override.is_empty(): return actor.attack_style_override == style
		if style == "laser": return actor.laser_palm_width > 0.0
		if style == "bite": return actor.hit_effect_texture != null and "bite_close" in actor.poses
	return true


func _wait_for_preview(seconds: float) -> void:
	while preview_paused: await get_tree().process_frame
	await get_tree().create_timer(seconds).timeout
	while preview_paused: await get_tree().process_frame


func _end_preview_action() -> void:
	preview_busy = false
	preview_paused = false
	_restore_time_scale()
	if _preview_finished:
		Game.battle_busy = false
		_disable_test_controls()
	else:
		set_busy(false)


func _can_edit_model() -> bool:
	# Check our own busy flag first: the parent's tools_locked() includes it.
	# Consulting that parent guard after claiming the lock would deadlock us.
	if not initialized or model == null or _preview_finished or preview_busy: return false
	if Game.battle_busy or Game.transition_locked or is_instance_valid(pile_overlay): return false
	return not _parent_modal_open() and not _parent_tools_locked()


func _can_start_preview_action() -> bool:
	return _can_edit_model() and not preview_paused and model.outcome.is_empty() and model.player_hp > 0


func _actor_has_hp(index: int) -> bool:
	if model == null: return false
	if index == 0: return int(model.player_hp) > 0
	var enemy_index := index - 1
	return enemy_index >= 0 and enemy_index < model.enemies.size() \
		and int(model.enemies[enemy_index].get("hp", 0)) > 0


func _actor_hp(index: int) -> int:
	if model == null: return 0
	if index == 0: return int(model.player_hp)
	var enemy_index := index - 1
	if enemy_index < 0 or enemy_index >= model.enemies.size(): return 0
	return int(model.enemies[enemy_index].get("hp", 0))


func _default_attack_target(index: int) -> int:
	if index == 0:
		for enemy_index in model.enemies.size():
			if int(model.enemies[enemy_index].get("hp", 0)) > 0: return enemy_index + 1
		return -1
	return 0 if _actor_has_hp(0) else -1


func _valid_attack_target(index: int, target: int) -> bool:
	if target == index or not _actor_has_hp(target): return false
	var defender := get_actor(target)
	return defender != null and defender.alive


func _card_definition_exists(id: String) -> bool:
	return model != null and not id.is_empty() and model.card_catalog.get(id) is Dictionary


func _new_test_uid() -> String:
	while true:
		var uid := "%s%06d" % [TEST_UID_PREFIX, _next_preview_uid]
		_next_preview_uid += 1
		if not model.instances.has(uid) and not _uid_in_any_zone(uid): return uid
	return ""


func _uid_in_any_zone(uid: String) -> bool:
	return uid in model.draw_pile or uid in model.hand \
		or uid in model.discard_pile or uid in model.exhaust_pile


func _purge_instance(uid: String) -> void:
	model.draw_pile.erase(uid)
	model.hand.erase(uid)
	model.discard_pile.erase(uid)
	model.exhaust_pile.erase(uid)
	model.instances.erase(uid)


func _rebuild_hand_views() -> void:
	cancel_selection()
	for uid in cards.keys():
		var view = cards[uid]
		if is_instance_valid(view):
			view.set_enabled(false)
			if view.get_parent() == self: remove_child(view)
			view.queue_free()
	cards.clear()
	for i in model.hand.size():
		var uid := str(model.hand[i])
		var view := create_card(uid, i, model.hand.size(), false)
		view.visible = true
		view.set_enabled(not _preview_finished)
	arrange_hand()
	refresh_counts()
	refresh_card_previews()


func _commit_unsaved() -> void:
	# This deliberately mirrors the useful part of Game.commit_combat() while
	# omitting save_game(), so test data cannot reach a player checkpoint.
	Game.state.combat = model.snapshot()
	Game.state.currentHp = model.player_hp
	Game.revision += 1
	expected_revision = Game.revision
	refresh_cyberware()
	refresh_card_previews()
	refresh_resources()
	Game.status_changed.emit()


func _disable_test_controls() -> void:
	for view in cards.values():
		if is_instance_valid(view): view.set_enabled(false)
	if is_instance_valid(end_button): end_button.disabled = true
	if is_instance_valid(cyberware_button): cyberware_button.disabled = true
	if is_instance_valid(exhaust_button): exhaust_button.disabled = true


func _request_parent_close() -> void:
	var parent_node := get_parent()
	if is_instance_valid(parent_node) and parent_node.has_method("request_close"):
		parent_node.call("request_close")


func _parent_modal_open() -> bool:
	var parent_node := get_parent()
	return is_instance_valid(parent_node) and parent_node.has_method("modal_open") \
		and bool(parent_node.call("modal_open"))


func _parent_tools_locked() -> bool:
	var parent_node := get_parent()
	return is_instance_valid(parent_node) and parent_node.has_method("tools_locked") \
		and bool(parent_node.call("tools_locked"))


func _parent_tool_contains(point: Vector2) -> bool:
	var parent_node := get_parent()
	return is_instance_valid(parent_node) and parent_node.has_method("tool_contains") \
		and bool(parent_node.call("tool_contains", point))


func _preview_keyboard_blocked() -> bool:
	var viewport := get_viewport()
	if not is_instance_valid(viewport): return true
	if _parent_tool_contains(viewport.get_mouse_position()): return true
	# Digit selection is an unhandled-key shortcut, so a focused tool button must
	# also suppress it even when the pointer is elsewhere.
	var focus := viewport.gui_get_focus_owner()
	return is_instance_valid(focus) and focus != self and not is_ancestor_of(focus)


func _restore_time_scale() -> void:
	if not _time_scale_owned: return
	Engine.time_scale = _previous_time_scale
	_time_scale_owned = false


func _exit_tree() -> void:
	_restore_time_scale()
	if preview_busy: Game.battle_busy = false
