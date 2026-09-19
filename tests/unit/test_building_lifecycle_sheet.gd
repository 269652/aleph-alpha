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


## REPLACED by test_each_house_tier_has_art_of_its_own below: all three
## tiers sharing one set was deliberate only while house_1_* was the only
## house art in the repo, and the doc said so. Cottage and manor sheets
## landed 2026-09-19. What is still worth pinning is that every tier has
## real art at all -- that was the reason for sharing in the first place.
func test_every_house_tier_has_real_art():
	for building_id in ["house_small", "house_medium", "house_large"]:
		assert_gt(
			BuildingLifecycleSheet.variation_sheets_of(building_id).size(), 0,
			"%s would fall back to a procedural box" % building_id
		)


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
		BuildingLifecycleSheet.build_cell_for("house_medium", 0.0),
		Vector2i(0, BuildingLifecycleSheet.BUILD_ROWS[0])
	)


func test_a_nearly_finished_site_shows_the_last_construction_frame():
	var last_row: int = BuildingLifecycleSheet.BUILD_ROWS[BuildingLifecycleSheet.BUILD_ROWS.size() - 1]
	assert_eq(
		BuildingLifecycleSheet.build_cell_for("house_medium", 1.0),
		Vector2i(BuildingLifecycleSheet.COLUMNS - 1, last_row)
	)


func test_the_build_walks_every_one_of_its_frames_in_order():
	var seen: Array = []
	for step in 200:
		var cell: Vector2i = BuildingLifecycleSheet.build_cell_for("house_medium", float(step) / 199.0)
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
	assert_eq(BuildingLifecycleSheet.build_cell_for("house_medium", -5.0), BuildingLifecycleSheet.build_cell_for("house_medium", 0.0))
	assert_eq(BuildingLifecycleSheet.build_cell_for("house_medium", 99.0), BuildingLifecycleSheet.build_cell_for("house_medium", 1.0))


# -- the finished house -----------------------------------------------------

func test_a_finished_house_stands_in_an_idle_row():
	for seed_value in 200:
		var cell: Vector2i = BuildingLifecycleSheet.idle_cell_for("house_medium", seed_value)
		assert_true(
			BuildingLifecycleSheet.IDLE_ROWS.has(cell.y),
			"seed %d puts a finished house in row %d, which is not a standing house" % [seed_value, cell.y]
		)
		assert_between(cell.x, 0, BuildingLifecycleSheet.COLUMNS - 1)


func test_every_finished_look_is_reachable():
	var seen: Dictionary = {}
	for seed_value in 4000:
		seen[BuildingLifecycleSheet.idle_cell_for("house_medium", seed_value)] = true
	assert_eq(
		seen.size(), BuildingLifecycleSheet.IDLE_ROWS.size() * BuildingLifecycleSheet.COLUMNS,
		"a finished look no seed can reach is art nobody will ever see"
	)


func test_a_house_keeps_the_same_finished_look_across_reloads():
	for seed_value in [3, 44, 777]:
		assert_eq(
			BuildingLifecycleSheet.idle_cell_for("house_medium", seed_value),
			BuildingLifecycleSheet.idle_cell_for("house_medium", seed_value)
		)


# -- and it is the catalog's houses this is declared for --------------------

func test_the_variations_are_declared_for_real_catalog_buildings():
	for building_id in BuildingLifecycleSheet.VARIATION_SHEETS:
		assert_true(BuildingCatalog.has_building(building_id), "%s is not a building" % building_id)
		assert_gt(
			BuildingCatalog.capacity_of(building_id), 0,
			"%s is not a home -- a hall or a mill drawn as a cottage is the wrong building" % building_id
		)


# -- each house tier is its own building now --------------------------------
#
# Asked directly, with the new art in the repo: *"I added cottage and manor
# sprites... please fix that villages use scaled houses for those and use the
# real illustrations ... cottage 2x2; house 3x2; manor 3x3"*.
#
# Until now all three tiers shared the five house_1_* sheets, which this
# file's own test above pinned as deliberate: no house had art of its own, so
# declaring it for the smallest tier only would have left a street half
# cottages and half boxes. The doc said what would end it -- "when grander art
# for those tiers lands they get their own entries here" -- and it has landed.
#
# The new sheets are on the OLDER 8x5 contract, not house_1_*'s 8x10 one.
# MEASURED, not assumed (tools/probe_building_lifecycle_sheet.gd against
# cottage_1 and manor_1): five divider-separated row bands, eight columns,
# and the rows really do read construction / active / idle / burning /
# ruined -- row 0 of cottage_1 is a foundation ring, row 3 is a cottage on
# fire, row 2 of manor_1 is a turreted manor. So a variation set carries its
# own grid rather than every set being assumed to be the richest one.


