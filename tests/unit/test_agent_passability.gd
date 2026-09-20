extends GutTest

## AgentPassability: what ground an agent may cross, and what it costs
## (see docs/concept/navigation.md "Terrain and water").
##
## Two separate questions, deliberately, because water and slope are not
## the same kind of obstacle:
##
##   BLOCKED -- a building, or ground too steep to climb. Absolute.
##   COSTLY  -- water. Crossable, just slow. Making it absolute would stop
##              creatures drinking (they must stand ON water to drink) and
##              delete the swim animation both they and villagers already
##              have.

const AgentPassability = preload("res://src/gameplay/agent_passability.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")


class FakeWorld:
	extends RefCounted
	var buildings: Array[Vector2i] = []
	var cliffs: Array[Vector2i] = []
	var rivers: Array[Vector2i] = []
	var ocean: Array[Vector2i] = []

	func has_building_at_global(x: int, y: int) -> bool:
		return buildings.has(Vector2i(x, y))

	func slope_at_global(x: int, y: int) -> float:
		return 70.0 if cliffs.has(Vector2i(x, y)) else 0.0

	func is_river_at_global(x: int, y: int) -> bool:
		return rivers.has(Vector2i(x, y))

	func is_lake_at_global(_x: int, _y: int) -> bool:
		return false

	func biome_at_global(x: int, y: int) -> String:
		return "ocean" if ocean.has(Vector2i(x, y)) else "grassland"


class WorldThatKnowsNothing:
	extends RefCounted


# -- blocked: buildings and cliffs -----------------------------------------

func test_a_building_is_blocked():
	var world := FakeWorld.new()
	world.buildings = [Vector2i(2, 2)]
	var blocked := AgentPassability.blocked_predicate_for(world)
	assert_true(blocked.call(Vector2i(2, 2)))
	assert_false(blocked.call(Vector2i(2, 3)))


func test_ground_too_steep_to_climb_is_blocked():
	# The same threshold TerrainPassability already owns -- not a second,
	# independently-invented steepness number.
	var world := FakeWorld.new()
	world.cliffs = [Vector2i(5, 5)]
	assert_false(TerrainPassability.is_passable(70.0), "precondition: 70 deg is impassable")
	assert_true(AgentPassability.blocked_predicate_for(world).call(Vector2i(5, 5)))


func test_water_is_never_blocked():
	# Creatures must be able to stand ON water to drink, and both villagers
	# and creatures already have swim animations. Blocking it would delete
	# real behaviour, not add safety.
	var world := FakeWorld.new()
	world.rivers = [Vector2i(1, 1)]
	world.ocean = [Vector2i(2, 1)]
	var blocked := AgentPassability.blocked_predicate_for(world)
	assert_false(blocked.call(Vector2i(1, 1)), "a river must be crossable")
	assert_false(blocked.call(Vector2i(2, 1)), "the sea must be swimmable")


func test_a_world_that_knows_nothing_blocks_nothing():
	# Fail-open, the same duck-typed contract every mover here keeps.
	assert_false(AgentPassability.blocked_predicate_for(WorldThatKnowsNothing.new()).is_valid())
	assert_false(AgentPassability.blocked_predicate_for(null).is_valid())


func test_a_world_that_only_knows_buildings_still_gives_a_predicate():
	# Partial worlds are normal here -- every hook is duck-typed, so an
	# older stub exposing only one of them must still work.
	var only_buildings := BuildingsOnlyWorld.new()
	var blocked := AgentPassability.blocked_predicate_for(only_buildings)
	assert_true(blocked.is_valid())
	assert_true(blocked.call(Vector2i(0, 0)))


class BuildingsOnlyWorld:
	extends RefCounted
	func has_building_at_global(x: int, y: int) -> bool:
		return x == 0 and y == 0


# -- cost: route by travel TIME, not distance ------------------------------

func test_dry_flat_ground_costs_nothing_extra():
	assert_almost_eq(AgentPassability.cost_scale_for(FakeWorld.new()).call(Vector2i(0, 0)), 1.0, 0.001)


func test_water_costs_what_swimming_actually_costs():
	# Derived from BASE_SWIM_SPEED (0.6), not invented: if swimming is 0.6x
	# walking speed, crossing a water tile takes 1/0.6 as long, and a route
	# costed in time should say exactly that.
	var world := FakeWorld.new()
	world.rivers = [Vector2i(3, 3)]
	assert_almost_eq(
		AgentPassability.cost_scale_for(world).call(Vector2i(3, 3)),
		1.0 / WaterMovementModel.BASE_SWIM_SPEED,
		0.001
	)


func test_a_cost_scale_is_never_below_one():
	# A* stays optimal only while the heuristic never overestimates, and the
	# octile heuristic assumes a scale of 1. A tile cheaper than 1 would
	# quietly make routes wrong rather than merely odd.
	var world := FakeWorld.new()
	world.rivers = [Vector2i(1, 1)]
	world.ocean = [Vector2i(2, 2)]
	var scale := AgentPassability.cost_scale_for(world)
	for tile in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2), Vector2i(9, 9)]:
		assert_gte(scale.call(tile), 1.0, "tile %s costs less than open ground" % tile)


func test_a_world_that_knows_nothing_costs_nothing():
	assert_false(AgentPassability.cost_scale_for(WorldThatKnowsNothing.new()).is_valid())
	assert_false(AgentPassability.cost_scale_for(null).is_valid())
