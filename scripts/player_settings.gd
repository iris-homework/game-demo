extends Node
## Player preferences are independent of adventure checkpoints.
signal status_changed(success: bool)

const DEFAULT_BINDINGS := {
	"advance": KEY_SPACE, "end_turn": KEY_E, "technology": KEY_Q,
	"draw_pile": KEY_D, "discard_pile": KEY_F,
	"hand_1": KEY_1, "hand_2": KEY_2, "hand_3": KEY_3, "hand_4": KEY_4,
	"hand_5": KEY_5, "hand_6": KEY_6, "hand_7": KEY_7, "hand_8": KEY_8,
	"hand_9": KEY_9, "hand_10": KEY_0,
}
const ACTION_LABELS := {
	"advance": "继续对白", "end_turn": "结束回合", "technology": "打开战斗科技",
	"draw_pile": "查看抽牌堆", "discard_pile": "查看弃牌堆",
}
var settings_path := "user://settings.cfg"
var master_volume := 1.0
var sfx_volume := 1.0
var sfx_enabled := true
var bindings: Dictionary = DEFAULT_BINDINGS.duplicate()
var pending_save := false
var retry_seconds := 0.0

func _ready() -> void:
	_ensure_audio_bus()
	reload_settings()

func _process(delta: float) -> void:
	if not pending_save: return
	retry_seconds += delta
	if retry_seconds >= 2.0: _save()

func _ensure_audio_bus() -> void:
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, "SFX")
		AudioServer.set_bus_send(index, "Master")

func _volume_value(value: Variant) -> float:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)): return 1.0
	return clampf(float(value), 0.0, 1.0)

func reload_settings() -> void:
	var config := ConfigFile.new()
	master_volume = 1.0
	sfx_volume = 1.0
	sfx_enabled = true
	bindings = DEFAULT_BINDINGS.duplicate()
	pending_save = false
	if config.load(settings_path) == OK:
		master_volume = _volume_value(config.get_value("audio", "master_volume", 1.0))
		sfx_volume = _volume_value(config.get_value("audio", "sfx_volume", 1.0))
		var enabled: Variant = config.get_value("audio", "sfx_enabled", true)
		sfx_enabled = enabled if typeof(enabled) == TYPE_BOOL else true
		# Validate the complete candidate map before accepting it (supports key swaps).
		var candidate := DEFAULT_BINDINGS.duplicate()
		for action in candidate:
			var code: Variant = config.get_value("keys", action, candidate[action])
			if typeof(code) == TYPE_INT and _allowed_key(code): candidate[action] = code
		for action in candidate:
			if not _conflict(action, candidate[action], candidate).is_empty():
				candidate = DEFAULT_BINDINGS.duplicate()
				break
		bindings = candidate
	_apply_audio()

func _apply_audio() -> void:
	_ensure_audio_bus()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.0)
	var index := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_mute(index, not sfx_enabled or sfx_volume <= 0.0)

func _save() -> bool:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "sfx_enabled", sfx_enabled)
	for action in bindings: config.set_value("keys", action, bindings[action])
	var temporary := settings_path + ".tmp"
	var result := config.save(temporary)
	if result == OK:
		result = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(settings_path))
	pending_save = result != OK
	retry_seconds = 0.0
	status_changed.emit(not pending_save)
	return not pending_save

func set_master_volume(value: float) -> bool:
	master_volume = _volume_value(value)
	_apply_audio()
	return _save()

func set_sfx_volume(value: float) -> bool:
	sfx_volume = _volume_value(value)
	_apply_audio()
	return _save()

func set_sfx_enabled(value: bool) -> bool:
	sfx_enabled = value
	_apply_audio()
	return _save()

func action_label(action: String) -> String:
	return ACTION_LABELS.get(action, "选择第%s张手牌" % action.trim_prefix("hand_"))

func key_label(action: String) -> String:
	var code := int(bindings.get(action, 0))
	if action == "advance" and code == KEY_SPACE: return "Space / Enter"
	return OS.get_keycode_string(code)

func _allowed_key(code: int) -> bool:
	return code == KEY_SPACE or (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9) or code in [KEY_F2, KEY_F3, KEY_F4, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12]

func _conflict(action: String, code: int, mapping: Dictionary) -> String:
	if action == "advance": return ""
	for other in mapping:
		if other != action and other != "advance" and mapping[other] == code: return action_label(other)
	return ""

func bind_key(action: String, code: int) -> String:
	if not bindings.has(action): return "未知操作"
	if not _allowed_key(code): return "请选择字母、数字、空格或 F2–F4 / F8–F12。"
	var conflict := _conflict(action, code, bindings)
	if not conflict.is_empty(): return "此键已用于“%s”，请先修改该操作。" % conflict
	bindings[action] = code
	_save()
	return ""

func matches(event: InputEvent, action: String) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo: return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed: return false
	var code := int(bindings.get(action, 0))
	if code == 0: return false
	if event.keycode == code: return true
	if action == "advance" and code == KEY_SPACE: return event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if action.begins_with("hand_") and code == DEFAULT_BINDINGS.get(action):
		var keypad := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9, KEY_KP_0]
		return event.keycode == keypad[int(action.trim_prefix("hand_")) - 1]
	return false

func reset_defaults() -> bool:
	master_volume = 1.0
	sfx_volume = 1.0
	sfx_enabled = true
	bindings = DEFAULT_BINDINGS.duplicate()
	_apply_audio()
	return _save()
