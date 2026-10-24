extends "res://scripts/audio/sfx_player.gd"
## Formal game audio bank for released scenes.
## The shared player owns voice management, throttling and cue playback; this
## bank only supplies preloaded streams from res://assets/audio/game so exported
## builds carry every bound clip as an explicit dependency.

const AUDIO_ROOT := "res://assets/audio/game"

const CLIPS := {
	"res://assets/audio/game/ui/ui_click_balatro_01.ogg": preload("res://assets/audio/game/ui/ui_click_balatro_01.ogg"),
	"res://assets/audio/game/ui/ui_cancel_balatro_01.ogg": preload("res://assets/audio/game/ui/ui_cancel_balatro_01.ogg"),
	"res://assets/audio/game/cards/card_hover_balatro_01.ogg": preload("res://assets/audio/game/cards/card_hover_balatro_01.ogg"),
	"res://assets/audio/game/cards/card_select_balatro_01.ogg": preload("res://assets/audio/game/cards/card_select_balatro_01.ogg"),
	"res://assets/audio/game/cards/card_deselect_balatro_01.ogg": preload("res://assets/audio/game/cards/card_deselect_balatro_01.ogg"),
	"res://assets/audio/game/cards/card_draw_balatro_01.ogg": preload("res://assets/audio/game/cards/card_draw_balatro_01.ogg"),
	"res://assets/audio/game/cards/card_crumple_balatro_01.ogg": preload("res://assets/audio/game/cards/card_crumple_balatro_01.ogg"),
	"res://assets/audio/game/cards/card_fan_balatro_02.ogg": preload("res://assets/audio/game/cards/card_fan_balatro_02.ogg"),
	"res://assets/audio/game/combat/effect_whoosh_out_balatro_02.ogg": preload("res://assets/audio/game/combat/effect_whoosh_out_balatro_02.ogg"),
	"res://assets/audio/game/dialogue/dialogue_blip_cozy_soft_01.wav": preload("res://assets/audio/game/dialogue/dialogue_blip_cozy_soft_01.wav"),
	"res://assets/audio/game/world/notice_highlight_balatro_01.ogg": preload("res://assets/audio/game/world/notice_highlight_balatro_01.ogg"),
	"res://assets/audio/game/world/credits_coin_balatro_07.ogg": preload("res://assets/audio/game/world/credits_coin_balatro_07.ogg"),
	"res://assets/audio/game/world/credits_coin_balatro_01.ogg": preload("res://assets/audio/game/world/credits_coin_balatro_01.ogg"),
	"res://assets/audio/game/cards/card_holo_apply_balatro_01.ogg": preload("res://assets/audio/game/cards/card_holo_apply_balatro_01.ogg"),
	"res://assets/audio/game/combat/effect_trigger_balatro_01.ogg": preload("res://assets/audio/game/combat/effect_trigger_balatro_01.ogg"),
	"res://assets/audio/game/cards/card_foil_apply_balatro_01.ogg": preload("res://assets/audio/game/cards/card_foil_apply_balatro_01.ogg"),
	"res://assets/audio/game/combat/effect_slice_balatro_01.ogg": preload("res://assets/audio/game/combat/effect_slice_balatro_01.ogg"),
	"res://assets/audio/game/cards/card_foil_trigger_balatro_02.ogg": preload("res://assets/audio/game/cards/card_foil_trigger_balatro_02.ogg"),
}


func _ready() -> void:
	_registered_streams = CLIPS.duplicate()
	for cue in DEFAULT_BINDINGS:
		var relative: String = DEFAULT_BINDINGS[cue]
		bindings[cue] = "" if relative.is_empty() else AUDIO_ROOT.path_join(relative)
	super._ready()

