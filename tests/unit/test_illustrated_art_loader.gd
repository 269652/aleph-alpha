extends GutTest

## illustrated_art_loader.gd -- see docs/concept/illustrated_art_addressing.md
## "The address" table's Anchors section, and "One generic loader slices,
## keys and anchors by this field." Tested against synthetic images
## (Image.create + hand-drawn pixels, mirroring test_composite_sheet_
## slicer.gd's own convention), not real sheet files -- `frames_for_image`
## takes an already-loaded Image directly so these tests never touch disk;
## `load_row` (path -> SpriteSheetLoader.load_image -> frames_for_image) is
## the thin, untested-here glue a real caller uses.

const IllustratedArtLoader = preload("res://src/rendering/illustrated_art_loader.gd")

const _MAGENTA := Color(1, 0, 1, 1)
const _TOLERANCE := 0.05


func _loader() -> IllustratedArtLoader:
	return IllustratedArtLoader.new()


## A single-row sheet with `count` frames, each `frame_width`x`height`, on
## a solid magenta chroma-key ground (real content, never itself read as
## a divider -- pure magenta is fully saturated, so it fails detect_frames'
## own near-white/low-saturation background check pre-keying, exactly like
## real chroma-keyed art), separated by a real near-white divider line
## (the actual file-format convention, not just relying on the gap between
## cells -- see illustrated_art_loader.gd's own doc comment on why cell
## detection must happen BEFORE chroma-keying). Each frame gets a small
## solid content block at `content_offset` within its own cell, sized
## `content_size`, in a distinct opaque colour -- never touching the
## cell's own edges, so content-cropping (center anchor) has real
## background to crop away on every side.
func _sheet(
	count: int, frame_width: int, height: int, content_offset: Vector2i, content_size: Vector2i
) -> Image:
	var divider := 2
	var width := count * frame_width + (count - 1) * divider
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(_MAGENTA)
	for i in range(count - 1):
		var divider_x := (i + 1) * frame_width + i * divider
		for y in height:
			for dx in divider:
				image.set_pixel(divider_x + dx, y, Color(1, 1, 1, 1))
	for i in count:
		var cell_x := i * (frame_width + divider)
		var color := Color(0.1 + 0.2 * i, 0.6, 0.2, 1)  # a distinct, non-magenta colour per frame
		for y in range(content_offset.y, content_offset.y + content_size.y):
			for x in range(content_offset.x, content_offset.x + content_size.x):
				image.set_pixel(cell_x + x, y, color)
	return image


# -- the pipeline itself: chroma-key, then detect_frames -------------------

func test_an_unrecognized_anchor_returns_no_frames():
	var image := _sheet(1, 20, 20, Vector2i(5, 5), Vector2i(10, 10))
	var frames := _loader().frames_for_image(image, "not_a_real_anchor", _MAGENTA, _TOLERANCE, Vector2i(32, 32), 16)
	assert_eq(frames.size(), 0)


func test_a_sheet_with_no_detectable_frames_returns_empty():
	# Genuinely transparent, not magenta -- a solid magenta fill is real,
	# opaque, fully-saturated content as far as detect_frames' own
	# pre-keying is_empty check is concerned (it only recognizes
	# transparency or a near-white divider -- see illustrated_art_
	# loader.gd's own doc comment), so an all-magenta image is actually
	# ONE valid, if entirely-background-once-keyed, frame -- not zero.
	var image := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	var frames := _loader().frames_for_image(image, "pivot", _MAGENTA, _TOLERANCE, Vector2i(32, 32), 16)
	assert_eq(frames.size(), 0)


# -- pivot: the whole cell, unmodified, content never re-centered ----------

func test_pivot_returns_one_frame_per_cell_at_the_cells_own_size():
	var image := _sheet(3, 20, 20, Vector2i(5, 5), Vector2i(10, 10))
	var frames := _loader().frames_for_image(image, "pivot", _MAGENTA, _TOLERANCE, Vector2i(32, 32), 16)
	assert_eq(frames.size(), 3)
	for frame in frames:
		assert_eq(frame.get_size(), Vector2i(20, 20), "pivot must keep the whole cell, never content-crop")


func test_pivot_keeps_content_at_its_own_drawn_pixel_not_recentered():
	# Content drawn off-centre within its cell (near the top-left) --
	# pivot's whole point is that a grip point stays at the same CELL
	# pixel every frame, so this must land at the exact same offset it
	# was drawn at, not slide toward the cell's centre the way a content-
	# cropped anchor (center/baseline) would.
	var image := _sheet(1, 20, 20, Vector2i(2, 2), Vector2i(6, 6))
	var frames := _loader().frames_for_image(image, "pivot", _MAGENTA, _TOLERANCE, Vector2i(32, 32), 16)
	assert_eq(frames.size(), 1)
	var frame: Image = frames[0]
	assert_gt(frame.get_pixel(4, 4).a, 0.5, "the drawn content must still be at its own cell offset")
	assert_almost_eq(frame.get_pixel(15, 15).a, 0.0, 0.01, "background elsewhere in the cell stays transparent")


