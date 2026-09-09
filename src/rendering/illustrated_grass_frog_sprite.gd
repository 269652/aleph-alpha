extends RefCounted

## Real illustrated art for the grass frog's four animations (see
## docs/concept/seasonal_behavior.md's phase 10, "Grass frog: new species,
## brumating, decorative-but-real"). Same "hand-drawn sheet -> SpriteSheet
## Slicer -> cached frames" shape as IllustratedCaterpillarSprite,
## deliberately mirrored rather than built on IllustratedAnimalSprite/
## IllustratedDecomposerSprite: a grass frog carries no CreatureMarker/
## AnimalAnatomy stack, and there is only ever one kind of frog in this
## game, so this skips the species dimension those two both carry and keys
## everything by action alone.
##
## grass_frog.png is a perfectly regular 8-column x 4-row grid (1536x1024,
## 192x256 per cell -- dimension-identical to caterpillar.png/worm.png),
## sliced directly from that KNOWN fixed grid rather than through
## SpriteSheetSlicer.detect_frames' content-gap heuristic, the same
## reasoning IllustratedCaterpillarSprite/IllustratedWormSprite's own doc
## comments give. All 32 cells were confirmed to hold real, non-blank
## content this way (a temporary probe script dumped every cell and
## measured its opaque-pixel count, all comfortably in the 9000-14500
## range, none anywhere near zero), and each row's own visual identity was
## confirmed against the actual sliced-and-despilled pixels before this
## class shipped:
##   row 1 "idle" -- sitting with a slight turn across its 8 frames: the
##     settled resting pose, and what ambient ground wander plays while not
##     hopping.
##   row 2 "hop" -- crouches, leaps into a stretched mid-air pose, lands
##     back in a crouch: real frog locomotion (frogs hop, they don't walk).
##   row 3 "eat" -- tongue shoots out to catch a fly mid-sequence: the real
##     feeding pose.
##   row 4 "croak" -- throat/vocal sac visibly inflates: a real frog call.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

const _SHEET_PATH := "res://assets/sprites/frogs/grass_frog.png"
const _COLUMNS := 8
const _CELL_SIZE := Vector2i(192, 256)

## Row index for each named action, top to bottom exactly as drawn.
const _ROW_FOR_ACTION := {
	"idle": 0,
	"hop": 1,
	"eat": 2,
	"croak": 3,
}

## The canvas every sliced frame is normalized onto, its feet landing on the
## same BASELINE_Y regardless of action -- mirrors IllustratedCaterpillar
## Sprite's own shared-canvas convention (same source cell aspect ratio, so
## the same canvas/baseline numbers apply unchanged).
const CANVAS_SIZE := Vector2i(200, 260)
const BASELINE_Y := 250

## Chroma-keyed opaque magenta -- same measured values as
## IllustratedCaterpillarSprite/IllustratedWormSprite (this sheet uses the
## identical background fill).
const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15

## Despill margin -- identical technique and reasoning to
## IllustratedCaterpillarSprite/IllustratedWormSprite/
## IllustratedDecomposerSprite's own, reused verbatim rather than
## reinvented.
const _MAGENTA_CAST_MARGIN := 0.03

## Real-world size: a grass frog's body reads bigger than a caterpillar/
## worm/millipede (IllustratedCaterpillarSprite.WORLD_LENGTH_TILES is 0.32)
## but nowhere near a mouse-or-larger quadruped -- bounded a little above
## their band rather than exact-matched, since there is no earlier
## ProceduralGrassFrogSprite to preserve continuity with (this is a brand
## new creature, not an art-only swap). Pinned by
## test_world_scale_reads_as_a_small_creature_bigger_than_a_caterpillar,
## not eyeballed.
const WORLD_LENGTH_TILES := 0.4
const TILE_SIZE := 16.0

var _slicer := SpriteSheetSlicer.new()

## Keyed by action, shared across instances -- every grass frog drawing the
## same action reuses the identical sliced frames (mirrors
## IllustratedCaterpillarSprite._frame_cache).
static var _frame_cache: Dictionary = {}
static var _keyed_image_cache: Image = null
static var _reference_width_cache := -1.0


