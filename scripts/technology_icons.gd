extends RefCounted
## One ID resolver for storefront, loadout, battle snapshots and the archive.
const PATHS := {
	"dimensional_pocket":"res://assets/technology/icons/dimensional_pocket-v1.png",
	"accelerated_clock":"res://assets/technology/icons/accelerated_clock-v1.png",
	"backup_energy":"res://assets/technology/icons/backup_energy-v1.png",
	"money_chip":"res://assets/technology/icons/money_chip-v1.png",
	"healing_chip":"res://assets/technology/icons/healing_chip-v1.png",
	"swift_chip":"res://assets/technology/icons/swift_chip-v1.png"
}

static func ids() -> Array:
	return PATHS.keys()

static func texture_for(id: String) -> Texture2D:
	var path: String = PATHS.get(id, "")
	if path.is_empty() or not ResourceLoader.exists(path): return null
	return load(path) as Texture2D

static func assign(view: TextureRect, id: String) -> void:
	view.texture = texture_for(id)
	view.visible = view.texture != null
	view.set_meta("technology_id", id)

static func create(parent: Node, id: String, pos: Vector2, dimensions: Vector2) -> TextureRect:
	var view := TextureRect.new()
	view.name = "technology_icon"
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	view.position = pos
	view.size = dimensions
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	assign(view, id)
	parent.add_child(view)
	return view

static func activation_label(definition: Dictionary) -> String:
	return "被动 · 自动生效" if CombatModel.is_passive_cyberware(definition) else "冷却 %d 回合" % int(definition.get("cooldownTurns",1))
