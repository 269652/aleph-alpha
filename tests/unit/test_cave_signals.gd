extends GutTest

## CaveSignals: turns what this world actually measures -- real slope,
## biome, ocean distance -- into the inputs CaveSiting needs (see
## docs/concept/underground.md). Pure translation, kept out of
## EarthChunkManager so it can be tested against known readings rather
## than against generated terrain.

const CaveSignals = preload("res://src/world/cave_signals.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const Lithology = preload("res://src/world/lithology.gd")

var signals_model: CaveSignals


func before_each():
	signals_model = CaveSignals.new()


# -- relief from real slope ------------------------------------------------

func test_flat_ground_is_zero_relief():
	assert_almost_eq(signals_model.relief_from_slope_degrees(0.0), 0.0, 0.001)


func test_a_mountain_slope_is_full_relief():
	assert_almost_eq(
		signals_model.relief_from_slope_degrees(CaveSignals.OROGEN_SLOPE_DEG), 1.0, 0.001
	)


func test_relief_stays_in_range_and_never_falls_with_slope():
	var previous := -1.0
	for degrees in range(0, 90):
		var relief: float = signals_model.relief_from_slope_degrees(float(degrees))
		assert_between(relief, 0.0, 1.0, "relief out of [0,1] at %d degrees" % degrees)
		assert_gte(relief, previous)
		previous = relief


func test_the_orogen_threshold_reuses_the_worlds_own_mountain_slope():
	# Not a second, independently-invented steepness constant -- the same
	# threshold BiomeClassifier already calls a mountain.
	assert_almost_eq(
		CaveSignals.OROGEN_SLOPE_DEG, BiomeClassifier.SLOPE_MOUNTAIN_THRESHOLD_DEG, 0.001
	)


# -- seasonality from biome ------------------------------------------------

func test_every_biome_has_a_real_seasonality():
	for biome in BiomeClassifier.KNOWN_BIOMES:
		var value: float = signals_model.seasonality_for_biome(biome)
		assert_between(value, 0.0, 1.0, "seasonality out of [0,1] for %s" % biome)


func test_grassland_is_the_strongly_seasonal_climate():
	# Savanna and steppe are the classic strong wet/dry contrast, which is
	# what turns ordinary sinkhole recharge into floodwater injection.
	assert_gt(
		signals_model.seasonality_for_biome("grassland"),
		CaveSignals.FLOODWATER_SEASONALITY_REFERENCE
	)


func test_tropical_rainforest_is_the_steadiest():
	var rainforest: float = signals_model.seasonality_for_biome("rainforest")
	for biome in BiomeClassifier.KNOWN_BIOMES:
		if biome == "ocean":
			continue
		assert_lte(rainforest, signals_model.seasonality_for_biome(biome))


func test_an_unknown_biome_is_steady_rather_than_extreme():
	assert_lt(
		signals_model.seasonality_for_biome("not_a_biome"),
		CaveSignals.FLOODWATER_SEASONALITY_REFERENCE
	)


# -- hypogenic provinces ---------------------------------------------------

func test_hypogenic_settings_are_a_real_minority():
	var hypogenic := 0
	var total := 700
	for i in total:
		if signals_model.hydrothermal_proximity_at(i * Lithology.PROVINCE_TILES, 0) > 0.5:
			hypogenic += 1
	var share := float(hypogenic) / float(total)
	assert_almost_eq(share, CaveSignals.HYPOGENIC_PROVINCE_SHARE, 0.05)
	assert_lt(share, 0.25, "hypogenic caves must stay the exception, not the rule")


func test_hydrothermal_proximity_is_deterministic_and_province_scale():
	var base := Vector2i(Lithology.PROVINCE_TILES * 9, Lithology.PROVINCE_TILES * 2)
	var expected: float = signals_model.hydrothermal_proximity_at(base.x, base.y)
	assert_eq(signals_model.hydrothermal_proximity_at(base.x, base.y), expected)
	assert_eq(signals_model.hydrothermal_proximity_at(base.x + 1, base.y + 1), expected)


func test_hydrothermal_proximity_is_a_fraction():
	for i in 200:
		assert_between(signals_model.hydrothermal_proximity_at(i * 97, i * 31), 0.0, 1.0)


# -- coast distance uses the MAP scale, not the play scale -----------------

func test_coast_distance_converts_on_the_map_scale():
	# Biomes and oceans are map-scale facts (~1km/tile), NOT the play-scale
	# ~1.426m/tile the cave passages themselves are built at. Mixing the
	# two would put the whole mixing zone inside a single tile.
	assert_almost_eq(
		signals_model.coast_distance_km(10.0), 10.0 * Lithology.KM_PER_TILE, 0.001
	)


func test_an_unfound_coast_is_far_away_not_zero():
	# A scan that found no ocean must read as inland, or every inland cave
	# would come out as a coastal mixing-zone sponge.
	assert_gt(signals_model.coast_distance_km(INF), 1000.0)
