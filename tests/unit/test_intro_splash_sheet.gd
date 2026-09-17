extends GutTest

## Real art for the boot intro splash (assets/sprites/intro.png) -- see
## docs/concept/intro_splash.md's "Re-measuring again: a contact sheet, not
## a sprite sheet".
##
## Unlike every other illustrated sheet in this codebase, this one is not a
## chroma-keyed sprite sheet at all: it is a 1672x941 CONTACT SHEET exported
## straight out of the source animation, 20 columns x 6 rows of 120 frames
## on opaque black, with the export tool's own chrome drawn on top -- a
## light-grey grid line between every pair of cells, and each cell's
## timestamp burned into its top-left corner. So the grid is hand-measured
## from those lines (pinned constants, re-derived here from the real file),
## not assumed by arithmetic division: it divides evenly on neither axis.
##
## Deliberately does NOT run frames through SpriteSheetSlicer.
## normalize_frames the way every other illustrated sheet does:
## normalize_frames picks ONE shared scale from the WIDEST/TALLEST content
## bounding box across the frames it's given, and here the globe grows and
## the "aleph alpha" wordmark builds in across the sequence -- rescaling
## would make the globe itself appear to change size. Frames are extracted
## as plain, un-rescaled regions instead.

const IntroSplashSheet = preload("res://src/rendering/intro_splash_sheet.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const IntroSplashSequencer = preload("res://src/rendering/intro_splash_sequencer.gd")

var sheet: IntroSplashSheet


func before_each():
	sheet = IntroSplashSheet.new()


func test_frame_count_matches_the_sequencer():
	assert_eq(sheet.generate_textures().size(), IntroSplashSequencer.FRAME_COUNT)


func test_every_frame_has_real_content():
	var frames := sheet.generate_textures()
	for i in frames.size():
		assert_true(_has_opaque_pixels(frames[i]), "frame %d is blank" % i)


## NOT the same corner-transparency check test_illustrated_worm_sprite.gd
## uses alongside its own magenta sweep -- confirmed by direct pixel probe
## that several real frames here (the light-streak/starfield reaching a
## cell's own edge) legitimately paint opaque content into their corners,
## unlike a worm silhouette drawn with generous blank padding around it.
## This sheet is meant to fill the WHOLE screen edge to edge, so a full
## sweep for any surviving OPAQUE MAGENTA pixel -- the thing that would
## actually look broken -- is the real invariant, and the only one a
## full-bleed sheet like this one can honestly assert.
func test_frames_have_no_leftover_magenta_background():
	var frames := sheet.generate_textures()
	for i in frames.size():
		var frame: Image = frames[i].get_image()
		var magenta_survivors := 0
		for y in frame.get_height():
			for x in frame.get_width():
				var c := frame.get_pixel(x, y)
				if c.a > 0.5 and c.r >= 0.85 and c.b >= 0.85 and c.g <= 0.15:
					magenta_survivors += 1
		assert_eq(magenta_survivors, 0, "frame %d: no opaque magenta pixel should survive chroma-keying" % i)


## The first frame (no wordmark yet) and the last frame (full wordmark,
## globe rotated) must genuinely differ -- a real animation, not
## a stack of copies of one drawing.
func test_first_and_last_frames_differ():
	var frames := sheet.generate_textures()
	assert_ne(frames[0].get_image().get_data(), frames[frames.size() - 1].get_image().get_data())


## Every frame must differ from its own immediate neighbour
## -- catches a slicing bug that accidentally duplicates a column/row
## boundary (e.g. an off-by-one that reads the same cell twice) even if
## the first-vs-last check above would not.
func test_consecutive_frames_differ():
	var frames := sheet.generate_textures()
	for i in range(frames.size() - 1):
		assert_ne(
			frames[i].get_image().get_data(), frames[i + 1].get_image().get_data(),
			"frame %d and %d are identical" % [i, i + 1]
		)


func test_frames_are_cached_not_rebuilt_per_call():
	var a := sheet.generate_textures()
	var b := sheet.generate_textures()
	assert_same(a[0], b[0])


## Bug #6 (2026-09-09): every frame must be the exact same
## pixel size. IntroSplash's own TextureRect (EXPAND_IGNORE_SIZE +
## STRETCH_KEEP_ASPECT_COVERED, see scenes/intro_splash.gd) scales and
## re-centers EACH frame independently, driven by that frame's own size --
## so if frame sizes differ even by a couple pixels, the effective
## on-screen scale factor and crop-center shift frame to frame, magnified
## by the real ~5.5x this sheet gets stretched by at the project's default
## 1280x720 viewport (project.godot). That reads as visible "wobble".
##
## Confirmed red against the unfixed per-frame CONTENT-based crop
## (SpriteSheetSlicer.detect_frames called once per frame, independently):
## real measured widths ranged 232-234px and heights stepped 181/183/182/
## 182px across the 32 frames (throwaway verification probe, since
## deleted -- mirroring how the prior 5 intro-splash bugs in this file's
## own git history were each verified against real numbers, not trusted
## from a code trace alone). Left edges were separately confirmed to
## already be a stable, fixed 8-column grid (row 0, 2, and 3 independently
## re-detect the IDENTICAL lefts array; only row 1 -- the one row with
## both the light-streak sweep and the first wordmark letters already
## present -- drifted by 1px at a single column), so the crop instability
## was real but entirely in the RIGHT edge/width (content-driven) and, at
## the 3 row-transition points, in height (hand-measured _ROW_BANDS
## differing by 1-2px row to row) -- never in the left edge/column grid
## itself.
func test_every_frame_is_the_same_size():
	var frames := sheet.generate_textures()
	var first_size := frames[0].get_image().get_size()
	for i in frames.size():
		var size := frames[i].get_image().get_size()
		assert_eq(
			size,
			first_size,
			"frame %d is %s, expected %s (frame 0's size) -- unstable geometry reads as wobble once stretched to fill a real viewport" % [i, size, first_size]
		)


func _has_opaque_pixels(texture: Texture2D) -> bool:
	var image := texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				return true
	return false


# -- the pinned grid must match the sheet that is actually on disk --------
#
# Reported in play after the art was replaced a SECOND time: "the intro has
# new resolution please fix the cropping properly".
#
# The replacement is a different KIND of sheet, not just a different size
# (see IntroSplashSheet's own class doc comment): 1672x941 instead of
# 1983x793, a 20x6 grid of 120 frames instead of 8x5 of 40, and -- the part
# that broke every measurement helper here -- an opaque BLACK background
# with light-grey GRID LINES drawn between cells, instead of a magenta
# background with gutters keyed out of it. The old helper below looked for
# rows that were entirely magenta; on this sheet there are none at all, so
# it measured the whole image as one row.
#
# These measure the real sheet at test time and compare, so the next art
# swap fails here instead of shipping a mis-cropped intro.


## A grid line is a run of near-neutral, clearly-lit pixels spanning most of
## the sheet -- the contact-sheet chrome drawn BETWEEN cells. Real frame art
## on this sheet is either near-black space or saturated blue/gold globe, so
## "bright AND unsaturated across most of the line" picks out the chrome and
## nothing else. Returns the runs as [first, last] index pairs.
func _grid_line_runs(image: Image, horizontal: bool) -> Array:
	var width := image.get_width()
	var height := image.get_height()
	var outer: int = height if horizontal else width
	var inner: int = width if horizontal else height
	var runs: Array = []
	var start := -1
	var previous := -99
	for i in outer:
		var hits := 0
		for j in range(0, inner, 2):
			var c: Color = image.get_pixel(j, i) if horizontal else image.get_pixel(i, j)
			var brightest: float = maxf(c.r, maxf(c.g, c.b))
			var darkest: float = minf(c.r, minf(c.g, c.b))
			if brightest > 0.18 and (brightest - darkest) < 0.08:
				hits += 1
		if float(hits) / float(inner / 2) > 0.45:
			if i != previous + 1:
				if start >= 0:
					runs.append([start, previous])
				start = i
			previous = i
	if start >= 0:
		runs.append([start, previous])
	return runs


## The sheet's own SHAPE, re-counted from the real file: 19 vertical lines
## make 20 columns, 5 horizontal lines make 6 rows, one cell per frame. A
## re-export at another grid -- which is exactly what happened here, twice --
## fails this instead of shipping a mis-crop.
func test_the_sheets_real_grid_is_the_one_the_slicing_assumes():
	var image := SpriteSheetLoader.load_image(IntroSplashSheet._SHEET_PATH)
	assert_not_null(image, "precondition: the sheet loads")
	var columns: int = _grid_line_runs(image, false).size() + 1
	var rows: int = _grid_line_runs(image, true).size() + 1
	assert_eq(columns, IntroSplashSheet._COLUMN_WINDOW_LEFTS.size(), "columns on the sheet")
	assert_eq(rows, IntroSplashSheet._ROW_WINDOW_TOPS.size(), "rows on the sheet")
	assert_eq(
		columns * rows,
		IntroSplashSequencer.FRAME_COUNT,
		"the sequencer plays a different number of frames than the sheet holds"
	)


## Every window has to land wholly inside the sheet -- the previous art swap
## left the last column's crop running 309px off the right-hand edge, which
## is why the final frame of every row came out blank.
func test_every_frame_is_inside_the_sheet():
	var image := SpriteSheetLoader.load_image(IntroSplashSheet._SHEET_PATH)
	for left in IntroSplashSheet._COLUMN_WINDOW_LEFTS:
		assert_lte(
			int(left) + IntroSplashSheet._FRAME_WIDTH, image.get_width(),
			"a pinned column runs off the sheet"
		)
	for top in IntroSplashSheet._ROW_WINDOW_TOPS:
		assert_lte(
			int(top) + IntroSplashSheet._FRAME_HEIGHT, image.get_height(),
			"a pinned row runs off the sheet"
		)


## The heart of "fix the cropping properly": not one pixel of the
## contact-sheet chrome may survive into a frame. A grid line is a bright,
## near-neutral vertical or horizontal STREAK; a frame that swallowed one
## shows it as a pale bar down its own edge. Checked on the built frames
## themselves, not on the crop arithmetic, so it holds whatever the crop
## does internally.
func test_no_frame_carries_a_slice_of_the_grid_line():
	var frames := sheet.generate_textures()
	for i in frames.size():
		var frame: Image = frames[i].get_image()
		for x in [0, frame.get_width() - 1]:
			assert_false(
				_is_grey_streak(frame, x, true),
				"frame %d keeps a grid line down its %s edge" % [i, "left" if x == 0 else "right"]
			)
		for y in [0, frame.get_height() - 1]:
			assert_false(
				_is_grey_streak(frame, y, false),
				"frame %d keeps a grid line across its %s edge" % [i, "top" if y == 0 else "bottom"]
			)


## Most of one row/column of `frame` being bright and near-neutral -- the
## same rule _grid_line_runs uses on the sheet, applied to a built frame.
func _is_grey_streak(frame: Image, index: int, vertical: bool) -> bool:
	var extent: int = frame.get_height() if vertical else frame.get_width()
	var hits := 0
	for j in extent:
		var c: Color = frame.get_pixel(index, j) if vertical else frame.get_pixel(j, index)
		var brightest: float = maxf(c.r, maxf(c.g, c.b))
		var darkest: float = minf(c.r, minf(c.g, c.b))
		if brightest > 0.18 and (brightest - darkest) < 0.08:
			hits += 1
	return float(hits) / float(extent) > 0.45


## The alignment invariant, and the one that actually catches a drifting
## crop. Every cell of this contact sheet carries its own timestamp burned
## in at the SAME offset below its own cell top (the export tool drew it
## there), so if the crop is aligned that label lands on the same row of all
## 120 built frames. A crop anchored a few pixels off per row is exactly
## what "the image is moving from bottom to top" looked like the last time
## this art was replaced -- this measures it directly, instead of inferring
## it from opaque-pixel bounds, which a full-bleed sheet like this one
## cannot distinguish at all (every pixel is opaque, so a bounds test passes
## vacuously here).
##
## Tolerance is exactly 1px, and that 1px is the art's, not the crop's: the
## labels are different strings ("0.00s" vs "1.25s"), so their glyphs put
## different amounts of ink on the topmost antialiased row -- measured
## directly, frames sharing ONE window and therefore ONE crop still report
## first-ink rows of 10 and 11. Anything beyond that spread is the crop
## moving, which is what this guards. The real drift it replaces was 14px.
##
## The label is kept in frame deliberately, not cropped away -- asked
## directly, when offered the choice: "Just crop with timestamp".
func test_every_frame_lands_its_timestamp_label_on_the_same_rows():
	var frames := sheet.generate_textures()
	var highest := 999
	var lowest := -1
	for i in frames.size():
		var top: int = _label_rows(frames[i].get_image()).x
		assert_gte(top, 0, "frame %d shows no timestamp label at all" % i)
		highest = mini(highest, top)
		lowest = maxi(lowest, top)
	assert_lte(
		lowest - highest, 1,
		"the timestamp sits as high as row %d in one frame and as low as row %d in another -- the crop is drifting between cells" % [highest, lowest]
	)


## First and last row carrying label text: >=4 near-white pixels within the
## left 48px, in the top 30 rows. Bounded to where the label is drawn so the
## globe's own bright limb (which reaches the top of a frame only lower down,
## from y~36) can never be counted as text.
func _label_rows(frame: Image) -> Vector2i:
	var first := -1
	var last := -1
	for y in mini(30, frame.get_height()):
		var run := 0
		for x in range(4, mini(48, frame.get_width())):
			var c := frame.get_pixel(x, y)
			if minf(c.r, minf(c.g, c.b)) > 0.60:
				run += 1
		if run >= 4:
			if first < 0:
				first = y
			last = y
	return Vector2i(first, last)
