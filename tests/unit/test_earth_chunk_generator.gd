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


## New Chunk field, needed so worldgen-time decoration placement (trees,
## grass -- see TreeRenderer.spawn_trees, TallGrass) can exclude river
## cells without each needing its own live generator reference: they
## already receive the whole Chunk. The Gaskugel's own chunk is used
## specifically (not an arbitrary one) so this test has a REAL true value
## to check, not just an all-false array that would pass by accident.
func test_chunk_is_river_matches_is_river_at_global_including_a_real_river_cell():
	var geo := GeoCoordinates.new()
	var river_tile := geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var chunk_size := 8
	var chunk_coord := Vector2i(
		floori(float(river_tile.x) / chunk_size), floori(float(river_tile.y) / chunk_size)
	)
	var chunk := generator.generate_chunk(chunk_coord, chunk_size)

	var found_a_river_cell := false
	for local_y in chunk_size:
		for local_x in chunk_size:
			var global_x := chunk_coord.x * chunk_size + local_x
			var global_y := chunk_coord.y * chunk_size + local_y
			var index := local_y * chunk_size + local_x
			var expected := generator.is_river_at_global(global_x, global_y)
			if expected:
				found_a_river_cell = true
			assert_eq(chunk.is_river[index] == 1, expected, "(%d, %d)" % [global_x, global_y])
	assert_true(found_a_river_cell, "expected the Gaskugel's own chunk to contain a real river cell")


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


## REPLACED a test that pinned RiverDepth.MAX_CURATED_RIVER_DEPTH_METERS
## (2.5 m) at the centreline. That constant was an AUTHORED taper maximum --
## a number chosen so a curated river would span the wading/swimming
## threshold, not a number derived from anything real. Depth is now solved
## from the Dreisam's real curated discharge, and the honest answer at the
## Gaskugel is far shallower.
##
## That is the correct real answer, not a regression: the Dreisam is a small
## Black Forest stream (mean 5.56 m3/s at Pegel Ebnet, low-flow 0.503) and
## is genuinely wadeable through Freiburg -- which is exactly why the town
## grew where it did. A model that made it chest-deep would be the wrong one.
func test_river_depth_at_a_curated_waypoint_is_the_real_solved_depth():
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var depth := generator.river_depth_meters_at_global(tile.x, tile.y)
	assert_gt(depth, 0.0, "the Dreisam has real water in it")
	assert_lt(depth, 1.5, "a real small stream should be wadeable, not chest-deep")


## Reported directly, after playtesting: procedural rivers were "scattered
## everywhere" and read as disconnected patches unrelated to any real
## river -- not "one coherent stream" the way a curated, GPS-traced river
## does. Measured before this fix: ~6% of tiles in a curated-river-free
## region tested true via the noise-contour proxy alone (see
## docs/concept/rivers.md's "Procedural fallback reverted" section). The
## procedural module itself (procedural_river.gd) stays real and tested,
## just no longer consulted live -- curated-only is what's live now.
func test_procedural_fallback_is_not_live_wired_far_from_any_curated_river():
	# The NOISE-CONTOUR proxy (procedural_river.gd) is what must stay
	# unwired. The hydrology bake is a different, connectivity-aware
	# fallback (docs/concept/hydrology.md); it is switched off here so this
	# test keeps asking only its original question.
	generator.hydrology_rivers_enabled = false
	for x in range(20000, 20400, 37):
		for y in range(7000, 7400, 41):
			assert_false(generator.is_river_at_global(x, y), "(%d, %d) should not be a river with procedural fallback disabled" % [x, y])
			assert_eq(generator.river_depth_meters_at_global(x, y), 0.0)


# -- real hydraulics (docs/concept/rivers.md) --------------------------------
#
# Depth used to be a made-up linear taper from a centreline maximum. It is
# now solved from the river's REAL curated discharge through Manning's
# equation and continuity, so depth, current speed and pressure are one
# self-consistent physical answer rather than three independent inventions.

