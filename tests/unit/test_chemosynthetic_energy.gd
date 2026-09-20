extends GutTest

## ChemosyntheticEnergy: the underground's energy budget, and the
## difficulty curve that falls out of it (see
## docs/concept/underground.md "Chemosynthesis: the second biosphere").
##
## The whole point is that depth is NOT a stat multiplier. The underground
## food web runs on chemical energy instead of sunlight, that energy is
## scarce and steeply zoned around wherever reduced fluids rise, and three
## real consequences follow: few individuals, very old ones, and -- only
## where endosymbiosis is involved -- genuinely enormous ones.

const ChemosyntheticEnergy = preload("res://src/world/chemosynthetic_energy.gd")

var energy: ChemosyntheticEnergy


func before_each():
	energy = ChemosyntheticEnergy.new()


# -- the energy field: starved rock, punctuated by rich seeps --------------

func test_a_seep_is_as_productive_as_a_good_surface_ecosystem():
	# Vent and seep communities reach biomass densities comparable to the
	# most productive ecosystems on Earth -- locally, right at the fluid.
	assert_almost_eq(
		energy.ambient_energy_at(0.0),
		ChemosyntheticEnergy.SEEP_PEAK_NPP_G_C_PER_M2_YR,
		0.001
	)


func test_rock_away_from_any_seep_is_genuinely_starved():
	var far: float = energy.ambient_energy_at(10000.0)
	assert_almost_eq(far, ChemosyntheticEnergy.BACKGROUND_NPP_G_C_PER_M2_YR, 0.01)
	assert_lt(
		far, ChemosyntheticEnergy.SURFACE_NPP_G_C_PER_M2_YR * 0.01,
		"the deep subsurface must be starved, not merely dimmer than the surface"
	)


func test_energy_falls_away_from_the_seep_and_never_rises():
	var previous := INF
	for metres in range(0, 400, 2):
		var value: float = energy.ambient_energy_at(float(metres))
		assert_lte(value, previous, "energy rose with distance from the seep at %dm" % metres)
		assert_gt(value, 0.0, "energy must never reach zero -- radiolytic hydrogen is everywhere")
		previous = value


func test_the_seep_zone_is_metres_wide_not_kilometres():
	# Real vent and seep communities are tightly zoned around the fluid,
	# on a scale of metres to tens of metres.
	assert_between(ChemosyntheticEnergy.SEEP_EFOLD_M, 1.0, 50.0)


func test_a_negative_distance_clamps_to_the_seep():
	assert_almost_eq(energy.ambient_energy_at(-5.0), energy.ambient_energy_at(0.0), 0.001)


# -- few: population density follows energy -------------------------------

func test_the_underground_is_sparsely_populated_away_from_seeps():
	var starved: float = energy.population_density_factor(
		ChemosyntheticEnergy.BACKGROUND_NPP_G_C_PER_M2_YR
	)
	assert_lt(starved, 0.05, "starved rock must be nearly empty, not merely quieter")
	assert_gt(starved, 0.0)


func test_population_density_rises_with_energy():
	var starved: float = energy.population_density_factor(
		ChemosyntheticEnergy.BACKGROUND_NPP_G_C_PER_M2_YR
	)
	var at_seep: float = energy.population_density_factor(
		ChemosyntheticEnergy.SEEP_PEAK_NPP_G_C_PER_M2_YR
	)
	assert_gt(at_seep, starved * 10.0, "a seep must be a real concentration of life")


# -- old: scarcity buys longevity -----------------------------------------

func test_starved_rock_produces_century_old_animals():
	# The olm, Proteus anguinus, is the anchor: Europe's blind cave
	# salamander has an estimated maximum lifespan past 100 years and an
	# average adult lifespan around 68 years (Voituron et al., 2011,
	# Biology Letters).
	var lifespan: float = energy.longevity_years(
		ChemosyntheticEnergy.BACKGROUND_NPP_G_C_PER_M2_YR
	)
	assert_almost_eq(lifespan, ChemosyntheticEnergy.OLM_MAX_LIFESPAN_YEARS, 5.0)


