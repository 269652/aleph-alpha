extends GutTest

const HeightmapGenerator = preload("res://src/world/heightmap_generator.gd")

var generator: HeightmapGenerator


func before_each():
	generator = HeightmapGenerator.new()


func test_generate_returns_one_value_per_cell():
	var heights := generator.generate(8, 5, 1)
	assert_eq(heights.size(), 8 * 5)


func test_generate_values_are_normalized_between_zero_and_one():
	var heights := generator.generate(16, 16, 1)
	for h in heights:
		assert_between(h, 0.0, 1.0)


func test_generate_is_deterministic_for_the_same_seed():
	var first := generator.generate(16, 16, 42)
	var second := generator.generate(16, 16, 42)
	assert_eq(first, second)


func test_generate_differs_for_a_different_seed():
	var first := generator.generate(16, 16, 1)
	var second := generator.generate(16, 16, 2)
	assert_ne(first, second)


func test_generate_is_spatially_smooth_enough_for_continent_scale_features():
	# Guards against speckled, per-cell-random terrain: neighboring cells
	# should mostly agree, so land/water forms large regions, not noise.
	var width := 60
	var height := 60
	var heights := generator.generate(width, height, 1)

	var total_diff := 0.0
	var count := 0
	for y in height:
		for x in width - 1:
			total_diff += absf(heights[y * width + x] - heights[y * width + x + 1])
			count += 1

	var average_diff := total_diff / count
	assert_lt(average_diff, 0.05)
