extends GutTest

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRelief = preload("res://src/world/terrain_relief.gd")
const EarthElevationSource = preload("res://src/world/earth_elevation_source.gd")

var generator: EarthChunkGenerator


func before_each():
	generator = EarthChunkGenerator.new()


func test_chunk_cells_match_direct_global_queries():
	# Proves chunking is just a slice of one globally-consistent function --
	# the actual guarantee of seamlessness across any chunk boundary, rather
	# than only checking one specific pair of adjacent chunks.
	var chunk_size := 8
	var chunk_coord := Vector2i(2, 3)
	var chunk := generator.generate_chunk(chunk_coord, chunk_size)

	var sample_cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(7, 7), Vector2i(3, 4)]
	for local in sample_cells:
		var global_x := chunk_coord.x * chunk_size + local.x
		var global_y := chunk_coord.y * chunk_size + local.y
		var expected := generator.elevation_at_global(global_x, global_y)
		assert_almost_eq(chunk.elevation[local.y * chunk_size + local.x], expected, 0.0001)


func test_biome_at_global_matches_the_generated_chunk_cell():
	# The public per-tile biome query must agree with generate_chunk()'s slice
	# of the same coordinate -- it's what cross-chunk border blending uses to
	# see a neighbor that lies in a not-yet-painted chunk.
	var chunk_size := 8
	var chunk_coord := Vector2i(2, 3)
	var chunk := generator.generate_chunk(chunk_coord, chunk_size)

	for local in [Vector2i(0, 0), Vector2i(7, 7), Vector2i(3, 4)]:
		var global_x: int = chunk_coord.x * chunk_size + local.x
		var global_y: int = chunk_coord.y * chunk_size + local.y
		assert_eq(
			generator.biome_at_global(global_x, global_y),
			chunk.biome[local.y * chunk_size + local.x]
		)


func test_generate_chunk_is_deterministic():
	var first := generator.generate_chunk(Vector2i(5, 5), 8)
	var second := generator.generate_chunk(Vector2i(5, 5), 8)
	assert_eq(first.elevation, second.elevation)
	assert_eq(first.biome, second.biome)


