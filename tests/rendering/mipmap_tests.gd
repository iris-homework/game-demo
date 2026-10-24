extends Node
## Imported mipmaps, production sampling and actor pose wiring for the formal game.

const Icons = preload("res://scripts/technology_icons.gd")
const BlackMarketArt = preload("res://scripts/black_market_art.gd")

const MIPMAP_FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
const PROJECT_DEFAULT_SETTING := "rendering/textures/canvas_textures/default_texture_filter"
const EXPECTED_PROJECT_DEFAULT := Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
const EXPECTED_CARDS := 40
const DEFAULT_OUTPUT := "res://artifacts/qa/mipmap-2026-10-25"
const CATEGORY_TEXTURES := {
	"background": "res://assets/backgrounds/bar.png",
	"character": "res://assets/characters/noren.png",
	"combat_test_pose": "res://assets/combat_test/noren/noren_slash.png",
	"published_image": "res://enemy_asset_pipeline/published/assets/9059dc2adc98383212bcb1f09ce1d76651f72d688ff7463f32da924853385368.png",
	"technology_icon": "res://assets/technology/icons/healing_chip-v1.png",
	"market_image": "res://assets/market/black-market-background-v2.png",
	"menu_background": "res://assets/menu/noren-bar-seated-v2-detail.png",
}

class AttachmentFixture:
	var texture: Texture2D
	var layer_order := 1.0
	var centered := true
	var use_affine := false
	var transform := Transform2D.IDENTITY
	var rotation_degrees := 0.0
	var visual_scale := Vector2.ONE
	var offset := Vector2.ZERO

	func _init(value: Texture2D) -> void:
		texture = value

var checks := 0
var failures: Array[String] = []
var output_dir := DEFAULT_OUTPUT
var requested_resolution := Vector2i.ZERO
var real_display := false
var captured: Array[String] = []
var ab_manifest: Dictionary = {"available": false, "reason": "capture not attempted"}
var app: Control

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		return
	failures.append(message)
	push_error("MIPMAP RENDERING: " + message)

func _ready() -> void:
	_parse_cli()
	real_display = DisplayServer.get_name().to_lower() != "headless"
	_prepare_qa()
	await _apply_resolution()
	_test_project_setting()
	_test_representative_imports()
	_test_card_faces()
	_test_technology_icons()
	await _start_menu_and_test_environment()
	await _test_market_material()
	await _test_mall_sampling()
	await _test_card_library_and_ab()
	await _test_formal_battle()
	_finish()

func _parse_cli() -> void:
	var args := OS.get_cmdline_user_args()
	var index := 0
	var output_overridden := false
	while index < args.size():
		var arg: String = args[index]
		if arg == "--output-dir" and index + 1 < args.size():
			output_dir = args[index + 1]
			output_overridden = true
			index += 2
			continue
		if arg.begins_with("--output-dir="):
			output_dir = arg.trim_prefix("--output-dir=")
			output_overridden = true
			index += 1
			continue
		if arg == "--resolution" and index + 1 < args.size():
			requested_resolution = _resolution_from_text(args[index + 1])
			index += 2
			continue
		if arg.begins_with("--resolution="):
			requested_resolution = _resolution_from_text(arg.trim_prefix("--resolution="))
		index += 1
	if output_dir.strip_edges().is_empty():
		output_dir = DEFAULT_OUTPUT
	var env_output := OS.get_environment("QA_OUT_DIR")
	if not output_overridden and not env_output.is_empty():
		output_dir = env_output

func _resolution_from_text(value: String) -> Vector2i:
	var parts := value.strip_edges().to_lower().split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		check(false, "resolution must be WIDTHxHEIGHT: " + value)
		return Vector2i.ZERO
	var parsed := Vector2i(parts[0].to_int(), parts[1].to_int())
	if parsed.x <= 0 or parsed.y <= 0 or parsed.x > 8192 or parsed.y > 8192:
		check(false, "resolution is outside the supported range: " + value)
		return Vector2i.ZERO
	return parsed

