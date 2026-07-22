extends GutTest

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")

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


func test_chunk_moisture_and_temperature_are_normalized():
	var chunk := generator.generate_chunk(Vector2i(100, 50), 8)
	for value in chunk.moisture:
		assert_between(value, 0.0, 1.0)
	for value in chunk.temperature:
		assert_between(value, 0.0, 1.0)
