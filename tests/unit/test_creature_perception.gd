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


## A world that ALSO exposes real per-tile vegetation density (see
## EarthChunkManager.vegetation_density_at_global) -- the SEPARATE, plain
## StubWorld above deliberately has no such method at all, so every
## existing test against it proves food-sensing still works unchanged for
## any duck-typed caller that doesn't expose density (CreaturePerception
## checks has_method before ever calling it).
class StubWorldWithDensity:
	extends StubWorld
	var _density_by_tile: Dictionary

	func _init(default_biome: String, biome_overrides: Dictionary, density_overrides: Dictionary) -> void:
		super(default_biome, biome_overrides)
		_density_by_tile = density_overrides

	## -1.0 (CreaturePerception's own "no data" sentinel) for any tile not
	## explicitly given a density -- a test that cares about a specific
	## tile's density always states it, rather than relying on a default
	## that could silently make every unlisted tile "food" or "not food".
	func vegetation_density_at_global(x: int, y: int) -> float:
		return _density_by_tile.get(Vector2i(x, y), -1.0)


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


# -- food sensing respects REAL per-tile density, not just the biome ceiling -
#
# Reported gap (docs/progress.md's Vegetation Growth Model row): a herbivore
# could not tell a freshly grazed-BARE grassland tile apart from a lush one
# right next to it -- both are "grassland", and the old check only ever
# asked the biome's own static ceiling, never the live density
# VegetationGrowthModel/EarthChunkManager already track per tile. Every
# test above (a plain StubWorld, no density method at all) must keep
# passing unchanged -- this is a strict, backward-compatible addition, only
# reachable when the world actually exposes live density.

func test_a_grazed_bare_tile_of_a_food_biome_does_not_count_as_food():
	# Standing on desert; grassland two tiles south, but grazed down to
	# near nothing -- must NOT read as "food" despite being a food biome.
	var world := StubWorldWithDensity.new(
		"desert", {Vector2i(0, 2): "grassland"}, {Vector2i(0, 2): 0.02}
	)
	var direction := perception.nearest_direction(Vector2i(0, 0), world, 3, "food")
	assert_eq(direction, Vector2.ZERO, "a near-bare tile must not be sensed as food even though its biome could support some")


func test_a_lush_tile_of_a_food_biome_still_counts_as_food():
	var world := StubWorldWithDensity.new(
		"desert", {Vector2i(0, 2): "grassland"}, {Vector2i(0, 2): 0.6}
	)
	var direction := perception.nearest_direction(Vector2i(0, 0), world, 3, "food")
	assert_gt(direction.y, 0.0, "a genuinely lush tile of a food biome must still be sensed as food")


func test_food_sensing_prefers_a_lusher_tile_over_a_nearer_bare_one_of_the_same_biome():
	# Both tiles are grassland (same biome, same static ceiling) -- only
	# their LIVE density differs. The nearer one is grazed bare; a real
	# lush patch sits one tile further. Without a live-density check both
	# would tie on biome alone and the nearer (bare) one would win first.
	var world := StubWorldWithDensity.new(
		"desert",
		{Vector2i(0, 1): "grassland", Vector2i(0, 2): "grassland"},
		{Vector2i(0, 1): 0.02, Vector2i(0, 2): 0.6}
	)
	var offset := perception.nearest_tile_offset(Vector2i(0, 0), world, 3, "food")
	assert_eq(offset, Vector2i(0, 2), "must skip the nearer bare tile for the further genuinely lush one")


func test_is_on_food_is_false_while_standing_on_a_grazed_bare_food_biome_tile():
	var world := StubWorldWithDensity.new("grassland", {}, {Vector2i(0, 0): 0.02})
	assert_false(perception.is_on(world, Vector2i(0, 0), "food"))


func test_food_sensing_falls_back_to_biome_ceiling_when_the_world_exposes_no_density():
	# The plain StubWorld (used by every test above) has no
	# vegetation_density_at_global at all -- CreaturePerception must not
	# error calling a method that doesn't exist, and must fall back to
	# exactly its old ceiling-only behavior.
	var world := StubWorld.new("grassland")
	assert_true(perception.is_on(world, Vector2i(0, 0), "food"))


func test_a_tile_with_no_reported_density_falls_back_to_the_biome_ceiling():
	# The density-aware stub itself reports -1.0 ("no data") for any tile
	# it wasn't told about -- must fall back to ceiling-only for THAT tile
	# specifically, not be treated as barren just because density is unknown.
	var world := StubWorldWithDensity.new("grassland", {}, {})
	assert_true(perception.is_on(world, Vector2i(0, 0), "food"))


# -- is_on --------------------------------------------------------------------

func test_is_on_water_true_only_on_ocean():
	assert_true(perception.is_on(StubWorld.new("ocean"), Vector2i(0, 0), "water"))
	assert_false(perception.is_on(StubWorld.new("grassland"), Vector2i(0, 0), "water"))


func test_is_on_food_true_on_a_vegetated_biome_false_on_a_barren_one():
	assert_true(perception.is_on(StubWorld.new("grassland"), Vector2i(0, 0), "food"))
	assert_false(perception.is_on(StubWorld.new("desert"), Vector2i(0, 0), "food"))
	assert_false(perception.is_on(StubWorld.new("ocean"), Vector2i(0, 0), "food"))


# -- the nearest tile itself (docs/concept/ethogram.md, slice 2) --------------
#
# A stimulus needs a real position, not a heading: the marker publishes the
# nearest water/food tile as a stimulus and the kernel derives the heading.

func test_nearest_tile_offset_points_at_the_nearest_ocean_tile():
	var world := StubWorld.new("grassland", {Vector2i(2, 0): "ocean", Vector2i(-3, 0): "ocean"})
	assert_eq(perception.nearest_tile_offset(Vector2i(0, 0), world, 3, "water"), Vector2i(2, 0))


func test_nearest_tile_offset_is_zero_on_the_tile_itself_or_with_nothing_in_range():
	assert_eq(perception.nearest_tile_offset(Vector2i(0, 0), StubWorld.new("ocean"), 3, "water"), Vector2i.ZERO)
	assert_eq(perception.nearest_tile_offset(Vector2i(0, 0), StubWorld.new("grassland"), 3, "water"), Vector2i.ZERO)


func test_the_direction_is_the_normalised_tile_offset():
	var world := StubWorld.new("grassland", {Vector2i(3, 4): "ocean"})
	assert_eq(perception.nearest_tile_offset(Vector2i(0, 0), world, 6, "water"), Vector2i(3, 4))
	var direction := perception.nearest_direction(Vector2i(0, 0), world, 6, "water")
	assert_almost_eq(direction.x, 0.6, 0.001)
	assert_almost_eq(direction.y, 0.8, 0.001)
