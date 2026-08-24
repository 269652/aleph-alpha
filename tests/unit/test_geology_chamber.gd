extends GutTest

## GeologyChamber.cells_for: which local Strata cells a cave entrance
## reveals -- the underground equivalent of RoomDetector's room cells (see
## docs/concept/geology.md "Reveal-on-entry, reused recursively").

const GeologyChamber = preload("res://src/world/geology_chamber.gd")


func test_includes_the_entrance_cell_itself():
	var cells := GeologyChamber.cells_for(Vector2i(5, 5))
	assert_true(cells.has(Vector2i(5, 5)))


func test_chamber_is_small_and_bounded():
	var cells := GeologyChamber.cells_for(Vector2i(0, 0))
	assert_gt(cells.size(), 1, "a chamber of just the entrance cell isn't a chamber")
	assert_lt(cells.size(), 50, "chamber must stay a small confined starter area")


func test_chamber_cells_are_all_within_the_configured_radius():
	var origin := Vector2i(10, 10)
	var cells := GeologyChamber.cells_for(origin)
	for cell in cells:
		var offset: Vector2i = cell - origin
		assert_true(
			Vector2(offset).length() <= GeologyChamber.CHAMBER_RADIUS + 0.51,
			"cell %s outside the chamber radius" % cell
		)


func test_chamber_translates_with_its_entrance():
	var at_origin := GeologyChamber.cells_for(Vector2i.ZERO)
	var shifted := GeologyChamber.cells_for(Vector2i(20, 20))
	assert_eq(at_origin.size(), shifted.size())
	for cell in at_origin:
		assert_true(shifted.has(cell + Vector2i(20, 20)))


func test_no_duplicate_cells():
	var cells := GeologyChamber.cells_for(Vector2i(3, 3))
	var seen := {}
	for cell in cells:
		assert_false(seen.has(cell), "duplicate cell %s" % cell)
		seen[cell] = true
