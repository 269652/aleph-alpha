extends GutTest

## BuildingLifecycleSheet: which picture a village house has, at every
## point in its life (docs/concept/building.md, "Building lifecycle
## variation sheets").
##
## The five sheets delivered 2026-09-17 (house_1_1.png .. house_1_5.png)
## are a richer contract than the older 8x5 one: 8 columns x 10 rows, whose
## own printed row labels read
##
##   00 Build (Foundation)    03 Complete (Idle 1)   06 Damaged (1)
##   01 Build (Frames)        04 Idle 2 (Details)    07 Damaged (2)
##   02 Build (Construction)  05 Idle 3 (Variants)   08 Destroyed (1)
##                                                   09 Destroyed (2)
##
## That is a real 24-frame construction animation per variation, which is
## what "wire the new house variation sprites with proper construction
## animations" asks for, and 24 finished looks per variation on top.

const BuildingLifecycleSheet = preload("res://src/rendering/building_lifecycle_sheet.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")


# -- the sheets themselves --------------------------------------------------

func test_every_declared_variation_sheet_is_really_on_disk():
	for building_id in BuildingLifecycleSheet.VARIATION_SHEETS:
		for path in BuildingLifecycleSheet.variation_sheets_of(building_id):
			assert_true(
				FileAccess.file_exists(path),
				"%s declares %s, which is not there" % [building_id, path]
			)


func test_all_three_house_tiers_draw_from_the_same_variations():
	var small: Array = BuildingLifecycleSheet.variation_sheets_of("house_small")
	assert_gt(small.size(), 0, "precondition: the cottage sheets are declared")
	assert_eq(BuildingLifecycleSheet.variation_sheets_of("house_medium"), small)
	assert_eq(BuildingLifecycleSheet.variation_sheets_of("house_large"), small)


func test_a_building_with_no_variations_declares_none():
	assert_eq(BuildingLifecycleSheet.variation_sheets_of("city_hall"), [])
	assert_eq(BuildingLifecycleSheet.sheet_for("city_hall", 7), "")


func test_a_house_keeps_the_same_variation_across_reloads():
	for seed_value in [1, 99, 12345, -7]:
		assert_eq(
			BuildingLifecycleSheet.sheet_for("house_small", seed_value),
			BuildingLifecycleSheet.sheet_for("house_small", seed_value),
			"a house that changed shape on reload would not be the same house"
		)


func test_different_houses_really_reach_every_variation():
	var seen: Dictionary = {}
	for seed_value in 400:
		seen[BuildingLifecycleSheet.sheet_for("house_small", seed_value)] = true
	assert_eq(
		seen.size(), BuildingLifecycleSheet.variation_sheets_of("house_small").size(),
		"a variation no seed can reach is art nobody will ever see"
	)


# -- the rows ---------------------------------------------------------------

func test_the_rows_cover_the_whole_sheet_exactly_once():
	var seen: Dictionary = {}
	for row in (
		BuildingLifecycleSheet.BUILD_ROWS + BuildingLifecycleSheet.IDLE_ROWS
		+ BuildingLifecycleSheet.DAMAGED_ROWS + BuildingLifecycleSheet.DESTROYED_ROWS
	):
		assert_false(seen.has(row), "row %d is claimed twice" % row)
		seen[row] = true
	assert_eq(seen.size(), BuildingLifecycleSheet.ROWS, "every row of the sheet has a meaning")
	for row in BuildingLifecycleSheet.ROWS:
		assert_true(seen.has(row), "row %d belongs to nothing" % row)


func test_building_comes_before_standing_which_comes_before_ruin():
	assert_lt(BuildingLifecycleSheet.BUILD_ROWS.max(), BuildingLifecycleSheet.IDLE_ROWS.min())
	assert_lt(BuildingLifecycleSheet.IDLE_ROWS.max(), BuildingLifecycleSheet.DAMAGED_ROWS.min())
	assert_lt(BuildingLifecycleSheet.DAMAGED_ROWS.max(), BuildingLifecycleSheet.DESTROYED_ROWS.min())


