extends GutTest

## The one rule every walking marker asks before it moves (see
## docs/concept/village_farms.md "The rail stands on the inner edge" and
## docs/concept/building.md).
##
## Reported live: "Creatures and NPCs also walk through houses". NpcMarker
## and CreatureMarker each had their own gate; the six OTHER person-shaped
## markers -- builder, farmer, lumberjack, logistics carrier, caravan, cart
## -- had none at all and walked through everything. This is that rule,
## extracted once so six callers cannot drift from it.

const WalkGate = preload("res://src/gameplay/walk_gate.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")

const TILE := 16.0


class StubWorld:
	var walls: Dictionary = {}
	var slopes: Dictionary = {}
	var rails: Dictionary = {}  # [from_tile, to_tile] joined -> true
	func piece_blocks_movement_at_global(x: int, y: int) -> bool:
		return walls.has(Vector2i(x, y))
	func slope_at_global(x: int, y: int) -> float:
		return float(slopes.get(Vector2i(x, y), 0.0))
	func fence_blocks_step_global(fx: int, fy: int, tx: int, ty: int) -> bool:
		return rails.has("%d,%d>%d,%d" % [fx, fy, tx, ty])


class DeafWorld:
	# Knows none of the three questions -- a test double, or a marker set up
	# before its world exists.
	var nothing := true


func _centre(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * TILE


# -- a gate that knows nothing lets everything through ----------------------

func test_no_world_at_all_leaves_the_move_alone():
	var to := _centre(Vector2i(1, 0))
	assert_eq(WalkGate.slide(null, _centre(Vector2i(0, 0)), to, TILE), to)


func test_a_world_that_answers_none_of_the_questions_leaves_the_move_alone():
	var to := _centre(Vector2i(1, 0))
	assert_eq(WalkGate.slide(DeafWorld.new(), _centre(Vector2i(0, 0)), to, TILE), to)


func test_open_ground_is_returned_exactly_not_merely_close():
	var world := StubWorld.new()
	var to := _centre(Vector2i(1, 0))
	assert_eq(
		WalkGate.slide(world, _centre(Vector2i(0, 0)), to, TILE), to,
		"a clear move must come back untouched, not re-derived"
	)


# -- a wall is a tile you cannot be in --------------------------------------

func test_a_wall_at_the_destination_refuses_the_step():
	var world := StubWorld.new()
	world.walls[Vector2i(1, 0)] = true
	assert_true(WalkGate.blocks(world, _centre(Vector2i(0, 0)), _centre(Vector2i(1, 0)), TILE))


## Brushing along a wall must keep the walker moving, not freeze it: the
## blocked axis is dropped and the free one survives.
func test_a_diagonal_into_a_wall_slides_along_the_free_axis():
	var world := StubWorld.new()
	# The DESTINATION must be the solid one, and the x-slide has to be shut
	# too, or the walker would simply take that instead and the test would
	# not say which axis survived. Getting this wrong the first time is what
	# the assertion message below is for.
	world.walls[Vector2i(1, 1)] = true
	world.walls[Vector2i(1, 0)] = true
	var from := _centre(Vector2i(0, 0))
	var to := _centre(Vector2i(1, 1))
	var slid: Vector2 = WalkGate.slide(world, from, to, TILE)
	assert_ne(slid, to, "the destination tile is solid, so the diagonal cannot stand")
	assert_eq(slid, Vector2(from.x, to.y), "the y half of the move is still free")


## ...and when the x half is the free one, that is what survives instead.
func test_the_x_half_survives_when_it_is_the_free_one():
	var world := StubWorld.new()
	world.walls[Vector2i(1, 1)] = true
	world.walls[Vector2i(0, 1)] = true
	var from := _centre(Vector2i(0, 0))
	var to := _centre(Vector2i(1, 1))
	assert_eq(WalkGate.slide(world, from, to, TILE), Vector2(to.x, from.y))


func test_a_walker_boxed_in_on_both_axes_stays_where_it_is():
	var world := StubWorld.new()
	world.walls[Vector2i(1, 0)] = true
	world.walls[Vector2i(0, 1)] = true
	world.walls[Vector2i(1, 1)] = true
	var from := _centre(Vector2i(0, 0))
	assert_eq(WalkGate.slide(world, from, _centre(Vector2i(1, 1)), TILE), from)


# -- terrain and rails ------------------------------------------------------

func test_an_impassable_slope_refuses_the_step():
	var world := StubWorld.new()
	# Degrees, not a 0-1 fraction: the first draft used 10.0 thinking it was
	# a fraction, and 10 degrees is an easy stroll.
	world.slopes[Vector2i(1, 0)] = TerrainPassability.HARD_THRESHOLD_DEG + 1.0
	assert_true(WalkGate.blocks(world, _centre(Vector2i(0, 0)), _centre(Vector2i(1, 0)), TILE))


## A rail is an EDGE you may not cross, not a tile you may not stand in --
## the distinction the field ring depends on.
func test_a_rail_on_the_line_refuses_the_step():
	var world := StubWorld.new()
	world.rails["0,0>1,0"] = true
	assert_true(WalkGate.blocks(world, _centre(Vector2i(0, 0)), _centre(Vector2i(1, 0)), TILE))


## ...but the worker whose own beds those rails enclose crosses them, in
## BOTH directions, or a farmer is either shut out of their field or shut
## into it (both measured, both reported).
func test_a_worker_crosses_the_rail_around_its_own_field_either_way():
	var world := StubWorld.new()
	world.rails["0,0>1,0"] = true
	world.rails["1,0>0,0"] = true
	var mine := {Vector2i(1, 0): true}
	assert_false(
		WalkGate.blocks(world, _centre(Vector2i(0, 0)), _centre(Vector2i(1, 0)), TILE, mine),
		"in to the beds"
	)
	assert_false(
		WalkGate.blocks(world, _centre(Vector2i(1, 0)), _centre(Vector2i(0, 0)), TILE, mine),
		"and back out again"
	)


## A neighbour's rail is not the worker's own, and still stops them.
func test_the_exemption_does_not_open_somebody_elses_fence():
	var world := StubWorld.new()
	world.rails["0,0>1,0"] = true
	assert_true(
		WalkGate.blocks(
			world, _centre(Vector2i(0, 0)), _centre(Vector2i(1, 0)), TILE,
			{Vector2i(5, 5): true}
		)
	)


## A wall is a wall even on the worker's own field -- the exemption is about
## rails, and only rails.
func test_the_field_exemption_never_opens_a_wall():
	var world := StubWorld.new()
	world.walls[Vector2i(1, 0)] = true
	assert_true(
		WalkGate.blocks(
			world, _centre(Vector2i(0, 0)), _centre(Vector2i(1, 0)), TILE,
			{Vector2i(1, 0): true}
		)
	)