# -- center: content-cropped and centered on a square canvas ---------------

func test_center_places_off_centre_content_at_the_canvas_centre():
	# A TALL, NARROW 4x16 block drawn near a cell's own top-left corner
	# (well off-centre) -- deliberately non-square, so scale-to-fit a
	# square canvas leaves real, checkable margin on the narrow axis
	# (a square content block scaled to a square canvas fills it exactly
	# with zero margin either way, which would prove nothing about
	# centering specifically). center must still land the content in the
	# MIDDLE of the returned canvas -- unlike pivot, which would leave it
	# at its own original off-centre cell offset.
	var image := _sheet(1, 30, 30, Vector2i(2, 2), Vector2i(4, 16))
	var canvas_size := Vector2i(32, 32)
	var frames := _loader().frames_for_image(image, "center", _MAGENTA, _TOLERANCE, canvas_size, 16)
	assert_eq(frames.size(), 1)
	var frame: Image = frames[0]
	assert_eq(frame.get_size(), canvas_size)
	# Content aspect 4:16 scaled to fit 32x32 -> height-bound, scale=2:
	# 8 wide, 32 tall (fills the canvas vertically exactly, leaving no
	# vertical margin to check -- only horizontal centering is testable
	# here, which is exactly what this test is for).
	assert_gt(frame.get_pixel(16, 16).a, 0.5, "content must be centered on the canvas")
	assert_almost_eq(frame.get_pixel(2, 16).a, 0.0, 0.01, "left margin must be empty -- content is centered, not left-aligned")
	assert_almost_eq(frame.get_pixel(29, 16).a, 0.0, 0.01, "right margin must be empty -- content is centered, not right-aligned")


func test_center_preserves_aspect_ratio_rather_than_stretching():
	# A wide, short content block (12x4) -- center must scale it down to
	# fit within the canvas without distorting its own proportions.
	var image := _sheet(1, 30, 30, Vector2i(5, 13), Vector2i(12, 4))
	var frames := _loader().frames_for_image(image, "center", _MAGENTA, _TOLERANCE, Vector2i(20, 20), 16)
	var frame: Image = frames[0]
	# Find the actual drawn bounding box within the returned canvas.
	var min_x := frame.get_width()
	var max_x := -1
	var min_y := frame.get_height()
	var max_y := -1
	for y in frame.get_height():
		for x in frame.get_width():
			if frame.get_pixel(x, y).a > 0.5:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	var drawn_width := max_x - min_x + 1
	var drawn_height := max_y - min_y + 1
	# Original aspect was 12:4 = 3:1 -- must still be close to 3:1, not
	# stretched toward the canvas's own 1:1 shape.
	assert_almost_eq(float(drawn_width) / float(drawn_height), 3.0, 0.5)


# -- footprint: width matches the tile, height scales proportionally -------

func test_footprint_scales_the_whole_cell_so_its_width_matches_the_tile():
	# A 20x40 cell (taller than wide, like a campfire) with tile_size=10:
	# width must become exactly 10, height half of 40 = 20, preserving
	# the cell's own 1:2 aspect -- a tall structure stays tall.
	var image := _sheet(1, 20, 40, Vector2i(5, 5), Vector2i(10, 10))
	var frames := _loader().frames_for_image(image, "footprint", _MAGENTA, _TOLERANCE, Vector2i(32, 32), 10)
	assert_eq(frames.size(), 1)
	var frame: Image = frames[0]
	assert_eq(frame.get_width(), 10)
	assert_eq(frame.get_height(), 20)


func test_footprint_does_not_content_crop_the_cell():
	# Content drawn off-centre -- footprint keeps the WHOLE cell (like
	# pivot), just uniformly scaled, so the content stays at its own
	# relative position within the scaled cell rather than re-centering.
	var image := _sheet(1, 20, 20, Vector2i(2, 2), Vector2i(4, 4))
	var frames := _loader().frames_for_image(image, "footprint", _MAGENTA, _TOLERANCE, Vector2i(32, 32), 10)
	var frame: Image = frames[0]
	assert_eq(frame.get_size(), Vector2i(10, 10), "width->tile_size, height scaled by the same factor as a 20->10 cell")
	# Scaled by half: content that was at (2,2)-(6,6) lands near (1,1)-(3,3).
	assert_gt(frame.get_pixel(2, 2).a, 0.3, "scaled content must still be near its own original corner")


# -- baseline: dispatches to the existing, already-tested normalize_frames -

func test_baseline_returns_frames_sized_to_the_requested_canvas():
	var image := _sheet(2, 20, 20, Vector2i(5, 5), Vector2i(10, 10))
	var canvas_size := Vector2i(40, 40)
	var frames := _loader().frames_for_image(image, "baseline", _MAGENTA, _TOLERANCE, canvas_size, 16)
	assert_eq(frames.size(), 2)
	for frame in frames:
		assert_eq(frame.get_size(), canvas_size)
