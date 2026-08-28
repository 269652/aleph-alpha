extends GutTest

## Regional/aggregate sparrow population: reproduction/migration/death as a
## function of local ground-seed density (see docs/concept/flora.md's
## ground_seed_cells and docs/concept/ecosystem_dynamics.md's "granivore
## half"). Mirrors HerbivorePopulationModel/RobinPopulationModel's test
## shape, with ground seed-cell count standing in for vegetation/worm
## density.

const SparrowPopulationModel = preload("res://src/world/sparrow_population_model.gd")
const RobinPopulationModel = preload("res://src/world/robin_population_model.gd")

var model: SparrowPopulationModel


func before_each():
	model = SparrowPopulationModel.new()


func test_carrying_capacity_is_zero_without_seeds():
	assert_eq(model.carrying_capacity(0.0), 0.0)


func test_carrying_capacity_increases_with_seed_density():
	var low := model.carrying_capacity(2.0)
	var high := model.carrying_capacity(20.0)
	assert_gt(high, low)


func test_growth_rate_is_faster_than_robin_baseline():
	# House sparrows are among the most fecund common songbirds -- routinely
	# 2-3 broods a year of 3-5 eggs each -- out-breeding the robin this
	# project already models.
	assert_gt(SparrowPopulationModel.GROWTH_RATE_PER_DAY, RobinPopulationModel.GROWTH_RATE_PER_DAY)


func test_step_grows_population_toward_capacity():
	var next := model.step(1.0, 10.0, 1.0)
	assert_gt(next, 1.0)
	assert_lte(next, 10.0)


func test_migrate_moves_population_toward_spare_capacity_neighbor():
	var populations := {Vector2i(0, 0): 10.0, Vector2i(1, 0): 0.0}
	var capacities := {Vector2i(0, 0): 1.0, Vector2i(1, 0): 10.0}

	var next: Dictionary = model.migrate(populations, capacities, 1.0)

	assert_gt(next[Vector2i(1, 0)], 0.0)
