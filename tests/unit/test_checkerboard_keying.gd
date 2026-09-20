extends GutTest

## Keying the checkerboard a delivered sheet paints where transparency
## belongs (docs/concept/ferns.md, "The checkerboard").
##
## This routine already existed, privately, inside IllustratedStructureSprite
## for the building yard sheets. The fern sheet arrives with the SAME two
## tones, so rather than a second copy it moves to the module that owns
## keying -- SpriteSheetSlicer, beside chroma_keyed -- and the structure
## sprite reaches for it there. These pin the behaviour that move must not
## change, and the one property that makes it a flood rather than a flat
## key at all.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

const LIGHT := Color(0.992, 0.992, 0.992)  # ~253, the checker's light square
const DARK := Color(0.835, 0.835, 0.835)   # ~213, its darker one
const LEAF := Color(0.18, 0.45, 0.16)


func _checkerboard(size: int, square: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var light := ((x / square) + (y / square)) % 2 == 0
			image.set_pixel(x, y, LIGHT if light else DARK)
	return image


func test_a_sheet_that_is_all_checkerboard_ends_up_entirely_transparent():
	var keyed := SpriteSheetSlicer.checkerboard_keyed(_checkerboard(16, 4))
	for y in 16:
		for x in 16:
			assert_eq(keyed.get_pixel(x, y).a, 0.0, "%d,%d survived" % [x, y])


func test_the_art_itself_survives():
	var image := _checkerboard(16, 4)
	for y in range(6, 10):
		for x in range(6, 10):
			image.set_pixel(x, y, LEAF)
	var keyed := SpriteSheetSlicer.checkerboard_keyed(image)
	for y in range(6, 10):
		for x in range(6, 10):
			assert_eq(keyed.get_pixel(x, y).a, 1.0, "the leaf at %d,%d was eaten" % [x, y])


## The whole reason it is a FLOOD and not a flat key: the checker's light
## square and a white highlight in the art are the same colour, so a key on
## colour alone would punch holes through every bright pixel of the drawing.
## A highlight enclosed by art is not reachable from the sheet's own edge
## and is not the checker's darker tone, so it survives.
func test_a_white_highlight_walled_in_by_art_is_not_mistaken_for_background():
	var image := _checkerboard(16, 4)
	for y in range(5, 12):
		for x in range(5, 12):
			image.set_pixel(x, y, LEAF)
	image.set_pixel(8, 8, LIGHT)  # a highlight, the checker's own light tone
	var keyed := SpriteSheetSlicer.checkerboard_keyed(image)
	assert_eq(keyed.get_pixel(8, 8).a, 1.0, "a highlight inside the art was keyed out")


## ...and the other half of that: the checker's DARKER square is a tone no
## art in these sheets uses, so checker showing through a GAP in the
## foliage goes even though art encloses it and no edge flood can reach it.
func test_checker_seen_through_a_gap_in_the_art_still_goes():
	var image := _checkerboard(16, 4)
	for y in range(5, 12):
		for x in range(5, 12):
			image.set_pixel(x, y, LEAF)
	image.set_pixel(8, 8, DARK)
	var keyed := SpriteSheetSlicer.checkerboard_keyed(image)
	assert_eq(keyed.get_pixel(8, 8).a, 0.0, "checker in a gap was left behind")


## Keying answers with a NEW image; the caller's own is untouched, so a
## cached source sheet is never quietly modified under whoever else holds
## it.
func test_the_source_image_is_left_alone():
	var image := _checkerboard(16, 4)
	SpriteSheetSlicer.checkerboard_keyed(image)
	assert_eq(image.get_pixel(0, 0).a, 1.0, "the source was keyed in place")


func test_an_opaque_rgb_sheet_comes_back_with_a_real_alpha_channel():
	var rgb := Image.create(8, 8, false, Image.FORMAT_RGB8)
	rgb.fill(LIGHT)
	var keyed := SpriteSheetSlicer.checkerboard_keyed(rgb)
	assert_eq(keyed.get_format(), Image.FORMAT_RGBA8)
	assert_eq(keyed.get_pixel(0, 0).a, 0.0)
