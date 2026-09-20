extends GutTest

## TileRouter: A* over the tile grid (see docs/concept/navigation.md
## "Villagers: a real route, computed once per destination").
##
## Reported live: "add proper wayfinding / routing". Axis sliding
## (NpcBuildingGate) gets an agent ALONG a wall but never AROUND one, so a
## villager whose doorstep sat behind its own house pressed into the wall
## forever. This is the search that fixes that.

const TileRouter = preload("res://src/gameplay/tile_router.gd")

const BUDGET := 4000


func _open() -> Callable:
	return func(_tile: Vector2i) -> bool: return false


## A vertical wall at x == 4 with exactly ONE gap, at y >= 9.
##
## Unbounded to the NORTH on purpose. The first version of this stopped at
## y == 0, which left the whole negative-y half-plane open -- so the router
## quite correctly went north instead of through the gap, and the test
## accusing it of ignoring the gap was accusing it of being right.
func _wall() -> Callable:
	return func(tile: Vector2i) -> bool:
		return tile.x == 4 and tile.y <= 8


func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return maxi(absi(a.x - b.x), absi(a.y - b.y)) == 1


# -- the basics ------------------------------------------------------------

func test_a_route_across_open_ground_is_a_straight_run():
	var route: Array = TileRouter.route(Vector2i(0, 0), Vector2i(5, 5), _open(), BUDGET)
	assert_eq(route.size(), 5, "an open diagonal should take five diagonal steps")
	assert_eq(route[-1], Vector2i(5, 5))


func test_the_start_tile_is_not_part_of_the_route():
	# The agent is already standing there; a route is what is still to walk.
	var route: Array = TileRouter.route(Vector2i(2, 2), Vector2i(4, 2), _open(), BUDGET)
	assert_false(route.has(Vector2i(2, 2)))
	assert_eq(route[-1], Vector2i(4, 2))


func test_routing_to_where_you_already_stand_is_an_empty_route():
	assert_eq(TileRouter.route(Vector2i(3, 3), Vector2i(3, 3), _open(), BUDGET), [])


func test_every_step_of_a_route_is_adjacent_to_the_last():
	var route: Array = TileRouter.route(Vector2i(0, 0), Vector2i(7, 3), _wall(), BUDGET)
	assert_gt(route.size(), 0)
	var previous := Vector2i(0, 0)
	for tile in route:
		assert_true(_is_adjacent(previous, tile), "%s does not follow %s" % [tile, previous])
		previous = tile


func test_the_route_is_deterministic():
	assert_eq(
		TileRouter.route(Vector2i(0, 0), Vector2i(7, 3), _wall(), BUDGET),
		TileRouter.route(Vector2i(0, 0), Vector2i(7, 3), _wall(), BUDGET)
	)


# -- the reported bug: going AROUND, not just along ------------------------

func test_a_route_goes_around_a_wall_rather_than_into_it():
	# Start west of the wall, goal east of it. The only way through is the
	# gap at y == 9, so a real route has to detour south and back up --
	# exactly what axis sliding could never do.
	var route: Array = TileRouter.route(Vector2i(0, 3), Vector2i(7, 3), _wall(), BUDGET)
	assert_gt(route.size(), 0, "no route found around a wall that plainly has a gap")
	assert_eq(route[-1], Vector2i(7, 3))
	for tile in route:
		assert_false(_wall().call(tile), "the route runs through the wall at %s" % tile)
	var went_south := false
	for tile in route:
		if tile.y >= 9:
			went_south = true
	assert_true(went_south, "the route never used the only gap in the wall")


func test_no_route_ever_passes_through_a_blocked_tile():
	var blocked := _wall()
	for goal_y in range(0, 8):
		var route: Array = TileRouter.route(Vector2i(0, 3), Vector2i(7, goal_y), blocked, BUDGET)
		for tile in route:
			assert_false(blocked.call(tile), "route to (7,%d) crosses the wall at %s" % [goal_y, tile])


func test_a_diagonal_never_cuts_between_two_blocked_corners():
	# Two buildings touching at a corner leave a diagonal seam that is not
	# actually walkable. Allowing it would let villagers slip through walls
	# that visibly meet.
	var seam := func(tile: Vector2i) -> bool:
		return tile == Vector2i(1, 0) or tile == Vector2i(0, 1)
	var route: Array = TileRouter.route(Vector2i(0, 0), Vector2i(1, 1), seam, BUDGET)
	assert_false(
		route.size() == 1 and route[0] == Vector2i(1, 1),
		"the route cut straight through the corner seam"
	)


# -- refusing honestly -----------------------------------------------------

func test_an_unreachable_goal_gives_no_route():
	# Fully enclosed goal: a ring of blocked tiles around (5,5).
	var boxed := func(tile: Vector2i) -> bool:
		return (
			absi(tile.x - 5) <= 1 and absi(tile.y - 5) <= 1
			and tile != Vector2i(5, 5)
		)
	assert_eq(TileRouter.route(Vector2i(0, 0), Vector2i(5, 5), boxed, BUDGET), [])


func test_a_blocked_goal_gives_no_route_rather_than_a_guess():
	# A villager's real destination is its doorstep, which is never inside a
	# footprint -- so a blocked goal means something genuinely unexpected,
	# and a nearest-reachable guess would hide it.
	var blocked := func(tile: Vector2i) -> bool: return tile == Vector2i(5, 5)
	assert_eq(TileRouter.route(Vector2i(0, 0), Vector2i(5, 5), blocked, BUDGET), [])


func test_the_search_budget_is_really_enforced():
	# The world is chunk-streamed and effectively infinite: an unbounded
	# search toward an unreachable goal would walk the whole loaded region.
	var visited := {"count": 0}
	var counting := func(tile: Vector2i) -> bool:
		visited["count"] += 1
		return tile.x == 4  # an infinite wall, no gap anywhere
	var route: Array = TileRouter.route(Vector2i(0, 0), Vector2i(9, 0), counting, 200)
	assert_eq(route, [], "an impossible route must come back empty")
	assert_lt(visited["count"], 5000, "the search blew past its own budget")


func test_an_invalid_predicate_routes_as_open_ground():
	var route: Array = TileRouter.route(Vector2i(0, 0), Vector2i(3, 0), Callable(), BUDGET)
	assert_eq(route.size(), 3)
	assert_eq(route[-1], Vector2i(3, 0))


func test_a_start_inside_a_wall_can_still_route_out():
	# Never trap anything -- the same escape every other rule here keeps.
	var blocked := func(tile: Vector2i) -> bool: return tile.x <= 0
	var route: Array = TileRouter.route(Vector2i(0, 0), Vector2i(3, 0), blocked, BUDGET)
	assert_gt(route.size(), 0, "an agent starting inside a wall could not route out")
	assert_eq(route[-1], Vector2i(3, 0))
