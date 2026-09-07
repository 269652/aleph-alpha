extends RefCounted

## Real illustrated art for the boot intro splash (see
## docs/concept/intro_splash.md, IntroSplashSequencer, scenes/
## intro_splash.gd). Same "hand/AI-illustrated sheet -> SpriteSheetSlicer
## -> cached frames" shape as IllustratedWormSprite, IllustratedDecomposer
## Sprite etc.
##
## assets/sprites/intro.png is 1983x793 -- AI-generated against an 8-column
## x 4-row prompt, but NOT evenly divisible by that grid (1983/8=247.875,
## 793/4=198.25), unlike worm.png's genuinely regular grid. Rather than
## either assume arithmetic division (would misalign later frames by
## several pixels, compounding row to row) or run the whole sheet through
## SpriteSheetSlicer.detect_frames blind (that function only finds COLUMN
## dividers within an already-known row band -- see its own doc comment),
## the 4 row bands below were measured directly with
## tools/probe_intro_sheet.gd (a row-wise analogue of detect_frames' own
## column scan) and are pinned here as real, confirmed constants -- the
## same "hand-measure the row bands, detect_frames for columns within one"
## two-step this project's other illustrated sheets already use.
##
## Frames are extracted as PLAIN regions, not run through
## SpriteSheetSlicer.normalize_frames -- see this file's own test's doc
## comment for why: normalize_frames' shared-scale-from-widest-content
## behaviour would make the globe itself appear to change size as the
## "ALEPH ALPHA" wordmark's own ink extent grows across the sequence,
## which the source art's consistently-framed camera (same globe position/
## size in every frame, by construction -- see the intro-generation
## prompt) doesn't need fixed up at all.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

const _SHEET_PATH := "res://assets/sprites/intro.png"

## [top_y, bottom_y) per row, top to bottom exactly as drawn -- measured,
## not eyeballed (see this file's own doc comment above).
const _ROW_BANDS: Array[Vector2i] = [
	Vector2i(12, 193),
	Vector2i(206, 389),
	Vector2i(402, 584),
	Vector2i(598, 780),
]

## Chroma-keyed opaque magenta -- identical thresholds to every other
## illustrated sheet in this codebase (e.g. IllustratedWormSprite),
## confirmed against this sheet's own corner pixel with
## tools/probe_intro_sheet.gd.
const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15

## Despill margin -- identical technique and reasoning to
## IllustratedWormSprite._despilled/IllustratedDecomposerSprite's own,
## reused verbatim rather than reinvented (this codebase's own established
## convention: this exact small technique is already duplicated across
## seven illustrated-sheet classes rather than pulled into a shared
## utility).
const _MAGENTA_CAST_MARGIN := 0.03

var _slicer := SpriteSheetSlicer.new()

static var _frame_cache: Array[ImageTexture] = []


## Every frame in play order (row 0 left-to-right, then row 1, ...),
## sliced+despilled once and cached thereafter.
func generate_textures() -> Array[ImageTexture]:
	if _frame_cache.is_empty():
		_frame_cache = _build_textures()
	return _frame_cache


func _build_textures() -> Array[ImageTexture]:
	var image := _prepared_for_slicing(SpriteSheetLoader.load_image(_SHEET_PATH))
	var textures: Array[ImageTexture] = []
	for band in _ROW_BANDS:
		var frames := _slicer.detect_frames(image, band.x, band.y)
		for rect in frames:
			var frame_image := image.get_region(rect)
			if frame_image.get_format() != Image.FORMAT_RGBA8:
				frame_image.convert(Image.FORMAT_RGBA8)
			textures.append(ImageTexture.create_from_image(frame_image))
	return textures


## Makes the sheet's magenta background genuinely transparent, and
## despills the magenta cast baked into every antialiased edge around it,
## before the image ever reaches SpriteSheetSlicer -- mirrors
## IllustratedWormSprite._prepared_for_slicing exactly.
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


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX


## `color` with any magenta-direction cast removed -- identical technique
## to IllustratedWormSprite._despilled. A pixel with no cast (a genuine
## dark tone -- the sheet's own starfield/space background) passes through
## completely unchanged.
static func _despilled(color: Color) -> Color:
	var cast: float = minf(color.r - color.g, color.b - color.g)
	if cast <= _MAGENTA_CAST_MARGIN:
		return color
	var removed := cast - _MAGENTA_CAST_MARGIN
	return Color(
		clampf(color.r - removed, 0.0, 1.0), color.g,
		clampf(color.b - removed, 0.0, 1.0), color.a
	)
