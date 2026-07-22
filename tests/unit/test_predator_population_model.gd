extends GutTest

const PredatorPopulationModel = preload("res://src/world/predator_population_model.gd")

var model: PredatorPopulationModel


func before_each():
	model = PredatorPopulationModel.new()


func test_carrying_capacity_is_zero_without_prey():
	assert_eq(model.carrying_capacity(0.0), 0.0)


func test_carrying_capacity_increases_with_prey_population():
	var low := model.carrying_capacity(10.0)
	var high := model.carrying_capacity(100.0)
	assert_gt(high, low)


func test_carrying_capacity_is_a_small_fraction_of_prey_population():
	# Trophic pyramid: an ecosystem sustains far fewer predators than prey.
	var prey_population := 100.0
	var capacity := model.carrying_capacity(prey_population)
	assert_lt(capacity, prey_population)


func test_step_grows_population_toward_capacity():
	var next := model.step(1.0, 5.0, 1.0)
	assert_gt(next, 1.0)
	assert_lte(next, 5.0)


func test_migrate_moves_population_toward_spare_capacity_neighbor():
	var populations := {Vector2i(0, 0): 5.0, Vector2i(1, 0): 0.0}
	var capacities := {Vector2i(0, 0): 0.5, Vector2i(1, 0): 5.0}

	var next: Dictionary = model.migrate(populations, capacities, 1.0)

	assert_gt(next[Vector2i(1, 0)], 0.0)