func test_longevity_falls_as_energy_rises():
	# Cave fauna are textbook K-strategists: low metabolic rate, slow
	# growth, delayed maturity, long life. Energy is what buys speed, and
	# speed is what costs longevity.
	var previous := 0.0
	for step in range(1, 40):
		var value: float = energy.longevity_years(float(step) * 12.0)
		if previous > 0.0:
			assert_lt(value, previous, "longevity rose with energy at step %d" % step)
		previous = value


func test_longevity_stays_a_real_lifespan():
	for npp in [0.01, 1.0, 100.0, 5000.0]:
		var value: float = energy.longevity_years(npp)
		assert_gt(value, 0.0)
		assert_lte(value, ChemosyntheticEnergy.OLM_MAX_LIFESPAN_YEARS)


func test_the_deepest_starved_rock_holds_the_oldest_individuals():
	# This is the link to worldbosses.md: age and accumulated traits are
	# exactly what its promotion threshold reads, so the emptiest places
	# underground are the ones most likely to produce a boss -- through
	# the existing mechanic, with no cave-specific boss code.
	var deep: float = energy.longevity_years(energy.ambient_energy_at(1000.0))
	var at_seep: float = energy.longevity_years(energy.ambient_energy_at(0.0))
	assert_gt(deep, at_seep * 5.0)


# -- enormous: endosymbiosis breaks the ambient ceiling -------------------

func test_body_size_is_capped_by_ambient_energy():
	var starved: float = energy.attainable_body_mass_factor(
		ChemosyntheticEnergy.BACKGROUND_NPP_G_C_PER_M2_YR
	)
	var at_seep: float = energy.attainable_body_mass_factor(
		ChemosyntheticEnergy.SEEP_PEAK_NPP_G_C_PER_M2_YR
	)
	assert_lt(starved, at_seep)
	assert_lt(starved, 0.2, "starved rock cannot grow anything large")


func test_a_symbiont_bearer_ignores_the_ambient_ceiling_entirely():
	# Riftia has no gut at all; Bathymodiolus and Kiwa farm their own
	# chemoautotrophs too. An animal carrying its own producers is not
	# limited by what the surrounding rock supplies -- which is the only
	# reason anything large can exist somewhere this energy-poor, and is
	# what an apex is down here.
	var starved := ChemosyntheticEnergy.BACKGROUND_NPP_G_C_PER_M2_YR
	var host_energy: float = energy.symbiotic_effective_energy(starved)
	assert_gt(host_energy, starved * 100.0)
	assert_gte(host_energy, ChemosyntheticEnergy.SEEP_PEAK_NPP_G_C_PER_M2_YR)


func test_a_symbiont_bearer_is_as_large_in_dead_rock_as_at_a_seep():
	var in_dead_rock: float = energy.attainable_body_mass_factor(
		energy.symbiotic_effective_energy(ChemosyntheticEnergy.BACKGROUND_NPP_G_C_PER_M2_YR)
	)
	var at_seep: float = energy.attainable_body_mass_factor(
		energy.symbiotic_effective_energy(ChemosyntheticEnergy.SEEP_PEAK_NPP_G_C_PER_M2_YR)
	)
	assert_almost_eq(in_dead_rock, at_seep, 0.001)


func test_symbiosis_never_reduces_what_is_available():
	for npp in [0.01, 1.0, 426.0, 5000.0]:
		assert_gte(energy.symbiotic_effective_energy(npp), npp)


# -- the model is pure ----------------------------------------------------

func test_the_model_is_pure():
	assert_eq(energy.ambient_energy_at(17.0), energy.ambient_energy_at(17.0))
	assert_eq(energy.longevity_years(3.0), energy.longevity_years(3.0))


func test_the_curve_reproduces_the_surface_end_it_was_not_fitted_to():
	# LONGEVITY_ENERGY_EXPONENT was derived from ONE end of a real
	# comparison pair -- the olm's century at starved-rock energy. Fed
	# surface-equivalent energy the same curve returns ~17 years, which is
	# a surface salamander's own lifespan. That end was never fitted, so
	# it is a real check on the relation rather than a restatement of it.
	var at_surface_energy: float = energy.longevity_years(
		ChemosyntheticEnergy.SURFACE_NPP_G_C_PER_M2_YR
	)
	assert_between(
		at_surface_energy, 12.0, 30.0,
		(
			"at surface-equivalent energy the model gives %.1f years; a real "
			+ "surface salamander lives 20-25"
		) % at_surface_energy
	)
