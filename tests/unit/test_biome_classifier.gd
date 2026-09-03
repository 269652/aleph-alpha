extends GutTest

const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")

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


# -- slope: a locally steep face forces mountain, real alpine tree-lines ----


func test_steep_slope_forces_mountain_outside_the_elevation_band():
	# 0.5/0.5/0.7 is ordinary forest land at the default thresholds (see
	# test_temperate_wet_land_is_forest above) -- well under the
	# elevation-based mountain band. A locally steep slope must still force
	# "mountain": the real alpine tree-line effect (bare rock/scree no
	# vegetation-based biome can hold), independent of elevation entirely.
	var steep_slope := TerrainPassability.HARD_THRESHOLD_DEG + 5.0
	assert_eq(
		classifier.classify(
			0.5, 0.5, 0.7, BiomeClassifier.SEA_LEVEL, BiomeClassifier.MOUNTAIN_LEVEL, steep_slope
		),
		"mountain"
	)


func test_slope_at_exactly_the_threshold_forces_mountain():
	# HARD_THRESHOLD_DEG's own doc comment says "at and beyond this" -- the
	# override must be inclusive of the threshold itself, not strictly past it.
	assert_eq(
		classifier.classify(
			0.5, 0.5, 0.7,
			BiomeClassifier.SEA_LEVEL, BiomeClassifier.MOUNTAIN_LEVEL,
			TerrainPassability.HARD_THRESHOLD_DEG
		),
		"mountain"
	)


func test_gentle_slope_does_not_force_mountain():
	var gentle_slope := TerrainPassability.HARD_THRESHOLD_DEG - 5.0
	assert_eq(
		classifier.classify(
			0.5, 0.5, 0.7, BiomeClassifier.SEA_LEVEL, BiomeClassifier.MOUNTAIN_LEVEL, gentle_slope
		),
		"forest"
	)


func test_omitting_slope_deg_leaves_existing_behavior_completely_unchanged():
	# No 6th argument at all -- every pre-existing call site/test must keep
	# behaving exactly as before this parameter existed.
	assert_eq(classifier.classify(0.5, 0.5, 0.7), "forest")
	assert_eq(classifier.classify(0.95, 0.9, 0.9), "mountain")
	assert_eq(classifier.classify(0.1, 0.5, 0.5), "ocean")


func test_ocean_stays_ocean_regardless_of_a_steep_slope():
	var steep_slope := TerrainPassability.HARD_THRESHOLD_DEG + 20.0
	assert_eq(
		classifier.classify(
			0.1, 0.5, 0.5, BiomeClassifier.SEA_LEVEL, BiomeClassifier.MOUNTAIN_LEVEL, steep_slope
		),
		"ocean"
	)


func test_slope_mountain_threshold_is_terrain_passabilitys_hard_threshold():
	# Tuned-value pin (CLAUDE.md: thresholds must be test-pinned constants,
	# never eyeballed) -- must be sourced from TerrainPassability's own real,
	# already-grounded scrambling/technical-climbing line, never a re-typed
	# literal that could silently drift out of sync with it.
	assert_eq(BiomeClassifier.SLOPE_MOUNTAIN_THRESHOLD_DEG, TerrainPassability.HARD_THRESHOLD_DEG)
