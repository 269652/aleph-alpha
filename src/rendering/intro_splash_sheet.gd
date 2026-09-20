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

## Where each cell's clean content ENDS -- the last pixel before the next
## divider begins, and the sheet's own last row/column for the final one.
## Measured off the file exactly as _ROW_TOPS/_COLUMN_LEFTS are, and
## re-measured every run by test_the_pinned_grid_is_where_the_sheets_own_
## cells_actually_are.
##
## Needed because the cells are NOT on a pitch: the clean widths run
## 171/165/164/164/163/164/163/163/165/170 and the clean heights
## 192/185/193/178/185, and the picture inside each cell fills its own cell
## edge to edge (measured: at every cell, content reaches all four edges).
## A cell is therefore the same drawing at its own cell's size, and reading
## a FIXED window out of a varying cell is what made the first column and
## the last jump sideways -- see _ROW_DRAWN_SCALE.
const _COLUMN_RIGHTS: Array[int] = [
	170, 337, 503, 669, 834, 1000, 1165, 1331, 1499, 1671,
]
const _ROW_BOTTOMS: Array[int] = [191, 378, 573, 753, 940]

## The one size every cell is resampled to before anything else is done to
## it, which is what takes the cells' own differing sizes out of the
## picture. Close to the cells' own median (166 x 160 against clean cells of
## 163-171 by 148-165 past the caption), so no cell is resampled far from
## 1:1.
const _CELL_WIDTH := 166
const _CELL_HEIGHT := 160

## How big the art is drawn in each ROW of the contact sheet, relative to
## row 1, and where that row puts the earth's centre in the resampled cell.
##
## Reported live after every earlier stabilisation pass had shipped: *"Can
## you properly stabilize the intro animation? The earth should be scaled
## and stabilised so there's no jitter and zooming"*.
##
## This sheet is DRAWN by an image model, not rendered as a video and cut
## up, and nothing made it draw the earth at one size across all five rows.
## Measured before changing anything (tools/probe_intro_stability.gd): of
## the 49 transitions between consecutive frames, the 45 that stay inside a
## contact-sheet row move the picture by at most 1px and rescale it by at
## most 0.5% -- and the 4 that cross a row boundary move it 4.5-9px and
## rescale it by up to 6%. The earth shrinks about 4% per row and climbs the
## cell as it goes; at 10fps with 10 frames to a row, that is a lurch once
## every second, which is exactly what was reported.
##
## That is also why no earlier pass fixed it. Passes eight through twelve
## each corrected the pipeline -- the upscale factor, the texture filter,
## the crop window, the display size -- and every one of them was a real
## fix. None of them could have worked: the wobble is in the picture, not in
## where it was cut.
##
## Measured by registering each row's cells against the row above, same
## column, ten frames apart (the earth is still by then, so anything that
## moves is the sheet and not the animation): the steps came out 1.015,
## 1.040 and 1.060 in scale with 3, 5 and 8px of vertical drift, tight to
## +/-0.005 and +/-1px across all seven interior columns. Composed into a
## per-row correction and re-measured, the residual steps are 0.990, 1.010
## and 0.995 with at most 1px of drift. Pinned by
## test_the_picture_does_not_jump_where_the_sheet_changes_row, which
## re-measures the real frames rather than trusting these numbers.
##
## Row 0 takes row 1's: the earth is still arriving through the whole of
## row 0, so the one measurable step into row 1 carries a frame of real
## animation as well as the sheet's own offset and the two cannot be told
## apart. Whatever is left of it lands inside the one second where the earth
## is deliberately moving fast, which is the only second of the five where a
## few pixels do not read as a lurch.
const _ROW_DRAWN_SCALE: Array[float] = [1.0, 1.0, 1.0200, 1.0446, 1.1184]
const _ROW_EARTH_ANCHOR: Array[Vector2] = [
	Vector2(83.0, 80.0),
	Vector2(83.0, 80.0),
	Vector2(84.0, 83.0),
	Vector2(82.1, 77.3),
	Vector2(81.2, 67.5),
]

