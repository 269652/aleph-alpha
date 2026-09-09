extends GutTest

## Pure ring-scan geometry for the ambient river-proximity layer (see
## docs/concept/soundscape.md's "Proximity layers" gap this closes, and
## docs/concept/creature_and_footstep_audio.md for the sibling "individual
## nearby animals" half of the same live request: "fully build the
## soundscape out of individual nearby animals and environment").
##
## Takes `is_water` as a plain Callable (the same (global_x: int,
## global_y: int) -> bool shape `is_river_at_global`/`is_lake_at_global`
## already use) rather than being hard-coded to either, so this is fully
## testable against synthetic, KNOWN coordinates -- the same "test the
## wiring, not exact results against unpredictable real generated
## terrain" reasoning test_earth_chunk_manager_footprints.gd's own
## record_footstep tests already document. A separate, standalone pure
## module (not a method on EarthChunkManager itself) so a test of this
## file's own geometry never has to compile that much heavier class.

const WaterProximity = preload("res://src/world/water_proximity.gd")


func _water_at(coords: Array) -> Callable:
	var set := {}
	for c in coords:
		set[c] = true
	return func(x: int, y: int): return set.has(Vector2i(x, y))


func test_returns_zero_when_standing_on_water():
	var is_water := _water_at([Vector2i(5, 5)])
	assert_eq(WaterProximity.nearest_distance_tiles(5, 5, 10, is_water), 0.0)


func test_returns_the_real_distance_to_an_adjacent_tile():
	var is_water := _water_at([Vector2i(6, 5)])
	assert_almost_eq(WaterProximity.nearest_distance_tiles(5, 5, 10, is_water), 1.0, 0.001)


func test_returns_the_real_euclidean_distance_not_a_tile_count():
	# 3 tiles east, 4 tiles north of the scan origin -- a real 3-4-5
	# right triangle, not the taxicab distance (7) a naive tile-count
	# would give.
	var is_water := _water_at([Vector2i(8, 1)])
	assert_almost_eq(WaterProximity.nearest_distance_tiles(5, 5, 10, is_water), 5.0, 0.001)


func test_picks_the_nearest_of_several_water_tiles():
	var is_water := _water_at([Vector2i(20, 20), Vector2i(6, 5), Vector2i(-20, -20)])
	assert_almost_eq(WaterProximity.nearest_distance_tiles(5, 5, 10, is_water), 1.0, 0.001)


func test_returns_inf_when_nothing_is_within_the_scan_radius():
	var is_water := _water_at([Vector2i(100, 100)])
	assert_eq(WaterProximity.nearest_distance_tiles(5, 5, 10, is_water), INF)


## A hit exactly at the scan radius's own edge must still be found -- an
## off-by-one here would silently shrink the documented radius.
func test_a_hit_exactly_at_the_scan_radius_is_still_found():
	var is_water := _water_at([Vector2i(15, 5)])  # exactly 10 tiles east
	assert_almost_eq(WaterProximity.nearest_distance_tiles(5, 5, 10, is_water), 10.0, 0.001)
