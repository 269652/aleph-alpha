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


# -- detect_rows: the horizontal counterpart of detect_frames ---------------
#
# detect_frames cuts a BAND of rows into frames by scanning for empty
# columns. A sheet laid out as a real grid -- the apple sapling sheet is 5
# growth stages down by 5 canopy frames across (see docs/concept/flora.md's
# "Sapling phase") -- needs the other axis first: which bands of rows a
# drawing occupies at all. The rows are NOT evenly spaced on that sheet (the
# bands measure 122, 173, 215, 250 and 302 pixels tall, because the tree
# gets bigger every stage), so they have to be found rather than assumed.

func _banded_image(bands: Array, width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for band in bands:
		for y in range(band[0], band[1]):
			for x in range(width):
				image.set_pixel(x, y, Color(0.2, 0.5, 0.2, 1.0))
	return image


func test_detect_rows_finds_the_bands_a_drawing_occupies():
	var image := _banded_image([[2, 10], [16, 30], [40, 44]], 12, 50)
	var rows := _slicer().detect_rows(image, 0, 12, 3)
	assert_eq(rows.size(), 3, "three separated bands should be three rows")
	assert_eq(rows[0], Rect2i(0, 2, 12, 8))
	assert_eq(rows[1], Rect2i(0, 16, 12, 14))
	assert_eq(rows[2], Rect2i(0, 40, 12, 4))


## A stray mark thinner than a real row is not a row -- the same contract
## min_frame_width gives detect_frames, on the other axis.
func test_detect_rows_ignores_a_band_thinner_than_the_minimum():
	var image := _banded_image([[2, 4], [16, 30]], 12, 40)
	var rows := _slicer().detect_rows(image, 0, 12, 5)
	assert_eq(rows.size(), 1, "a two-pixel stray is not a growth stage")
	assert_eq(rows[0].position.y, 16)


## Only the given columns are scanned, so one column of a grid can be read
## on its own -- exactly what detect_frames' own top_y/bottom_y band does.
func test_detect_rows_only_looks_inside_the_given_columns():
	var image := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(4, 8):
		image.set_pixel(15, y, Color(0.2, 0.5, 0.2, 1.0))
	assert_eq(_slicer().detect_rows(image, 0, 10, 2).size(), 0, "content outside the columns")
	var rows := _slicer().detect_rows(image, 10, 20, 2)
	assert_eq(rows.size(), 1)
	assert_eq(rows[0], Rect2i(10, 4, 10, 4))


## A pale, unsaturated divider counts as empty, the same way detect_frames
## reads one -- which is what lets a row band be found on a sheet whose
## background is still the delivered CHECKERBOARD, before any keying has
## happened and while every pixel is opaque.
func test_detect_rows_reads_a_pale_divider_as_empty():
	var image := Image.create(8, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.992, 0.992, 0.992, 1.0))  # the checker's light tone
	for y in range(5, 9):
		for x in range(8):
			image.set_pixel(x, y, Color(0.2, 0.5, 0.2, 1.0))
	var rows := _slicer().detect_rows(image, 0, 8, 2)
	assert_eq(rows.size(), 1, "an opaque pale background is still background")
	assert_eq(rows[0], Rect2i(0, 5, 8, 4))


# -- what "empty" means to detect_frames, and why the art brief says magenta


## A DARK opaque backdrop never separates frames -- pure black included.
## Nothing dark and opaque is empty to detect_frames, so every column reads
## as drawing and the row collapses to one frame.
##
## Worth pinning precisely because the code says otherwise: the column
## scan's `mx == 0` branch carries a comment claiming it matches
## "is_empty()'s own zero-max case", which does not exist -- is_empty calls
## black content too, and that branch is a divide-by-zero guard for the
## saturation ratio below it, unreachable for an opaque pixel at any normal
## divider_gray_min. Reading that comment is what put "#0a0a0a is fine if
## it is exactly black" into docs/concept/monsters.md's art brief; this
## test is what took it back out.
func test_no_dark_opaque_backdrop_separates_frames_not_even_pure_black():
	for backdrop in [Color8(0, 0, 0), Color8(10, 10, 10), Color8(30, 30, 42), Color8(14, 16, 17)]:
		var frames := _slicer().detect_frames(_sheet_on(backdrop), 0, 40, 8, 1)
		assert_eq(frames.size(), 1, "backdrop %s should defeat frame detection" % backdrop)


