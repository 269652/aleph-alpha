extends GutTest

## Real illustrated art for the boot intro splash (assets/sprites/intro.png)
## -- see docs/concept/intro_splash.md. Same "hand/AI-illustrated sheet ->
## SpriteSheetSlicer -> cached frames" shape as IllustratedWormSprite, but
## the sheet's own grid is NOT perfectly regular (AI-generated at
## 1983x793, not evenly divisible by the prompted 8 columns x 4 rows --
## confirmed with tools/probe_intro_sheet.gd), so this hand-measures the 4
## ROW bands (pinned constants) and reuses SpriteSheetSlicer.detect_frames
## for the columns within each band, rather than assuming arithmetic
## division the way the worm sheet's own (genuinely regular) grid can.
##
## Deliberately does NOT run frames through SpriteSheetSlicer.
## normalize_frames the way every other illustrated sheet in this codebase
## does: normalize_frames picks ONE shared scale from the WIDEST/TALLEST
## content bounding box across the frames it's given, and here the "ALEPH
## ALPHA" wordmark's own ink extent genuinely grows across the sequence --
## content-cropping and rescaling would scale every frame by the TEXT's
## own extent, making the globe appear to change size as the words build
## in. Frames are extracted as plain, un-rescaled regions instead, and the
## globe is held still by measuring the globe itself (see the frame-
## stabilisation tests at the end of this file) rather than by trusting
## the source art to have framed it consistently -- measured, it does
## not.

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
	assert_ne(frames[0].get_image().get_data(), frames[31].get_image().get_data())


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
# Reported in play after the intro art was replaced: "the new intro has
# wrong row sizes the image is moving from bottom to top".
#
# _ROW_BANDS and _COLUMN_LEFTS are measured constants, pinned once against
# the sheet as it was (see this file's own doc comment and
# tools/probe_intro_sheet.gd). Nothing checked they still described the
# file, so replacing intro.png left every row cropped at the OLD row's
# offset -- drifting further down the sheet row by row, which reads on
# screen as the picture climbing upward.
#
# These measure the real sheet at test time and compare, so the next art
# swap fails here instead of shipping a drifting intro.


## A grid line is drawn across EVERYTHING, so every pixel along it is
## light; content lines always have some black in them. The MINIMUM along a
## line is therefore what separates the two, and a mean cannot: by the end
## of this animation the globe is brighter than the dividers are.
func _line_minimum(image: Image, index: int, along_rows: bool) -> float:
	var inner: int = image.get_width() if along_rows else image.get_height()
	var lowest := 1.0
	for j in inner:
		var x: int = j if along_rows else index
		var y: int = index if along_rows else j
		var pixel := image.get_pixel(x, y)
		lowest = minf(lowest, maxf(pixel.r, maxf(pixel.g, pixel.b)))
	return lowest


## Where each cell starts: the sheet's own edge, then the first pixel AFTER
## each divider run ends -- not its centre, since a line is 1-3px wide and a
## crop starting inside one carries that ink. Mirrors tools/probe_intro_grid.gd.
func _measured_cell_starts(image: Image, along_rows: bool) -> Array:
	var outer: int = image.get_height() if along_rows else image.get_width()
	var starts: Array = [0]
	var previous := -99
	var in_run := false
	for i in outer:
		if _line_minimum(image, i, along_rows) < IntroSplashSheet.DIVIDER_BRIGHTNESS:
			continue
		if i != previous + 1 and in_run:
			starts.append(previous + 1)
		in_run = true
		previous = i
	if in_run:
		starts.append(previous + 1)
	return starts


## The sheet as it is ON DISK. Deliberately not SpriteSheetLoader (which
## prefers the imported texture, and a stale import cache is how a swapped
## sheet got past this guard once) and not Image.load_from_file (which warns
## on a res:// path, and an engine warning fails a GUT run).
func _sheet_from_disk() -> Image:
	var image := Image.new()
	image.load_png_from_buffer(FileAccess.get_file_as_bytes(IntroSplashSheet._SHEET_PATH))
	return image


