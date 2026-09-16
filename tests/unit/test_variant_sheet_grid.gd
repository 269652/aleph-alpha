extends GutTest

## VariantSheetGrid: where a grid sheet's cells really are.
##
## A variant sheet (docs/concept/building.md, "Building variant sheets") is
## a grid of complete buildings on a dark background. Dividing the image
## evenly ASSUMES the art was laid out on an exact pitch with no margin,
## and hand-drawn sheets are not: house_1.png's own rows sit ~213px apart
## with 45px of blank at the bottom, so an even fifth-of-the-height cut
## drifts further into the next row with every row -- slicing the chimney
## off one cottage and gluing a strip of grass to the next.
##
## So the cuts are found in the sheet's own background GUTTERS, and fall
## back to even division when a sheet genuinely has none.

const VariantSheetGrid = preload("res://src/rendering/variant_sheet_grid.gd")


## A sheet with `count` content bands separated by real gutters: content
## rows are white, gutters are black. `heights`/`gaps` let a test build an
## UNEVEN sheet, which is the whole point.
func _striped(heights: Array, gaps: Array, horizontal: bool) -> Image:
	var total := 0
	for i in heights.size():
		total += int(heights[i])
		if i < gaps.size():
			total += int(gaps[i])
	var long_side := total
	var short_side := 20
	var image := Image.create_empty(
		short_side if horizontal else long_side, long_side if horizontal else short_side, false, Image.FORMAT_RGBA8
	)
	image.fill(Color.BLACK)
	var at := 0
	for i in heights.size():
		for step in int(heights[i]):
			for other in short_side:
				if horizontal:
					image.set_pixel(other, at + step, Color.WHITE)
				else:
					image.set_pixel(at + step, other, Color.WHITE)
		at += int(heights[i])
		if i < gaps.size():
			at += int(gaps[i])
	return image


func test_evenly_spaced_bands_are_found_where_they_are():
	var image := _striped([10, 10, 10], [4, 4], true)
	var bands: Array = VariantSheetGrid.row_bands(image, 3)
	assert_eq(bands.size(), 3)
	assert_eq(bands[0], Vector2i(0, 9))
	assert_eq(bands[1], Vector2i(14, 23))
	assert_eq(bands[2], Vector2i(28, 37))


## The case that matters: bands of DIFFERENT heights, which an even
## division gets progressively wronger about.
func test_unevenly_spaced_bands_are_still_found_exactly():
	var image := _striped([20, 12, 30], [5, 3], true)
	var bands: Array = VariantSheetGrid.row_bands(image, 3)
	assert_eq(bands.size(), 3)
	assert_eq(bands[0], Vector2i(0, 19))
	assert_eq(bands[1], Vector2i(25, 36))
	assert_eq(bands[2], Vector2i(40, 69))


func test_a_trailing_margin_is_not_mistaken_for_a_band():
	# 30px of blank at the end, exactly what house_1.png has.
	var image := _striped([10, 10, 30], [4, 4], true)
	image.fill_rect(Rect2i(0, 38, image.get_width(), 30), Color.BLACK)
	var bands: Array = VariantSheetGrid.row_bands(image, 3)
	assert_eq(bands.size(), 3, "the blank tail is margin, not a fourth row")
	assert_eq(bands[2].x, 28)


func test_columns_are_found_the_same_way_along_the_other_axis():
	var image := _striped([8, 8], [6], false)
	var bands: Array = VariantSheetGrid.column_bands(image, 2)
	assert_eq(bands.size(), 2)
	assert_eq(bands[0], Vector2i(0, 7))
	assert_eq(bands[1], Vector2i(14, 21))


## A sheet with no gutters at all must still slice, evenly -- detection is
## an improvement on even division, never a precondition for slicing.
func test_a_sheet_with_no_gutters_falls_back_to_even_division():
	var image := Image.create_empty(40, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var bands: Array = VariantSheetGrid.row_bands(image, 4)
	assert_eq(bands.size(), 4)
	assert_eq(bands[0], Vector2i(0, 9))
	assert_eq(bands[3], Vector2i(30, 39))


## Finding a DIFFERENT number of bands than asked for is not a licence to
## guess -- an even division is the honest answer then.
func test_finding_the_wrong_number_of_bands_falls_back_to_even_division():
	var image := _striped([10, 10], [4], true)  # two bands
	var bands: Array = VariantSheetGrid.row_bands(image, 5)  # asked for five
	assert_eq(bands.size(), 5)
	assert_eq(bands[0].x, 0, "an even fifth of the height, not a guess")


func test_cell_rect_combines_the_two_axes():
	var image := Image.create_empty(40, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var rect: Rect2i = VariantSheetGrid.cell_rect(image, 2, 2, 1, 1)
	assert_eq(rect, Rect2i(20, 20, 20, 20))


# -- against the real sheet ------------------------------------------------

func test_the_real_cottage_sheet_slices_without_cutting_a_single_house():
	var path := "res://assets/sprites/buildings/house_1.png"
	if not FileAccess.file_exists(path):
		pass_test("the cottage sheet is not in this checkout")
		return
	var SpriteSheetLoader = load("res://src/rendering/sprite_sheet_loader.gd")
	var image: Image = SpriteSheetLoader.load_image(path)
	assert_not_null(image, "precondition: the sheet loads")

	var rows: Array = VariantSheetGrid.row_bands(image, 5)
	assert_eq(rows.size(), 5, "five real rows of cottages")
	# Every row must be a real band with a real gutter after it -- which is
	# exactly what an even division of this sheet does NOT produce.
	for i in rows.size() - 1:
		assert_lt(rows[i].y, rows[i + 1].x, "row %d runs into row %d" % [i, i + 1])
	var columns: Array = VariantSheetGrid.column_bands(image, 5)
	assert_eq(columns.size(), 5, "five real columns of cottages")
