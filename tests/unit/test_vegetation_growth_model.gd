extends GutTest

const VegetationGrowthModel = preload("res://src/world/vegetation_growth_model.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")

var model: VegetationGrowthModel


func before_each():
	model = VegetationGrowthModel.new()


# -- carrying_capacity_for_biome ---------------------------------------------

func test_ocean_has_zero_carrying_capacity():
	assert_eq(model.carrying_capacity_for_biome("ocean"), 0.0)


## Mountain is no longer a hard zero -- real alpine terrain above the tree
## line still sustains sparse vegetation, so a mountain goat pool (see
## CreatureRenderer's biome species pools) has something to graze. Tuned
## placeholder pinned exactly per CLAUDE.md's no-eyeballed-constants rule.
func test_mountain_carrying_capacity_is_a_small_nonzero_placeholder():
	assert_almost_eq(model.carrying_capacity_for_biome("mountain"), 0.12, 0.0001)


func test_mountain_carrying_capacity_is_sparser_than_tundra():
	var mountain := model.carrying_capacity_for_biome("mountain")
	var tundra := model.carrying_capacity_for_biome("tundra")
	assert_gt(mountain, 0.0, "mountain should sustain at least sparse vegetation")
	assert_lt(mountain, tundra, "mountain should be sparser than tundra")


func test_every_known_biome_has_a_defined_carrying_capacity():
	for biome_name in BiomeClassifier.KNOWN_BIOMES:
		assert_true(
			model.carrying_capacity_for_biome(biome_name) >= 0.0,
			"missing carrying capacity for %s" % biome_name
		)


func test_denser_biomes_have_higher_carrying_capacity_than_sparser_ones():
	var rainforest := model.carrying_capacity_for_biome("rainforest")
	var forest := model.carrying_capacity_for_biome("forest")
	var grassland := model.carrying_capacity_for_biome("grassland")
	var desert := model.carrying_capacity_for_biome("desert")
	var tundra := model.carrying_capacity_for_biome("tundra")

	assert_gt(rainforest, forest, "rainforest should out-grow forest")
	assert_gt(forest, grassland, "forest should out-grow grassland")
	assert_gt(grassland, desert, "grassland should out-grow desert")
	assert_gt(grassland, tundra, "grassland should out-grow tundra")


# -- growth_rate --------------------------------------------------------------

func test_growth_rate_is_zero_without_moisture():
	assert_eq(model.growth_rate(1.0, 0.0), 0.0)


func test_growth_rate_is_zero_without_warmth():
	assert_eq(model.growth_rate(0.0, 1.0), 0.0)


func test_growth_rate_is_bounded_between_zero_and_one():
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for m in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var rate := model.growth_rate(t, m)
			assert_between(rate, 0.0, 1.0, "rate(%s, %s) out of bounds" % [t, m])


func test_growth_rate_increases_with_more_moisture_and_warmth():
	var low := model.growth_rate(0.3, 0.3)
	var high := model.growth_rate(0.9, 0.9)
	assert_gt(high, low)


# -- effective_capacity --------------------------------------------------------

func test_effective_capacity_is_the_biome_ceiling_under_ideal_conditions():
	assert_almost_eq(
		model.effective_capacity("grassland", 1.0, 1.0),
		model.carrying_capacity_for_biome("grassland"),
		0.0001
	)


func test_effective_capacity_drops_when_conditions_are_unsuitable():
	var ideal := model.effective_capacity("grassland", 1.0, 1.0)
	var drought := model.effective_capacity("grassland", 1.0, 0.0)
	assert_lt(drought, ideal)


# -- step_density (logistic growth/decline toward effective_capacity) ----------

func test_step_density_moves_toward_capacity():
	var next := model.step_density(0.1, 1.0, 1.0)
	assert_gt(next, 0.1)
	assert_lt(next, 1.0)


func test_step_density_never_exceeds_capacity_even_with_a_huge_delta():
	var next := model.step_density(0.5, 1.0, 1000.0)
	assert_almost_eq(next, 1.0, 0.0001)


func test_step_density_decays_toward_zero_when_capacity_is_zero():
	var next := model.step_density(0.5, 0.0, 1.0)
	assert_lt(next, 0.5)
	assert_gte(next, 0.0)


func test_step_density_declines_when_effective_capacity_drops_below_current_density():
	# A drought lowers effective_capacity (see effective_capacity tests above)
	# out from under already-established vegetation -- it should visibly die
	# back toward the new, lower target, not freeze in place.
	var next := model.step_density(1.0, 0.15, 1.0)
	assert_lt(next, 1.0)


func test_step_density_never_goes_negative():
	var next := model.step_density(0.0, 1.0, 5.0)
	assert_gte(next, 0.0)


# -- step_grid (growth + spread to neighbor cells) -----------------------------

