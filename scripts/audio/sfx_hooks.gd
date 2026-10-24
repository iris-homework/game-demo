extends Node
## Shared presentation observer. Never changes models, pages, or saves.
var ui_root: Node
var bank: Node
var view: Control
var cards: Array[WeakRef] = []
var watched: Dictionary = {}
var previous: Dictionary = {}
var selected_uid := ""
var revealed := 0
var dialogue_label: Label
var enabled := true
var observe_choices := true
var connections: Array[Dictionary] = []
var muted_combat_audio: WeakRef
var snap_was_muted := false

func _ready() -> void:
	get_tree().node_added.connect(_node_added)
	Game.status_changed.connect(_state_changed)

func attach(value: Control) -> void:
	_restore_return_audio()
	for item in connections:
		var source: Object = item.source.get_ref()
		if is_instance_valid(source) and source.is_connected(item.signal_name,item.callback):
			source.disconnect(item.signal_name,item.callback)
	connections.clear()
	view = value
	cards.clear()
	watched.clear()
	selected_uid = ""
	revealed = 0
	dialogue_label = null
	previous = _summary()
	if not is_instance_valid(view): return
	if _is_battle():
		var audio: Node = view.stage.combat_audio
		muted_combat_audio = weakref(audio)
		snap_was_muted = "snap" in audio.muted_cues
		if not snap_was_muted: audio.muted_cues.append("snap")
	if view.get_script().resource_path == "res://scripts/dialogue.gd":
		dialogue_label = view.text_label
		_connect(view.advance_requested,_cue.bind("dialogue_advance"))
		if observe_choices: _connect(view.choice_confirmed,_cue.bind("ui_click"))
	if view.has_signal("card_aim_started"):
		_connect(view.card_aim_started,func(_uid: String): _cue("card_select"))
		_connect(view.card_aim_cancelled,_cue.bind("card_deselect"))
		_connect(view.card_played,func(_uid: String): _cue("card_play"))
	_watch(ui_root if is_instance_valid(ui_root) else view)

func _exit_tree() -> void:
	_restore_return_audio()

func _restore_return_audio() -> void:
	if muted_combat_audio == null: return
	var audio: Node = muted_combat_audio.get_ref()
	if is_instance_valid(audio) and not snap_was_muted:
		audio.muted_cues.erase("snap")
	muted_combat_audio = null

func _connect(source: Signal, callback: Callable) -> void:
	source.connect(callback)
	connections.append({"source":weakref(source.get_object()),"signal_name":source.get_name(),"callback":callback})

func _node_added(node: Node) -> void:
	_register_deferred.call_deferred(weakref(node))

func _register_deferred(reference: WeakRef) -> void:
	var node: Node = reference.get_ref()
	if not is_instance_valid(node) or not is_instance_valid(view): return
	if node == view or view.is_ancestor_of(node) or (is_instance_valid(ui_root) and (node == ui_root or ui_root.is_ancestor_of(node))): _watch(node)

func _watch(node: Node) -> void:
	if watched.has(node.get_instance_id()): return
	watched[node.get_instance_id()] = true
	if node is CombatCard:
		cards.append(weakref(node))
		node.set_meta("audio_lab_hovered", false)
	elif node is BaseButton and not node.get_parent() is CombatCard:
		_connect(node.pressed,_button_pressed.bind(weakref(node)))
	var script: Script = node.get_script()
	if script != null:
		match script.resource_path:
			"res://scripts/combat/draw_fx.gd": _connect(node.departed,_cue.bind("card_draw"))
			"res://scripts/combat/discard_fx.gd": _cue("card_discard")
			"res://scripts/combat/exhaust_fx.gd": _cue("card_exhaust")
			"res://scripts/combat/shuffle_fx.gd": _cue("card_shuffle")
	for child in node.get_children(): _watch(child)

func _cue(cue: String) -> void:
	if enabled and is_instance_valid(bank): bank.play_cue(cue)