## The guard that exists precisely to catch the sheet being replaced -- and
## did not, when it was (2026-09-17, a 1983x793 sheet of 8x5 frames swapped
## for a 1672x941 contact sheet of 20x6). Two holes, both closed here:
##
## 1. It loaded through SpriteSheetLoader, which prefers the IMPORTED
##    texture. A stale .godot import cache hands back the art the constants
##    were measured FROM, so the comparison could not fail. It reads the raw
##    file now, which is the thing that actually changed.
## 2. It detected MAGENTA gutters. The replacement is drawn on black with
##    thin light grid lines and no magenta anywhere, so the detector saw one
##    band covering the whole sheet and the assertion passed vacuously.
##
## Re-measure with tools/probe_intro_grid.gd whenever the sheet changes.
func test_the_pinned_grid_is_where_the_sheets_own_cells_actually_are():
	var image := _sheet_from_disk()
	assert_gt(image.get_width(), 0, "precondition: the sheet loads from disk")
	assert_eq(
		IntroSplashSheet._COLUMN_LEFTS, _measured_cell_starts(image, false),
		"the pinned columns no longer describe assets/sprites/intro.png -- re-measure with tools/probe_intro_grid.gd"
	)
	assert_eq(
		IntroSplashSheet._ROW_TOPS, _measured_cell_starts(image, true),
		"the pinned rows no longer describe assets/sprites/intro.png -- re-measure with tools/probe_intro_grid.gd"
	)


## Every cell of the contact sheet has its own timestamp printed inside its
## top edge ("0.00s" ... "4.96s"), white on black. Cropping from the cell's
## own top puts that caption on screen over the globe, which is half of what
## "the new intro crops are still not correct" was about.
##
## Asserted STRUCTURALLY -- the crop begins below where the caption really
## is -- rather than by looking for white ink in the finished frames. That
## was the first attempt and it does not work: measured on this sheet, the
## caption is (0.91, 0.92, 0.91) and the blown-out core of a late flare is
## (1.00, 0.99, 0.98), so no brightness or neutrality rule separates them.
## Where the caption BAND sits is measurable, and that is what this pins.
##
## Measured in the FIRST cells of row 0 -- 0.00s, 0.04s, 0.08s, where the
## globe is still a barely-lit crescent -- so the only bright thing there is
## the timestamp itself. Row 0's later cells are already bright enough by
## 0.75s to read as "caption" to any brightness rule, and the row divider
## that ends the band is bright too; both were measured, not assumed.
func test_the_crop_starts_below_the_sheets_own_timestamp_caption():
	var image := _sheet_from_disk()
	var last_ink := -1
	for left in [IntroSplashSheet._COLUMN_LEFTS[0], IntroSplashSheet._COLUMN_LEFTS[1], IntroSplashSheet._COLUMN_LEFTS[2]]:
		# Exactly the columns the crop itself reads, and only the top of the
		# cell: scanning the whole row band would find the row divider that
		# ends it, which is bright too and is not a caption.
		var from_x: int = int(left) + IntroSplashSheet._CELL_INSET
		var right: int = from_x + IntroSplashSheet._FRAME_WIDTH
		for y in range(0, 40):
			for x in range(from_x, right):
				var pixel := image.get_pixel(x, y)
				if pixel.r > 0.75 and pixel.g > 0.75 and pixel.b > 0.75:
					last_ink = maxi(last_ink, y)
					break
	assert_gt(last_ink, 0, "precondition: row 0's cells really do carry caption ink")
	assert_gt(
		IntroSplashSheet._CAPTION_HEIGHT, last_ink,
		"the crop starts at row %d of a cell, but the caption runs to row %d" % [
			IntroSplashSheet._CAPTION_HEIGHT, last_ink
		]
	)


## ...and the other half: no frame may carry the grid's own divider ink up
## its side. That one IS checkable from the finished frames, because a
## divider is a straight line the full height of the frame where art never
## is -- measured at column 9, where the line is 2px wide but the detector
## reads it as 1, which is why the crop keeps _CELL_INSET clear of it.
func test_no_frame_carries_the_grids_own_divider_up_its_edge():
	var frames := IntroSplashSheet.new().generate_textures()
	assert_gt(frames.size(), 0, "precondition: frames were built")
	for index in frames.size():
		var image: Image = frames[index].get_image()
		for x in [0, image.get_width() - 1]:
			var lit := 0
			for y in image.get_height():
				var pixel := image.get_pixel(x, y)
				if maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.35:
					lit += 1
			assert_lt(
				lit, image.get_height() / 2,
				"frame %d's column %d is lit down half its height -- that is a divider, not art" % [index, x]
			)


