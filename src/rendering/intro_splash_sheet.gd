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
## assume arithmetic division (would misalign later frames by several
## pixels, compounding row to row), both the row bands AND the column left
## edges below were measured directly with tools/probe_intro_sheet.gd and
## a dedicated verification probe (throwaway, since deleted -- see bug #6
## below) and are pinned here as real, confirmed constants.
##
## Every one of the 32 frames is cropped to the SAME fixed-size window
## (_FRAME_WIDTH x _FRAME_HEIGHT), anchored at its own row's top and its
## own column's left edge -- deliberately NOT SpriteSheetSlicer.
## detect_frames' own per-frame CONTENT-based crop, which this file used
## until bug #6 (2026-09-09, see docs/concept/intro_splash.md). That
## crop measured each frame's own left/right content boundary
## independently, and while the underlying 8-column GRID itself turned out
## to already be fixed (row 0, 2 and 3 each independently re-detect the
## identical column lefts pinned below), the RIGHT edge drifted by up to
## 2px frame to frame -- driven by the light-streak sweep and the growing
## "ALEPH ALPHA" wordmark's own ink extent, both of which are real content
## that varies in exactly the columns detect_frames scans, even though the
## globe itself sits at a consistent position/size in every frame by
## construction (see the intro-generation prompt). IntroSplash's own
## TextureRect (STRETCH_KEEP_ASPECT_COVERED + EXPAND_IGNORE_SIZE) scales
## and re-centers each frame independently based on that frame's own size,
## so a couple pixels of source-crop instability, magnified by the ~5.5x
## this sheet gets stretched by at the project's default 1280x720
## viewport, read as visible on-screen "wobble" -- confirmed both by
## direct measurement (widths ranged 232-234px, heights stepped
## 181/183/182/182px across the 32 frames) and by rendering the actual
## STRETCH_KEEP_ASPECT_COVERED transform for a consecutive run of frames.
##
## A single fixed crop window per frame -- same width, same height, no
## per-frame content detection at all -- removes that instability at the
## source rather than trying to re-stabilize a content-based measurement.
## See test_every_frame_is_the_same_size (tests/unit/
## test_intro_splash_sheet.gd) for the regression coverage, confirmed red
## against the old per-frame detect_frames crop before this fix.
##
## Frames are extracted as PLAIN regions, not run through
## SpriteSheetSlicer.normalize_frames -- see this file's own test's doc
## comment for why: normalize_frames' shared-scale-from-widest-content
## behaviour would make the globe itself appear to change size as the
## "ALEPH ALPHA" wordmark's own ink extent grows across the sequence,
## which the source art's consistently-framed camera (same globe position/
## size in every frame, by construction -- see the intro-generation
## prompt) doesn't need fixed up at all. Do NOT reintroduce
## normalize_frames here -- this is a real, deliberate divergence from
## every other illustrated-sheet consumer, not an oversight.

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

const _SHEET_PATH := "res://assets/sprites/intro.png"

## [top_y, bottom_y) per row, top to bottom exactly as drawn -- measured,
## not eyeballed (see this file's own doc comment above). Only top_y (each
## band's own `.x`) is actually used as a crop anchor now; bottom_y still
## documents the real measured row extent and drives _FRAME_HEIGHT's own
## derivation below.
const _ROW_BANDS: Array[Vector2i] = [
	Vector2i(12, 193),
	Vector2i(206, 389),
	Vector2i(402, 584),
	Vector2i(598, 780),
]

## Left edge (source-image space) of each of the 8 columns, identical
## across all 4 rows by construction -- the AI drew one consistent column
## grid, reused for every row. Measured from row 0 (SpriteSheetSlicer.
## detect_frames on its own row band): the one row with neither the
## light-streak sweep nor any wordmark ink yet, so nothing biases a
## content-based measurement. Rows 2 and 3 independently re-detect this
## EXACT same array; only row 1 (mid-sequence, both streak and the first
## wordmark letters already present) drifts by 1px at a single column --
## see test_column_lefts_match_a_content_free_measurement for the
## regression check against the real image.
const _COLUMN_LEFTS: Array[int] = [13, 259, 506, 752, 998, 1245, 1492, 1739]

## ONE fixed crop size, used for every one of the 32 frames -- no
## per-frame content cropping (see this file's own doc comment above for
## why). _FRAME_WIDTH is comfortably larger than the widest content any
## frame's own OLD per-frame detect_frames crop ever measured (234px,
## across all 32 frames) and comfortably smaller than the tightest real
## column pitch (246px, the minimum left-to-left gap among _COLUMN_LEFTS)
## so it can never bleed into the next column. _FRAME_HEIGHT is the
## tallest of the 4 hand-measured _ROW_BANDS (row 1, 183px) -- already
## the height every row-1 frame used even before this fix, so this only
## extends the other 3 rows a further 1-2px down into their own real,
## measured inter-row gutter (13-14px, see _ROW_BANDS), never into
## another row's content. Both bounds are re-verified against the real
## sheet by test_frame_size_has_real_safety_margins, not just claimed in
## this comment (see CLAUDE.md: tuned thresholds must be tested, not
## eyeballed).
const _FRAME_WIDTH := 240
const _FRAME_HEIGHT := 183

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
		for left in _COLUMN_LEFTS:
			var rect := Rect2i(left, band.x, _FRAME_WIDTH, _FRAME_HEIGHT)
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