func _uniform_array(size: int, value) -> Array:
	var result := []
	result.resize(size)
	result.fill(value)
	return result


func test_step_grid_never_exceeds_each_cells_effective_capacity():
	# 3x3 grassland patch, wildly uneven starting density.
	var width := 3
	var height := 3
	var biome := _uniform_array(width * height, "grassland")
	var temperature := PackedFloat32Array()
	temperature.resize(width * height)
	temperature.fill(0.8)
	var moisture := PackedFloat32Array()
	moisture.resize(width * height)
	moisture.fill(0.8)
	var density := PackedFloat32Array([1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0])

	var next := model.step_grid(density, biome, temperature, moisture, width, height, 10.0)

	var capacity := model.carrying_capacity_for_biome("grassland")
	for value in next:
		assert_between(value, 0.0, capacity + 0.0001)


func test_step_grid_spreads_density_toward_a_lower_density_vegetated_neighbor():
	# 2x1: left cell already at capacity, right cell starts empty but can
	# support vegetation -- it should pick up density from its neighbor.
	var width := 2
	var height := 1
	var biome := PackedStringArray(["grassland", "grassland"])
	var temperature := PackedFloat32Array([0.8, 0.8])
	var moisture := PackedFloat32Array([0.8, 0.8])
	var density := PackedFloat32Array([1.0, 0.0])
	var capacity := model.carrying_capacity_for_biome("grassland")
	density[0] = capacity

	var next := model.step_grid(density, biome, temperature, moisture, width, height, 1.0)

	assert_gt(next[1], 0.0, "empty neighbor should gain some density from its full neighbor")


func test_step_grid_does_not_spread_into_a_non_vegetated_biome():
	# Grassland next to ocean: ocean must stay at zero no matter how dense
	# its vegetated neighbor is.
	var width := 2
	var height := 1
	var biome := PackedStringArray(["grassland", "ocean"])
	var temperature := PackedFloat32Array([0.8, 0.8])
	var moisture := PackedFloat32Array([0.8, 0.8])
	var density := PackedFloat32Array([model.carrying_capacity_for_biome("grassland"), 0.0])

	var next := model.step_grid(density, biome, temperature, moisture, width, height, 1.0)

	assert_eq(next[1], 0.0)


# -- land health: overharvesting leaves a lasting mark (docs/concept/world.md
# "Land health: overharvesting leaves a lasting mark, not just a slower
# respawn") -------------------------------------------------------------------

func test_effective_capacity_defaults_land_health_to_full_and_is_unaffected():
	# Backward compatibility: every existing caller that doesn't pass
	# land_health must see the exact same number as before this feature.
	var with_default := model.effective_capacity("grassland", 0.8, 0.8)
	var with_explicit_full := model.effective_capacity("grassland", 0.8, 0.8, 1.0)
	assert_almost_eq(with_default, with_explicit_full, 0.0001)


func test_effective_capacity_is_multiplied_down_by_degraded_land_health():
	var healthy := model.effective_capacity("grassland", 0.8, 0.8, 1.0)
	var degraded := model.effective_capacity("grassland", 0.8, 0.8, 0.5)
	assert_almost_eq(degraded, healthy * 0.5, 0.0001)


func test_effective_capacity_at_zero_land_health_is_zero():
	assert_eq(model.effective_capacity("grassland", 0.8, 0.8, 0.0), 0.0)


func test_effective_capacity_clamps_land_health_above_one():
	# Land health cannot boost a cell PAST its weather-driven ceiling.
	var uncapped := model.effective_capacity("grassland", 0.8, 0.8, 5.0)
	var capped := model.effective_capacity("grassland", 0.8, 0.8, 1.0)
	assert_almost_eq(uncapped, capped, 0.0001)


# -- regrowth_rate: the live regrowth speed land health compares harvest against

func test_regrowth_rate_is_zero_when_capacity_is_zero():
	assert_eq(model.regrowth_rate(0.5, 0.0), 0.0)


func test_regrowth_rate_is_zero_when_density_has_met_or_passed_capacity():
	assert_eq(model.regrowth_rate(1.0, 1.0), 0.0)
	assert_eq(model.regrowth_rate(1.2, 1.0), 0.0)


func test_regrowth_rate_is_positive_below_capacity():
	assert_gt(model.regrowth_rate(0.3, 1.0), 0.0)


## Exact pinned value -- the same logistic term step_density's growth branch
## integrates over delta_days, factored out rather than reinvented.
func test_regrowth_rate_matches_the_logistic_growth_term_exactly():
	var density := 0.4
	var capacity := 1.0
	var expected: float = VegetationGrowthModel.GROWTH_PACE_PER_DAY * density * (1.0 - density / capacity)
	assert_almost_eq(model.regrowth_rate(density, capacity), expected, 0.0001)


# -- step_land_health: depletes under sustained overharvest, recovers when fallow