func test_a_frame_never_reaches_into_the_row_below_it():
	# What produced the drift once: art from the next row pulled into this
	# row's frame. Mirrors _build_textures' own crop exactly -- from the
	# cell's top, past the caption, one fixed height.
	var tops: Array = IntroSplashSheet._ROW_TOPS
	var sheet_height: int = _sheet_from_disk().get_height()
	for i in tops.size():
		var top: int = int(tops[i])
		var limit: int = int(tops[i + 1]) - 1 if i + 1 < tops.size() else sheet_height
		assert_lte(
			top + IntroSplashSheet._CAPTION_HEIGHT + IntroSplashSheet._FRAME_HEIGHT, limit,
			"row %d's crop reaches into what follows it" % i
		)


func test_a_frame_never_reaches_into_the_column_beside_it():
	var lefts: Array = IntroSplashSheet._COLUMN_LEFTS
	for i in range(lefts.size() - 1):
		assert_lte(
			IntroSplashSheet._FRAME_WIDTH, int(lefts[i + 1]) - int(lefts[i]),
			"column %d's crop reaches into column %d" % [i, i + 1]
		)


func test_every_frame_is_inside_the_sheet():
	var image := SpriteSheetLoader.load_image(IntroSplashSheet._SHEET_PATH)
	var last_left: int = IntroSplashSheet._COLUMN_LEFTS[IntroSplashSheet._COLUMN_LEFTS.size() - 1]
	assert_lte(last_left + IntroSplashSheet._FRAME_WIDTH, image.get_width(), "the last column runs off the sheet")


## Rows of a built FRAME that carry opaque art, as [top, bottom).
func _opaque_band(texture: Texture2D) -> Vector2i:
	var image := texture.get_image()
	var top := -1
	var bottom := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				if top < 0:
					top = y
				bottom = y
				break
	return Vector2i(top, bottom)


## Reported in play right after the art was replaced: "the new intro has
## wrong row sizes the image is moving from bottom to top".
##
## The rows of this sheet are genuinely DIFFERENT heights -- 162, 158,
## 158, 147, 134, measured, not assumed (see _ROW_BANDS) -- while the
## globe they draw stays the same size and sits at its own row's middle.
## Every frame shares one fixed canvas (test_every_frame_is_the_same_size),
## so a short row has to pad somewhere, and a frame anchored at its row's
## TOP puts the whole shortfall below the art: the globe's centre climbs
## 14px up the source frame across the sequence, magnified ~5.3x by the
## viewport stretch, which is exactly the reported upward drift. Padding
## the shortfall EQUALLY above and below leaves the globe where it is.
func test_every_frame_puts_its_art_at_the_same_height():
	var frames := sheet.generate_textures()
	var height: int = frames[0].get_image().get_height()
	var frame_centre := float(height - 1) / 2.0
	for i in frames.size():
		var band := _opaque_band(frames[i])
		assert_gte(band.x, 0, "frame %d has no opaque art at all" % i)
		var art_centre := float(band.x + band.y) / 2.0
		assert_almost_eq(
			art_centre, frame_centre, 1.0,
			"frame %d centres its art at %.1f, not %.1f -- art anchored anywhere but the frame's own middle drifts up (or down) the screen as the rows change height" % [i, art_centre, frame_centre]
		)


# -- frame stabilisation: the globe lands in the same place every frame ---
# -- (see IntroSplashSheet.globe_centre_of, docs/concept/intro_splash.md's --
# -- "Frame stabilisation") -- reported in play, repeatedly across this ----
# -- file's own history: "stabilize the intro video", "it jumps left to ----
# -- right" ---------------------------------------------------------------

