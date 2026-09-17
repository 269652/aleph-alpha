extends GutTest

## Where a building sheet's cells actually are (see
## IllustratedStructureSprite.even_cell_rect, docs/concept/building.md's
## "Building sheets"). Reported live: "The warehouse has the rows cropped
## wrongly and its scale as well."
##
## Pure arithmetic over a canvas size, so the real 1536x1024 sheets can be
## checked without loading a 1.5MB image per assertion.

const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

## Every production/civic sheet on disk today, measured.
const REAL_SHEET_WIDTH := 1536
const REAL_SHEET_HEIGHT := 1024


## The bug, stated as a test. 1536/8 is exactly 192, but 1024/5 is 204.8 --
## so dividing the canvas evenly on BOTH axes walks every row after the
## first progressively further down the sheet (0, +13, +26, +38, +51px),
## which at a 192px cell is a quarter of a cell of someone else's art.
func test_the_real_sheets_rows_sit_on_the_column_pitch_not_the_canvas_height():
	for row in 5:
		var rect: Rect2i = IllustratedStructureSprite.even_cell_rect(
			REAL_SHEET_WIDTH, REAL_SHEET_HEIGHT, 8, 5, row, 0
		)
		assert_eq(rect.position.y, row * 192, "row %d must start on the 192 grid the art is drawn on" % row)
		assert_eq(rect.size, Vector2i(192, 192), "a cell is square: the art is drawn in square cells")


func test_columns_are_unchanged_because_they_were_always_right():
	for column in 8:
		var rect: Rect2i = IllustratedStructureSprite.even_cell_rect(
			REAL_SHEET_WIDTH, REAL_SHEET_HEIGHT, 8, 5, 0, column
		)
		assert_eq(rect.position.x, column * 192, "column %d" % column)


## The slack the generator left below the grid (1024 - 5*192 = 64px) is not
## art and must never be cropped into a cell.
func test_the_canvas_slack_below_the_grid_is_never_reached():
	var last: Rect2i = IllustratedStructureSprite.even_cell_rect(
		REAL_SHEET_WIDTH, REAL_SHEET_HEIGHT, 8, 5, 4, 7
	)
	assert_eq(last.position.y + last.size.y, 960, "the grid ends at 960; the rest is slack")
	assert_lte(last.position.x + last.size.x, REAL_SHEET_WIDTH)


## A sheet whose canvas ALREADY matches its grid exactly must be cut
## exactly as before -- this fix may only change what was wrong.
func test_a_sheet_that_already_divided_evenly_is_cut_exactly_as_before():
	for row in 5:
		for column in 8:
			var rect: Rect2i = IllustratedStructureSprite.even_cell_rect(1536, 960, 8, 5, row, column)
			assert_eq(rect, Rect2i(column * 192, row * 192, 192, 192), "r%d c%d" % [row, column])


## Never off the canvas, whatever it is handed -- a sheet smaller than its
## own declared grid must clamp rather than ask for pixels that do not
## exist.
func test_a_cell_never_runs_off_the_canvas():
	var rect: Rect2i = IllustratedStructureSprite.even_cell_rect(100, 100, 8, 5, 4, 7)
	assert_lte(rect.position.x + rect.size.x, 100)
	assert_lte(rect.position.y + rect.size.y, 100)
	assert_gt(rect.size.x, 0)
	assert_gt(rect.size.y, 0)


# -- the warehouse's own footprint -----------------------------------------

## Reported live: "should be only 3 tiles wide not 4". The art is drawn in
## SQUARE cells, and footprint_frame_texture scales a frame by its WIDTH
## (tile_size * footprint_width), so a warehouse claiming 4 tiles was drawn
## a third wider than it should be -- the "scale as well" half of the same
## report.
func test_the_warehouse_is_three_tiles_wide():
	assert_eq(BuildingCatalog.footprint_of("warehouse").x, 3)


## Its depth is untouched: only the width was reported wrong, and a
## 3x3 warehouse matches the square cell its art is drawn in.
func test_the_warehouse_keeps_its_depth():
	assert_eq(BuildingCatalog.footprint_of("warehouse").y, 3)
