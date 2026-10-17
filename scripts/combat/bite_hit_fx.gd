extends Node2D
## Authored transparent bite imprint. Presentation only; it never applies damage.
const TEXTURE := preload("res://assets/combat_test/fish_bite_hit_fx.png")
const HOLD_TIME := 0.095
const FADE_TIME := 0.18
var blocked := false
var elapsed := 0.0
var sprite := Sprite2D.new()

func _ready() -> void:
	z_index = 9
	add_to_group("bite_hit_fx")
	sprite.texture = TEXTURE
	sprite.scale = Vector2.ONE*(105.0/TEXTURE.get_width())
	if blocked: sprite.modulate = Color(0.55,0.85,1.0,0.85)
	add_child(sprite)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= HOLD_TIME+FADE_TIME:
		queue_free()
		return
	var progress := clampf((elapsed-HOLD_TIME)/FADE_TIME,0,1)
	sprite.scale = Vector2.ONE*(105.0/TEXTURE.get_width())*lerpf(1.0,1.12,progress)
	modulate.a = 1.0-progress