func test_each_house_tier_has_art_of_its_own():
	var small: Array = BuildingLifecycleSheet.variation_sheets_of("house_small")
	var medium: Array = BuildingLifecycleSheet.variation_sheets_of("house_medium")
	var large: Array = BuildingLifecycleSheet.variation_sheets_of("house_large")
	for tier in [small, medium, large]:
		assert_gt(tier.size(), 0, "every tier still has real art")
	assert_ne(small, medium, "a cottage is not a house")
	assert_ne(medium, large, "a house is not a manor")
	assert_ne(small, large, "and a cottage is certainly not a manor")


func test_the_smallest_tier_draws_cottages_and_the_largest_manors():
	for path in BuildingLifecycleSheet.variation_sheets_of("house_small"):
		assert_true(path.contains("cottage"), "house_small should draw a cottage, found %s" % path)
	for path in BuildingLifecycleSheet.variation_sheets_of("house_large"):
		assert_true(path.contains("manor"), "house_large should draw a manor, found %s" % path)


## Every tier keeps five variations, so a street of any one tier is still a
## street of different buildings.
func test_every_tier_still_has_five_variations_to_pick_from():
	for building_id in ["house_small", "house_medium", "house_large"]:
		assert_eq(
			BuildingLifecycleSheet.variation_sheets_of(building_id).size(), 5,
			building_id
		)


# -- and each set is read on its own grid -----------------------------------


func test_a_variation_set_knows_the_grid_its_art_is_drawn_on():
	var cottage := BuildingLifecycleSheet.grid_for("house_small")
	var house := BuildingLifecycleSheet.grid_for("house_medium")
	assert_eq(int(cottage["columns"]), 8, "both contracts are eight columns wide")
	assert_eq(int(house["columns"]), 8)
	assert_eq(int(cottage["rows"]), 5, "the cottage sheets are the 8x5 contract -- measured")
	assert_eq(int(house["rows"]), 10, "house_1_* is the richer 8x10 one")
	assert_eq(int(BuildingLifecycleSheet.grid_for("house_large")["rows"]), 5, "so are the manors")


func test_a_building_with_no_variations_has_no_grid():
	assert_eq(BuildingLifecycleSheet.grid_for("city_hall"), {})


## Every row a set draws from has to be a row that set really has.
func test_no_set_ever_reads_a_row_off_the_end_of_its_own_sheet():
	for building_id in BuildingLifecycleSheet.VARIATION_SHEETS:
		var grid := BuildingLifecycleSheet.grid_for(building_id)
		var rows := int(grid["rows"])
		for seed_value in 200:
			var idle := BuildingLifecycleSheet.idle_cell_for(building_id, seed_value)
			assert_lt(idle.y, rows, "%s idle row %d is off its own sheet" % [building_id, idle.y])
			assert_lt(idle.x, int(grid["columns"]), "%s idle column is off its own sheet" % building_id)
		for step in 50:
			var build := BuildingLifecycleSheet.build_cell_for(building_id, float(step) / 49.0)
			assert_lt(build.y, rows, "%s build row %d is off its own sheet" % [building_id, build.y])
			assert_lt(build.x, int(grid["columns"]), "%s build column is off its own sheet" % building_id)


## A cottage rises through its own sheet's single construction row, eight
## stages left to right -- the 8x5 contract's own build animation, not the
## 24-frame one only the richer sheets have.
func test_a_cottage_rises_through_its_own_sheets_eight_stages():
	var seen: Dictionary = {}
	for step in 80:
		var cell := BuildingLifecycleSheet.build_cell_for("house_small", float(step) / 79.0)
		assert_eq(cell.y, 0, "the 8x5 contract's build row is row 0")
		seen[cell.x] = true
	assert_eq(seen.size(), 8, "all eight stages are walked")


## And a medium house still walks all 24 of its richer sheet's frames, which
## is the whole reason that contract exists.
func test_a_medium_house_still_walks_all_twenty_four_build_frames():
	var seen: Dictionary = {}
	for step in 240:
		var cell := BuildingLifecycleSheet.build_cell_for("house_medium", float(step) / 239.0)
		seen[cell] = true
	assert_eq(seen.size(), BuildingLifecycleSheet.BUILD_FRAMES)


## A finished cottage or manor stands in its own sheet's IDLE row -- never
## the burning or ruined ones, which are the same rows an 8x5 sheet keeps
## for a building that is on fire or gone.
func test_a_finished_cottage_or_manor_is_never_drawn_burning_or_ruined():
	for building_id in ["house_small", "house_large"]:
		for seed_value in 300:
			assert_eq(
				BuildingLifecycleSheet.idle_cell_for(building_id, seed_value).y,
				BuildingCatalog.ROW_IDLE,
				"%s drew a finished house from a row that is not the idle one" % building_id
			)