func _prepare_qa() -> void:
	var result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	check(result == OK or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir)), "QA output directory is writable")
	var sandbox_dir := output_dir.path_join("isolated-saves")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sandbox_dir))
	Game.save_enabled = false
	Game.save_path = sandbox_dir.path_join("checkpoint-%d.json" % OS.get_process_id())
	Game.meta_path = sandbox_dir.path_join("meta-%d.json" % OS.get_process_id())
	Game.transition_locked = false
	Game.battle_busy = false
	Game.pending_save_kind = ""
	Game.training_mode = false
	Game.training_backup.clear()
	Game.state = Game.initial_state()
	Game.page = "menu"
	check(not Game.state.is_empty(), "formal initial state is available")

func _apply_resolution() -> void:
	if requested_resolution == Vector2i.ZERO or not real_display:
		return
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = requested_resolution
	await _settle(0.25)
	await RenderingServer.frame_post_draw
	var rendered := get_viewport().get_texture().get_image()
	check(rendered != null and rendered.get_size() == requested_resolution, "viewport renders requested resolution %s" % str(requested_resolution))

func _settle(seconds: float = 0.2) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame
	await get_tree().process_frame

func _wait_for_page(page: String, timeout_ms: int = 12000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(app) and str(app.get("shown_page")) == page and is_instance_valid(app.get("view")):
			return true
		await get_tree().process_frame
	check(false, "formal page did not settle: " + page)
	return false

func _test_project_setting() -> void:
	var configured := int(ProjectSettings.get_setting(PROJECT_DEFAULT_SETTING, -1))
	check(configured == EXPECTED_PROJECT_DEFAULT, "project default matches the engine's Viewport LINEAR_WITH_MIPMAPS constant")
	check(int(get_viewport().canvas_item_default_texture_filter) == EXPECTED_PROJECT_DEFAULT, "running root Viewport actually uses LINEAR_WITH_MIPMAPS")

func _check_texture_mips(texture: Texture2D, label: String) -> void:
	check(texture != null, label + " texture loads")
	if texture == null:
		return
	var image := texture.get_image()
	check(image != null, label + " exposes image data")
	if image != null:
		check(image.has_mipmaps(), label + " has generated import mipmaps")

func _load_and_check(path: String, label: String) -> Texture2D:
	if not ResourceLoader.exists(path, "Texture2D"):
		check(false, label + " exists as Texture2D: " + path)
		return null
	var texture := load(path) as Texture2D
	_check_texture_mips(texture, label)
	return texture

func _test_representative_imports() -> void:
	for category in CATEGORY_TEXTURES:
		_load_and_check(str(CATEGORY_TEXTURES[category]), category + " representative import")

func _test_card_faces() -> void:
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cards/card_faces_no_character.json"))
	check(int(settings.get("schemaVersion", 0)) == 1, "fixed card-face schema is version 1")
	var cards_value = settings.get("cards", {})
	check(cards_value is Dictionary, "fixed card-face bindings are a dictionary")
	if not cards_value is Dictionary:
		return
	var entries: Dictionary = cards_value
	check(entries.size() == EXPECTED_CARDS, "fixed card-face manifest contains exactly forty entries")
	for number in range(1, EXPECTED_CARDS + 1):
		var id := "noren_%02d" % number
		var entry_value = entries.get(id, {})
		check(entry_value is Dictionary, id + " has a fixed face binding")
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var path := str(entry.get("path", ""))
		var definition: Dictionary = Game.card_catalog.get(id, {})
		check(not definition.is_empty(), id + " exists in the formal combat catalog")
		if definition.is_empty():
			continue
		var card := CombatCard.new()
		card.setup(id, definition, true)
		var texture := card.face_texture
		check(texture != null, id + " resolves through the formal fixed-face boundary")
		check(texture != null and texture.resource_path == path and texture.get_size() == Vector2(1086, 1448), id + " loads its authored 1086x1448 texture")
		_check_texture_mips(texture, id + " production card face")
		card.free()

func _test_technology_icons() -> void:
	for id in Icons.ids():
		var texture := Icons.texture_for(id)
		_check_texture_mips(texture, "technology " + id)
	var host := Control.new()
	add_child(host)
	var icon := Icons.create(host, "healing_chip", Vector2.ZERO, Vector2(96, 96))
	check(icon.texture_filter == MIPMAP_FILTER, "technology icon factory sets explicit LINEAR_WITH_MIPMAPS")
	check(_effective_filter(icon) == MIPMAP_FILTER, "technology icon effective filter uses mipmapped linear sampling")
	host.queue_free()

func _start_menu_and_test_environment() -> void:
	Game.save_enabled = false
	Game.state = Game.initial_state()
	Game.page = "menu"
	Game.training_mode = false
	Game.transition_locked = false
	Game.battle_busy = false
	app = preload("res://scenes/main.tscn").instantiate() as Control
	check(app != null, "formal main scene instantiates")
	if app == null:
		return
	add_child(app)
	await _settle(0.45)
	if not (await _wait_for_page("menu")):
		return
	var menu := app.get("view") as Control
	check(menu != null, "formal menu page is active")
	if menu == null:
		return
	var environment := menu.get("environment") as Control
	check(environment != null, "formal menu environment exists")
	if environment == null:
		return
	check(environment.texture_filter == MIPMAP_FILTER, "menu environment explicitly uses LINEAR_WITH_MIPMAPS")
	var background := environment.get("background") as TextureRect
	check(background != null, "current menu background node exists")
	if background != null:
		check(_effective_filter(background) == MIPMAP_FILTER, "current menu background inherits mipmapped linear sampling")
		_check_texture_mips(background.texture, "current menu background in production node")
	var source := environment.get("source_texture") as Texture2D
	_check_texture_mips(source, "current menu source artwork")
	await _capture("menu-current")

func _test_market_material() -> void:
	var art := BlackMarketArt.new()
	add_child(art)
	await _settle(0.1)
	var background := art.get_node_or_null("black_market_background") as TextureRect
	var shopkeeper := art.get_node_or_null("black_market_shopkeeper") as TextureRect
	var counter := art.get_node_or_null("black_market_counter") as Polygon2D
	check(background != null and background.texture_filter == MIPMAP_FILTER, "formal market backdrop image uses LINEAR_WITH_MIPMAPS")
	check(shopkeeper != null and shopkeeper.texture_filter == MIPMAP_FILTER, "formal market shopkeeper image uses LINEAR_WITH_MIPMAPS")
	check(counter != null and counter.texture_filter == MIPMAP_FILTER, "formal market counter uses LINEAR_WITH_MIPMAPS")
	if background != null:
		_check_texture_mips(background.texture, "market backdrop")
	if shopkeeper != null:
		_check_texture_mips(shopkeeper.texture, "market shopkeeper")
	art.queue_free()
	await get_tree().process_frame

func _test_mall_sampling() -> void:
	Game.page = "map"
	Game.state = Game.initial_state()
	Game.state.currentScene = "map"
	Game.transition_locked = false
	Game.changed.emit()
	await _settle(0.1)
	Game.visit("mall")
	if not (await _wait_for_page("place")):
		return
	while Game.transition_locked or Game.battle_busy:
		await get_tree().process_frame
	await _settle(0.2)
	var view := app.get("view") as Control
	var artwork: TextureRect
	var original := Game.texture("woss_mall_shop")
	for child in view.get_children():
		if child is TextureRect and child.texture == original:
			artwork = child
	check(artwork != null, "mall keeps its original combined artwork and character")
	if artwork == null:
		return
	check(artwork.texture.get_size() == Vector2(1586, 992), "mall uses full-resolution imported original")
	check(artwork.material == null and artwork.modulate == Color.WHITE, "mall has no blur material or tint")
	check(_effective_filter(artwork) == MIPMAP_FILTER, "mall inherits actual linear mipmap filtering from its Viewport")
	_check_texture_mips(artwork.texture, "mall original artwork")
	if real_display:
		await _capture("mall-fixed-linear-mipmaps")
		var viewport := get_viewport()
		var correct_filter := viewport.canvas_item_default_texture_filter
		viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		await _capture("mall-old-nearest-mipmaps-control")
		viewport.canvas_item_default_texture_filter = correct_filter
		check(viewport.canvas_item_default_texture_filter == EXPECTED_PROJECT_DEFAULT, "mall A/B restores the correct native Viewport filter")
	check(artwork.texture == original, "mall sampling check does not replace or redraw the source artwork")

func _test_card_library_and_ab() -> void:
	Game.page = "menu"
	Game.state = Game.initial_state()
	Game.save_enabled = false
	Game.transition_locked = false
	Game.battle_busy = false
	Game.changed.emit()
	await _settle(0.2)
	Game.open_card_library()
	if not (await _wait_for_page("card_library")):
		return
	var library := app.get("view") as Control
	check(library != null and library.has_method("set_scope"), "formal card library page is active")
	if library == null:
		return
	library.call("set_scope", false)
	await _settle(0.2)
	var views_value = library.get("card_views")
	check(views_value is Array, "formal card library exposes its production card views")
	if not views_value is Array:
		return
	var views: Array = views_value
	check(views.size() == EXPECTED_CARDS, "card library builds all forty production cards")
	var target: CombatCard = null
	for value in views:
		var card := value as CombatCard
		if card == null:
			continue
		check(card.texture_filter == MIPMAP_FILTER, card.uid + " card view explicitly uses LINEAR_WITH_MIPMAPS")
		if card.uid == "noren_03":
			target = card
	check(target != null, "card library includes noren_03")
	if target == null:
		return
	_check_texture_mips(target.face_texture, "noren_03 card library texture")
	await _capture("card-library-all")
	await _capture_noren_03_ab(target)
	if real_display:
		target.show_zoom_preview()
		await _settle(0.1)
		check(is_instance_valid(target.zoom_card), "noren_03 formal read-only zoom preview opens")
		if is_instance_valid(target.zoom_card):
			await _capture_noren_03_ab(target.zoom_card, "noren_03-zoom")
		target.hide_zoom_preview()

func _test_formal_battle() -> void:
	Game.page = "menu"
	Game.state = Game.initial_state()
	Game.save_enabled = false
	Game.training_mode = false
	Game.training_backup.clear()
	Game.transition_locked = false
	Game.battle_busy = false
	Game.changed.emit()
	await _settle(0.15)
	Game.start_training("B04")
	if not (await _wait_for_page("battle")):
		return
	var deadline := Time.get_ticks_msec() + 12000
	while (Game.transition_locked or Game.battle_busy) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not Game.transition_locked and not Game.battle_busy, "battle entry transition and opening hand animations complete")
	await _settle(0.2)
	check(Game.training_mode and not Game.save_enabled, "formal battle uses isolated training mode with autosave disabled")
	var view := app.get("view") as Control
	var stage_value = view.get("stage") if view != null else null
	check(stage_value is Control, "formal battle stage is constructed")
	if not stage_value is Control:
		return
	var stage := stage_value as Control
	var scenery := stage.get("scenery") as TextureRect
	check(scenery != null, "formal battle background node is constructed")
	if scenery != null:
		check(_effective_filter(scenery) == MIPMAP_FILTER, "formal battle background uses effective mipmapped filtering")
		_check_texture_mips(scenery.texture, "formal battle background")
	var actor_values: Array = [stage.get("player")]
	var enemies_value = stage.get("enemies")
	if enemies_value is Array:
		var enemy_actors: Array = enemies_value
		actor_values.append_array(enemy_actors)
	for index in actor_values.size():
		var actor := actor_values[index] as Node2D
		check(actor != null, "formal battle actor %d exists" % index)
		if actor == null:
			continue
		var sprite := actor.get("sprite") as Sprite2D
		check(bool(actor.get("use_mipmapped_textures")), "formal battle actor %d defaults to mipmapped textures" % index)
		check(sprite != null and sprite.texture_filter == MIPMAP_FILTER, "formal battle actor %d sprite uses LINEAR_WITH_MIPMAPS" % index)
		if sprite != null:
			_check_texture_mips(sprite.texture, "formal battle actor %d sprite" % index)
	var player := stage.get("player") as Node2D
	if player == null:
		return
	var player_sprite := player.get("sprite") as Sprite2D
	if player_sprite == null or player_sprite.texture == null:
		check(false, "formal battle player sprite can seed an attachment check")
		return
	player.call("_show_attachments", [AttachmentFixture.new(player_sprite.texture)], Transform2D.IDENTITY)
	var attachments := player.get("attachment_above") as Node2D
	check(attachments != null and attachments.get_child_count() == 1, "formal battle Actor builds its attachment container")
	if attachments != null and attachments.get_child_count() == 1:
		var attachment_sprite := attachments.get_child(0) as Sprite2D
		check(attachment_sprite != null and attachment_sprite.texture_filter == MIPMAP_FILTER, "formal battle Actor attachment uses LINEAR_WITH_MIPMAPS")
		if attachment_sprite != null:
			_check_texture_mips(attachment_sprite.texture, "formal battle Actor attachment")
	var frames_value = player.get("pipeline_frames")
	var slash_frames: Array = []
	if frames_value is Dictionary:
		var frames: Dictionary = frames_value
		var slash_value = frames.get("slash", [])
		if slash_value is Array:
			var authored_frames: Array = slash_value
			slash_frames = authored_frames
	player.call("set_pose", "slash")
	check(str(player.get("pose")) == "slash", "formal battle Actor switches to slash pose")
	check(player_sprite.texture_filter == MIPMAP_FILTER, "Actor keeps mipmapped sampling after pose switch")
	_check_texture_mips(player_sprite.texture, "formal battle slash pose")
	var expected_slash: Texture2D = null
	if not slash_frames.is_empty():
		expected_slash = slash_frames[0].get("texture") as Texture2D
	else:
		var poses_value = player.get("poses")
		if poses_value is Dictionary:
			expected_slash = poses_value.get("slash") as Texture2D
	check(expected_slash != null and player_sprite.texture == expected_slash, "slash pose selects its authored texture")
	player.call("set_pose", "idle")
	check(str(player.get("pose")) == "idle", "formal battle Actor returns to idle pose")
	check(player_sprite.texture_filter == MIPMAP_FILTER, "Actor retains mipmapped sampling on idle restore")
	var plain_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	plain_image.fill(Color(0.25, 0.5, 0.75, 1.0))
	var plain := ImageTexture.create_from_image(plain_image)
	check(plain != null and not plain.get_image().has_mipmaps(), "runtime-only source can be prepared without import mipmaps")
	var generated := player.call("_display_texture", plain) as Texture2D
	check(generated != null and generated != plain, "Actor generates a fallback texture for unimported runtime images")
	if generated != null:
		var generated_image := generated.get_image()
		check(generated_image != null and generated_image.has_mipmaps(), "Actor fallback texture still contains mipmaps")
	await _capture("formal-battle-B04")

