extends RefCounted

## Real illustrated art for the boot intro splash (see
## docs/concept/intro_splash.md, IntroSplashSequencer, scenes/
## intro_splash.gd). Same "hand/AI-illustrated sheet -> SpriteSheetSlicer
## -> cached frames" shape as IllustratedWormSprite, IllustratedDecomposer
## Sprite etc.
##
## assets/sprites/intro.png is 1672x941 -- a 10-column x 5-row contact
## sheet, NOT evenly divisible by that grid (1672/10=167.2, 941/5=188.2).
## Rather than assume arithmetic division (would misalign later frames by
## several pixels, compounding row to row), both the row tops AND the column
## left edges below are measured directly off the file and pinned here as
## real, confirmed constants, with tests that re-measure them every run.
##
## Every one of the 50 frames is cropped to the SAME fixed-size window
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

## The sheet is a CONTACT SHEET: 10 columns x 5 rows of frames drawn on
## black, separated by thin light grid lines, with its own timestamp
## ("0.00s" ... "4.90s", 10fps) printed inside the top of every cell.
## Measured against the file on disk, never divided arithmetically: the
## drawn lines drift up to 2px from an even 1672/10 split, which at this
## cell size is a visible wobble.
##
## 10x5, not the 20x6 this used to say. The sheet was replaced a third time
## ("bump resolution", 2026-09-17) with half as many frames at twice the
## size, and nothing re-measured -- so every crop was taken from a window
## that had not existed since the swap, which is what "the intro still
## doesn't have the correct frame crops" was. The grid is now tied to the
## file by test_the_frame_count_is_exactly_the_grid_the_sheet_really_has as
## well as by the two that compare these arrays, so a fourth swap cannot
## leave the count behind.
##
## Re-measure whenever the art changes. test_the_pinned_grid_is_where_the_
## sheets_own_cells_actually_are compares these against the real file every
## run, so the next swap fails there instead of shipping.
## Each is the first pixel AFTER its divider ends, not the divider's own
## centre: a drawn line is 1-3px wide, and a crop that starts inside one
## carries that ink in its own first column.
const _COLUMN_LEFTS: Array[int] = [
	0, 173, 340, 506, 672, 837, 1003, 1169, 1335, 1502,
]
const _ROW_TOPS: Array[int] = [0, 194, 381, 576, 756]

## How light a line has to be at its DARKEST pixel to be one of the sheet's
## own grid lines rather than content. A line is drawn across everything, so
## every pixel along it is light; content always has some black in it. A
## MEAN cannot tell them apart -- by the end of this animation the globe is
## brighter than the dividers -- which is why the measurement, and the test
## that re-checks it, both key on the minimum.
const DIVIDER_BRIGHTNESS := 0.18

## The timestamp caption printed inside each cell's top edge. Measured: the
## ink occupies rows 11..21 of every cell, and the earliest globe pixel in
## any cell is row 40, so 28 clears the caption with margin and takes
## nothing from the art. Cropping from the cell's own top instead puts
## "0.04s" on screen over the globe.
const _CAPTION_HEIGHT := 28

## One pixel in from every measured cell edge. The drawn lines are not a
## uniform width down their length -- measured at column 9, the divider is
## 2px (0.52 and 0.76 bright) where the line-minimum detector reads it as
## 1px, because further down it fades under the threshold -- so a crop that
## starts exactly at the measured edge carries that second pixel as a bright
## stripe up its own side. One pixel of margin costs nothing and cannot be
## caught out by a line that thickens somewhere this did not sample.
const _CELL_INSET := 1

## ONE fixed crop, shared by all 50 frames -- no per-frame content
## detection (see this file's own doc comment for why). Both are bounded by
## the CLEAN extent of the tightest cell -- from its own start to where the
## next divider begins, not to where the next cell starts -- less the inset
## above, and for the height less the caption too.
##
## Measured on the sheet on disk: the clean cell widths are
## 172/165/164/164/164/164/164/164/165/170, so the tightest is 164 and the
## window is 163 wide; the clean cell heights are 192/185/194/178/185, so
## the tightest is 178 and the window is 178 - 28 - 1 = 149 tall. Every cell
## can supply that same window from the same offset, which is what keeps the
## globe still from frame to frame.
const _FRAME_WIDTH := 163
const _FRAME_HEIGHT := 149

## Chroma-keyed opaque magenta, the convention every other illustrated
## sheet in this codebase uses. The sheet delivered on 2026-09-17 does NOT:
## it is drawn on black, so nothing is keyed out of it and the build path
## no longer prepares or despills anything. This stays as the tripwire --
## test_frames_have_no_leftover_magenta_background still runs, so a future
## magenta-backed sheet fails there rather than shipping with its own
## background painted into every frame.
const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15

static var _frame_cache: Array[ImageTexture] = []


## Every frame in play order (row 0 left-to-right, then row 1, ...),
## sliced+despilled once and cached thereafter.
func generate_textures() -> Array[ImageTexture]:
	if _frame_cache.is_empty():
		_frame_cache = _build_textures()
	return _frame_cache


func _build_textures() -> Array[ImageTexture]:
	var image := SpriteSheetLoader.load_image(_SHEET_PATH)
	if image == null:
		return []
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var textures: Array[ImageTexture] = []
	for top in _ROW_TOPS:
		for left in _COLUMN_LEFTS:
			# A plain region from a fixed offset inside the cell: past the
			# caption, and the same window everywhere so nothing rescales
			# or drifts between frames.
			textures.append(ImageTexture.create_from_image(
				image.get_region(Rect2i(
					left + _CELL_INSET, top + _CAPTION_HEIGHT, _FRAME_WIDTH, _FRAME_HEIGHT
				))
			))
	return textures


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX
