extends GutTest

const CreaturePerception = preload("res://src/gameplay/creature_perception.gd")

var perception: CreaturePerception


## Duck-typed stand-in for EarthChunkManager: answers biome_at_global(x, y).
class StubWorld:
	var _biome_by_tile: Dictionary
	var _default: String

	func _init(default_biome: String, overrides: Dictionary = {}) -> void:
		_default = default_biome
		_biome_by_tile = overrides

	func biome_at_global(x: int, y: int) -> String:
		return _biome_by_tile.get(Vector2i(x, y), _default)


func before_each():
	perception = CreaturePerception.new()


# -- nearby (radius filter) ---------------------------------------------------

func test_nearby_keeps_only_positions_within_the_radius():
	var result := perception.nearby(Vector2.ZERO, [Vector2(5, 0), Vector2(500, 0)], 20.0)
	assert_eq(result, [Vector2(5, 0)])


func test_nearby_returns_empty_when_nothing_is_close():
	var result := perception.nearby(Vector2.ZERO, [Vector2(500, 0)], 20.0)
	assert_eq(result, [])


# -- water sensing ------------------------------------------------------------

func test_direction_to_water_is_zero_when_standing_on_water():
	var world := StubWorld.new("ocean")
	var direction := perception.nearest_direction(Vector2i(0, 0), world, 3, "water")
	assert_eq(direction, Vector2.ZERO)


func test_direction_to_water_points_at_the_nearest_ocean_tile():
	# Land everywhere except one ocean tile to the east.
	var world := StubWorld.new("grassland", {Vector2i(2, 0): "ocean"})
	var direction := perception.nearest_direction(Vector2i(0, 0), world, 3, "water")
	assert_gt(direction.x, 0.0)
	assert_almost_eq(direction.y, 0.0, 0.001)


func test_direction_to_water_is_zero_when_no_water_in_range():
	var world := StubWorld.new("grassland")
	var direction := perception.nearest_direction(Vector2i(0, 0), world, 3, "water")
	assert_eq(direction, Vector2.ZERO)


# -- food sensing -------------------------------------------------------------

func test_direction_to_food_points_at_a_vegetated_tile_from_a_barren_one():
	# Standing on desert (barren), grassland (food) to the south.
	var world := StubWorld.new("desert", {Vector2i(0, 2): "grassland"})
	var direction := perception.nearest_direction(Vector2i(0, 0), world, 3, "food")
	assert_gt(direction.y, 0.0)
	assert_almost_eq(direction.x, 0.0, 0.001)


func test_direction_to_food_is_zero_when_standing_on_a_food_biome():
	var world := StubWorld.new("forest")
	var direction := perception.nearest_direction(Vector2i(0, 0), world, 3, "food")
	assert_eq(direction, Vector2.ZERO)


func test_unloaded_tiles_are_never_food_or_water():
	var world := StubWorld.new("")  # EarthChunkManager returns "" for unloaded tiles
	assert_eq(perception.nearest_direction(Vector2i(0, 0), world, 3, "water"), Vector2.ZERO)
	assert_eq(perception.nearest_direction(Vector2i(0, 0), world, 3, "food"), Vector2.ZERO)


# -- is_on --------------------------------------------------------------------

func test_is_on_water_true_only_on_ocean():
	assert_true(perception.is_on(StubWorld.new("ocean"), Vector2i(0, 0), "water"))
	assert_false(perception.is_on(StubWorld.new("grassland"), Vector2i(0, 0), "water"))


func test_is_on_food_true_on_a_vegetated_biome_false_on_a_barren_one():
	assert_true(perception.is_on(StubWorld.new("grassland"), Vector2i(0, 0), "food"))
	assert_false(perception.is_on(StubWorld.new("desert"), Vector2i(0, 0), "food"))
	assert_false(perception.is_on(StubWorld.new("ocean"), Vector2i(0, 0), "food"))