func _effective_filter(item: CanvasItem) -> int:
	var cursor: Node = item
	while cursor != null:
		if cursor is CanvasItem:
			var configured := (cursor as CanvasItem).texture_filter
			if configured != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
				return configured
		cursor = cursor.get_parent()
	match item.get_viewport().canvas_item_default_texture_filter:
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST: return CanvasItem.TEXTURE_FILTER_NEAREST
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR: return CanvasItem.TEXTURE_FILTER_LINEAR
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS: return CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST_WITH_MIPMAPS: return CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return -1

func _capture_noren_03_ab(card: CombatCard, prefix: String = "noren_03") -> void:
	if not real_display:
		ab_manifest = {"available": false, "reason": "headless display; pixel captures are intentionally skipped"}
		return
	card.texture_filter = MIPMAP_FILTER
	var with_result := await _capture(prefix + "-with-mipmaps", card.get_global_rect())
	card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var linear_result := await _capture(prefix + "-linear-control", card.get_global_rect())
	card.texture_filter = MIPMAP_FILTER
	check(card.texture_filter == MIPMAP_FILTER, "noren_03 restores formal mipmapped sampling after A/B capture")
	check(with_result.get("size") == linear_result.get("size"), "noren_03 A/B captures use identical pixel dimensions")
	ab_manifest = {
		"available": true,
		"subject": "noren_03",
		"source": card.face_texture.resource_path if card.face_texture != null else "",
		"withMipmaps": {"label": "正式 WITH_MIPMAPS", "file": with_result.get("file", ""), "filter": "LINEAR_WITH_MIPMAPS"},
		"linearControl": {"label": "旧 LINEAR 对照", "file": linear_result.get("file", ""), "filter": "LINEAR"},
		"note": "同一纹理、同一卡牌尺寸；仅截图节点的采样过滤不同。正式代码没有用户开关。",
	}
	check(_write_json(prefix + "-mipmap-ab.json", ab_manifest), "noren_03 A/B labels are saved beside the captures")

