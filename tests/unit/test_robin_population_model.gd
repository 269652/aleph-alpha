extends GutTest

## Regional/aggregate robin population: reproduction/migration/death as a
## function of local earthworm density (see docs/concept/soil_fauna.md and
## docs/concept/ecosystem_dynamics.md's "Open questions" -- "eaten worms do
## not yet affect bird numbers"). Mirrors HerbivorePopulationModel's test
## shape exactly, with worm burrow count standing in for vegetation density.

const RobinPopulationModel = preload("res://src/world/robin_population_model.gd")
const HerbivorePopulationModel = preload("res://src/world/herbivore_population_model.gd")

var model: RobinPopulationModel


func before_each():
	model = RobinPopulationModel.new()


func test_carrying_capacity_is_zero_without_worms():
	assert_eq(model.carrying_capacity(0.0), 0.0)


func test_carrying_capacity_increases_with_worm_density():
	var low := model.carrying_capacity(2.0)
	var high := model.carrying_capacity(20.0)
	assert_gt(high, low)


func test_growth_rate_is_faster_than_herbivore_baseline():
	# Songbirds turn over generations faster than large land mammals -- a
	# robin can raise two or three broods a season, unlike the herbivores
	# HerbivorePopulationModel models.
	assert_gt(RobinPopulationModel.GROWTH_RATE_PER_DAY, HerbivorePopulationModel.GROWTH_RATE_PER_DAY)


func test_step_grows_population_toward_capacity():
	var next := model.step(1.0, 10.0, 1.0)
	assert_gt(next, 1.0)
	assert_lte(next, 10.0)


func test_migrate_moves_population_toward_spare_capacity_neighbor():
	var populations := {Vector2i(0, 0): 10.0, Vector2i(1, 0): 0.0}
	var capacities := {Vector2i(0, 0): 1.0, Vector2i(1, 0): 10.0}

	var next: Dictionary = model.migrate(populations, capacities, 1.0)

	assert_gt(next[Vector2i(1, 0)], 0.0)
