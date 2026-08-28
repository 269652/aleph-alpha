extends RefCounted

## Regional/aggregate sparrow population: reproduction/migration/death as a
## function of local ground-seed density (see FlowerPatch.ground_seed_cells /
## TallGrass.ground_seed_cells and docs/concept/ecosystem_dynamics.md's
## "granivore half"). Thin domain wrapper around the resource-agnostic
## PopulationModel, the granivore sibling of RobinPopulationModel.
##
## `seed_cell_count` is the combined size of every loaded ground-seed-bearing
## patch's `ground_seed_cells()` for a chunk (FlowerPatch + TallGrass) -- an
## absolute count, not a fraction, the same convention RobinPopulationModel
## uses for worm burrows.

const PopulationModel = preload("res://src/world/population_model.gd")
const RobinPopulationModel = preload("res://src/world/robin_population_model.gd")

## House sparrows are among the most fecund common songbirds -- routinely 2-3
## broods a year of 3-5 eggs each -- out-breeding the robin this project
## already models. Verified by test_growth_rate_is_faster_than_robin_baseline.
const GROWTH_RATE_PER_DAY := 0.45
const MIGRATION_RATE_PER_DAY := 0.5

## How many sparrows one ground-seed cell can sustain. A single seed is far
## less food than a worm, so it takes proportionally more seed cells than
## RobinPopulationModel.ROBINS_PER_WORM_CELL's worm cells to sustain one
## bird -- a sparrow's diet is bulk-feeding on small, low-energy items rather
## than a robin's fewer, larger prey. Verified indirectly by
## test_carrying_capacity_increases_with_seed_density.
const SPARROWS_PER_SEED_CELL := 0.1

var _population_model := PopulationModel.new(GROWTH_RATE_PER_DAY)


func carrying_capacity(seed_cell_count: float) -> float:
	return maxf(0.0, seed_cell_count) * SPARROWS_PER_SEED_CELL


func step(population: float, carrying_capacity: float, delta_days: float) -> float:
	return _population_model.step(population, carrying_capacity, delta_days)


func migrate(populations: Dictionary, capacities: Dictionary, delta_days: float) -> Dictionary:
	return _population_model.migrate(populations, capacities, MIGRATION_RATE_PER_DAY, delta_days)
