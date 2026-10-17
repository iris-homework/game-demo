extends Node2D
## Authored transparent bite imprint. Presentation only; it never applies damage.
var texture: Texture2D
const HOLD_TIME := 0.095
const FADE_TIME := 0.18
var blocked := false
var elapsed := 0.0
var sprite := Sprite2D.new()

func _ready() -> void:
	if texture == null:
		push_warning("Bite visual has no hitEffectTexture.")
		sprite.free()
		queue_free()
		return
	z_index = 9
	add_to_group("bite_hit_fx")
	sprite.texture = texture
	sprite.scale = Vector2.ONE*(105.0/texture.get_width())
	if blocked: sprite.modulate = Color(0.55,0.85,1.0,0.85)
	add_child(sprite)

func _process(delta: float) -> void:
	if texture == null: return
	elapsed += delta
	if elapsed >= HOLD_TIME+FADE_TIME:
		queue_free()
		return
	var progress := clampf((elapsed-HOLD_TIME)/FADE_TIME,0,1)
	sprite.scale = Vector2.ONE*(105.0/texture.get_width())*lerpf(1.0,1.12,progress)
	modulate.a = 1.0-progress
