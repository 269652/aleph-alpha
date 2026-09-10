extends GutTest

## SpriteSheetSlicer's own general-purpose pieces, tested directly against
## synthetic images (Image.create + hand-drawn pixels, mirroring
## test_composite_sheet_slicer.gd's own convention) rather than real sheet
## assets -- no existing test file covered this class before (it was
## exercised only indirectly, through IllustratedAnimalSprite/
## IllustratedFlowerHead). detect_frames/normalize_frames stay untested
## here deliberately (out of scope for this pass -- already proven
## indirectly, and not what this task's own new code needs); chroma_keyed
## and content_rect are the two pieces the new illustrated-art-addressing
## loader actually calls.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")


func _slicer() -> SpriteSheetSlicer:
	return SpriteSheetSlicer.new()


# -- chroma_keyed: turn a solid key colour transparent ----------------------
#
# Ported from an unmerged branch's own addition (never itself tested --
# see docs/progress.md's illustrated-art-addressing entry) with fresh
# tests, per CLAUDE.md's strict-TDD rule against committing untested code
# even when the implementation itself is a straight port.

func test_chroma_keyed_turns_the_key_colour_fully_transparent():
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 0, 1, 1))  # solid magenta
	var keyed := SpriteSheetSlicer.chroma_keyed(image, Color(1, 0, 1), 0.05)
	for y in 4:
		for x in 4:
			assert_almost_eq(keyed.get_pixel(x, y).a, 0.0, 0.01, "every magenta pixel must key out")


func test_chroma_keyed_leaves_a_dissimilar_colour_opaque():
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.6, 0.1, 1))  # a real drawing colour: green
	var keyed := SpriteSheetSlicer.chroma_keyed(image, Color(1, 0, 1), 0.05)
	for y in 4:
		for x in 4:
			assert_almost_eq(keyed.get_pixel(x, y).a, 1.0, 0.01, "a real drawing colour must stay opaque")


func test_chroma_keyed_respects_its_own_tolerance():
	var image := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	# Just inside tolerance of pure magenta at 0.1 -- must key out.
	image.set_pixel(0, 0, Color(0.95, 0.05, 0.95, 1))
	# Well outside tolerance -- must NOT key out, a saturated drawing colour.
	image.set_pixel(1, 0, Color(1.0, 0.0, 0.5, 1))
	var keyed := SpriteSheetSlicer.chroma_keyed(image, Color(1, 0, 1), 0.1)
	assert_almost_eq(keyed.get_pixel(0, 0).a, 0.0, 0.01, "within tolerance must key out")
	assert_almost_eq(keyed.get_pixel(1, 0).a, 1.0, 0.01, "outside tolerance must stay opaque")


func test_chroma_keyed_does_not_mutate_the_source_image():
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 0, 1, 1))
	SpriteSheetSlicer.chroma_keyed(image, Color(1, 0, 1), 0.05)
	assert_almost_eq(image.get_pixel(0, 0).a, 1.0, 0.01, "the caller's own image must be untouched")


# -- content_rect: the tight bounding box of real (non-background) pixels --

func test_content_rect_finds_the_tight_bounding_box_of_a_drawing():
	var image := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	for y in range(5, 12):
		for x in range(3, 9):
			image.set_pixel(x, y, Color(0, 0, 0, 1))
	var rect := _slicer().content_rect(image, Rect2i(0, 0, 20, 20), 0.3, 0.7)
	assert_eq(rect, Rect2i(3, 5, 6, 7))


func test_content_rect_ignores_pixels_outside_the_given_rect():
	var image := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	image.set_pixel(1, 1, Color(0, 0, 0, 1))    # outside the queried rect below
	image.set_pixel(15, 15, Color(0, 0, 0, 1))  # inside it
	var rect := _slicer().content_rect(image, Rect2i(10, 10, 10, 10), 0.3, 0.7)
	assert_eq(rect, Rect2i(15, 15, 1, 1))


func test_content_rect_of_an_empty_area_has_zero_size():
	var image := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	var rect := _slicer().content_rect(image, Rect2i(0, 0, 10, 10), 0.3, 0.7)
	assert_eq(rect.size, Vector2i.ZERO)


# -- performance: reported live, repeatedly, as "Still at 1fps" -------------
#
# A --solo boot instrumented end to end traced its own ~52-88s real cost to
# chroma_keyed/content_rect/detect_frames/normalize_frames specifically --
# every one a plain GDScript double for calling Image.get_pixel/set_pixel
# once per pixel (see each function's own doc comment for the fix and the
# fuller live-measurement writeup, and illustrated_mushroom_sprite.gd's own
# identical, independently-found duplicate of the same technique). A real
# budgeted upper bound at real-sheet resolution (not an eyeballed comment)
# is the only way to pin "fast" as a fact a future change can't silently
# regress back to the seconds-per-call the naive version measured at this
# size. Synthetic images throughout, matching this file's own convention
# (see header comment) -- real sheet assets belong to
# test_illustrated_mushroom_sprite.gd's own equivalent pin instead.

const _REAL_SHEET_SIZE := 1254