func _capture(label: String, requested_rect: Rect2 = Rect2()) -> Dictionary:
	if not real_display:
		return {"file": "", "size": Vector2i.ZERO}
	await RenderingServer.frame_post_draw
	var rendered := get_viewport().get_texture().get_image()
	if rendered == null or rendered.get_width() <= 0 or rendered.get_height() <= 0:
		check(false, "rendered viewport is available for " + label)
		return {"file": "", "size": Vector2i.ZERO}
	var bounds := Rect2i(Vector2i.ZERO, rendered.get_size())
	var region := bounds
	if requested_rect.size != Vector2.ZERO:
		var visible := get_viewport().get_visible_rect().size
		var scale := Vector2(rendered.get_size()) / visible
		var position := Vector2i(roundi(requested_rect.position.x * scale.x), roundi(requested_rect.position.y * scale.y))
		var dimensions := Vector2i(roundi(requested_rect.size.x * scale.x), roundi(requested_rect.size.y * scale.y))
		region = Rect2i(position, dimensions).intersection(bounds)
	if region.size.x <= 0 or region.size.y <= 0:
		check(false, "capture region is onscreen for " + label)
		return {"file": "", "size": Vector2i.ZERO}
	var image := rendered.get_region(region)
	var filename := "%s-%dx%d.png" % [label, image.get_width(), image.get_height()]
	var path := output_dir.path_join(filename)
	var result := image.save_png(ProjectSettings.globalize_path(path))
	check(result == OK, "saved screenshot " + filename)
	if result == OK:
		captured.append(filename)
		return {"file": filename, "size": image.get_size()}
	return {"file": "", "size": image.get_size()}

func _write_json(filename: String, value: Dictionary) -> bool:
	var file := FileAccess.open(ProjectSettings.globalize_path(output_dir.path_join(filename)), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	return true

func _finish() -> void:
	Game.save_enabled = false
	check(not FileAccess.file_exists(Game.save_path), "disabled autosave wrote no QA checkpoint")
	check(not FileAccess.file_exists(Game.meta_path), "disabled autosave wrote no QA metadata")
	var report := {
		"checks": checks,
		"failures": failures,
		"realDisplay": real_display,
		"requestedResolution": str(requested_resolution) if requested_resolution != Vector2i.ZERO else "engine-default",
		"outputDir": output_dir,
		"screenshots": captured,
		"noren03AB": ab_manifest,
		"scope": "all 40 loaded card-face textures, project Viewport filter, representative background/character/pose/published/technology/market/menu imports and node filters, formal battle Actor sprite and attachment sampling, pose switching, and runtime fallback mipmap generation; no physical input or gameplay assertions",
	}
	var report_written := _write_json("result.json", report)
	if not report_written:
		failures.append("result.json could not be written")
		push_error("MIPMAP RENDERING: result.json could not be written")
	print("MIPMAP RENDERING: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
