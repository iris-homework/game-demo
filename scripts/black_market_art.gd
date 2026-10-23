extends Control
## Independent lossless character artwork keeps portrait detail out of the scene plate.
const CANVAS := Vector2(1440,900)
const SHOPKEEPER_RECT := Rect2(30,139,540,720)
# Counter silhouette in the 1586×992 background plate; UVs reuse that exact texture.
const COUNTER_EDGE := [
	Vector2(0,468),Vector2(178,491),Vector2(202,600),
	Vector2(220,600),Vector2(220,584),Vector2(252,584),Vector2(277,602),
	Vector2(292,607),Vector2(626,627),Vector2(640,505),
	Vector2(1586,505),Vector2(1586,992),Vector2(0,992)
]

func _ready() -> void:
	name = "black_market_art"
	size = CANVAS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := Game.texture("black_market_background")
	var shopkeeper := Game.texture("black_market_shopkeeper")
	if backdrop == null or shopkeeper == null:
		add_picture("black_market_fallback",Game.texture("black_market_shop"),Rect2(Vector2.ZERO,CANVAS))
		return
	add_picture("black_market_background",backdrop,Rect2(Vector2.ZERO,CANVAS))
	add_picture("black_market_shopkeeper",shopkeeper,SHOPKEEPER_RECT)
	var foreground := Polygon2D.new()
	foreground.name = "black_market_counter"
	foreground.texture = backdrop
	foreground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var vertices := PackedVector2Array()
	var coordinates := PackedVector2Array()
	for point in COUNTER_EDGE:
		var normalized: Vector2 = point / Vector2(1586,992)
		vertices.append(normalized * CANVAS)
		coordinates.append(normalized * backdrop.get_size())
	foreground.polygon = vertices
	foreground.uv = coordinates
	add_child(foreground)

func add_picture(node_name: String, texture: Texture2D, area: Rect2) -> TextureRect:
	var picture := TextureRect.new()
	picture.name = node_name
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.texture = texture
	picture.position = area.position
	picture.size = area.size
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	return picture