func test_chroma_keyed_completes_quickly_at_real_sheet_resolution():
	var image := Image.create(_REAL_SHEET_SIZE, _REAL_SHEET_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.5, 1.0))  # uniformly outside tolerance of the key below
	var start_usec := Time.get_ticks_usec()
	SpriteSheetSlicer.chroma_keyed(image, Color(0.98, 0.01, 0.98), 0.25)
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	assert_lt(elapsed_ms, 500.0, "chroma_keyed took %.0fms at real sheet resolution" % elapsed_ms)


## Tested at the full real-sheet size rather than one frame's own smaller
## share of it (content_rect's actual live callers pass roughly a 25th of
## this, one per detected frame) -- a wide, reliably non-flaky margin
## between the naive version's seconds-scale cost and the byte-array
## version's tens-of-ms cost matters more here than matching the exact
## real per-call size.
##
## Mostly TRANSPARENT background with a real (not full-canvas) opaque
## region in the middle, not a wall-to-wall solid fill: a real sheet's
## background is the majority of any frame rect (chroma-keyed fully
## transparent), with the actual silhouette a minority. This matters here
## specifically because a full-canvas opaque fill doesn't just skip the
## per-pixel check's own early-outs -- it ALSO forces a bounding-box
## mini/maxi update on every single pixel instead of only the real content
## ones, which measured as slow as the pre-fix naive version even after
## the check itself was properly inlined (a second false-negative test
## design caught the same way test_detect_frames_... 's own header
## documents for its function).
func test_content_rect_completes_quickly_at_real_sheet_resolution():
	var image := Image.create(_REAL_SHEET_SIZE, _REAL_SHEET_SIZE, false, Image.FORMAT_RGBA8)
	var margin := _REAL_SHEET_SIZE / 4
	for y in range(margin, _REAL_SHEET_SIZE - margin):
		for x in range(margin, _REAL_SHEET_SIZE - margin):
			image.set_pixel(x, y, Color(0, 0, 0, 1))
	var rect := Rect2i(0, 0, _REAL_SHEET_SIZE, _REAL_SHEET_SIZE)
	var start_usec := Time.get_ticks_usec()
	_slicer().content_rect(image, rect, 0.3, 0.7)
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	assert_lt(elapsed_ms, 500.0, "content_rect took %.0fms at real sheet resolution" % elapsed_ms)


## One real row-band's worth of scanning (full sheet width, one band's real
## height -- see IllustratedMushroomSprite._ROW_BANDS for the real shape).
##
## Filled fully TRANSPARENT, not with opaque content: _column_is_empty's own
## per-column scan short-circuits the instant it finds one non-empty pixel,
## so an all-content image (the actual worst case for content_rect, which
## has no such early-out) is actually the BEST case here -- it never scans
## past the first row. An all-BACKGROUND image is what forces every single
## column to scan its own full band height before concluding "empty",
## which is detect_frames' own real worst case (confirmed by first writing
## this test with an opaque fill and finding it passed even against the
## unfixed naive version -- a false-negative regression pin, caught before
## being trusted).
func test_detect_frames_completes_quickly_at_real_band_resolution():
	var band_height := _REAL_SHEET_SIZE / 5
	var image := Image.create(_REAL_SHEET_SIZE, band_height, false, Image.FORMAT_RGBA8)
	var start_usec := Time.get_ticks_usec()
	_slicer().detect_frames(image, 0, band_height)
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	# Tighter than this file's other budgets: one band's own real working set
	# (full width x one band's own height) is inherently smaller than a full
	# sheet's, so the naive version already measured only ~157ms here (still
	# a real, clearly-failing number -- comfortable margin above the
	# byte-array version's expected low-single-digit ms).
	assert_lt(elapsed_ms, 80.0, "detect_frames took %.0fms at real band resolution" % elapsed_ms)


## End to end, real shape: 5 drawn frames in one real-sized band, separated
## by real divider gaps -- detect_frames finds them, normalize_frames crops/
## scales/positions each one, exactly the pipeline _load_one_sheet actually
## runs per band.
##
## Each frame draws a real (not cell-filling) silhouette with a real
## transparent margin around it, not solid content wall to wall -- see
## test_content_rect_completes_quickly_at_real_sheet_resolution's own doc
## comment for why a full-cell fill is an unrealistic worst case that
## doesn't actually distinguish the fix from the naive version (content_
## rect runs once per frame here too).
func test_normalize_frames_completes_quickly_for_one_real_band_of_frames():
	var band_height := _REAL_SHEET_SIZE / 5
	var image := Image.create(_REAL_SHEET_SIZE, band_height, false, Image.FORMAT_RGBA8)
	var frame_width := _REAL_SHEET_SIZE / 5
	var margin := band_height / 4
	for frame_index in 5:
		var frame_left := frame_index * frame_width + 4  # +4: leaves a real divider gap
		for y in range(margin, band_height - margin):
			for x in range(frame_left + margin, frame_left + frame_width - margin):
				image.set_pixel(x, y, Color(0, 0, 0, 1))
	var slicer := _slicer()
	var frames := slicer.detect_frames(image, 0, band_height)
	assert_eq(frames.size(), 5, "the premise: 5 real frames must actually be detected")
	var start_usec := Time.get_ticks_usec()
	slicer.normalize_frames(image, frames, Vector2i(64, 64), 60)
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	assert_lt(elapsed_ms, 200.0, "normalize_frames took %.0fms for one real band of frames" % elapsed_ms)