func test_a_global_tile_over_everest_is_classified_as_mountain():
	var global_x := floori((86.92 + 180.0) / 360.0 * EarthChunkGenerator.WORLD_WIDTH_TILES)
	var global_y := floori((90.0 - 27.99) / 180.0 * EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var elevation := generator.elevation_at_global(global_x, global_y)
	assert_gt(elevation, EarthChunkGenerator.EARTH_MOUNTAIN_LEVEL)


func test_a_global_tile_over_the_mariana_trench_is_ocean():
	var global_x := floori((142.0 + 180.0) / 360.0 * EarthChunkGenerator.WORLD_WIDTH_TILES)
	var global_y := floori((90.0 - 11.0) / 180.0 * EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var elevation := generator.elevation_at_global(global_x, global_y)
	assert_lt(elevation, EarthChunkGenerator.EARTH_SEA_LEVEL)


func test_fine_detail_only_slightly_perturbs_the_real_macro_elevation():
	var global_x := 12345
	var global_y := 6789
	var macro := generator.macro_elevation_at_global(global_x, global_y)
	var blended := generator.elevation_at_global(global_x, global_y)
	assert_lt(absf(blended - macro), EarthChunkGenerator.FINE_DETAIL_AMPLITUDE + 0.001)


# -- slope/aspect: real relief from the same real elevation data -----------------

func test_slope_at_global_matches_a_direct_terrain_relief_computation():
	var global_x := 12345
	var global_y := 6789
	var geo := GeoCoordinates.new()
	var latitude := geo.latitude_for_tile(global_y, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var longitude := geo.longitude_for_tile(global_x, EarthChunkGenerator.WORLD_WIDTH_TILES)
	var expected := TerrainRelief.new().slope_at(EarthElevationSource.new(), latitude, longitude)
	assert_almost_eq(generator.slope_at_global(global_x, global_y), expected, 0.0001)


func test_aspect_at_global_matches_a_direct_terrain_relief_computation():
	var global_x := 12345
	var global_y := 6789
	var geo := GeoCoordinates.new()
	var latitude := geo.latitude_for_tile(global_y, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var longitude := geo.longitude_for_tile(global_x, EarthChunkGenerator.WORLD_WIDTH_TILES)
	var expected := TerrainRelief.new().aspect_at(EarthElevationSource.new(), latitude, longitude)
	assert_almost_eq(generator.aspect_at_global(global_x, global_y), expected, 0.0001)


func test_slope_at_global_is_never_negative():
	assert_gte(generator.slope_at_global(12345, 6789), 0.0)


func test_aspect_at_global_is_either_undefined_or_a_valid_compass_bearing():
	var aspect := generator.aspect_at_global(12345, 6789)
	assert_true(
		aspect == -1.0 or (aspect >= 0.0 and aspect < 360.0),
		"aspect should be -1 (undefined) or a real compass bearing, got %f" % aspect
	)


## Real-world sanity check, same spirit as this file's existing Everest/
## Mariana Trench tests: the dramatic local relief around the Himalayas
## should read as measurably steeper than a genuinely flat plain, using
## real landmark coordinates rather than an invented pair of points.
func test_himalayan_terrain_is_steeper_than_a_great_plain():
	var himalaya_x := floori((86.92 + 180.0) / 360.0 * EarthChunkGenerator.WORLD_WIDTH_TILES)
	var himalaya_y := floori((90.0 - 27.99) / 180.0 * EarthChunkGenerator.WORLD_HEIGHT_TILES)
	# Central Kansas, USA -- proverbially flat farmland.
	var plains_x := floori((-98.0 + 180.0) / 360.0 * EarthChunkGenerator.WORLD_WIDTH_TILES)
	var plains_y := floori((90.0 - 38.5) / 180.0 * EarthChunkGenerator.WORLD_HEIGHT_TILES)
	assert_gt(
		generator.slope_at_global(himalaya_x, himalaya_y),
		generator.slope_at_global(plains_x, plains_y)
	)


## RULE-9 pin for the hillshade path: taking the gradient once and deriving
## both readings from it must produce EXACTLY what slope_at_global and
## aspect_at_global return, at real coordinates spanning flat ocean, a desert
## slope and Himalayan relief. If this holds, EarthChunkManager's hillshade
## painter can halve its elevation sampling without any tile changing.
func test_gradient_at_global_derives_exactly_slope_and_aspect_at_global():
	var relief := generator.terrain_relief()
	for tile in [Vector2i(12345, 6789), Vector2i(21600, 6900), Vector2i(9100, 5720), Vector2i(21468, 4160)]:
		var gradient := generator.gradient_at_global(tile.x, tile.y)
		assert_eq(
			relief.slope_degrees_from_gradient(gradient.x, gradient.y),
			generator.slope_at_global(tile.x, tile.y),
			"slope at %s must not depend on how many times the gradient was sampled" % tile
		)
		assert_eq(
			relief.aspect_degrees_from_gradient(gradient.x, gradient.y),
			generator.aspect_at_global(tile.x, tile.y),
			"aspect at %s must not depend on how many times the gradient was sampled" % tile
		)


# -- slope: locally steep terrain forces mountain (real wiring) -------------

## _slope_override_deg_for is the conditional gate that avoids paying
## TerrainRelief.slope_at's four extra elevation samples for a cell whose
## biome elevation alone has already decided the outcome (see
## generate_chunk's own perf comment) -- verified against three real classes
## of cell: ocean, already-elevation-mountain, and ordinary land where slope
## genuinely can still matter.

func test_slope_override_is_not_provided_for_an_ocean_cell():
	# Mariana Trench -- same coordinate as
	# test_a_global_tile_over_the_mariana_trench_is_ocean. Ocean's
	# classification can't change on slope (classify() checks ocean first,
	# unconditionally), so the four extra elevation samples must be skipped
	# entirely rather than spent on a reading that can't matter.
	var global_x := floori((142.0 + 180.0) / 360.0 * EarthChunkGenerator.WORLD_WIDTH_TILES)
	var global_y := floori((90.0 - 11.0) / 180.0 * EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var elevation := generator.elevation_at_global(global_x, global_y)
	assert_eq(
		generator._slope_override_deg_for(global_x, global_y, elevation),
		BiomeClassifier.SLOPE_NOT_PROVIDED
	)


func test_slope_override_is_not_provided_for_an_already_elevation_mountain_cell():
	# Everest summit -- same coordinate as
	# test_a_global_tile_over_everest_is_classified_as_mountain. Already
	# "mountain" by elevation alone, so slope can't change that outcome
	# either -- skip sampling it there too.
	var global_x := floori((86.92 + 180.0) / 360.0 * EarthChunkGenerator.WORLD_WIDTH_TILES)
	var global_y := floori((90.0 - 27.99) / 180.0 * EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var elevation := generator.elevation_at_global(global_x, global_y)
	assert_eq(
		generator._slope_override_deg_for(global_x, global_y, elevation),
		BiomeClassifier.SLOPE_NOT_PROVIDED
	)


func test_slope_override_is_the_real_slope_for_an_undecided_land_cell():
	# Annapurna flank, Nepal -- real land below EARTH_MOUNTAIN_LEVEL
	# (elevation ~0.746 < 0.75, verified below) where the outcome is NOT
	# already decided by elevation alone, so slope must be genuinely
	# sampled -- not skipped, and not the sentinel.
	var global_x := floori((84.10 + 180.0) / 360.0 * EarthChunkGenerator.WORLD_WIDTH_TILES)
	var global_y := floori((90.0 - 28.42) / 180.0 * EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var elevation := generator.elevation_at_global(global_x, global_y)
	assert_gte(elevation, EarthChunkGenerator.EARTH_SEA_LEVEL, "precondition: not ocean")
	assert_lt(elevation, EarthChunkGenerator.EARTH_MOUNTAIN_LEVEL, "precondition: not already mountain")
	assert_eq(
		generator._slope_override_deg_for(global_x, global_y, elevation),
		generator.slope_at_global(global_x, global_y)
	)


func test_generated_biomes_are_all_known():
	var chunk := generator.generate_chunk(Vector2i(100, 50), 8)
	for biome_name in chunk.biome:
		assert_true(BiomeClassifier.KNOWN_BIOMES.has(biome_name))


func test_chunk_moisture_and_temperature_match_direct_global_queries():
	var chunk_size := 8
	var chunk_coord := Vector2i(2, 3)
	var chunk := generator.generate_chunk(chunk_coord, chunk_size)

	var sample_cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(7, 7), Vector2i(3, 4)]
	for local in sample_cells:
		var global_x := chunk_coord.x * chunk_size + local.x
		var global_y := chunk_coord.y * chunk_size + local.y
		var index := local.y * chunk_size + local.x
		assert_almost_eq(
			chunk.moisture[index], generator.moisture_at_global(global_x, global_y), 0.0001
		)
		assert_almost_eq(
			chunk.temperature[index], generator.temperature_at_global(global_x, global_y), 0.0001
		)


# -- elevation reuse: temperature no longer re-derives what the caller has ------

## generate_chunk and biome_at_global both compute a cell's elevation one
## line before asking for its temperature, and temperature_at_global used to
## re-derive it -- four extra bilinear elevation samples (sixteen byte reads)
## per cell for a number already sitting in a local. temperature_at_elevation
## is the same formula taking that local, so the two must agree EXACTLY, not
## approximately: elevation_at_global is a deterministic pure function of the
## tile, so both paths see the identical double and any difference at all
## would mean the formula drifted.
func test_temperature_at_elevation_is_exactly_temperature_at_global():
	for tile in [Vector2i(12345, 6789), Vector2i(21600, 6900), Vector2i(9100, 5720), Vector2i(0, 0)]:
		var cell_elevation := generator.elevation_at_global(tile.x, tile.y)
		assert_eq(
			generator.temperature_at_elevation(tile.y, cell_elevation),
			generator.temperature_at_global(tile.x, tile.y),
			"temperature at %s must not depend on which of the two entry points asked" % tile
		)


## RULE-9 pin for the whole generation path: every cell of a real chunk must
## be bit-for-bit what the public per-tile queries return for the same
## coordinate. The pre-existing test_chunk_cells_match_direct_global_queries
## samples three cells at 1e-4 tolerance; this one walks ALL of them at exact
## equality, across an arctic chunk, the Berlin chunk and a Himalayan one, so
## the elevation-reuse refactor cannot move terrain, climate or biomes by a
## bit.
##
## The expected values are collected into PackedFloat32Arrays rather than
## compared as loose floats, because Chunk stores them in PackedFloat32Array
## fields: a raw double from a per-tile query is NOT equal to the same number
## after that 32-bit round trip (measured, e.g. 0.58563596010208 vs
## 0.5856359670667), so comparing the packed arrays is what makes "exact"
## mean exact instead of quietly meaning "within a float32 ulp".
func test_every_generated_cell_is_exactly_the_per_tile_query():
	var chunk_size := 8
	for chunk_coord in [Vector2i(2, 3), Vector2i(2683, 520), Vector2i(1235, 690)]:
		var chunk := generator.generate_chunk(chunk_coord, chunk_size)
		var expected_elevation := PackedFloat32Array()
		var expected_moisture := PackedFloat32Array()
		var expected_temperature := PackedFloat32Array()
		var expected_biome := PackedStringArray()
		for local_y in chunk_size:
			for local_x in chunk_size:
				var global_x: int = chunk_coord.x * chunk_size + local_x
				var global_y: int = chunk_coord.y * chunk_size + local_y
				expected_elevation.append(generator.elevation_at_global(global_x, global_y))
				expected_moisture.append(generator.moisture_at_global(global_x, global_y))
				expected_temperature.append(generator.temperature_at_global(global_x, global_y))
				expected_biome.append(generator.biome_at_global(global_x, global_y))
		assert_eq(chunk.elevation, expected_elevation, "elevation of chunk %s" % chunk_coord)
		assert_eq(chunk.moisture, expected_moisture, "moisture of chunk %s" % chunk_coord)
		assert_eq(chunk.temperature, expected_temperature, "temperature of chunk %s" % chunk_coord)
		assert_eq(chunk.biome, expected_biome, "biomes of chunk %s" % chunk_coord)


func test_chunk_moisture_and_temperature_are_normalized():
	var chunk := generator.generate_chunk(Vector2i(100, 50), 8)
	for value in chunk.moisture:
		assert_between(value, 0.0, 1.0)
	for value in chunk.temperature:
		assert_between(value, 0.0, 1.0)


# -- is_river_at_global (docs/concept/rivers.md) -----------------------------
#
# Rivers never change biome_at_global's own result (see rivers.md's
# "Rendering" section -- a river is an overlay over whatever land biome was
# already there, not an eighth entry in BiomeClassifier.KNOWN_BIOMES). This
# is a SEPARATE query, consulted only by EarthChunkManager's water overlay.

func test_the_gaskugel_spawn_point_is_a_river_tile():
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_true(generator.is_river_at_global(tile.x, tile.y))


func test_a_point_far_from_any_curated_river_and_off_the_procedural_contour_is_not_a_river():
	# Ocean elevation both rules out the curated-river width band (too far
	# from any curated polyline) AND the procedural gate (ocean never
	# passes it) -- deep Pacific is a safe "definitely not a river" fixture.
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		0.0, -160.0, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_false(generator.is_river_at_global(tile.x, tile.y))


func test_river_depth_at_global_is_deepest_at_a_curated_waypoint():
	const RiverDepth = preload("res://src/world/river_depth.gd")
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_almost_eq(
		generator.river_depth_meters_at_global(tile.x, tile.y),
		RiverDepth.MAX_CURATED_RIVER_DEPTH_METERS,
		0.01
	)


func test_river_depth_at_global_is_zero_far_from_any_river():
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		0.0, -160.0, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_eq(generator.river_depth_meters_at_global(tile.x, tile.y), 0.0)


func test_river_tiles_still_report_their_ordinary_land_biome():
	# The core "overlay, not a new biome" guarantee: a river tile's
	# biome_at_global is completely unaffected by is_river_at_global.
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_true(generator.is_river_at_global(tile.x, tile.y))
	assert_ne(generator.biome_at_global(tile.x, tile.y), "river")
	assert_true(BiomeClassifier.KNOWN_BIOMES.has(generator.biome_at_global(tile.x, tile.y)))