func test_step_land_health_depletes_when_harvest_exceeds_regrowth():
	var next := model.step_land_health(1.0, 0.5, 0.1, 1.0)
	assert_lt(next, 1.0)


func test_step_land_health_recovers_when_harvest_does_not_exceed_regrowth():
	var next := model.step_land_health(0.5, 0.05, 0.1, 1.0)
	assert_gt(next, 0.5)


func test_step_land_health_recovers_when_left_entirely_fallow():
	var next := model.step_land_health(0.5, 0.0, 0.0, 1.0)
	assert_gt(next, 0.5)


func test_step_land_health_at_the_boundary_recovers_not_depletes():
	# Harvest exactly matching regrowth is sustainable, not overharvest.
	var next := model.step_land_health(0.5, 0.1, 0.1, 1.0)
	assert_gt(next, 0.5)


func test_step_land_health_never_exceeds_one():
	var next := model.step_land_health(0.999, 0.0, 0.0, 1000.0)
	assert_almost_eq(next, 1.0, 0.0001)


func test_step_land_health_never_goes_below_zero():
	var next := model.step_land_health(0.001, 100.0, 0.0, 1000.0)
	assert_almost_eq(next, 0.0, 0.0001)


func test_step_land_health_exact_depletion_pace():
	var next := model.step_land_health(1.0, 1.0, 0.0, 1.0)
	assert_almost_eq(
		next, 1.0 - VegetationGrowthModel.LAND_HEALTH_DEPLETION_PACE_PER_DAY, 0.0001
	)


func test_step_land_health_exact_recovery_pace():
	var next := model.step_land_health(0.0, 0.0, 0.0, 1.0)
	assert_almost_eq(next, VegetationGrowthModel.LAND_HEALTH_RECOVERY_PACE_PER_DAY, 0.0001)


## Real-world grounding (see the constants' own doc comments): soil organic
## matter/structure recovers on the order of a DECADE-PLUS of rest once
## depleted, dramatically slower than a single growing season's biomass
## regrowth (GROWTH_PACE_PER_DAY) -- land health recovery must be at least an
## order of magnitude slower than raw biomass growth. Degradation from
## sustained overuse is documented faster than recovery but still slower than
## raw biomass growth, so it sits strictly between the two.
func test_land_health_recovery_is_at_least_an_order_of_magnitude_slower_than_growth():
	assert_lt(
		VegetationGrowthModel.LAND_HEALTH_RECOVERY_PACE_PER_DAY,
		VegetationGrowthModel.GROWTH_PACE_PER_DAY * 0.1
	)


func test_land_health_depletion_sits_between_recovery_and_raw_growth_pace():
	assert_gt(
		VegetationGrowthModel.LAND_HEALTH_DEPLETION_PACE_PER_DAY,
		VegetationGrowthModel.LAND_HEALTH_RECOVERY_PACE_PER_DAY
	)
	assert_lt(
		VegetationGrowthModel.LAND_HEALTH_DEPLETION_PACE_PER_DAY,
		VegetationGrowthModel.GROWTH_PACE_PER_DAY
	)


# -- step_grid applies land health as a further multiplier ---------------------

func test_step_grid_default_land_health_matches_pre_existing_behavior():
	var width := 2
	var height := 1
	var biome := PackedStringArray(["grassland", "grassland"])
	var temperature := PackedFloat32Array([0.8, 0.8])
	var moisture := PackedFloat32Array([0.8, 0.8])
	var density := PackedFloat32Array([0.1, 0.1])

	var with_default := model.step_grid(density, biome, temperature, moisture, width, height, 1.0)
	var with_explicit_full := model.step_grid(
		density, biome, temperature, moisture, width, height, 1.0, 1.0
	)

	assert_eq(with_default, with_explicit_full)


func test_step_grid_degraded_land_health_caps_growth_below_the_weather_ceiling():
	var width := 1
	var height := 1
	var biome := PackedStringArray(["grassland"])
	var temperature := PackedFloat32Array([0.8])
	var moisture := PackedFloat32Array([0.8])
	# A small nonzero starting density -- pure logistic growth cannot
	# bootstrap from an exact 0.0 (0 * anything is still 0), same as real
	# vegetation needs some existing seed stock to spread from.
	var density := PackedFloat32Array([0.05])

	# A long time, so both regions would otherwise fully reach their ceiling.
	var healthy := model.step_grid(density, biome, temperature, moisture, width, height, 100.0, 1.0)
	var degraded := model.step_grid(density, biome, temperature, moisture, width, height, 100.0, 0.3)

	assert_lt(degraded[0], healthy[0], "degraded land health must cap growth below the healthy ceiling")
	assert_almost_eq(
		degraded[0], model.effective_capacity("grassland", 0.8, 0.8, 0.3), 0.001
	)