func test_river_hydraulics_at_the_gaskugel_are_physically_self_consistent():
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var flow := generator.river_hydraulics_at_global(tile.x, tile.y)

	assert_gt(flow.discharge_m3_s, 0.0, "the Dreisam carries real water at the spawn point")
	assert_gt(flow.width_m, 0.0)
	assert_gt(flow.depth_m, 0.0)
	assert_gt(flow.velocity_m_s, 0.0)
	# Continuity: Q = width * depth * velocity, by construction.
	assert_almost_eq(
		(flow.width_m * flow.depth_m * flow.velocity_m_s) / flow.discharge_m3_s, 1.0, 0.15
	)


## Real-world sanity, the same spirit as this file's Everest/Mariana tests:
## the Dreisam is a small Black Forest stream, so its numbers must land in
## the range a real small river occupies -- not a millimetre, not an ocean.
func test_the_dreisam_reads_like_a_real_small_river_not_a_torrent_or_a_puddle():
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var flow := generator.river_hydraulics_at_global(tile.x, tile.y)
	# NIWA/Jowett instream-habitat survey: 0.1-0.3 m/s is "adequate",
	# 0.3-0.5 "good" for stream life; USGS gauged flood peaks reach ~3 m/s.
	# A real small river sits well inside that whole band.
	assert_between(flow.velocity_m_s, 0.05, 3.0, "current speed %f m/s is not a real river" % flow.velocity_m_s)
	assert_between(flow.depth_m, 0.05, 5.0, "depth %f m is not a real small river" % flow.depth_m)
	assert_between(flow.width_m, 2.0, 120.0, "width %f m is not a real small river" % flow.width_m)


