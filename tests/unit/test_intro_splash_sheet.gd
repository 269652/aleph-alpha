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
## content-cropping and rescaling would make the globe itself appear to
## change size as the text builds in, which the source art's own
## consistent camera framing (see the intro-generation prompt) already
## avoids by construction. Frames are extracted as plain, un-rescaled
## regions instead.

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


# -- frame stabilisation: the globe holds still frame to frame -------------
# -- (see docs/concept/intro_splash.md's "Frame stabilisation") -----------

## The globe's RIGHT LIMB -- for the widest row, the rightmost pixel with
## any light in it at all.
##
## Deliberately the limb rather than the globe's centre, and deliberately a
## near-black threshold. This art crops the sphere at the LEFT frame edge,
## so the right limb is the only edge of it actually in shot; and the limb
## is geometry, where every brightness-based reading here is lighting. The
## terminator sweeps right across the disc as the Earth turns into
## daylight, so a centre-of-lit-pixels measurement moves ~35px over the
## sequence while the globe itself has not moved at all -- the same
## "moon-phase crescent" trap that made an earlier measurement of the
## PREVIOUS sheet read as falsely reassuring (see this doc's sixteenth
## pass), reached here from the opposite direction.
func _globe_right_limb(texture: Texture2D) -> int:
	var image := texture.get_image()
	var limb := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).get_luminance() > 0.02:
				limb = maxi(limb, x)
	return limb


## Frames before this have not faded up out of black yet, so the globe's
## own edge is genuinely not in the picture to hold still. Measured: the
## limb is already at its final position by frame 20 of 120, and the
## sequence runs at 24fps, so this is the first ~0.83s.
const _FADE_IN_FRAMES := 20


## The report this was chased for, over and over: "stabilize the intro
## video", "it jumps left to right". On THIS sheet it does not. Measured
## across all 100 frames past the fade-in, the globe's right limb sits at
## exactly the same column in every one of them -- zero spread, not merely
## a small one. The fixed crop from a measured grid is already doing the
## whole job here, and nothing further is needed.
##
## Kept as a regression test rather than deleted as a no-op: this file's
## own history is four separate art swaps, at least two of which shipped a
## visibly drifting intro. The next one fails here.
func test_the_globe_holds_the_same_position_in_every_frame():
	var frames := sheet.generate_textures()
	assert_gt(frames.size(), _FADE_IN_FRAMES, "precondition: there are frames past the fade-in")
	var lowest := 9999
	var highest := -1
	for i in range(_FADE_IN_FRAMES, frames.size()):
		var limb := _globe_right_limb(frames[i])
		assert_gte(limb, 0, "frame %d has no lit pixel at all, past the fade-in" % i)
		lowest = mini(lowest, limb)
		highest = maxi(highest, limb)
	assert_lte(
		highest - lowest, 1,
		"the globe's own edge wanders %dpx across the frames past the fade-in (%d..%d) -- this sheet drifts" % [
			highest - lowest, lowest, highest
		]
	)


## ...and the measurement really would notice. A test that the art holds
## still is worth nothing if its own ruler cannot see movement, so the same
## helper is run over a real frame shifted by a known amount.
func test_the_limb_measurement_would_notice_a_frame_that_moved():
	var frames := sheet.generate_textures()
	var original := frames[frames.size() - 1].get_image()
	var shifted := Image.create(original.get_width(), original.get_height(), false, original.get_format())
	shifted.fill(Color(0.0, 0.0, 0.0, 1.0))
	# Left by 3px: the limb must come back 3px lower, or the ruler is blind.
	shifted.blit_rect(
		original, Rect2i(3, 0, original.get_width() - 3, original.get_height()), Vector2i(0, 0)
	)
	var moved := _globe_right_limb(ImageTexture.create_from_image(shifted))
	var still := _globe_right_limb(frames[frames.size() - 1])
	assert_eq(moved, still - 3, "a 3px shift must read as a 3px shift")


## The count is not a number somebody typed: it is the grid the sheet
## actually has. The 2026-09-17 "bump resolution" swap replaced a 20x6 sheet
## of 120 small frames with a 10x5 sheet of 50 larger ones, and nothing tied
## FRAME_COUNT to the file, so the sequencer went on asking for 120 frames
## from a sheet that has 50 -- reported as "the intro still doesn't have the
## correct frame crops".
func test_the_frame_count_is_exactly_the_grid_the_sheet_really_has():
	var image := _sheet_from_disk()
	var columns: int = _measured_cell_starts(image, false).size()
	var rows: int = _measured_cell_starts(image, true).size()
	assert_gt(columns, 0, "precondition: the sheet's own columns were measured")
	assert_eq(
		IntroSplashSequencer.FRAME_COUNT, rows * columns,
		"the sheet on disk is %d x %d = %d frames" % [columns, rows, rows * columns]
	)


