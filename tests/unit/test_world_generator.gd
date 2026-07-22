extends GutTest

const WorldGenerator = preload("res://src/world/world_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")

var generator: WorldGenerator


func before_each():
	generator = WorldGenerator.new()


func test_generate_world_returns_a_chunk_sized_to_the_requested_dimensions():
	var chunk = generator.generate_world(6, 4, 1, 10)
	assert_eq(chunk.width, 6)
	assert_eq(chunk.height, 4)
	assert_eq(chunk.elevation.size(), 24)
	assert_eq(chunk.biome.size(), 24)


func test_generate_world_produces_only_known_biome_names():
	var chunk = generator.generate_world(8, 8, 3, 20)
	for biome_name in chunk.biome:
		assert_true(
			BiomeClassifier.KNOWN_BIOMES.has(biome_name), "unexpected biome: %s" % biome_name
		)


func test_generate_world_is_deterministic_for_the_same_seed():
	var first = generator.generate_world(8, 8, 42, 20)
	var second = generator.generate_world(8, 8, 42, 20)
	assert_eq(first.elevation, second.elevation)
	assert_eq(first.biome, second.biome)


func test_generate_world_differs_for_a_different_seed():
	var first = generator.generate_world(8, 8, 1, 20)
	var second = generator.generate_world(8, 8, 2, 20)
	assert_ne(first.elevation, second.elevation)


func test_generate_world_starts_with_no_player_modifications():
	var chunk = generator.generate_world(4, 4, 1, 5)
	assert_eq(chunk.modifications, {})


func test_latitude_is_zero_at_the_vertical_center():
	assert_almost_eq(generator.latitude_at(4, 9), 0.0, 0.001)


func test_latitude_is_one_at_the_top_edge():
	assert_almost_eq(generator.latitude_at(0, 9), 1.0, 0.001)


func test_latitude_is_one_at_the_bottom_edge_too():
	assert_almost_eq(generator.latitude_at(8, 9), 1.0, 0.001)


func test_latitude_is_symmetric_around_the_center():
	assert_almost_eq(generator.latitude_at(2, 9), generator.latitude_at(6, 9), 0.001)


func test_recommended_erosion_iterations_scales_with_map_area():
	assert_eq(generator.recommended_erosion_iterations(80, 30), 300)
	assert_eq(generator.recommended_erosion_iterations(40, 40), 200)


func test_generate_world_with_recommended_erosion_stays_spatially_coherent():
	# Regression guard: erosion_iterations exceeding cell count carves scattered
	# single-cell pits instead of coherent rivers/lakes (discovered by hand via
	# the ASCII preview tool). This measures the same average-adjacent-cell-diff
	# smoothness used for the base heightmap, but after erosion is applied,
	# where some added roughness from carved river edges is expected. The
	# threshold (0.08) sits between the measured value at the recommended
	# ratio (~0.071) and at double that ratio (~0.082), so doubling the
	# recommended iterations by mistake would fail this test.
	var width := 40
	var height := 40
	var chunk = generator.generate_world(
		width, height, 1, generator.recommended_erosion_iterations(width, height)
	)

	var total_diff := 0.0
	var count := 0
	for y in height:
		for x in width - 1:
			total_diff += absf(chunk.elevation[y * width + x] - chunk.elevation[y * width + x + 1])
			count += 1

	var average_diff := total_diff / count
	assert_lt(average_diff, 0.08)