## Transparency separates them...
func test_frames_separate_over_a_transparent_backdrop():
	var frames := _slicer().detect_frames(_sheet_on(Color(0, 0, 0, 0)), 0, 40, 8, 1)
	assert_eq(frames.size(), 3, "three drawings separated by transparent gaps")


## ...and so does an opaque near-WHITE one, with no chroma key at all,
## because pale and near-neutral is exactly what the divider rule calls
## empty. This is not a hypothetical: boar_walk.png ships on a
## rgba(253,254,253) backdrop, declares no chroma_key, and slices to its 8
## frames. Pinned because the obvious generalisation from the black case --
## "no opaque backdrop works" -- is false, and briefing an artist on it
## would send them to a chroma key they do not need.
func test_an_opaque_near_white_backdrop_separates_frames_with_no_key():
	var frames := _slicer().detect_frames(_sheet_on(Color8(253, 254, 253)), 0, 40, 8, 1)
	assert_eq(frames.size(), 3, "white is pale and neutral, so it reads as empty")


## The catch that decides between the two, and why sheep/wolf use magenta
## while boar/deer/horse do not: a white backdrop is indistinguishable from
## near-white, low-saturation ART. A creature carrying bone, cream wool or
## white cloth loses it to the backdrop rule.
func test_a_white_backdrop_eats_near_white_parts_of_the_drawing():
	var image := _sheet_on(Color8(253, 254, 253))
	# A bone-white detail on the middle drawing -- pale, barely saturated.
	for x in range(45, 65):
		for y in range(12, 28):
			image.set_pixel(x, y, Color8(246, 244, 238))
	var slicer := _slicer()
	var frames := slicer.detect_frames(image, 0, 40, 8, 1)
	var middle := slicer.content_rect(image, frames[1], 0.3, 0.7)
	assert_eq(
		middle.size.x, 20,
		"the bone detail should have been swallowed, leaving only the 20px body"
	)


## Chroma-keying that backdrop to real transparency first is what rescues
## it -- the route every sheet in this repo actually takes, just with
## magenta rather than a colour the art also contains.
func test_keying_the_backdrop_out_first_restores_the_frames():
	var keyed := SpriteSheetSlicer.chroma_keyed(_sheet_on(Color8(10, 10, 10)), Color8(10, 10, 10), 0.05)
	assert_eq(_slicer().detect_frames(keyed, 0, 40, 8, 1).size(), 3)


## A drawn cell BORDER only stays out of the way when it is pale on every
## channel (>= DEFAULT_DIVIDER_GRAY_MIN) and near-neutral. This is the more
## dangerous half of the pair, because a border runs the full WIDTH of its
## row: one mid-grey horizontal rule puts a content pixel in every column
## at once, so the row has no empty column anywhere and collapses to a
## single frame no matter how clean the gaps between the drawings are.
## The other half of the same reported delivery -- its borders measured
## around 112-143, where 178 is the floor.
func test_a_mid_grey_cell_border_collapses_the_row_to_one_frame():
	var pale := _sheet_on(Color(0, 0, 0, 0), Color8(200, 200, 200))
	assert_eq(_slicer().detect_frames(pale, 0, 40, 8, 1).size(), 3, "a pale border stays out of the way")
	var mid := _sheet_on(Color(0, 0, 0, 0), Color8(128, 128, 128))
	assert_eq(_slicer().detect_frames(mid, 0, 40, 8, 1).size(), 1, "a mid-grey one does not")


## A vertical rule inside a gap is harmless whatever its colour -- it is
## narrower than min_frame_width, so it is discarded rather than mistaken
## for a drawing. Worth stating beside the test above, because the two look
## like the same "drawn divider" problem and only one of them is.
func test_a_narrow_vertical_rule_in_a_gap_is_discarded_not_mistaken_for_a_frame():
	var image := _sheet_on(Color(0, 0, 0, 0))
	for gap in 4:
		var x: int = gap * 30 + 4
		for y in image.get_height():
			image.set_pixel(x, y, Color8(128, 128, 128))
	assert_eq(_slicer().detect_frames(image, 0, 40, 8, 1).size(), 3)


