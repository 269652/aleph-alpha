extends GutTest

const VegetationGrowthModel = preload("res://src/world/vegetation_growth_model.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")

var model: VegetationGrowthModel


func before_each():
	model = VegetationGrowthModel.new()


# -- carrying_capacity_for_biome ---------------------------------------------

func test_non_vegetated_biomes_have_zero_carrying_capacity():
	assert_eq(model.carrying_capacity_for_biome("ocean"), 0.0)
	assert_eq(model.carrying_capacity_for_biome("mountain"), 0.0)


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
