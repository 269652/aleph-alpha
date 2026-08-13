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


## Water fills every tile column up to (and including) max_water_tile_x --
## a straight north-south shoreline, for asserting a fish slides along it
## rather than beaching or freezing against it.
class ShorelineWorld:
	var max_water_tile_x := 6
	func biome_at_global(x: int, _y: int) -> String:
		return "ocean" if x <= max_water_tile_x else "grassland"


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


## The reported stranding bug: a fish whose wander heading pointed at the
## shore used to just stop dead for the whole direction interval, piling
## fish up motionless along the waterline. It must instead deflect and keep
## swimming (any turn that stays in water), every single frame.
func test_fish_keeps_moving_along_a_shoreline_instead_of_freezing():
	var world := ShorelineWorld.new()
	marker.home = Vector2(6.5 * TILE_SIZE, 6.5 * TILE_SIZE)  # water tile right at the shore
	marker.position = marker.home
	marker.setup(world, TILE_SIZE)

	var moved := 0
	for i in 150:
		var before := marker.position
		marker._process(0.25)
		if marker.position != before:
			moved += 1
	assert_eq(moved, 150, "a fish beside a shoreline should deflect and keep swimming every frame, never freeze")


## The other half of "stranded at the shoreline": moving is gated on the
## fish keeping CLEARANCE_PX of open water on every side of its center --
## roughly the sprite's half-extent -- so no part of the fish ever visually
## overlaps the beach, whichever way it's pointing.
func test_fish_clearance_keeps_it_clear_of_the_waterline():
	var world := ShorelineWorld.new()
	marker.home = Vector2(6.0 * TILE_SIZE, 6.5 * TILE_SIZE)  # inside the shore tile, clear of the edge
	marker.position = marker.home
	marker.setup(world, TILE_SIZE)

	var water_edge_x := (world.max_water_tile_x + 1) * TILE_SIZE
	for i in 200:
		marker._process(0.25)
		assert_lt(
			marker.position.x, water_edge_x - FishMarker.CLEARANCE_PX + 0.01,
			"the fish's center must stay at least CLEARANCE_PX clear of the waterline (step %d)" % i
		)
