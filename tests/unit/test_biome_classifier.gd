extends GutTest

const BiomeClassifier = preload("res://src/world/biome_classifier.gd")

var classifier: BiomeClassifier


func before_each():
	classifier = BiomeClassifier.new()


func test_low_elevation_is_ocean():
	assert_eq(classifier.classify(0.1, 0.5, 0.5), "ocean")


func test_very_high_elevation_is_mountain_regardless_of_climate():
	assert_eq(classifier.classify(0.95, 0.9, 0.9), "mountain")


func test_hot_dry_land_is_desert():
	assert_eq(classifier.classify(0.5, 0.9, 0.1), "desert")


func test_hot_wet_land_is_rainforest():
	assert_eq(classifier.classify(0.5, 0.9, 0.9), "rainforest")


func test_temperate_wet_land_is_forest():
	assert_eq(classifier.classify(0.5, 0.5, 0.7), "forest")


func test_temperate_dry_land_is_grassland():
	assert_eq(classifier.classify(0.5, 0.5, 0.4), "grassland")


func test_cold_land_is_tundra_regardless_of_moisture():
	assert_eq(classifier.classify(0.5, 0.1, 0.4), "tundra")


func test_depth_is_zero_at_sea_level():
	assert_eq(classifier.depth_at(BiomeClassifier.SEA_LEVEL), 0.0)


func test_depth_is_zero_above_sea_level():
	assert_eq(classifier.depth_at(BiomeClassifier.SEA_LEVEL + 0.1), 0.0)


func test_depth_is_deepest_at_the_ocean_floor():
	assert_almost_eq(classifier.depth_at(0.0), 1.0, 0.001)


func test_depth_is_half_partway_between_sea_level_and_the_floor():
	assert_almost_eq(classifier.depth_at(BiomeClassifier.SEA_LEVEL / 2.0), 0.5, 0.001)


func test_classify_uses_a_custom_sea_level_when_provided():
	# 0.4 is land at the default sea level (0.3) but ocean at a custom, higher one.
	assert_ne(classifier.classify(0.4, 0.5, 0.5), "ocean")
	assert_eq(classifier.classify(0.4, 0.5, 0.5, 0.5), "ocean")


func test_classify_uses_a_custom_mountain_level_when_provided():
	# 0.7 is land at the default mountain level (0.85) but mountain at a lower one.
	assert_ne(classifier.classify(0.7, 0.5, 0.5), "mountain")
	assert_eq(classifier.classify(0.7, 0.5, 0.5, BiomeClassifier.SEA_LEVEL, 0.6), "mountain")


func test_depth_at_uses_a_custom_sea_level_when_provided():
	assert_eq(classifier.depth_at(0.4), 0.0)
	assert_gt(classifier.depth_at(0.4, 0.5), 0.0)


func test_depth_meters_is_zero_at_or_above_sea_level():
	assert_eq(classifier.depth_meters_at(0.6, 0.5556, 8000.0), 0.0)


func test_depth_meters_is_the_full_range_at_the_ocean_floor():
	assert_almost_eq(classifier.depth_meters_at(0.0, 0.5556, 8000.0), 8000.0, 0.01)


func test_depth_meters_is_half_the_range_halfway_down():
	assert_almost_eq(classifier.depth_meters_at(0.2778, 0.5556, 8000.0), 4000.0, 1.0)


func test_depth_meters_gives_a_small_realistic_value_for_shallow_coastal_water():
	# 0.0001 below sea level should be a shallow, wadeable few meters -- not a
	# large fraction of the full ocean-depth range. This is exactly the
	# calibration this method exists to get right for real bathymetry.
	var depth := classifier.depth_meters_at(0.5556 - 0.0001, 0.5556, 8000.0)
	assert_between(depth, 0.5, 3.0)


# -- dominant_biome -----------------------------------------------------------


func test_dominant_biome_of_an_empty_array_is_empty_string():
	assert_eq(classifier.dominant_biome(PackedStringArray()), "")


func test_dominant_biome_of_a_single_biome_chunk_is_that_biome():
	var biome_array := PackedStringArray(["tundra", "tundra", "tundra"])
	assert_eq(classifier.dominant_biome(biome_array), "tundra")


func test_dominant_biome_returns_the_most_frequent_biome():
	var biome_array := PackedStringArray(["forest", "forest", "grassland"])
	assert_eq(classifier.dominant_biome(biome_array), "forest")


func test_dominant_biome_breaks_ties_by_known_biomes_order():
	# "forest" precedes "desert" in KNOWN_BIOMES, so an equal-count tie
	# between them resolves to "forest" -- same tie-break style as
	# TerrainRenderer._is_more_dominant.
	var biome_array := PackedStringArray(["desert", "forest"])
	assert_eq(classifier.dominant_biome(biome_array), "forest")
