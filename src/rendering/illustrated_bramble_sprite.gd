extends RefCounted

## The delivered blackberry art, sliced into its twenty-five clumps (see
## docs/concept/brambles.md).
##
## Deliberately NOT built on IllustratedFernPatch or IllustratedGrassPatch.
## Those exist to make a chunk's worth of BLADES bend in the wind as one
## GPU-instanced mesh, which a bramble neither needs nor wants: brambles are
## sparse (BlackberryBramble.MAX_PATCHES is 36 against a fern's 123 and a
## meadow's hundreds), and a woody thicket does not sway like bracken. One
## ordinary Sprite2D per thicket is the honest shape, the same one desert
## scrub and aquatic invertebrates already use at this density.
##
## The sheet carries REAL ALPHA, unlike fern.png's painted checkerboard, so
## nothing here keys anything -- it slices and caches.

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

const SHEET_PATH := "res://assets/sprites/plants/blackberry.png"

## The delivered grid: twenty-five clumps, five by five.
const COLUMNS := 5
const ROWS := 5

## How wide a thicket is drawn, in world units. A bramble is a bush a person
## could walk around rather than a tuft, so it stands wider than a tile --
## the same "world size is a world decision, never the art canvas's" rule
## ProceduralWormSprite's doc comment records this project hitting twice.
const WORLD_WIDTH := 20.0

## Sliced frames are shared across every chunk: there is no per-instance
## variation to lose (which clump a cell wears is chosen by SEED, not baked
## into the texture), and re-slicing a 1254px sheet per chunk would be pure
## waste.
static var _frames: Array[ImageTexture] = []


## Every clump on the sheet, sliced once and cached. Empty if the sheet is
## missing, which is the caller's cue to draw nothing rather than a box.
static func frames() -> Array[ImageTexture]:
	if not _frames.is_empty():
		return _frames
	var image := SpriteSheetLoader.load_image(SHEET_PATH)
	if image == null:
		return _frames
	var cell_width := image.get_width() / COLUMNS
	var cell_height := image.get_height() / ROWS
	for row in range(ROWS):
		for column in range(COLUMNS):
			var frame := image.get_region(
				Rect2i(column * cell_width, row * cell_height, cell_width, cell_height)
			)
			if frame.get_format() != Image.FORMAT_RGBA8:
				frame.convert(Image.FORMAT_RGBA8)
			_frames.append(ImageTexture.create_from_image(frame))
	return _frames


## Which clump the thicket at this global cell wears -- hash-derived, so a
## reloaded chunk shows the same bramble in the same place, the same
## seeded-determinism convention every other art pick in this project
## follows. Null when the sheet is missing.
static func frame_for(global_cell: Vector2i) -> ImageTexture:
	var all := frames()
	if all.is_empty():
		return null
	var index := absi(hash("%d_%d_bramble_clump" % [global_cell.x, global_cell.y])) % all.size()
	return all[index]


## How much a sliced frame must be scaled to stand WORLD_WIDTH wide. Derived
## from the art rather than assumed, so a re-exported sheet does not silently
## change how big a bramble looks.
static func world_scale() -> float:
	var all := frames()
	if all.is_empty():
		return 1.0
	return WORLD_WIDTH / float(maxi(all[0].get_width(), 1))
