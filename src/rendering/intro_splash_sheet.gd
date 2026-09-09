extends RefCounted

## Real illustrated art for the boot intro splash (see
## docs/concept/intro_splash.md, IntroSplashSequencer, scenes/
## intro_splash.gd). Same "hand/AI-illustrated sheet -> SpriteSheetSlicer
## -> cached frames" shape as IllustratedWormSprite, IllustratedDecomposer
## Sprite etc.
##
## assets/sprites/intro.png is 1983x793 -- AI-generated, currently a
## 9-column x 5-row grid (a fifth row -- a pure sparkle/starburst
## flourish, no globe -- and a ninth column, added in the same real-art
## pass on top of the original 8x4/32-frame layout: see docs/concept/
## intro_splash.md's "A fifteenth pass"), NOT evenly divisible by that
## grid (1983/9=220.3, 793/5=158.6), unlike worm.png's genuinely regular
## grid. Rather than assume arithmetic division (would misalign later
## frames by several pixels, compounding row to row), both the row bands
## AND the column left edges below were measured directly with
## tools/probe_intro_sheet.gd (fully generic -- detects row/column
## boundaries from the real image rather than assuming a row/column count,
## so it needed no changes at all to re-measure the new 5-row layout) and
## are pinned here as real, confirmed constants.
##
## Every one of the 45 frames is cropped to the SAME fixed-size window
## (_FRAME_WIDTH x _FRAME_HEIGHT), anchored at its own row's top and its
## own column's left edge -- deliberately NOT SpriteSheetSlicer.
## detect_frames' own per-frame CONTENT-based crop, which this file used
## until bug #6 (2026-09-09, see docs/concept/intro_splash.md). That
## crop measured each frame's own left/right content boundary
## independently, and while the underlying column GRID itself turned out
## to already be fixed (multiple rows independently re-detect the
## identical column lefts pinned below), the RIGHT edge drifted frame to
## frame -- driven by the light-streak sweep and the growing "ALEPH
## ALPHA" wordmark's own ink extent, both of which are real content that
## varies in exactly the columns detect_frames scans, even though the
## globe itself sits at a consistent position/size in every frame by
## construction (see the intro-generation prompt). IntroSplash's own
## TextureRect (STRETCH_KEEP_ASPECT_COVERED + EXPAND_IGNORE_SIZE) scales
## and re-centers each frame independently based on that frame's own size,
## so a couple pixels of source-crop instability, magnified by the real
## stretch factor this sheet gets at the project's default 1280x720
## viewport, read as visible on-screen "wobble" -- confirmed both by
## direct measurement of the original 32-frame sheet (widths ranged
## 232-234px, heights stepped 181/183/182/182px) and by rendering the
## actual STRETCH_KEEP_ASPECT_COVERED transform for a consecutive run of
## frames.
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
## derivation below. 5 real bands -- tools/probe_intro_sheet.gd's own row
## detector found a 6th, (792, 793), a single stray 1px sliver at the very
## bottom edge with 0 real column frames in it (not a real row -- excluded
## here, the same "sanity-check the detector, don't trust it blindly"
## discipline this sheet's own history already established).
const _ROW_BANDS: Array[Vector2i] = [
	Vector2i(10, 157),
	Vector2i(165, 311),
	Vector2i(319, 467),
	Vector2i(475, 626),
	Vector2i(634, 783),
]

## Left edge (source-image space) of each of the 9 columns, identical
## across all 5 rows by construction -- the AI drew one consistent column
## grid, reused for every row (re-measured directly with tools/
## probe_intro_sheet.gd: every one of the 5 real row bands independently
## detects this exact same array).
const _COLUMN_LEFTS: Array[int] = [10, 244, 470, 696, 922, 1148, 1365, 1578, 1780]

## ONE fixed crop size, used for every one of the 45 frames -- no
## per-frame content cropping (see this file's own doc comment above for
## why). Real per-frame content width ranged 194-226px across the sheet
## (widest at column 0, narrowest at columns 7-8 -- tools/probe_intro_
## sheet.gd's own detect_frames pass) and the tightest real column pitch
## is 202px (columns 7->8; the sheet's own right edge leaves column 8
## slightly more, 203px) -- so _FRAME_WIDTH sits below BOTH the tightest
## pitch (never bleeds into the next column) and, confirmed by rendering
## actual cropped swatches at 195px for the widest/narrowest columns on
## every row (a real visual check, not just these numbers -- the globe,
## every sparkle point, and the wordmark text all sit comfortably inside
## 195px with real margin to spare; a shorter crop than the raw 226px
## widest-content number is genuinely safe here, unlike the original
## 32-frame sheet where widest-content-plus-margin comfortably UNDERCUT
## the tightest pitch instead). _FRAME_HEIGHT is the tallest of the 5
## hand-measured _ROW_BANDS (row 3, 151px) -- already the height every
## row-3 frame used even before this fix, so this only extends the other
## 4 rows a further few px down into their own real, measured inter-row
## gutter, never into another row's content. Both bounds are re-verified
## against the real sheet by test_frame_width_fits_within_the_tightest_
## real_column_pitch/test_frame_height_fits_within_the_tightest_real_row_
## gap, not just claimed in this comment (see CLAUDE.md: tuned thresholds
## must be tested, not eyeballed).
const _FRAME_WIDTH := 195
const _FRAME_HEIGHT := 151

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
