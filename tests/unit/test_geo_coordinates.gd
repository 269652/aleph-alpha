extends GutTest

const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
# Real-world scale constants only (WORLD_WIDTH_TILES/WORLD_HEIGHT_TILES) --
# not instantiated, so this doesn't pull in the rest of chunk generation.
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

var geo: GeoCoordinates


func before_each():
	geo = GeoCoordinates.new()


func test_top_row_is_the_north_pole():
	assert_almost_eq(geo.latitude_for_tile(0, 9), 90.0, 0.001)


func test_bottom_row_is_the_south_pole():
	assert_almost_eq(geo.latitude_for_tile(8, 9), -90.0, 0.001)


func test_middle_row_is_the_equator():
	assert_almost_eq(geo.latitude_for_tile(4, 9), 0.0, 0.001)


func test_left_edge_is_the_date_line():
	assert_almost_eq(geo.longitude_for_tile(0, 80), -180.0, 0.001)


func test_horizontal_center_is_the_prime_meridian():
	assert_almost_eq(geo.longitude_for_tile(40, 80), 0.0, 0.001)


func test_longitude_increases_moving_east():
	assert_lt(geo.longitude_for_tile(10, 80), geo.longitude_for_tile(50, 80))


func test_tile_for_latitude_is_the_inverse_of_latitude_for_tile():
	for tile_y in [0, 3, 4, 8]:
		var latitude := geo.latitude_for_tile(tile_y, 9)
		assert_eq(geo.tile_for_latitude(latitude, 9), tile_y)


func test_tile_for_longitude_is_the_inverse_of_longitude_for_tile():
	for tile_x in [0, 20, 40, 60, 79]:
		var longitude := geo.longitude_for_tile(tile_x, 80)
		assert_eq(geo.tile_for_longitude(longitude, 80), tile_x)


## --- Reverse lookup with radius (shared infra for coordinate-triggered
## Easter eggs -- docs/concept/easter_eggs.md's Mothman/Jersey Devil/
## Roswell/Area 51 cameos, and later entries in the same doc). ---


## tile_for_coordinate is just tile_for_longitude + tile_for_latitude
## combined into one call -- the actual "given a real lat/lon, which tile
## does that correspond to" reverse lookup the doc asks for.
func test_tile_for_coordinate_combines_lat_and_lon():
	var tile := geo.tile_for_coordinate(0.0, 0.0, 80, 9)
	assert_eq(tile.x, geo.tile_for_longitude(0.0, 80))
	assert_eq(tile.y, geo.tile_for_latitude(0.0, 9))


## Round trip at the real game-world scale (EarthChunkGenerator's actual
## WORLD_WIDTH_TILES/WORLD_HEIGHT_TILES, ~111 tiles/degree) rather than the
## tiny toy dimensions above -- this is the scale every coordinate-triggered
## Easter egg will actually run at, so the round trip needs to hold up here,
## not just at a 9x80 toy grid. tile -> latlon -> tile should return within
## one tile of the original (rounding tolerance, not exact equality --
## converting to a float lat/lon and back can round either way).
func test_round_trip_tile_to_latlon_to_tile_at_real_world_scale():
	var world_width := EarthChunkGenerator.WORLD_WIDTH_TILES
	var world_height := EarthChunkGenerator.WORLD_HEIGHT_TILES
	# A spread of tiles, including this stage's own Easter egg coordinates
	# converted forward once, so this test doubles as a sanity check on the
	# exact tiles those eggs will be placed at.
	var sample_tiles := [
		Vector2i(0, 0),
		Vector2i(world_width - 1, world_height - 1),
		Vector2i(world_width / 2, world_height / 2),
		geo.tile_for_coordinate(38.85, -82.13, world_width, world_height),  # Mothman
		geo.tile_for_coordinate(39.7, -74.5, world_width, world_height),  # Jersey Devil
		geo.tile_for_coordinate(33.4, -104.5, world_width, world_height),  # Roswell
		geo.tile_for_coordinate(37.2, -115.8, world_width, world_height),  # Area 51
	]
	for tile in sample_tiles:
		var latitude := geo.latitude_for_tile(tile.y, world_height)
		var longitude := geo.longitude_for_tile(tile.x, world_width)
		var round_tripped := geo.tile_for_coordinate(latitude, longitude, world_width, world_height)
		assert_true(
			abs(round_tripped.x - tile.x) <= 1,
			"x round-trip for %s was %s" % [tile, round_tripped]
		)
		assert_true(
			abs(round_tripped.y - tile.y) <= 1,
			"y round-trip for %s was %s" % [tile, round_tripped]
		)


## radius_in_tiles converts a real-world km radius into this world's tile
## space using the same ~111 km/degree scale EarthChunkGenerator's own
## TILES_PER_DEGREE comment documents -- pinned relatively (bigger radius ->
## bigger tile radius, bigger world -> more tiles per km) rather than
## against a hand-eyeballed literal number.
func test_radius_in_tiles_scales_with_km_and_world_size():
	var small_world := geo.radius_in_tiles(10.0, 180)
	var large_radius := geo.radius_in_tiles(20.0, 180)
	assert_gt(large_radius, small_world)

	var finer_world := geo.radius_in_tiles(10.0, 1800)
	assert_gt(finer_world, small_world)
	assert_almost_eq(finer_world, small_world * 10.0, 0.01)


func test_tile_is_within_radius_true_at_the_exact_target_tile():
	var world_width := 3600
	var world_height := 1800
	var target := geo.tile_for_coordinate(38.85, -82.13, world_width, world_height)
	assert_true(
		geo.tile_is_within_radius(
			target.x, target.y, 38.85, -82.13, 5.0, world_width, world_height
		)
	)


func test_tile_is_within_radius_false_far_outside_the_radius():
	var world_width := 3600
	var world_height := 1800
	# Antipodal-ish tile: about as far from the target as this world gets.
	var target := geo.tile_for_coordinate(38.85, -82.13, world_width, world_height)
	var far_tile := Vector2i(
		posmod(target.x + world_width / 2, world_width), world_height - 1 - target.y
	)
	assert_false(
		geo.tile_is_within_radius(
			far_tile.x, far_tile.y, 38.85, -82.13, 5.0, world_width, world_height
		)
	)


func test_tile_is_within_radius_respects_the_radius_boundary():
	var world_width := 3600
	var world_height := 1800
	var target := geo.tile_for_coordinate(0.0, 0.0, world_width, world_height)
	var radius_km := 50.0
	var radius_tiles := geo.radius_in_tiles(radius_km, world_height)

	var just_inside := target + Vector2i(int(radius_tiles) - 1, 0)
	var just_outside := target + Vector2i(int(radius_tiles) + 5, 0)

	assert_true(
		geo.tile_is_within_radius(
			just_inside.x, just_inside.y, 0.0, 0.0, radius_km, world_width, world_height
		)
	)
	assert_false(
		geo.tile_is_within_radius(
			just_outside.x, just_outside.y, 0.0, 0.0, radius_km, world_width, world_height
		)
	)
