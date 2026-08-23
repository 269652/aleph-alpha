extends GutTest

## See docs/concept/fishing.md#aquatic-population-model.

const AquaticPopulationModel = preload("res://src/world/aquatic_population_model.gd")

var model: AquaticPopulationModel


func before_each():
	model = AquaticPopulationModel.new()


func test_carrying_capacity_is_zero_without_water_area():
	assert_eq(model.carrying_capacity(0.0, 0.5), 0.0)


func test_carrying_capacity_increases_with_water_area():
	var small := model.carrying_capacity(10.0, 0.5)
	var large := model.carrying_capacity(100.0, 0.5)
	assert_gt(large, small)


func test_carrying_capacity_peaks_near_optimal_temperature():
	var at_optimal := model.carrying_capacity(50.0, AquaticPopulationModel.OPTIMAL_TEMPERATURE)
	var far_from_optimal := model.carrying_capacity(50.0, 0.0)
	assert_gt(at_optimal, far_from_optimal)


func test_carrying_capacity_never_negative_at_extreme_temperature():
	assert_gte(model.carrying_capacity(50.0, 1.0), 0.0)
	assert_gte(model.carrying_capacity(50.0, -1.0), 0.0)


func test_growth_rate_is_faster_than_herbivore_baseline():
	# Fish are more r-selected than land mammals -- high fecundity, high
	# juvenile mortality -- see the class doc comment.
	assert_gt(AquaticPopulationModel.GROWTH_RATE_PER_DAY, 0.3)


func test_step_grows_population_toward_capacity():
	var next := model.step(1.0, 10.0, 1.0)
	assert_gt(next, 1.0)
	assert_lte(next, 10.0)


func test_migrate_moves_population_toward_spare_capacity_neighbor():
	var populations := {Vector2i(0, 0): 10.0, Vector2i(1, 0): 0.0}
	var capacities := {Vector2i(0, 0): 1.0, Vector2i(1, 0): 10.0}

	var next: Dictionary = model.migrate(populations, capacities, 1.0)

	assert_gt(next[Vector2i(1, 0)], 0.0)