## A synthetic frame: a filled disc (the globe) plus a bright bar that
## sticks out well past it on ONE side (the "ALEPH ALPHA" wordmark and the
## light-streak sweep, which really do extend past the globe's own edge --
## see the real sheet). The disc's centre is the answer; the bar is the
## trap.
func _synthetic_globe(centre: Vector2i, radius: int, bar_reach: int) -> Image:
	var image := Image.create(243, 162, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 1.0))  # opaque near-black space, as the real sheet has
	for y in image.get_height():
		for x in image.get_width():
			if Vector2(x - centre.x, y - centre.y).length() <= float(radius):
				image.set_pixel(x, y, Color(0.2, 0.5, 0.9, 1.0))
	for x in range(centre.x, mini(centre.x + bar_reach, image.get_width())):
		for y in range(centre.y - 4, centre.y + 4):
			image.set_pixel(x, y, Color(1.0, 0.85, 0.2, 1.0))
	return image


## The whole point of the estimator: a plain bounding box of everything
## bright is dragged sideways by the wordmark, and the wordmark's reach
## GROWS across the sequence, so a bbox-based registration would itself
## drift. Taking the MEDIAN of each row's own centre ignores the handful
## of rows the bar touches and reads the disc.
func test_the_globe_centre_ignores_a_wordmark_that_sticks_out_past_it():
	var centre := Vector2i(100, 80)
	for bar_reach in [0, 30, 60, 90]:
		var measured := IntroSplashSheet.globe_centre_of(_synthetic_globe(centre, 50, bar_reach))
		assert_almost_eq(
			measured.x, float(centre.x), 1.0,
			"a wordmark reaching %dpx past the globe must not move the measured centre" % bar_reach
		)
		assert_almost_eq(measured.y, float(centre.y), 1.0, "nor its vertical centre")


func test_the_globe_centre_follows_a_globe_that_really_moved():
	var moved := IntroSplashSheet.globe_centre_of(_synthetic_globe(Vector2i(120, 70), 50, 40))
	assert_almost_eq(moved.x, 120.0, 1.0)
	assert_almost_eq(moved.y, 70.0, 1.0)


## The report itself. The source art does NOT draw the globe at the same
## place in every cell: measured on the real sheet, its centre wanders 6px
## horizontally and 2px vertically, with a sawtooth jump at every row
## boundary (the first column of each row sits ~3px left of its
## neighbours). This sheet is stretched ~5.3x onto the screen, so 6px of
## source wander reads as ~32px of on-screen sway -- the reported "jumps
## left to right".
##
## Registering every frame on its own measured globe centre removes it at
## the source. Nothing is rescaled and no frame is re-cropped: the art is
## simply blitted into its shared canvas at a whole-pixel offset, so the
## fixed-size-frame rule (test_every_frame_is_the_same_size) and the
## no-resampling rule both still hold.
func test_every_frame_puts_the_globe_in_the_same_place():
	var frames := sheet.generate_textures()
	var centres: Array[Vector2] = []
	for frame in frames:
		centres.append(IntroSplashSheet.globe_centre_of(frame.get_image()))
	var min_x: float = centres[0].x
	var max_x: float = centres[0].x
	var min_y: float = centres[0].y
	var max_y: float = centres[0].y
	for centre in centres:
		min_x = minf(min_x, centre.x)
		max_x = maxf(max_x, centre.x)
		min_y = minf(min_y, centre.y)
		max_y = maxf(max_y, centre.y)
	assert_lte(
		max_x - min_x, 1.0,
		"the globe wanders %.1fpx horizontally across the 40 frames (%.1f..%.1f)" % [max_x - min_x, min_x, max_x]
	)
	assert_lte(
		max_y - min_y, 1.0,
		"the globe wanders %.1fpx vertically across the 40 frames (%.1f..%.1f)" % [max_y - min_y, min_y, max_y]
	)


## Stabilisation must not sneak a rescale in: a shifted frame is the SAME
## art, moved by whole pixels, so the globe's own drawn width is untouched
## by this pass. (It does shrink ~5% across the sequence on its own -- real
## drift in the art itself, deliberately NOT resampled away; see
## docs/concept/intro_splash.md's "Frame stabilisation".)
func test_stabilising_never_resamples_the_art():
	var frames := sheet.generate_textures()
	for i in frames.size():
		var image := frames[i].get_image()
		assert_eq(image.get_width(), frames[0].get_image().get_width(), "frame %d" % i)
		assert_eq(image.get_height(), frames[0].get_image().get_height(), "frame %d" % i)
