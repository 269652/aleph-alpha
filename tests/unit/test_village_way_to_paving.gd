extends GutTest

## A way home for a building the village raised off its street grid
## (docs/concept/village_ponds.md, "The hut on the bank").
##
## Reported live with the hut in shot: *"Fisher hut is there but not
## connected to street system"*. Every other building a village places is
## sited ON frontage, so the layout lays its doorstep among the plot's own
## road cells and the plot is joined by construction. A fisher's hut
## belongs to the water instead, and the first answer to that was a single
## paved cell at its door -- which is a front step, not a road home. A step
## that reaches nothing is exactly what the screenshot shows.
##
## Pure geometry, like everything else in VillageLayout: cells in, cells
## out, nothing about ponds or huts in here at all. Any building raised off
## the grid can ask it.

const VillageLayout = preload("res://src/world/village_layout.gd")

const SIZE := 32

var _anywhere := func(_cell: Vector2i) -> bool: return true


func _paved(cells: Array) -> Callable:
	var set: Dictionary = {}
	for cell in cells:
		set[cell as Vector2i] = true
	return func(cell: Vector2i) -> bool: return set.has(cell)


func _free_except(blocked: Array) -> Callable:
	var set: Dictionary = {}
	for cell in blocked:
		set[cell as Vector2i] = true
	return func(cell: Vector2i) -> bool: return not set.has(cell)


## A door that already touches the village's paving needs nothing laid.
func test_a_door_already_on_the_street_needs_no_way_laid():
	var way = VillageLayout.way_to_paving(
		Vector2i(10, 10), SIZE, _anywhere, _paved([Vector2i(10, 11)])
	)
	assert_eq(way, [], "a door beside paving is already joined")


## Three tiles out in a straight line: the cells between, and only those.
func test_a_door_in_line_with_paving_gets_the_cells_between_it():
	var way = VillageLayout.way_to_paving(
		Vector2i(10, 10), SIZE, _anywhere, _paved([Vector2i(10, 14)])
	)
	assert_eq(way, [Vector2i(10, 11), Vector2i(10, 12), Vector2i(10, 13)])


## A way the nearest paving cannot give is looked for at the next one --
## the search is over TARGETS, not over one target's routes.
##
## The first version of this test asked for a corner to be turned when the
## straight run south was blocked, with paving only at the end of that
## run. There is no such corner: when the door and the paving share a
## column, both L orders ARE that straight line, so the honest answer is
## null and the test was asking the code to be cleverer than an L. What
## actually saves a hut in that spot is other paving somewhere else, which
## a village has plenty of.
func test_a_blocked_run_is_answered_by_paving_somewhere_else():
	var blocked := [Vector2i(10, 11), Vector2i(10, 12), Vector2i(10, 13)]
	var way = VillageLayout.way_to_paving(
		Vector2i(10, 10), SIZE, _free_except(blocked),
		_paved([Vector2i(10, 14), Vector2i(14, 10)])
	)
	assert_not_null(way, "the paving to the east is clear even though the run south is not")
	for cell in way:
		assert_false(blocked.has(cell), "%s is blocked ground" % str(cell))
	assert_eq(way, [Vector2i(11, 10), Vector2i(12, 10), Vector2i(13, 10)])


## ...and when the only paving is behind blocked ground in its own column,
## null is the truthful answer rather than a clever one.
func test_a_door_walled_off_from_the_only_paving_gets_no_way():
	var blocked := [Vector2i(10, 11), Vector2i(10, 12), Vector2i(10, 13)]
	assert_null(VillageLayout.way_to_paving(
		Vector2i(10, 10), SIZE, _free_except(blocked), _paved([Vector2i(10, 14)])
	))


## Nothing clear in reach is null, not an empty way -- "already joined" and
## "cannot be joined" must never read the same.
func test_a_door_nothing_can_reach_gets_no_way_at_all():
	var way = VillageLayout.way_to_paving(
		Vector2i(10, 10), SIZE,
		func(_cell: Vector2i) -> bool: return false,
		_paved([Vector2i(10, 14)])
	)
	assert_null(way)


func test_a_village_with_no_paving_at_all_has_nowhere_to_join():
	assert_null(VillageLayout.way_to_paving(Vector2i(10, 10), SIZE, _anywhere, _paved([])))


## Never off the chunk, however far the paving is.
func test_a_way_never_leaves_the_chunk():
	var way = VillageLayout.way_to_paving(
		Vector2i(0, 0), SIZE, _anywhere, _paved([Vector2i(0, 5)])
	)
	assert_not_null(way)
	for cell in way:
		var c: Vector2i = cell
		assert_true(c.x >= 0 and c.y >= 0 and c.x < SIZE and c.y < SIZE, str(c))


## Deterministic, like every other siting in this module: the same ground
## lays the same way on every reload, or a village grows a second road
## every time it is walked past.
func test_the_same_ground_lays_the_same_way_twice():
	var paved := _paved([Vector2i(10, 14), Vector2i(14, 10)])
	assert_eq(
		VillageLayout.way_to_paving(Vector2i(10, 10), SIZE, _anywhere, paved),
		VillageLayout.way_to_paving(Vector2i(10, 10), SIZE, _anywhere, paved)
	)


## The reach is derived, not picked: a building raised off the grid stands
## between two street rows, so a way home never needs to be longer than the
## distance from one to the next and along it.
func test_the_reach_is_derived_from_the_street_pitch():
	assert_eq(
		VillageLayout.WAY_TO_PAVING_MAX_TILES,
		VillageLayout.STREET_PITCH_TILES * 2,
		"a way home is at most one street pitch down and one along"
	)


## And it really stops there rather than paving across the whole chunk.
func test_paving_further_off_than_the_reach_is_not_joined_to():
	var far := Vector2i(10, 10 + VillageLayout.WAY_TO_PAVING_MAX_TILES + 2)
	assert_null(VillageLayout.way_to_paving(Vector2i(10, 10), SIZE, _anywhere, _paved([far])))