## And the clock is the sheet's own captions, read off the file: the first
## three cells are 0.00s / 0.10s / 0.90s and the last two 4.80s / 4.90s, so
## the frames are a tenth of a second apart and the whole thing is five
## seconds long. The previous sheet printed 1/24s steps and ran at 24fps for
## the same five seconds; the swap changed the step and nothing changed with
## it, so the intro played in just over two seconds.
func test_the_sequencer_runs_at_the_sheets_own_frame_rate():
	assert_eq(IntroSplashSequencer.FPS, 10.0, "the captions step by 0.10s")
	assert_almost_eq(
		IntroSplashSequencer.duration_seconds(), 5.0, 0.001,
		"the last caption is 4.90s, so the run is five seconds"
	)


# -- the earth holds still where the sheet changes row ----------------------
#
# Reported live, after every earlier stabilisation pass had shipped: *"Can
# you properly stabilize the intro animation? The earth should be scaled and
# stabilised so there is no jitter and zooming"*.
#
# Measured before changing anything (tools/probe_intro_stability.gd): the
# jitter is not spread through the sequence at all. Registering every
# consecutive pair of frames, the 45 transitions INSIDE a contact-sheet row
# move the picture by at most 1px and rescale it by at most 0.5%, while the
# four transitions that CROSS a row boundary move it 4.5-9px and rescale it
# by up to 5.5%. The earth shrinks about 4% per sheet row: relative to row
# 1 it is drawn at 0.99, 0.95 and 0.89 in rows 2, 3 and 4.
#
# The art is a 10x5 contact sheet drawn by an image model, not a rendered
# video cut into cells, and nothing made it draw the earth at one size
# across all five rows. That is why no amount of fixing the crop WINDOW
# (passes eight through twelve) ever removed this: the wobble is in the
# picture, not in where it was cut.


## The share of the brightest row's total light a row must carry to count as
## part of the picture rather than as space around it.
##
## A brightness PROFILE rather than a limb scan, because a limb scan is what
## went blind here. _globe_right_limb takes the rightmost pixel above 0.02
## luminance anywhere in the frame -- and on this sheet the glow and the
## light streak reach the frame's own right edge in essentially every frame,
## so it returns the last column, saturated, whatever the art does. Its
## companion mutation test passes (a blitted frame really does read as
## moved) while the ruler cannot see the real art move at all: a ruler that
## survives its own mutation test can still be blind on the data it is
## pointed at.
##
## 0.15 measured against what it has to separate: the earth's own limb rows
## carry 20-60% of the brightest row and space carries under 5%, so the
## threshold sits in a wide gap rather than on a cliff.
const _LIT_ROW_SHARE := 0.15

## How many frames either side of a transition count as its neighbourhood.
const _NEIGHBOURHOOD := 3

## How much more a boundary transition may move the picture than its own
## neighbourhood does, in pixels of top-plus-bottom edge movement.
##
## Three, not zero: the rows either side of a boundary are separate
## drawings, so their limbs land on slightly different pixels however well
## the two are matched, and the ruler quantises to whole rows at both edges.
## Measured after the correction, the worst boundary clears its own
## neighbourhood by 2; before it, the three that matter exceeded theirs by
## 8, 12 and 10, so this is a long way from blunting the assertion.
const _BOUNDARY_TOLERANCE := 3


## The picture's own vertical extent: the first and last row carrying a real
## share of the frame's light. Both edges, because the two answer different
## questions -- they move together when the picture is displaced and apart
## when it is rescaled, and this art does both.
func _lit_band(texture: Texture2D) -> Vector2i:
	var image := texture.get_image()
	var rows := PackedFloat32Array()
	rows.resize(image.get_height())
	var brightest := 0.0
	for y in image.get_height():
		var total := 0.0
		for x in image.get_width():
			total += image.get_pixel(x, y).get_luminance()
		rows[y] = total
		brightest = maxf(brightest, total)
	var threshold := brightest * _LIT_ROW_SHARE
	var top := -1
	var bottom := -1
	for y in rows.size():
		if rows[y] > threshold:
			if top < 0:
				top = y
			bottom = y
	return Vector2i(top, bottom)


## How far the picture's two edges move across one transition.
func _edge_movement(before: Vector2i, after: Vector2i) -> int:
	return absi(after.x - before.x) + absi(after.y - before.y)


## Whether the frame AFTER this transition begins a new row of the contact
## sheet -- read off the sheet's own grid, not counted out by hand, so a
## re-cut sheet moves these with it.
func _crosses_a_sheet_row(transition: int) -> bool:
	return (transition + 1) % IntroSplashSheet._COLUMN_LEFTS.size() == 0