## The frame every cell is finally laid into, earth's centre at its centre.
##
## Unchanged at 163 x 149 -- the size the display's own integer scale is
## built on (IntroSplash.DISPLAY_SCALE) -- but it is now a CANVAS rather
## than a crop window: the corrected cell is drawn into it centred on the
## earth, and whatever falls outside is black space and glow at the
## picture's edge, never the earth. Checked: at this size the earth's own
## lit band spans 131-141 px of the 149 in every row, so every row keeps at
## least 4px of margin above and below it.
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
	for row in _ROW_TOPS.size():
		for column in _COLUMN_LEFTS.size():
			textures.append(ImageTexture.create_from_image(_frame_image(image, row, column)))
	return textures


## One frame: the cell's own clean content, resampled to a common size, then
## corrected for how big THIS row drew the earth and where it put it, then
## laid into the frame canvas with the earth's centre at the centre.
##
## Three steps rather than one crop, because there are three different
## things wrong with reading a fixed window out of this sheet, and each step
## answers exactly one of them:
##
## 1. The cells are not the same size (171 wide for the first column against
##    163 for the fifth), and each holds the same drawing at its own cell's
##    size. Resampling every clean cell to one size removes that, and it is
##    what fixed the sideways jump on the first column of every row --
##    measured at 4.5-5.5px before, at most 2px after.
## 2. Each ROW drew the earth at its own size and height (_ROW_DRAWN_SCALE).
##    Scaling by that row's own factor removes the once-a-second lurch.
## 3. What is left is centred on the EARTH rather than on the cell, so the
##    thing the eye tracks is the thing that is held still.
func _frame_image(sheet: Image, row: int, column: int) -> Image:
	var left := _COLUMN_LEFTS[column] + _CELL_INSET
	var top := _ROW_TOPS[row] + _CAPTION_HEIGHT
	var cell := sheet.get_region(Rect2i(
		left, top,
		_COLUMN_RIGHTS[column] - _CELL_INSET - left + 1,
		_ROW_BOTTOMS[row] - _CELL_INSET - top + 1
	))
	var drawn_scale := _ROW_DRAWN_SCALE[row]
	cell.resize(
		int(round(_CELL_WIDTH * drawn_scale)),
		int(round(_CELL_HEIGHT * drawn_scale)),
		Image.INTERPOLATE_LANCZOS
	)
	if cell.get_format() != Image.FORMAT_RGBA8:
		cell.convert(Image.FORMAT_RGBA8)
	var frame := Image.create(_FRAME_WIDTH, _FRAME_HEIGHT, false, Image.FORMAT_RGBA8)
	frame.fill(Color(0.0, 0.0, 0.0, 1.0))
	var anchor := _ROW_EARTH_ANCHOR[row] * drawn_scale
	var offset := Vector2i(
		int(round(_FRAME_WIDTH * 0.5 - anchor.x)), int(round(_FRAME_HEIGHT * 0.5 - anchor.y))
	)
	# Only the part that lands inside the canvas -- worked out here rather
	# than left to blit_rect, so a row whose correction pushes the cell past
	# an edge loses that edge cleanly instead of depending on how the engine
	# clips a negative destination.
	var source := Rect2i(
		maxi(0, -offset.x), maxi(0, -offset.y),
		mini(cell.get_width() - maxi(0, -offset.x), _FRAME_WIDTH - maxi(0, offset.x)),
		mini(cell.get_height() - maxi(0, -offset.y), _FRAME_HEIGHT - maxi(0, offset.y))
	)
	if source.size.x > 0 and source.size.y > 0:
		frame.blit_rect(cell, source, Vector2i(maxi(0, offset.x), maxi(0, offset.y)))
	return frame


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX
