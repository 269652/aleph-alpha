extends GutTest

## Lithology: which rock the bedrock actually is, at province scale (see
## docs/concept/underground.md "Lithology: caves need the right rock").
##
## The load-bearing property is the CARBONATE SHARE: carbonate rocks crop
## out over 15.2% of the global ice-free continental surface (Goldscheider
## et al., 2020, World Karst Aquifer Map, Hydrogeology Journal), and that
## is what decides how much of this planet can have a solutional cave
## system under it at all. Pinned here rather than left as a comment.

const Lithology = preload("res://src/world/lithology.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

var lithology: Lithology


func before_each():
	lithology = Lithology.new()


# -- rock_at: a real, deterministic, province-scale classification ----------

func test_every_classified_rock_is_a_known_type():
	for i in 200:
		var rock: String = lithology.rock_at(i * 37, i * 91, float(i % 10) / 9.0)
		assert_true(
			Lithology.ROCK_TYPES.has(rock), "'%s' is not a known rock type" % rock
		)


func test_classification_is_deterministic():
	for i in 50:
		var first: String = lithology.rock_at(i * 13, i * 29, 0.4)
		var second: String = lithology.rock_at(i * 13, i * 29, 0.4)
		assert_eq(first, second, "same tile and relief must give the same rock")


func test_a_province_is_one_uniform_rock():
	# Real lithological provinces are regional, so a cave system is not
	# chopped up by per-tile noise. Two tiles inside the same province cell
	# must agree.
	var base := Vector2i(Lithology.PROVINCE_TILES * 7, Lithology.PROVINCE_TILES * 3)
	var expected: String = lithology.rock_at(base.x, base.y, 0.3)
	for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(Lithology.PROVINCE_TILES - 1, 1)]:
		assert_eq(
			lithology.rock_at(base.x + offset.x, base.y + offset.y, 0.3),
			expected,
			"tile %s left its own province" % offset
		)


func test_a_province_is_tens_of_kilometres_across():
	# ~1km/tile (EarthChunkGenerator.TILES_PER_DEGREE = 111 over 111km/deg).
	var km: float = Lithology.PROVINCE_TILES * Lithology.KM_PER_TILE
	assert_between(km, 10.0, 100.0, "a lithological province should be tens of km across")


func test_neighbouring_provinces_are_not_all_the_same_rock():
	var seen := {}
	for i in 60:
		seen[lithology.rock_at(i * Lithology.PROVINCE_TILES, 0, 0.5)] = true
	assert_gt(seen.size(), 2, "the whole planet came out as one or two rock types")


# -- the measured global carbonate share ------------------------------------

func test_carbonate_outcrop_matches_the_measured_global_share():
	var carbonate := 0
	var total := 0
	for i in 400:
		for relief_step in 5:
			var rock: String = lithology.rock_at(
				i * Lithology.PROVINCE_TILES, relief_step * Lithology.PROVINCE_TILES, float(relief_step) / 4.0
			)
			if Lithology.CARBONATES.has(rock):
				carbonate += 1
			total += 1
	var share := float(carbonate) / float(total)
	assert_almost_eq(
		share, Lithology.GLOBAL_CARBONATE_SHARE, 0.03,
		"carbonate outcrop share is %.1f%%, not the measured %.1f%%" % [
			share * 100.0, Lithology.GLOBAL_CARBONATE_SHARE * 100.0
		]
	)


func test_the_carbonate_share_does_not_depend_on_relief():
	# Alpine karst is real and widespread -- carbonate outcrop is not a
	# lowland-only phenomenon, so relief must redistribute the OTHER rocks
	# without eating into the carbonate share.
	var shares: Array[float] = []
	for relief_step in 4:
		var relief := float(relief_step) / 3.0
		var carbonate := 0
		for i in 400:
			if Lithology.CARBONATES.has(lithology.rock_at(i * Lithology.PROVINCE_TILES, 0, relief)):
				carbonate += 1
		shares.append(float(carbonate) / 400.0)
	for share in shares:
		assert_almost_eq(
			share, Lithology.GLOBAL_CARBONATE_SHARE, 0.05,
			"carbonate share drifted to %.1f%% at some relief" % [share * 100.0]
		)


func test_high_relief_exposes_more_crystalline_basement():
	# Real orogenic belts expose granite/gneiss basement; low-relief
	# cratonic platforms are buried under clastic sedimentary cover.
	var lowland := 0
	var orogen := 0
	for i in 500:
		if Lithology.CRYSTALLINE.has(lithology.rock_at(i * Lithology.PROVINCE_TILES, 0, 0.0)):
			lowland += 1
		if Lithology.CRYSTALLINE.has(lithology.rock_at(i * Lithology.PROVINCE_TILES, 0, 1.0)):
			orogen += 1
	assert_gt(orogen, lowland, "high relief must expose more crystalline basement than lowland")


# -- solubility: real dissolution rates, not tiers --------------------------

func test_solubility_orders_by_real_dissolution_rate():
	# Gypsum's equilibrium solubility (~2.4 g/L) is about an order of
	# magnitude above CO2-charged limestone (~0.25 g/L); dolomite dissolves
	# about an order of magnitude more slowly than calcite.
	var gypsum: float = lithology.solubility_of(Lithology.ROCK_GYPSUM)
	var limestone: float = lithology.solubility_of(Lithology.ROCK_LIMESTONE)
	var dolomite: float = lithology.solubility_of(Lithology.ROCK_DOLOMITE)
	assert_gt(gypsum, limestone)
	assert_gt(limestone, dolomite)
	assert_gt(dolomite, 0.0, "dolomite karst is real -- it is slower, not absent")


func test_limestone_is_the_solubility_reference():
	assert_eq(lithology.solubility_of(Lithology.ROCK_LIMESTONE), 1.0)


func test_insoluble_rock_is_exactly_zero_not_merely_small():
	for rock in [
		Lithology.ROCK_SANDSTONE, Lithology.ROCK_SHALE,
		Lithology.ROCK_GRANITE, Lithology.ROCK_GNEISS, Lithology.ROCK_BASALT,
	]:
		assert_eq(
			lithology.solubility_of(rock), 0.0,
			"%s must be exactly insoluble -- no solutional cave forms in it" % rock
		)


func test_unknown_rock_has_no_solubility():
	assert_eq(lithology.solubility_of("not_a_real_rock"), 0.0)


func test_the_soluble_rocks_are_exactly_the_carbonates_and_evaporites():
	for rock in Lithology.ROCK_TYPES:
		var soluble: bool = lithology.solubility_of(rock) > 0.0
		var expected: bool = Lithology.CARBONATES.has(rock) or Lithology.EVAPORITES.has(rock)
		assert_eq(soluble, expected, "%s disagrees about being soluble" % rock)


func test_km_per_tile_agrees_with_the_world_generator_scale():
	# Lithology deliberately does NOT preload EarthChunkGenerator (that
	# would couple a tiny pure classifier to the whole world-gen pipeline,
	# and invite a cycle once the cave stack calls back into it), so the
	# agreement is pinned here instead of asserted by construction.
	var generator_km_per_tile: float = Lithology.KM_PER_DEGREE / EarthChunkGenerator.TILES_PER_DEGREE
	assert_almost_eq(
		Lithology.KM_PER_TILE, generator_km_per_tile, 0.0001,
		"Lithology's world scale drifted from EarthChunkGenerator.TILES_PER_DEGREE"
	)
