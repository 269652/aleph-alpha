extends RefCounted

## Real illustrated art for the earthworm's four animations (see
## EarthwormPatch, docs/concept/soil_fauna.md's "Illustrated worm sprite:
## crawl, emerge, retreat, die"), replacing ProceduralWormSprite's drawn
## silhouette and the region-rect emergence-reveal trick with real
## per-row frame animation. Same "hand-drawn sheet -> SpriteSheetSlicer ->
## cached frames" shape as IllustratedDecomposerSprite, deliberately NOT
## built on IllustratedAnimalSprite: a worm carries no CreatureMarker/
## AnimalAnatomy stack at all (see EarthChunkManager's own doc comment --
## every surfaced worm is a bare Sprite2D it manages directly), so this
## class needs none of that stack's per-species profile machinery.
##
## One sheet, one worm -- unlike ants/bugs/sheep/wolf there is only ever
## one kind of worm in this game, so this class skips the species
## dimension IllustratedDecomposerSprite/IllustratedAnimalSprite both
## carry and keys everything by action alone.
##
## worm.png is a perfectly regular 8-column x 4-row grid (1536x1024,
## 192x256 per cell -- confirmed with tools/probe_worm_sheet.gd), sliced
## directly from that KNOWN fixed grid rather than through
## SpriteSheetSlicer.detect_frames' content-gap heuristic: the early
## coiled-worm poses in the "die" row have an internal notch (the loop
## against the body, ~8-13px) that misreads as a second frame boundary
## under detect_frames' default divider width -- the same class of bug
## IllustratedBirdSprite's own "sing" row hit with its radiating
## sound-lines -- but unlike that row, no single min_divider_width both
## bridges the internal notch and still separates real cells here, since
## this sheet's own real inter-cell gaps range from ~1px (a pose that
## fills its whole cell edge to edge) up to 30+px (a smaller pose with
## real padding around it) -- narrower in places than the false notch is
## wide. Since the grid itself is exactly regular, slicing it directly
## sidesteps the problem entirely: normalize_frames finds each frame's
## own tight content bounding box regardless of whether the outer rect it
## is given came from content detection or, as here, from grid
## arithmetic. All 32 cells were confirmed to hold real, non-blank
## content this way before this class shipped.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

const _SHEET_PATH := "res://assets/sprites/animals/worm.png"
const _COLUMNS := 8
const _CELL_SIZE := Vector2i(192, 256)

## Row index for each named action, top to bottom exactly as drawn.
const _ROW_FOR_ACTION := {
	"crawl": 0,
	"emerge": 1,
	"retreat": 2,
	"die": 3,
}

## The canvas every sliced frame is normalized onto, its feet landing on
## the same BASELINE_Y regardless of action -- mirrors
## IllustratedDecomposerSprite/IllustratedAnimalSprite's own shared-canvas
## convention exactly.
const CANVAS_SIZE := Vector2i(200, 260)
const BASELINE_Y := 250

## Chroma-keyed opaque magenta -- measured directly from the sheet's own
## cell-interior background (not its corners/gutters, which carry a thin
## near-white divider line SpriteSheetSlicer's own is_empty already
## treats as background separately -- see tools/probe_worm_sheet.gd).
const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15

## Despill margin -- identical technique and reasoning to
## IllustratedDecomposerSprite._despilled/_MAGENTA_CAST_MARGIN, reused
## verbatim rather than reinvented.
const _MAGENTA_CAST_MARGIN := 0.03

## Real-world size: matches ProceduralWormSprite's own intended length
## exactly, so switching to real art is a pure art upgrade, not a sudden
## size change -- the same reasoning already applied when ants/bugs/
## sheep/wolf switched over.
const WORLD_LENGTH_TILES := 0.32
const TILE_SIZE := 16.0

var _slicer := SpriteSheetSlicer.new()

## Keyed by action, shared across instances -- every worm drawing the same
## action reuses the identical sliced frames (mirrors
## IllustratedDecomposerSprite._frame_cache).
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
		# IllustratedDecomposerSprite._build_textures).
		_despill_image(frame_image)
		textures.append(ImageTexture.create_from_image(frame_image))
	return textures


func _keyed_image() -> Image:
	if _keyed_image_cache == null:
		_keyed_image_cache = _prepared_for_slicing(SpriteSheetLoader.load_image(_SHEET_PATH))
	return _keyed_image_cache


## Makes the sheet's magenta background genuinely transparent, and
## despills the magenta cast baked into every antialiased edge around it,
## before the image ever reaches SpriteSheetSlicer -- mirrors
## IllustratedDecomposerSprite._prepared_for_slicing exactly.
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


## `color` with any magenta-direction cast removed -- identical technique
## to IllustratedDecomposerSprite._despilled. A pixel with no cast (a
## genuine dark tone) passes through completely unchanged.
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
## WORLD_LENGTH_TILES on screen. ONE shared scale across every action
## (not a per-action marker_scale the way IllustratedDecomposerSprite
## measures for genuinely different-sized species/poses): a worm is the
## same creature at the same real length whether it's crawling, emerging
## or retreating, and the "die" row's own progressive widening is exactly
## the animation this must NOT scale away -- normalize_frames already
## preserves each row's own relative frame sizes internally (one scale per
## row batch, not per frame), so layering one more flat calibration on top
## keeps a squashing worm reading as the same creature getting visibly
## flatter, not as a creature that changes size when the game switches
## which row it's drawing from. Measured off "crawl" specifically: a
## steady loop is the one action guaranteed to represent the worm's own
## resting length, unlike "emerge"/"retreat" whose own frame 0 can be a
## bare nose or an almost-buried tail.
func world_scale() -> float:
	return (WORLD_LENGTH_TILES * TILE_SIZE) / _reference_width()


func _reference_width() -> float:
	if _reference_width_cache > 0.0:
		return _reference_width_cache
	var frame: Image = generate_textures("crawl")[0].get_image()
	var min_x := frame.get_width()
	var max_x := -1
	for y in frame.get_height():
		for x in frame.get_width():
			if frame.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	_reference_width_cache = float(max_x - min_x + 1) if max_x >= min_x else float(CANVAS_SIZE.x)
	return _reference_width_cache
