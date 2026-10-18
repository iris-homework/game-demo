extends CombatCard
## Trial resting fan height. Lifted poses keep their production screen coordinates.
const REST_RAISE := 60.0

func refresh_pose(force: bool = false) -> void:
	if preview_only: return
	if not enabled and not force: return
	if hover_tween: hover_tween.kill()
	hover_tween = create_tween().set_parallel(true)
	var lifted := hovered or selected
	z_index = (31 if selected else 30) if lifted else home_z
	var offset_y := REST_RAISE - 150.0 if selected else (REST_RAISE - 140.0 if lifted else 0.0)
	hover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self, "position", home + Vector2(0, offset_y), 0.14)
	hover_tween.tween_property(self, "scale", Vector2.ONE * (1.12 if lifted else home_scale), 0.14)
	hover_tween.tween_property(self, "rotation", 0.0 if lifted else home_rotation, 0.14)