## The whole point of curating discharge: a big river must actually read as
## bigger than a small one. The Rhine carries ~267x the Dreisam's flow.
func test_the_rhine_is_deeper_wider_and_carries_far_more_than_the_dreisam():
	var geo := GeoCoordinates.new()
	var dreisam := geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var rhine := geo.tile_for_coordinate(
		50.93639, 6.95278, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var small := generator.river_hydraulics_at_global(dreisam.x, dreisam.y)
	var big := generator.river_hydraulics_at_global(rhine.x, rhine.y)
	assert_gt(big.discharge_m3_s, small.discharge_m3_s * 50.0)
	assert_gt(big.width_m, small.width_m)
	assert_gt(big.depth_m, small.depth_m)


func test_hydraulics_are_all_zero_away_from_any_river():
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		0.0, -160.0, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var flow := generator.river_hydraulics_at_global(tile.x, tile.y)
	assert_eq(flow.depth_m, 0.0)
	assert_eq(flow.velocity_m_s, 0.0)
	assert_eq(flow.discharge_m3_s, 0.0)


## Real pressure at the bed, from the real solved depth -- p = rho*g*h.
func test_bed_pressure_follows_from_the_solved_depth():
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var flow := generator.river_hydraulics_at_global(tile.x, tile.y)
	assert_almost_eq(flow.bed_pressure_pa, 1000.0 * 9.81 * flow.depth_m, 1.0)


## river_depth_meters_at_global must now report the SOLVED depth -- it is the
## number the player's wading/swimming/submersion chain already reads, so
## real hydraulics reaching it is what makes the physics playable rather
## than merely computed.
func test_the_depth_query_reports_the_solved_hydraulic_depth():
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_almost_eq(
		generator.river_depth_meters_at_global(tile.x, tile.y),
		generator.river_hydraulics_at_global(tile.x, tile.y).depth_m,
		0.0001
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


# -- hydrology (docs/concept/hydrology.md, phase 1) ---------------------------
#
# A synthetic 7x7 bake read over the REAL world grid: a 0.8 plateau under a
# sea row, a 3x3 crater at 0.3, and the crater's outlet channel (column 3,
# rows 1-2) at 0.7. Asset cell (3,1) is the outlet: its centreline runs
# along longitude 0 from ~26N to ~77N, so Greenwich sits on it. Crater cell
# (2,4) spans 51W-0 x 39S-13S: the Parana plateau (~1,100 m, below the
# crater's 0.7 = 2,080 m spill) sits inside it.

const HydrologyData = preload("res://src/world/hydrology_data.gd")
const HydrologyField = preload("res://src/world/hydrology_field.gd")
const DrainageNetwork = preload("res://src/world/drainage_network.gd")

## Longitude 0, latitude 51.4N: on the synthetic outlet's centreline.
const GREENWICH_TILE := Vector2i(19980, 4284)
## Longitude 51.4W, latitude 25.7S: inside the synthetic crater, on real land.
const PARANA_TILE := Vector2i(14271, 12842)


func _synthetic_field() -> HydrologyField:
	var heights := PackedFloat32Array()
	heights.resize(49)
	heights.fill(0.8)
	for x in 7:
		heights[x] = 0.2
	for y in range(3, 6):
		for x in range(2, 5):
			heights[y * 7 + x] = 0.3
	heights[1 * 7 + 3] = 0.7
	heights[2 * 7 + 3] = 0.7
	var network = DrainageNetwork.new().build(heights, 7, 7, 0.5)
	var weights := PackedFloat32Array()
	weights.resize(49)
	weights.fill(1.0)
	var data := HydrologyData.new()
	data.build_from_network(network, network.accumulate_weighted(weights))
	var field := HydrologyField.new(
		data, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	field.river_min_discharge = 5.0
	return field


func test_fine_detail_never_flips_land_to_sea_or_sea_to_land():
	# The procedural fine detail is +-432 m of texture; near a coast it used
	# to scatter below-sea-level tiles across every plain within reach of
	# sea level -- "dozens of small ponds to the sides of rivers", each an
	# ocean-biome speckle. Land stays land, sea stays sea; only the macro
	# data decides the coastline.
	generator.set_hydrology(null)
	var sea_level := EarthChunkGenerator.EARTH_SEA_LEVEL
	var flips := 0
	var checked := 0
	# A band across the Loire estuary and the Vendee coast, where the
	# macro elevation hugs sea level.
	for y in range(4700, 4900, 7):
		for x in range(19600, 19900, 11):
			var macro := generator.macro_elevation_at_global(x, y)
			var blended := generator.elevation_at_global(x, y)
			checked += 1
			if (macro < sea_level) != (blended < sea_level):
				flips += 1
	assert_gt(checked, 500)
	assert_eq(flips, 0)


func test_the_coastline_is_the_bakes_sea_contour():
	# With a bake, sea is where the smoothed baked sea mask passes half,
	# not where the bilinear elevation dips: the synthetic bake's sea row
	# covers the far north, so a tile over Greenland's ice (real macro
	# elevation far above sea level) is sea, and a tile in the synthetic
	# plateau over the real South China Sea is land.
	generator.set_hydrology(_synthetic_field())
	var greenland := Vector2i(19980, 1110)
	assert_eq(generator.biome_at_global(greenland.x, greenland.y), "ocean")
	assert_lt(generator.elevation_at_global(greenland.x, greenland.y), EarthChunkGenerator.EARTH_SEA_LEVEL)
	var south_china_sea := Vector2i(32745, 8325)
	assert_ne(generator.biome_at_global(south_china_sea.x, south_china_sea.y), "ocean")
	assert_gt(generator.elevation_at_global(south_china_sea.x, south_china_sea.y), EarthChunkGenerator.EARTH_SEA_LEVEL)


func test_a_generator_without_a_bake_reports_no_hydrology():
	generator.set_hydrology(null)
	assert_false(generator.has_hydrology())
	assert_eq(generator.hydrology_at_global(GREENWICH_TILE.x, GREENWICH_TILE.y)["kind"], "")
	assert_false(generator.is_lake_at_global(PARANA_TILE.x, PARANA_TILE.y))
	assert_eq(generator.lake_depth_meters_at_global(PARANA_TILE.x, PARANA_TILE.y), 0.0)


func test_an_injected_bake_makes_a_basin_tile_a_lake_with_real_depth():
	generator.set_hydrology(_synthetic_field())
	assert_true(generator.is_lake_at_global(PARANA_TILE.x, PARANA_TILE.y))
	assert_gt(generator.lake_depth_meters_at_global(PARANA_TILE.x, PARANA_TILE.y), 0.0)
	# An overlay on untouched land, never a biome (rivers.md's model).
	var biome := generator.biome_at_global(PARANA_TILE.x, PARANA_TILE.y)
	assert_true(BiomeClassifier.KNOWN_BIOMES.has(biome))
	assert_ne(biome, "ocean")


func test_generated_chunk_is_lake_matches_is_lake_at_global():
	generator.set_hydrology(_synthetic_field())
	var chunk_size := 8
	var chunk_coord := Vector2i(
		floori(float(PARANA_TILE.x) / chunk_size), floori(float(PARANA_TILE.y) / chunk_size)
	)
	var chunk := generator.generate_chunk(chunk_coord, chunk_size)
	var local := PARANA_TILE - chunk_coord * chunk_size
	var index := local.y * chunk_size + local.x
	assert_eq(chunk.is_lake[index], 1)
	assert_true(chunk.blocks_ground_cover(index))
	for y in chunk_size:
		for x in chunk_size:
			var expected := 1 if generator.is_lake_at_global(chunk_coord.x * chunk_size + x, chunk_coord.y * chunk_size + y) else 0
			assert_eq(chunk.is_lake[y * chunk_size + x], expected)


func test_hydrology_rivers_are_on_by_default():
	# Switched on the day the spawn moved onto an emergent river; the
	# instance flag still lets a test (or a rollback) turn them off.
	assert_true(EarthChunkGenerator.HYDROLOGY_RIVERS_ENABLED)
	assert_true(generator.hydrology_rivers_enabled)


func test_with_hydrology_rivers_disabled_a_channel_tile_is_not_a_river():
	generator.set_hydrology(_synthetic_field())
	generator.hydrology_rivers_enabled = false
	assert_false(generator.is_river_at_global(GREENWICH_TILE.x, GREENWICH_TILE.y))
	assert_eq(generator.river_depth_meters_at_global(GREENWICH_TILE.x, GREENWICH_TILE.y), 0.0)
	var apron := RiverCatalog.RIVER_HALF_WIDTH_TILES + RiverCatalog.RIVER_BANK_APRON_TILES
	assert_gt(generator.nearest_river_at(GREENWICH_TILE.x, GREENWICH_TILE.y).distance_tiles, apron)


func test_with_hydrology_rivers_enabled_a_channel_tile_is_a_river_with_solved_hydraulics():
	generator.set_hydrology(_synthetic_field())
	generator.hydrology_rivers_enabled = true
	assert_true(generator.is_river_at_global(GREENWICH_TILE.x, GREENWICH_TILE.y))

	var hydraulics := generator.river_hydraulics_at_global(GREENWICH_TILE.x, GREENWICH_TILE.y)
	assert_eq(hydraulics.river_name, "", "an unnamed baked channel, not a curated river")
	assert_gt(hydraulics.discharge_m3_s, 0.0)
	assert_gt(hydraulics.width_m, 0.0)
	assert_gt(hydraulics.depth_m, 0.0)
	# The same continuity the curated solve guarantees: Q = w * d * v.
	assert_almost_eq(
		hydraulics.width_m * hydraulics.depth_m * hydraulics.velocity_m_s,
		hydraulics.discharge_m3_s, hydraulics.discharge_m3_s * 1e-6
	)
	assert_almost_eq(
		generator.river_depth_meters_at_global(GREENWICH_TILE.x, GREENWICH_TILE.y), hydraulics.depth_m, 1e-9
	)

	# The flow overlay's geometry, in the catalog's own shape, plus the
	# channel's own half-width.
	var nearest := generator.nearest_river_at(GREENWICH_TILE.x, GREENWICH_TILE.y)
	assert_eq(nearest.name, "")
	assert_lte(nearest.distance_tiles, nearest.half_width_tiles)
	assert_gt(nearest.half_width_tiles, 0.0)
	assert_almost_eq(nearest.course_bearing_deg, 0.0, 1e-6, "the outlet flows due north to the sea row")

	# A bank tile just past the waterline is in the apron (a boulder there
	# bends the water); a tile well beyond it is not.
	var bank_x := GREENWICH_TILE.x + int(ceil(nearest.half_width_tiles))
	assert_false(generator.is_river_at_global(bank_x, GREENWICH_TILE.y))
	assert_true(generator.is_within_river_apron(bank_x, GREENWICH_TILE.y))
	assert_false(generator.is_within_river_apron(GREENWICH_TILE.x + 12, GREENWICH_TILE.y))

	# Still an overlay: the tile's biome is ordinary land.
	assert_true(BiomeClassifier.KNOWN_BIOMES.has(generator.biome_at_global(GREENWICH_TILE.x, GREENWICH_TILE.y)))


func test_a_curated_river_is_authoritative_over_the_hydrology_fallback():
	generator.set_hydrology(_synthetic_field())
	generator.hydrology_rivers_enabled = true
	var geo := GeoCoordinates.new()
	var dreisam := geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_true(generator.is_river_at_global(dreisam.x, dreisam.y))
	var nearest := generator.nearest_river_at(dreisam.x, dreisam.y)
	assert_eq(nearest.name, "Dreisam")
	assert_almost_eq(nearest.half_width_tiles, RiverCatalog.RIVER_HALF_WIDTH_TILES, 1e-9, "curated rivers keep the catalog's width")
	assert_eq(generator.river_hydraulics_at_global(dreisam.x, dreisam.y).river_name, "Dreisam")


func test_the_valley_carves_a_channel_tile_below_its_macro_elevation():
	# The carve does not wait on the river flag: a valley is terrain.
	generator.set_hydrology(_synthetic_field())
	var probe := generator.hydrology_at_global(GREENWICH_TILE.x, GREENWICH_TILE.y)
	assert_gt(probe["carve"], 0.0)
	assert_eq(probe["fine_detail_scale"], 0.0)
	var macro := generator.macro_elevation_at_global(GREENWICH_TILE.x, GREENWICH_TILE.y)
	assert_almost_eq(
		generator.elevation_at_global(GREENWICH_TILE.x, GREENWICH_TILE.y), macro - probe["carve"], 1e-6
	)


func test_generate_chunk_with_a_bake_still_matches_the_per_tile_queries():
	generator.set_hydrology(_synthetic_field())
	generator.hydrology_rivers_enabled = true
	var chunk_size := 8
	var chunk_coord := Vector2i(
		floori(float(GREENWICH_TILE.x) / chunk_size), floori(float(GREENWICH_TILE.y) / chunk_size)
	)
	var chunk := generator.generate_chunk(chunk_coord, chunk_size)
	var found_a_river_cell := false
	for y in chunk_size:
		for x in chunk_size:
			var global_x := chunk_coord.x * chunk_size + x
			var global_y := chunk_coord.y * chunk_size + y
			var index := y * chunk_size + x
			assert_eq(chunk.elevation[index], generator.elevation_at_global(global_x, global_y))
			assert_eq(chunk.biome[index], generator.biome_at_global(global_x, global_y))
			assert_eq(chunk.is_river[index], 1 if generator.is_river_at_global(global_x, global_y) else 0)
			assert_eq(chunk.is_lake[index], 1 if generator.is_lake_at_global(global_x, global_y) else 0)
			if chunk.is_river[index] == 1:
				found_a_river_cell = true
	assert_true(found_a_river_cell, "the chunk around Greenwich holds the synthetic outlet")
