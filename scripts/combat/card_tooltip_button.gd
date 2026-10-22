extends Button
## The console keeps its compact add-one buttons and delegates art to CombatCard.
var definition: Dictionary = {}

func _make_custom_tooltip(_for_text: String) -> Object:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(396, 640)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := CombatCard.new()
	card.allow_zoom_preview = false
	card.managed_input = true
	card.setup(str(definition.get("id", "")), definition, true)
	card.pivot_offset = Vector2.ZERO
	card.scale = Vector2.ONE * CombatCard.ZOOM_SCALE
	holder.add_child(card)
	card.label(holder, str(definition.get("description", "")), Vector2(8, 512), Vector2(380, 120), 17)
	return holder