func _button_pressed(reference: WeakRef) -> void:
	var button: BaseButton = reference.get_ref()
	if not is_instance_valid(button) or button.disabled: return
	if is_instance_valid(dialogue_label) and button in view.choice_buttons: return
	var caption := str(button.get("text"))
	if _is_battle() and button == view.end_button and caption.begins_with("结束回合"): return
	var cancel := str(button.name).begins_with("close_") or str(button.name) == "cancel_trade" or "返回" in caption or "取消" in caption or "离开" in caption
	_cue("ui_cancel" if cancel else "ui_click")

func _dialogue_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_cue("dialogue_advance")

func _process(_delta: float) -> void:
	if not is_instance_valid(view): return
	if is_instance_valid(dialogue_label):
		var count := dialogue_label.visible_characters
		if count >= 0 and count > revealed and count <= dialogue_label.text.length():
			var character := dialogue_label.text.substr(count - 1, 1)
			if not character in [" ", "\n", "，", "。", "！", "？", "、", "…"]:
				if enabled and is_instance_valid(bank): bank.play_dialogue(_dialogue_role())
		revealed = count
	for reference in cards:
		var card: Node = reference.get_ref()
		if not is_instance_valid(card): continue
		var was_hovered := bool(card.get_meta("audio_lab_hovered", false))
		if card.hovered and not was_hovered: _cue("card_hover")
		card.set_meta("audio_lab_hovered", card.hovered)
	if _is_battle() and not view.has_signal("card_aim_started"):
		var current: String = view.selected_uid
		if current != selected_uid:
			if not current.is_empty(): _cue("card_select")
			elif not selected_uid.is_empty():
				_cue("card_deselect" if selected_uid in view.model.hand else "card_play")
			selected_uid = current
	_state_changed()

func _dialogue_role() -> String:
	if not is_instance_valid(view) or not is_instance_valid(dialogue_label): return "narrator"
	var speaker := Game.resolve_character_id(str(view.node.get("speakerId", "")))
	if speaker.is_empty(): return "narrator"
	return "noren" if speaker == "noren" else "npc"

func _is_battle() -> bool:
	return is_instance_valid(view) and view.get_script().resource_path in ["res://scripts/battle.gd", "res://tests/combat/workbench/battle_background_preview_view.gd"]

func _summary() -> Dictionary:
	var combat: Dictionary = Game.state.get("combat", {})
	var noren: Dictionary = combat.get("norenState", {})
	return {"credits":Game.state.get("credits", 0), "hp":Game.state.get("currentHp", 0),
		"owned":Game.state.get("ownedCyberwareIds", []).size(), "deck":Game.state.get("deck", []).size(),
		"reward":Game.state.get("battleReward", {}).get("status", ""),
		"turn":combat.get("turn", 0), "stance":noren.get("stance", ""),
		"ammo":noren.get("ammo", 0), "energy":noren.get("energy", 0), "block":noren.get("block", 0),
		"parry":noren.get("parry", 0), "cooldowns":combat.get("cyberwareCooldowns", {}).duplicate()}

func _state_changed() -> void:
	if not is_instance_valid(view): return
	var next := _summary()
	if previous.is_empty():
		previous = next
		return
	if Game.page == "place" and next.credits != previous.credits: _cue("trade_success")
	elif next.credits > previous.credits: _cue("reward")
	if next.reward == "claimed" and next.reward != previous.reward: _cue("reward")
	if next.hp > previous.hp: _cue("heal")
	if _is_battle():
		if next.turn > previous.turn:
			_cue("turn_start")
			# New-round resets are not card or technology effects.
			previous = next
			return
		if next.stance != previous.stance: _cue("stance")
		if next.ammo > previous.ammo: _cue("ammo")
		if next.energy > previous.energy: _cue("energy")
		if next.block > previous.block: _cue("block")
		if next.parry < previous.parry: _cue("parry")
		for id in next.cooldowns:
			if int(next.cooldowns[id]) > int(previous.cooldowns.get(id, 0)):
				_cue("technology")
				break
	previous = next
