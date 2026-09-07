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