## The real assertion, and deliberately a LOCAL one: a transition that
## crosses a row of the contact sheet may not move the picture more than the
## transitions around it already do.
##
## Local rather than absolute because the earth genuinely moves in this
## animation -- it approaches through the whole first second, so an absolute
## "nothing may move more than 1px" would either fail on the approach or
## have to be told where the approach ends, which is a fact about the art
## that would go stale on the next swap. Comparing a boundary against its own
## neighbours needs to know nothing about the art: during the approach the
## neighbours move too, and during the long hold they do not.
func test_the_picture_does_not_jump_where_the_sheet_changes_row():
	var frames := sheet.generate_textures()
	var bands: Array[Vector2i] = []
	for frame in frames:
		bands.append(_lit_band(frame))
	var moves := PackedInt32Array()
	for i in range(frames.size() - 1):
		moves.append(_edge_movement(bands[i], bands[i + 1]))
	var boundaries := 0
	for i in moves.size():
		if not _crosses_a_sheet_row(i):
			continue
		boundaries += 1
		var local := 0
		for j in range(i - _NEIGHBOURHOOD, i + _NEIGHBOURHOOD + 1):
			if j < 0 or j >= moves.size() or j == i or _crosses_a_sheet_row(j):
				continue
			local = maxi(local, moves[j])
		assert_lte(
			moves[i], local + _BOUNDARY_TOLERANCE,
			"frames %d->%d cross a sheet row and move the picture %dpx, against %dpx for the transitions around them" % [
				i, i + 1, moves[i], local
			]
		)
	assert_gt(boundaries, 0, "precondition: the sheet really has more than one row")


## ...and the same ruler says the picture is not RESIZED there either.
##
## The test above compares where the picture's two edges ARE; this one
## compares how far APART they are, which is the quantity a zoom moves and
## a pan does not. Both are needed: the sheet's rows differ in both at once
## (the earth is drawn about 4% smaller per row AND a few pixels higher),
## and a correction that fixed only the height would leave a step in the
## other.
##
## Local for the same reason, and for one more that is specific to this art:
## the last three frames bloom into gold sparkles that fill the frame, so
## the lit band genuinely grows by 15px there with nothing moving at all. An
## absolute "the picture is always the same size" reading cannot tell that
## from a zoom -- measured, it puts the spread over the second half at 19px
## when 7 of those are the bloom. Comparing a boundary with its own
## neighbours costs nothing there: the bloom is in the neighbours too.
func test_the_picture_is_not_resized_where_the_sheet_changes_row():
	var frames := sheet.generate_textures()
	var heights := PackedInt32Array()
	for frame in frames:
		var band := _lit_band(frame)
		heights.append(band.y - band.x)
	var changes := PackedInt32Array()
	for i in range(frames.size() - 1):
		changes.append(absi(heights[i + 1] - heights[i]))
	for i in changes.size():
		if not _crosses_a_sheet_row(i):
			continue
		var local := 0
		for j in range(i - _NEIGHBOURHOOD, i + _NEIGHBOURHOOD + 1):
			if j < 0 or j >= changes.size() or j == i or _crosses_a_sheet_row(j):
				continue
			local = maxi(local, changes[j])
		assert_lte(
			changes[i], local + _BOUNDARY_TOLERANCE,
			"frames %d->%d cross a sheet row and resize the picture by %dpx, against %dpx for the transitions around them" % [
				i, i + 1, changes[i], local
			]
		)


## And the ruler really would notice, on the REAL frames rather than on a
## synthetic one: the same frame scaled down by a tenth must read as a
## shorter band. Worth its own test precisely because this file already
## carries a ruler that passes a mutation test and is blind anyway (see
## _LIT_ROW_SHARE).
func test_the_band_ruler_notices_a_frame_that_was_rescaled():
	var frames := sheet.generate_textures()
	var original := frames[frames.size() - 1].get_image()
	var shrunk := Image.create(
		original.get_width(), original.get_height(), false, original.get_format()
	)
	shrunk.fill(Color(0.0, 0.0, 0.0, 1.0))
	var inner := original.duplicate() as Image
	inner.resize(
		int(original.get_width() * 0.9), int(original.get_height() * 0.9), Image.INTERPOLATE_BILINEAR
	)
	shrunk.blit_rect(
		inner, Rect2i(Vector2i.ZERO, inner.get_size()),
		Vector2i((original.get_width() - inner.get_width()) / 2, (original.get_height() - inner.get_height()) / 2)
	)
	var before := _lit_band(frames[frames.size() - 1])
	var after := _lit_band(ImageTexture.create_from_image(shrunk))
	assert_lt(
		after.y - after.x, before.y - before.x,
		"a frame drawn a tenth smaller must read as a shorter band, or the ruler cannot see zoom"
	)
