extends GutTest

## Where a building sheet's cells actually are, and which pixels of one get
## cropped (see IllustratedStructureSprite.even_cell_rect /
## even_cell_crop, docs/concept/building.md's "Building sheets").
## Reported live: "The warehouse has the rows cropped wrongly and its scale
## as well."
##
## Pure arithmetic over a canvas size, so the real 1536x1024 sheets can be
## checked without loading a 1.5MB image per assertion.

const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

## Any tile size: the contract is "the frame is footprint_width tiles
## across", not a particular pixel count.
const _TILE := 16

## Every production/civic sheet on disk today, measured.
const REAL_SHEET_WIDTH := 1536
const REAL_SHEET_HEIGHT := 1024


# -- the grid the art is drawn on ------------------------------------------

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


# -- the divider line, and the crop that clears it -------------------------

## The sheets draw a thin light divider between cells and a border around
## the canvas. Measured on warehouse.png: the pixel at the cell corner
## (0, 384) reads (0.992, 0.969, 0.996) -- near-white, so neither the
## magenta nor the near-black key removes it, and the sheet's own magenta
## background only starts 5px in. A cell cut exactly on the grid therefore
## carries that line up its own top and left edge as a hard opaque fringe.
##
## 3px clears a divider measured at up to 3px, and the real art starts 8px
## inside a cell boundary on these sheets, so it can never reach a
## building.
func test_the_inset_clears_the_divider_without_reaching_the_art():
	assert_gte(IllustratedStructureSprite.CELL_INSET, 3, "must clear a divider measured at up to 3px")
	assert_lt(IllustratedStructureSprite.CELL_INSET, 8, "must never reach the art, which starts 8px in")


## An inset is only worth taking while it costs a small part of the cell.
## On a cell small enough that trimming both edges eats more than
## MAX_INSET_SHARE of it, the fringe is the lesser evil -- so the rule is
## the share, not a hand-picked pixel count.
func test_a_192_cell_takes_the_full_inset():
	assert_eq(IllustratedStructureSprite.inset_for_cell(192), IllustratedStructureSprite.CELL_INSET)


func test_a_cell_too_small_to_spare_its_edges_keeps_the_fringe():
	assert_eq(IllustratedStructureSprite.inset_for_cell(16), 0)


func test_the_inset_is_taken_exactly_while_it_costs_no_more_than_the_allowed_share():
	var share := IllustratedStructureSprite.MAX_INSET_SHARE
	var inset := IllustratedStructureSprite.CELL_INSET
	for cell in range(1, 400):
		var trimmed := float(IllustratedStructureSprite.inset_for_cell(cell) * 2) / float(cell)
		assert_lte(trimmed, share, "cell %d may never lose more than the allowed share" % cell)
		if float(inset * 2) / float(cell) <= share:
			assert_eq(
				IllustratedStructureSprite.inset_for_cell(cell), inset,
				"cell %d can afford the inset and must take it" % cell
			)


## The crop is the grid square minus the divider, on all four edges: the
## divider straddles a boundary, so the neighbour's half shows up on this
## cell's far edge too.
func test_the_crop_sits_inside_its_own_grid_square_on_every_edge():
	for row in 5:
		for column in 8:
			var cell: Rect2i = IllustratedStructureSprite.even_cell_rect(
				REAL_SHEET_WIDTH, REAL_SHEET_HEIGHT, 8, 5, row, column
			)
			var crop: Rect2i = IllustratedStructureSprite.even_cell_crop(
				REAL_SHEET_WIDTH, REAL_SHEET_HEIGHT, 8, 5, row, column
			)
			assert_gt(crop.position.x, cell.position.x, "r%d c%d left" % [row, column])
			assert_gt(crop.position.y, cell.position.y, "r%d c%d top" % [row, column])
			assert_lt(
				crop.position.x + crop.size.x, cell.position.x + cell.size.x,
				"r%d c%d right" % [row, column]
			)
			assert_lt(
				crop.position.y + crop.size.y, cell.position.y + cell.size.y,
				"r%d c%d bottom" % [row, column]
			)


## Still square after the inset -- the whole point of the square-cell rule
## is that the art's aspect is preserved, and an inset applied to one axis
## only would quietly reintroduce the stretch.
func test_the_cropped_cell_is_still_square():
	var crop: Rect2i = IllustratedStructureSprite.even_cell_crop(
		REAL_SHEET_WIDTH, REAL_SHEET_HEIGHT, 8, 5, 2, 3
	)
	assert_eq(crop.size.x, crop.size.y)


## A cell too small to afford the inset is cropped to its whole grid
## square, unchanged -- the crop never degenerates.
func test_a_tiny_cell_is_cropped_to_its_whole_square():
	var cell: Rect2i = IllustratedStructureSprite.even_cell_rect(100, 100, 8, 5, 4, 7)
	var crop: Rect2i = IllustratedStructureSprite.even_cell_crop(100, 100, 8, 5, 4, 7)
	assert_eq(crop, cell)
	assert_gt(crop.size.x, 0)
	assert_gt(crop.size.y, 0)


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


