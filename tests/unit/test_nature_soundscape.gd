extends GutTest

## NatureSoundscape (docs/concept/soundscape.md): pure layer-mixing logic for
## the ambient nature soundscape. Every input is a plain, already-computed
## primitive (biome/season/weather Strings, is_night/is_snowing bools) --
## same shape as KrakenTrigger/EasterEggSightings' own tests, no node/scene/
## chunk manager involved.

const NatureSoundscape = preload("res://src/audio/nature_soundscape.gd")

var soundscape: NatureSoundscape


func before_each():
	soundscape = NatureSoundscape.new()


# -- LAYERS: every asset this system can play, and where from ---------------

func test_layers_has_all_eleven_registered_files():
	var expected_keys := [
		"ocean", "forest_day", "forest_winter", "grassland_day", "rainforest_day",
		"rainforest_night", "temperate_night", "wind", "rain", "storm", "mountain_hawk_call",
	]
	for key in expected_keys:
		assert_true(NatureSoundscape.LAYERS.has(key), key)
	assert_eq(NatureSoundscape.LAYERS.size(), expected_keys.size())


func test_every_layer_path_points_into_the_real_soundscape_assets_directory():
	for layer_name in NatureSoundscape.LAYERS:
		var path: String = NatureSoundscape.LAYERS[layer_name]
		assert_true(
			path.begins_with("res://assets/audio/soundscape/"), "%s -> %s" % [layer_name, path]
		)


# -- layer_mix: ocean -- unchanged by season or time of day ------------------

func test_ocean_bed_plays_by_day():
	var mix := soundscape.layer_mix("ocean", "summer", "clear", false, false)
	assert_true(mix.has("ocean"))
	assert_gt(mix["ocean"], 0.0)


func test_ocean_bed_is_unchanged_at_night():
	var day_mix := soundscape.layer_mix("ocean", "summer", "clear", false, false)
	var night_mix := soundscape.layer_mix("ocean", "summer", "clear", true, false)
	assert_eq(day_mix["ocean"], night_mix["ocean"])


func test_ocean_bed_is_unchanged_across_seasons():
	var summer := soundscape.layer_mix("ocean", "summer", "clear", false, false)
	var winter := soundscape.layer_mix("ocean", "winter", "clear", false, false)
	assert_eq(summer["ocean"], winter["ocean"])


# -- layer_mix: forest -- day/night swap, real winter swap -------------------

func test_forest_plays_forest_day_bed_in_spring_summer_autumn():
	for season in ["spring", "summer", "autumn"]:
		var mix := soundscape.layer_mix("forest", season, "clear", false, false)
		assert_true(mix.has("forest_day"), season)
		assert_false(mix.has("forest_winter"), season)


func test_forest_swaps_to_forest_winter_bed_in_winter():
	var mix := soundscape.layer_mix("forest", "winter", "clear", false, false)
	assert_true(mix.has("forest_winter"))
	assert_false(mix.has("forest_day"))


func test_forest_swaps_to_temperate_night_bed_after_dark():
	var mix := soundscape.layer_mix("forest", "summer", "clear", true, false)
	assert_true(mix.has("temperate_night"))
	assert_false(mix.has("forest_day"))


# -- layer_mix: grassland -- day/night swap, winter VOLUME cut not a swap ----

func test_grassland_plays_grassland_day_bed_at_full_volume_outside_winter():
	var mix := soundscape.layer_mix("grassland", "summer", "clear", false, false)
	assert_almost_eq(mix["grassland_day"], 1.0, 0.001)


func test_grassland_cuts_its_bed_volume_in_winter_rather_than_swapping_files():
	var mix := soundscape.layer_mix("grassland", "winter", "clear", false, false)
	assert_true(mix.has("grassland_day"))
	assert_eq(mix["grassland_day"], NatureSoundscape.GRASSLAND_WINTER_VOLUME)
	assert_lt(NatureSoundscape.GRASSLAND_WINTER_VOLUME, 1.0)


func test_grassland_swaps_to_temperate_night_bed_after_dark():
	var mix := soundscape.layer_mix("grassland", "summer", "clear", true, false)
	assert_true(mix.has("temperate_night"))
	assert_false(mix.has("grassland_day"))


# -- layer_mix: rainforest -- day/night swap, NO winter swap (aseasonal) -----

func test_rainforest_plays_rainforest_day_bed_regardless_of_season():
	for season in ["spring", "summer", "autumn", "winter"]:
		var mix := soundscape.layer_mix("rainforest", season, "clear", false, false)
		assert_true(mix.has("rainforest_day"), season)


func test_rainforest_swaps_to_rainforest_night_bed_after_dark():
	var mix := soundscape.layer_mix("rainforest", "summer", "clear", true, false)
	assert_true(mix.has("rainforest_night"))
	assert_false(mix.has("rainforest_day"))


# -- layer_mix: desert/tundra/mountain -- share one wind bed, own volume ----

func test_desert_tundra_and_mountain_all_play_the_shared_wind_bed():
	for biome in ["desert", "tundra", "mountain"]:
		var mix := soundscape.layer_mix(biome, "summer", "clear", false, false)
		assert_true(mix.has("wind"), biome)


func test_desert_tundra_and_mountain_wind_volumes_are_distinct_and_pinned():
	var desert := soundscape.layer_mix("desert", "summer", "clear", false, false)
	var tundra := soundscape.layer_mix("tundra", "summer", "clear", false, false)
	var mountain := soundscape.layer_mix("mountain", "summer", "clear", false, false)
	assert_eq(desert["wind"], NatureSoundscape.DESERT_WIND_VOLUME)
	assert_eq(tundra["wind"], NatureSoundscape.TUNDRA_WIND_VOLUME)
	assert_eq(mountain["wind"], NatureSoundscape.MOUNTAIN_WIND_VOLUME)
	assert_ne(NatureSoundscape.DESERT_WIND_VOLUME, NatureSoundscape.TUNDRA_WIND_VOLUME)


func test_desert_tundra_and_mountain_wind_bed_is_unchanged_at_night_and_by_season():
	var day := soundscape.layer_mix("tundra", "summer", "clear", false, false)
	var night := soundscape.layer_mix("tundra", "summer", "clear", true, false)
	var winter := soundscape.layer_mix("tundra", "winter", "clear", false, false)
	assert_eq(day["wind"], night["wind"])
	assert_eq(day["wind"], winter["wind"])
