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


## Rows of the sheet that are entirely background, i.e. the gutters -- the
## same magenta rule the slicer itself keys on. Returns each content band
## as [top, bottom).
func _measured_row_bands(image: Image) -> Array:
	var bands: Array = []
	var top := -1
	for y in image.get_height():
		var is_gutter := true
		for x in image.get_width():
			if not IntroSplashSheet._is_magenta(image.get_pixel(x, y)):
				is_gutter = false
				break
		if is_gutter:
			if top >= 0:
				bands.append(Vector2i(top, y))
				top = -1
		elif top < 0:
			top = y
	if top >= 0:
		bands.append(Vector2i(top, image.get_height()))
	return bands


func test_the_pinned_row_tops_are_where_the_sheets_rows_actually_start():
	var image := SpriteSheetLoader.load_image(IntroSplashSheet._SHEET_PATH)
	assert_not_null(image, "precondition: the sheet loads")
	var measured := _measured_row_bands(image)
	var real_tops: Array = []
	for band in measured:
		# A one-pixel sliver at the sheet's edge is an artefact of the
		# render, not a row of art.
		if (band as Vector2i).y - (band as Vector2i).x > 8:
			real_tops.append((band as Vector2i).x)
	var pinned_tops: Array = []
	for band in IntroSplashSheet._ROW_BANDS:
		pinned_tops.append((band as Vector2i).x)
	assert_eq(
		pinned_tops, real_tops,
		"the pinned rows no longer describe assets/sprites/intro.png -- re-measure with tools/probe_intro_sheet.gd"
	)


func test_a_frame_never_reaches_into_the_row_below_it():
	# What produced the drift: art from the next row pulled into this row's
	# frame. The CROP is what must stay clear -- the frame canvas is a
	# fixed size for every row and pads around a short row's art, so
	# asserting on _FRAME_HEIGHT alone would be asserting the wrong
	# quantity. This mirrors _build_textures' own crop exactly.
	var bands: Array = IntroSplashSheet._ROW_BANDS
	for i in bands.size():
		var band: Vector2i = bands[i]
		var limit: int = int((bands[i + 1] as Vector2i).x) if i + 1 < bands.size() else 793
		var crop: int = mini(IntroSplashSheet._FRAME_HEIGHT, band.y - band.x)
		assert_lte(band.x + crop, limit, "row %d's crop reaches into what follows it" % i)
		assert_eq(crop, band.y - band.x, "row %d's own art does not fit in its crop" % i)


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