# -- the construction animation ---------------------------------------------

func test_the_build_animation_is_every_frame_of_every_build_row():
	assert_eq(
		BuildingLifecycleSheet.BUILD_FRAMES,
		BuildingLifecycleSheet.BUILD_ROWS.size() * BuildingLifecycleSheet.COLUMNS,
		"the frame count is derived from the grid, not written down"
	)


func test_a_fresh_site_shows_the_first_foundation_frame():
	assert_eq(
		BuildingLifecycleSheet.build_cell_for(0.0),
		Vector2i(0, BuildingLifecycleSheet.BUILD_ROWS[0])
	)


func test_a_nearly_finished_site_shows_the_last_construction_frame():
	var last_row: int = BuildingLifecycleSheet.BUILD_ROWS[BuildingLifecycleSheet.BUILD_ROWS.size() - 1]
	assert_eq(
		BuildingLifecycleSheet.build_cell_for(1.0),
		Vector2i(BuildingLifecycleSheet.COLUMNS - 1, last_row)
	)


func test_the_build_walks_every_one_of_its_frames_in_order():
	var seen: Array = []
	for step in 200:
		var cell: Vector2i = BuildingLifecycleSheet.build_cell_for(float(step) / 199.0)
		if seen.is_empty() or seen[seen.size() - 1] != cell:
			seen.append(cell)
	assert_eq(
		seen.size(), BuildingLifecycleSheet.BUILD_FRAMES,
		"a frame the animation skips is a frame the artist drew for nothing"
	)
	for i in seen.size():
		var expected_row: int = BuildingLifecycleSheet.BUILD_ROWS[i / BuildingLifecycleSheet.COLUMNS]
		assert_eq(
			seen[i], Vector2i(i % BuildingLifecycleSheet.COLUMNS, expected_row),
			"frame %d is out of order -- the build must read left to right, row by row" % i
		)


func test_progress_outside_the_range_still_lands_on_a_real_frame():
	assert_eq(BuildingLifecycleSheet.build_cell_for(-5.0), BuildingLifecycleSheet.build_cell_for(0.0))
	assert_eq(BuildingLifecycleSheet.build_cell_for(99.0), BuildingLifecycleSheet.build_cell_for(1.0))


# -- the finished house -----------------------------------------------------

func test_a_finished_house_stands_in_an_idle_row():
	for seed_value in 200:
		var cell: Vector2i = BuildingLifecycleSheet.idle_cell_for(seed_value)
		assert_true(
			BuildingLifecycleSheet.IDLE_ROWS.has(cell.y),
			"seed %d puts a finished house in row %d, which is not a standing house" % [seed_value, cell.y]
		)
		assert_between(cell.x, 0, BuildingLifecycleSheet.COLUMNS - 1)


func test_every_finished_look_is_reachable():
	var seen: Dictionary = {}
	for seed_value in 4000:
		seen[BuildingLifecycleSheet.idle_cell_for(seed_value)] = true
	assert_eq(
		seen.size(), BuildingLifecycleSheet.IDLE_ROWS.size() * BuildingLifecycleSheet.COLUMNS,
		"a finished look no seed can reach is art nobody will ever see"
	)


func test_a_house_keeps_the_same_finished_look_across_reloads():
	for seed_value in [3, 44, 777]:
		assert_eq(
			BuildingLifecycleSheet.idle_cell_for(seed_value),
			BuildingLifecycleSheet.idle_cell_for(seed_value)
		)


# -- and it is the catalog's houses this is declared for --------------------

func test_the_variations_are_declared_for_real_catalog_buildings():
	for building_id in BuildingLifecycleSheet.VARIATION_SHEETS:
		assert_true(BuildingCatalog.has_building(building_id), "%s is not a building" % building_id)
		assert_gt(
			BuildingCatalog.capacity_of(building_id), 0,
			"%s is not a home -- a hall or a mill drawn as a cottage is the wrong building" % building_id
		)