## Three 20px drawings on `backdrop`, separated by 10px gaps. `border`, when
## given, is ruled across the FULL WIDTH at the top and bottom of the band
## -- what a drawn cell grid actually puts on a sheet.
func _sheet_on(backdrop: Color, border = null) -> Image:
	var image := Image.create(100, 40, false, Image.FORMAT_RGBA8)
	image.fill(backdrop)
	for drawing in 3:
		var left := 10 + drawing * 30
		for x in range(left, left + 20):
			for y in range(10, 30):
				image.set_pixel(x, y, Color(0.2, 0.7, 0.3))
	if border != null:
		for x in image.get_width():
			image.set_pixel(x, 1, border)
			image.set_pixel(x, image.get_height() - 2, border)
	return image


## Content far larger than the canvas does NOT overflow it: normalize_frames
## picks ONE scale for the whole set, min(canvas.x / widest, baseline_y /
## tallest), and every frame is resized by it before being blitted. width
## can therefore never exceed canvas.x and height never exceeds baseline_y,
## so `left` and `top` are always >= 0.
##
## Pinned because the opposite was written down in two places and acted on:
## IllustratedAnimalSprite's CANVAS_SIZE comment says "too little margin
## overflows the canvas outright (Image.set_pixel errors on an out-of-bounds
## index, not a silent clip)", and that claim was carried into
## docs/concept/monsters.md's art brief as a hard ~300x290 ceiling on drawn
## content. Whatever was once true of it, this is what the code does now --
## an oversized sheet comes back scaled down, not raising.
func test_content_far_larger_than_the_canvas_is_scaled_down_not_overflowed():
	var image := Image.create(2000, 1200, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in range(100, 1900):
		for y in range(100, 1100):
			image.set_pixel(x, y, Color(0.2, 0.7, 0.3))
	var canvas := Vector2i(340, 330)
	var normalized := _slicer().normalize_frames(image, [Rect2i(0, 0, 2000, 1200)], canvas, 310)
	assert_eq(normalized.size(), 1)
	assert_eq(normalized[0].get_size(), canvas, "comes back canvas-sized, having been scaled to fit")


## And the drawing really is inside the canvas afterwards, feet on the
## baseline -- not merely clipped to it.
func test_an_oversized_frame_still_lands_with_its_feet_on_the_baseline():
	var image := Image.create(1200, 900, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in range(50, 1150):
		for y in range(50, 850):
			image.set_pixel(x, y, Color(0.2, 0.7, 0.3))
	var normalized := _slicer().normalize_frames(image, [Rect2i(0, 0, 1200, 900)], Vector2i(340, 330), 310)
	var frame: Image = normalized[0]
	var lowest := -1
	for y in frame.get_height():
		for x in frame.get_width():
			if frame.get_pixel(x, y).a > 0.5:
				lowest = maxi(lowest, y)
	assert_between(lowest, 305, 310, "the drawing's own bottom row should sit on the baseline")


## ONE scale serves the whole set, so a single oversized frame shrinks
## every other frame in the same action. This is the real cost of a row
## whose creature is not drawn at a consistent size -- not a crash, which
## is what the canvas comment claimed, but a whole animation rendering
## smaller because of one frame in it.
func test_one_oversized_frame_shrinks_every_other_frame_in_its_set():
	var image := Image.create(900, 400, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	# Two equal drawings, then a third drawn twice as tall.
	_box(image, Rect2i(10, 200, 100, 100))
	_box(image, Rect2i(310, 200, 100, 100))
	var alone := _slicer().normalize_frames(
		image, [Rect2i(0, 0, 300, 400), Rect2i(300, 0, 300, 400)], Vector2i(340, 330), 310
	)
	_box(image, Rect2i(610, 100, 100, 200))
	var together := _slicer().normalize_frames(
		image,
		[Rect2i(0, 0, 300, 400), Rect2i(300, 0, 300, 400), Rect2i(600, 0, 300, 400)],
		Vector2i(340, 330), 310
	)
	assert_lt(
		_drawn_height(together[0]), _drawn_height(alone[0]),
		"frame 0 should render smaller once an oversized sibling joins its set"
	)


func _box(image: Image, rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			image.set_pixel(x, y, Color(0.2, 0.7, 0.3))


func _drawn_height(frame: Image) -> int:
	var top := -1
	var bottom := -1
	for y in frame.get_height():
		for x in frame.get_width():
			if frame.get_pixel(x, y).a > 0.5:
				if top < 0:
					top = y
				bottom = y
				break
	return 0 if top < 0 else bottom - top + 1
