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


# -- sheets that divide their cells with MAGENTA LINES ----------------------
#
# The sheets delivered 2026-09-17 (house_1_1.png .. house_1_5.png, well.png)
# separate their cells with magenta divider lines rather than with dark
# gutters, and the house sheets additionally carry a row of COLUMN LABELS
# across the top and a column of ROW LABELS down the left, plus a blank
# margin on the right -- all of them real, divider-separated bands that are
# not art. Measured with tools/probe_building_lifecycle_sheet.gd, never
# assumed.


## A sheet whose content bands are separated by 3px magenta divider lines,
## with one line before the first band and one after the last -- exactly
## how the real sheets are drawn.
func _divided(sizes: Array, horizontal: bool) -> Image:
	var line := 3
	var total := line
	for size in sizes:
		total += int(size) + line
	var short_side := 40
	var image := Image.create_empty(
		short_side if horizontal else total, total if horizontal else short_side, false, Image.FORMAT_RGBA8
	)
	image.fill(Color.MAGENTA)
	var at := line
	for size in sizes:
		for step in int(size):
			for other in short_side:
				if horizontal:
					image.set_pixel(other, at + step, Color.WHITE)
				else:
					image.set_pixel(at + step, other, Color.WHITE)
		at += int(size) + line
	return image


func test_divider_bands_finds_every_cell_between_the_magenta_lines():
	var bands: Array = VariantSheetGrid.divider_bands(_divided([10, 20, 30], true), true)
	assert_eq(bands.size(), 3)
	assert_eq(bands[0], Vector2i(3, 12))
	assert_eq(bands[1], Vector2i(16, 35))
	assert_eq(bands[2], Vector2i(39, 68))


func test_the_art_window_is_the_run_whose_cells_are_most_alike():
	# A label gutter, four art cells, a blank margin -- the real shape.
	var image := _divided([30, 100, 101, 99, 100, 40], true)
	var bands: Array = VariantSheetGrid.art_bands(image, 4, true)
	assert_eq(bands.size(), 4)
	for band in bands:
		var size: int = (band as Vector2i).y - (band as Vector2i).x + 1
		assert_between(size, 99, 101, "%s is a label or a margin, not an art cell" % str(band))


func test_asking_for_more_cells_than_the_sheet_has_falls_back_to_even_division():
	var image := _divided([10, 20], true)
	var bands: Array = VariantSheetGrid.art_bands(image, 5, true)
	assert_eq(bands.size(), 5, "an unreadable sheet still cuts, just evenly")
	assert_eq(bands[0].x, 0, "an even division starts at the very top")


func test_the_real_lifecycle_sheet_carries_a_label_row_a_label_column_and_a_margin():
	var image := Image.load_from_file("res://assets/sprites/buildings/house_1_1.png")
	assert_not_null(image, "precondition: the sheet is on disk")
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	assert_eq(
		VariantSheetGrid.divider_bands(image, true).size(), 11,
		"ten rows of art, plus the column-label row across the top"
	)
	assert_eq(
		VariantSheetGrid.divider_bands(image, false).size(), 10,
		"eight columns of art, plus the row-label gutter and the right margin"
	)


func test_the_real_lifecycle_sheets_art_window_skips_the_labels():
	var image := Image.load_from_file("res://assets/sprites/buildings/house_1_1.png")
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var rows: Array = VariantSheetGrid.art_bands(image, 10, true)
	var columns: Array = VariantSheetGrid.art_bands(image, 8, false)
	assert_eq(rows.size(), 10)
	assert_eq(columns.size(), 8)
	assert_gt(
		(rows[0] as Vector2i).x, 40,
		"the first art row must start below the column-label row, not at the top of the sheet"
	)
	assert_gt(
		(columns[0] as Vector2i).x, 110,
		"the first art column must start right of the row-label gutter"
	)
	var last: Vector2i = columns[columns.size() - 1]
	assert_lt(last.y, image.get_width() - 40, "the blank right margin is not an art column")


func test_every_cell_of_the_real_lifecycle_sheet_holds_real_art():
	var image := Image.load_from_file("res://assets/sprites/buildings/house_1_1.png")
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	for row in 10:
		for column in 8:
			var rect := VariantSheetGrid.divider_cell_rect(image, 8, 10, row, column)
			var cell := image.get_region(rect)
			var lit := 0
			for y in range(0, cell.get_height(), 4):
				for x in range(0, cell.get_width(), 4):
					var pixel := cell.get_pixel(x, y)
					if pixel.r > 0.2 or pixel.g > 0.2 or pixel.b > 0.2:
						lit += 1
			assert_gt(lit, 0, "cell (row %d, column %d) is empty -- the grid is cutting in the wrong place" % [row, column])


func test_the_well_sheet_is_a_five_by_five_grid_between_its_dividers():
	var image := Image.load_from_file("res://assets/sprites/buildings/well.png")
	assert_not_null(image, "precondition: the sheet is on disk")
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	assert_eq(VariantSheetGrid.divider_bands(image, true).size(), 5)
	assert_eq(VariantSheetGrid.divider_bands(image, false).size(), 5)
