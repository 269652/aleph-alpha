extends GutTest

## BuildingWalls.predicate_for: the one place a mover learns which tiles a
## building stands on (see docs/concept/navigation.md).
##
## One definition, three consumers (NpcMarker, CreatureMarker,
## BondedCompanionMarker), so they can never disagree about what a wall
## is -- the same "one function, so two callers cannot drift" discipline
## BuildingCatalog.finished_sheet_for already keeps.

const BuildingWalls = preload("res://src/gameplay/building_walls.gd")


class WorldWithAHouse:
	extends RefCounted
	var asked: Array[Vector2i] = []

	func has_building_at_global(x: int, y: int) -> bool:
		asked.append(Vector2i(x, y))
		return x == 3 and y == 4


class WorldThatCannotAnswer:
	extends RefCounted
	func biome_at_global(_x: int, _y: int) -> String:
		return "grassland"


func test_a_world_that_knows_its_buildings_gives_a_real_predicate():
	var world := WorldWithAHouse.new()
	var walls := BuildingWalls.predicate_for(world)
	assert_true(walls.is_valid())
	assert_true(walls.call(Vector2i(3, 4)))
	assert_false(walls.call(Vector2i(3, 5)))


func test_the_predicate_asks_the_world_the_tile_it_was_given():
	var world := WorldWithAHouse.new()
	BuildingWalls.predicate_for(world).call(Vector2i(9, -2))
	assert_eq(world.asked, [Vector2i(9, -2)] as Array[Vector2i])


func test_a_world_that_cannot_answer_gives_an_invalid_predicate():
	# Fail-open, the same duck-typed contract NpcMarker._is_in_water keeps:
	# a stub or an unbound marker must walk exactly as it always did, and
	# both gates read an invalid Callable as "nothing is solid".
	assert_false(BuildingWalls.predicate_for(WorldThatCannotAnswer.new()).is_valid())


func test_a_null_world_gives_an_invalid_predicate():
	assert_false(BuildingWalls.predicate_for(null).is_valid())
