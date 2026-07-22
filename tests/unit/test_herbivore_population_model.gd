extends GutTest

const HerbivorePopulationModel = preload("res://src/world/herbivore_population_model.gd")

var model: HerbivorePopulationModel


func before_each():
	model = HerbivorePopulationModel.new()


func test_carrying_capacity_is_zero_without_vegetation():
	assert_eq(model.carrying_capacity(0.0, 1.0), 0.0)


func test_carrying_capacity_increases_with_vegetation_density():
	var low := model.carrying_capacity(0.2, 0.5)
	var high := model.carrying_capacity(0.8, 0.5)
	assert_gt(high, low)


func test_carrying_capacity_increases_with_water_access():
	var far_from_water := model.carrying_capacity(0.5, 0.0)
	var near_water := model.carrying_capacity(0.5, 1.0)
	assert_gt(near_water, far_from_water)


func test_carrying_capacity_is_still_positive_far_from_water():
	# Herbivores can travel to drink -- water access softens capacity, it
	# doesn't gate it entirely the way zero vegetation (no food at all) does.
	var capacity := model.carrying_capacity(0.5, 0.0)
	assert_gt(capacity, 0.0)


func test_step_grows_population_toward_capacity():
	var next := model.step(1.0, 10.0, 1.0)
	assert_gt(next, 1.0)
	assert_lte(next, 10.0)


func test_migrate_moves_population_toward_spare_capacity_neighbor():
	var populations := {Vector2i(0, 0): 10.0, Vector2i(1, 0): 0.0}
	var capacities := {Vector2i(0, 0): 1.0, Vector2i(1, 0): 10.0}

	var next: Dictionary = model.migrate(populations, capacities, 1.0)

	assert_gt(next[Vector2i(1, 0)], 0.0)
