extends GutTest

## FishMarker: a lightweight (no needs/perception/behavior AI, unlike
## CreatureMarker) swimming entity -- reuses CreatureWander's pure idle-drift
## pattern, but stays confined to water tiles instead of orbiting freely, so a
## small pond's fish don't wander up onto the grass.

const FishMarker = preload("res://src/rendering/fish_marker.gd")
const CreatureWander = preload("res://src/rendering/creature_wander.gd")

const TILE_SIZE := 16


## Duck-typed world, same shape as CreatureMarker's tests: every tile is the
## same biome unless overridden.
class StubWorld:
	var biome := "ocean"
	func biome_at_global(_x: int, _y: int) -> String:
		return biome


## Only the tile the fish starts on is water; every other tile is land -- lets
## tests assert the fish never swims off its home tile.
class SinglePondWorld:
	var home_tile: Vector2i
	func biome_at_global(x: int, y: int) -> String:
		return "ocean" if Vector2i(x, y) == home_tile else "grassland"


var marker: FishMarker


func before_each():
	marker = FishMarker.new()
	marker.home = Vector2(100, 100)
	marker.position = Vector2(100, 100)
	marker.wander_seed = 5
	marker.species = "goldfish"
	add_child(marker)


func after_each():
	remove_child(marker)
	marker.free()


func test_position_changes_after_processing():
	var before := marker.position
	marker._process(0.5)
	assert_ne(marker.position, before)


func test_stays_within_a_bounded_range_of_home_over_many_steps():
	for i in 100:
		marker._process(0.5)
	assert_lt(marker.position.distance_to(marker.home), CreatureWander.WANDER_RADIUS * 2.0)


func test_two_markers_with_different_seeds_move_differently():
	var other := FishMarker.new()
	other.home = Vector2(100, 100)
	other.position = Vector2(100, 100)
	other.wander_seed = 999
	add_child(other)

	marker._process(0.5)
	other._process(0.5)
	assert_ne(marker.position, other.position)

	remove_child(other)
	other.free()


## Without setup() called, there's no world to check against -- same
## isolated-test fallback CreatureMarker uses (world defaults to null).
func test_swims_freely_when_no_world_is_configured():
	for i in 50:
		marker._process(0.2)
	assert_ne(marker.position, marker.home)


func test_never_swims_onto_land_when_confined_to_a_single_water_tile():
	var world := SinglePondWorld.new()
	world.home_tile = Vector2i(6, 6)
	marker.home = Vector2((6.5) * TILE_SIZE, (6.5) * TILE_SIZE)
	marker.position = marker.home
	marker.setup(world, TILE_SIZE)

	for i in 100:
		marker._process(0.3)
		var tile_x := int(floor(marker.position.x / TILE_SIZE))
		var tile_y := int(floor(marker.position.y / TILE_SIZE))
		assert_eq(world.biome_at_global(tile_x, tile_y), "ocean", "fish left the water on step %d" % i)


func test_swims_around_within_a_larger_water_body():
	var world := StubWorld.new()
	marker.setup(world, TILE_SIZE)
	for i in 60:
		marker._process(0.3)
	assert_ne(marker.position, marker.home)