func has_action(action: String) -> bool:
	return _ROW_FOR_ACTION.has(action)


## The registered frames for `action`, sliced+normalized once and cached
## thereafter. Empty for anything has_action would reject.
func generate_textures(action: String) -> Array[ImageTexture]:
	if not has_action(action):
		return []
	if not _frame_cache.has(action):
		_frame_cache[action] = _build_textures(action)
	return _frame_cache[action]


func _build_textures(action: String) -> Array[ImageTexture]:
	var image := _keyed_image()
	var row: int = _ROW_FOR_ACTION[action]
	var frames: Array[Rect2i] = []
	for col in _COLUMNS:
		frames.append(Rect2i(col * _CELL_SIZE.x, row * _CELL_SIZE.y, _CELL_SIZE.x, _CELL_SIZE.y))
	var textures: Array[ImageTexture] = []
	for frame_image in _slicer.normalize_frames(image, frames, CANVAS_SIZE, BASELINE_Y):
		# A second, final cleanup pass over each already-cropped-and-resized
		# SMALL frame -- SpriteSheetSlicer's own crop+resize can still ring a
		# few output pixels back toward a magenta cast even once the SOURCE
		# sheet has been despilled above (same reasoning as
		# IllustratedCaterpillarSprite._build_textures).
		_despill_image(frame_image)
		textures.append(ImageTexture.create_from_image(frame_image))
	return textures


func _keyed_image() -> Image:
	if _keyed_image_cache == null:
		_keyed_image_cache = _prepared_for_slicing(SpriteSheetLoader.load_image(_SHEET_PATH))
	return _keyed_image_cache


## Makes the sheet's magenta background genuinely transparent, and despills
## the magenta cast baked into every antialiased edge around it, before the
## image ever reaches SpriteSheetSlicer -- mirrors
## IllustratedCaterpillarSprite._prepared_for_slicing exactly.
func _prepared_for_slicing(image: Image) -> Image:
	var prepared := image.duplicate() as Image
	if prepared.get_format() != Image.FORMAT_RGBA8:
		prepared.convert(Image.FORMAT_RGBA8)
	for y in prepared.get_height():
		for x in prepared.get_width():
			var pixel := prepared.get_pixel(x, y)
			if _is_magenta(pixel):
				prepared.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
			else:
				prepared.set_pixel(x, y, _despilled(pixel))
	return prepared


func _despill_image(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, _despilled(pixel))


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX


## `color` with any magenta-direction cast removed -- identical technique to
## IllustratedCaterpillarSprite._despilled. A pixel with no cast (a genuine
## dark tone) passes through completely unchanged.
static func _despilled(color: Color) -> Color:
	var cast: float = minf(color.r - color.g, color.b - color.g)
	if cast <= _MAGENTA_CAST_MARGIN:
		return color
	var removed := cast - _MAGENTA_CAST_MARGIN
	return Color(
		clampf(color.r - removed, 0.0, 1.0), color.g,
		clampf(color.b - removed, 0.0, 1.0), color.a
	)


## How much to scale a CANVAS_SIZE-normalized frame so it reads at
## WORLD_LENGTH_TILES on screen. ONE shared scale across every action (not a
## per-action marker_scale the way IllustratedDecomposerSprite measures for
## genuinely different-sized species/poses): a grass frog is the same
## creature at the same real length whether it's idling, hopping, eating or
## croaking. Measured off "idle" specifically: a settled resting pose is the
## one action guaranteed to represent the frog's own resting length, unlike
## "hop"'s stretched mid-leap extension.
func world_scale() -> float:
	return (WORLD_LENGTH_TILES * TILE_SIZE) / _reference_width()


func _reference_width() -> float:
	if _reference_width_cache > 0.0:
		return _reference_width_cache
	var frame: Image = generate_textures("idle")[0].get_image()
	var min_x := frame.get_width()
	var max_x := -1
	for y in frame.get_height():
		for x in frame.get_width():
			if frame.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	_reference_width_cache = float(max_x - min_x + 1) if max_x >= min_x else float(CANVAS_SIZE.x)
	return _reference_width_cache