## The report, end to end and through the real sheet chain the live
## building node uses: a finished warehouse is drawn exactly three tiles
## across. Everything above this is the machinery; this is the number the
## player actually sees.
func test_a_finished_warehouse_is_drawn_exactly_three_tiles_across():
	var sprite := IllustratedStructureSprite.new()
	var footprint := BuildingCatalog.footprint_of("warehouse")
	var texture: ImageTexture = null
	for entry in BuildingCatalog.finished_sheet_chain("warehouse", 0):
		texture = sprite.footprint_frame_texture(
			entry["path"], entry["columns"], entry["rows"], entry["row"], entry["column"],
			_TILE, footprint.x, entry["grid"]
		)
		if texture != null:
			break
	assert_not_null(texture, "the warehouse has a real sheet to draw from")
	assert_eq(texture.get_width(), _TILE * 3, "three tiles across, as reported -- not four")
	assert_eq(texture.get_width(), _TILE * footprint.x, "and it is the catalog footprint that says so")


## The other half of the same report ("its scale as well"): four tiles
## really would have drawn it a third wider, so the fix is worth a third of
## the building.
func test_four_tiles_would_have_drawn_it_a_third_wider():
	var sprite := IllustratedStructureSprite.new()
	var entry: Dictionary = BuildingCatalog.finished_sheet_chain("warehouse", 0)[-1]
	var three := sprite.footprint_frame_texture(
		entry["path"], entry["columns"], entry["rows"], entry["row"], entry["column"],
		_TILE, 3, entry["grid"]
	)
	var four := sprite.footprint_frame_texture(
		entry["path"], entry["columns"], entry["rows"], entry["row"], entry["column"],
		_TILE, 4, entry["grid"]
	)
	assert_almost_eq(float(four.get_width()) / float(three.get_width()), 4.0 / 3.0, 0.01)


# -- a sheet is read with the column count its own art is drawn on ---------
#
# Reported live with the sawmill and the warehouse in shot: "There are still
# two buildings with wrong crops ... Please fix the slicer." Those two are
# right now (see the grid and inset above). The FARMHOUSE still is not, and
# it is a different fault in the same place.
#
# MEASURED off the sheets' own magenta divider lines
# (tools/probe_building_lifecycle_sheet.gd):
#
#   sawmill.png    8 columns of ~143px   warehouse.png  8 columns of ~146px
#   city_hall.png  8 columns of ~189px   blacksmith.png 8 columns of ~189px
#   brewery.png    8 columns of ~190px   farmhouse.png  6 columns of ~182px
#
# farmhouse.png is SIX columns wide, not the eight every other contract
# sheet uses -- so its art is on a 256px pitch and reading it at 192 cuts
# 64px off every farmhouse. Rendered (tools/probe_building_idle_crops.gd),
# that is the tree and the left-hand third of the farmyard gone, with the
# house itself sitting off-centre in its own frame.

const SheetGrid = preload("res://src/rendering/variant_sheet_grid.gd")
const SheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")


func _every_building_id() -> Array:
	var ids: Array = []
	ids.append_array(BuildingCatalog.BUILDING_IDS)
	ids.append_array(BuildingCatalog.CIVIC_BUILDING_IDS)
	ids.append_array(BuildingCatalog.PRODUCTION_BUILDING_IDS)
	return ids


func _sheet_image(path: String):
	var image: Image = SheetLoader.load_image(path)
	if image == null:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


## The cross-pin, driven off each sheet's own drawn columns rather than a
## hand-copied list: a sheet drawn on a different pitch than the one it is
## read at fails HERE, not in somebody's screenshot.
func test_every_contract_sheet_is_read_with_the_column_count_its_art_is_drawn_on():
	for building_id in _every_building_id():
		var path: String = BuildingCatalog.sheet_of(building_id)
		var image = _sheet_image(path)
		if image == null:
			continue  # not on disk -- the renderer's own fallback chain covers that
		var drawn: int = SheetGrid.divider_bands(image, false).size()
		assert_eq(
			BuildingCatalog.sheet_columns_of(building_id), drawn,
			"%s is drawn in %d columns" % [path.get_file(), drawn]
		)


## ...and the finished cell really is taken at that pitch, so the count is
## wired through rather than merely declared.
func test_a_farmhouses_cell_is_taken_at_its_own_sheets_pitch():
	var entry: Dictionary = BuildingCatalog.finished_sheet_for("farmhouse", 1)
	assert_eq(int(entry["columns"]), 6, "farmhouse.png is six columns wide")
	var rect: Rect2i = IllustratedStructureSprite.even_cell_rect(
		REAL_SHEET_WIDTH, REAL_SHEET_HEIGHT, int(entry["columns"]), int(entry["rows"]), 0, 1
	)
	assert_eq(rect.position.x, 256, "the second column of six starts at 1536/6")


## A sheet with fewer columns has fewer construction stages -- eight stages
## read off six cells would walk two of them off the end of the row.
func test_a_six_column_sheet_has_six_construction_stages():
	assert_eq(BuildingCatalog.construction_stage_for(0.99, "farmhouse"), 5, "the last of six")
	assert_eq(BuildingCatalog.construction_stage_for(0.99, "warehouse"), 7, "the last of eight")
	for progress in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
		assert_lt(
			BuildingCatalog.construction_stage_for(progress, "farmhouse"),
			BuildingCatalog.sheet_columns_of("farmhouse"),
			"a stage must be a column the sheet really has"
		)
