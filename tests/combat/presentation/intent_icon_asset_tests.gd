extends Node
## Read-only widget/resource checks; no battle playback, saves, or physical input.
## Texture boxes overlap the number row's transparent margin; pixel QA is separate.
const Intent = preload("res://scripts/combat/enemy_intent.gd")
const TYPES := ["attack", "fortify", "energy_suit", "charge", "strength_allies", "vulnerable", "pollution", "weak", "heal_ally", "unknown"]
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("INTENT ICON ASSET: " + message)

func check_icon(icon: TextureRect, widget: Control, expected_path: String) -> void:
	check(icon.texture != null and icon.texture.resource_path == expected_path, "visible icon uses the mapped texture: " + expected_path)
	check(icon.size == Vector2(40,40) and Rect2(Vector2.ZERO,widget.size).encloses(Rect2(icon.position,icon.size)), "icon fits the existing head HUD")
	check(icon.mouse_filter == Control.MOUSE_FILTER_IGNORE and icon.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "icon preserves hover routing and uses smooth mipmapped filtering")

func _ready() -> void:
	Game.save_enabled = false
	var font := ThemeDB.fallback_font
	for kind in TYPES:
		var path: String = str(Intent.ICON_PATHS.get(kind,""))
		check(path.begins_with("res://assets/icons/intents/") and path.ends_with(".svg"), "mapped SVG exists for " + kind)
		var texture := load(path) as Texture2D if not path.is_empty() else null
		check(texture != null and texture.get_size() == Vector2(64,64), "64x64 source texture loads: " + kind)
		if texture != null:
			check(texture.get_image().has_mipmaps(), "imported icon includes minification mipmaps: " + kind)

	var cases := [
		["attack", "攻击 17 ×3", "17×3"],
		["fortify", "强化", "强化"],
		["energy_suit", "能量防护服", "强化"],
		["charge", "充能 5", "+5"],
		["strength_allies", "全体力量 5", "+5"],
		["vulnerable", "易伤 5", "5"],
		["pollution", "污染 5", "5"],
		["weak", "虚弱 5", "5"],
		["heal_ally", "治疗 5", "+5"],
		["future_intent", "等待", "等待"],
		["", "等待", "等待"],
	]
	for item in cases:
		# The caller's attack preview intentionally differs from raw amount.
		var source := {"type":item[0], "amount":5, "hits":3, "onHitWeak":0, "metadata":{"unchanged":true}}
		var before := source.duplicate(true)
		var widget: Control = Intent.new()
		widget.setup(source,item[1],font)
		check(source == before and widget.value_label.text == item[2], "setup keeps model input and caller preview: " + str(item[0]))
		check(widget.size == Vector2(96,66) and widget.icon_views.size() == 1, "single intention keeps one icon in the existing HUD")
		if widget.icon_views.size() == 1:
			var mapped_kind: String = item[0] if TYPES.has(item[0]) else "unknown"
			check_icon(widget.icon_views[0],widget,Intent.ICON_PATHS[mapped_kind])
			check(widget.icon_views[0].position == Vector2(28,0), "single icon remains centered above its value")
		widget.free()

	var compound: Control = Intent.new()
	var tooltip := {"plain":"攻击10并施加2层虚弱", "title":"敌人意图"}
	compound.configure_tooltip(tooltip)
	var source := {"type":"attack", "amount":8, "hits":1, "onHitWeak":2}
	var before := source.duplicate(true)
	compound.setup(source,"攻击 10",font)
	var weak := compound.find_child("IntentWeakAmount",true,false) as Label
	check(source == before and compound.value_label.text == "10" and weak != null and weak.text == "2", "compound intent preserves preview damage and separate weak stacks without changing input")
	check(compound.icon_views.size() == 2, "attack with weak shows both intentions")
	if compound.icon_views.size() == 2:
		check_icon(compound.icon_views[0],compound,Intent.ICON_PATHS.attack)
		check_icon(compound.icon_views[1],compound,Intent.ICON_PATHS.weak)
		check(compound.icon_views[0].position == Vector2(4,0) and compound.icon_views[1].position == Vector2(52,0), "compound icons occupy separate columns")
	if weak != null:
		check(compound.value_label.position.x+compound.value_label.size.x <= weak.position.x and Rect2(Vector2.ZERO,compound.size).encloses(Rect2(weak.position,weak.size)), "compound amounts remain separate and inside the HUD")
	check(compound.tooltip_data == tooltip and compound.tooltip_text == tooltip.plain, "icon setup preserves the detailed tooltip")
	compound.setup({"type":"attack", "amount":10, "hits":3, "onHitWeak":2},"攻击 10 ×3",font)
	var size_used: int = compound.value_label.get_theme_font_size("font_size")
	check(compound.value_label.text == "10×3" and font.get_string_size("10×3",HORIZONTAL_ALIGNMENT_LEFT,-1,size_used).x <= compound.value_label.size.x-4, "multi-hit damage fits its compound column without spilling into weak stacks")
	# A reused widget must release the previous compound labels and textures.
	compound.setup({"type":"heal_ally", "amount":10},"治疗 10",font)
	var icons := compound.get_children().filter(func(child): return child is TextureRect)
	var labels := compound.get_children().filter(func(child): return child is Label)
	check(compound.icon_views.size() == 1 and icons.size() == 1 and labels.size() == 1 and compound.find_child("IntentWeakAmount",true,false) == null, "setup reuse removes stale compound children")
	check(compound.value_label.text == "+10" and compound.value_label.size.x == 96 and compound.tooltip_data == tooltip, "reuse restores ordinary numeric presentation and preserves tooltip data")
	compound.free()
	print("INTENT ICON ASSET: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
