extends RefCounted

## Regional/aggregate robin population: reproduction/migration/death as a
## function of local earthworm burrow density (see docs/concept/soil_fauna.md
## and docs/concept/ecosystem_dynamics.md's Open questions -- "eaten worms do
## not yet affect bird numbers"). Thin domain wrapper around the
## resource-agnostic PopulationModel, the avian sibling of
## HerbivorePopulationModel/PredatorPopulationModel/AquaticPopulationModel.
##
## `worm_cell_count` is EarthwormPatch.worm_cells().size() -- an absolute
## burrow count per chunk (0..EarthwormPatch.MAX_WORMS), not a fraction. A
## burrow's EXISTENCE, not whether its worm currently happens to be surfaced,
## is the food-density signal: a robin forages a territory for worms it can
## reach over time, not just the ones visibly up at this exact instant.

const PopulationModel = preload("res://src/world/population_model.gd")
const HerbivorePopulationModel = preload("res://src/world/herbivore_population_model.gd")

## Songbirds turn over generations faster than the land mammals
## HerbivorePopulationModel models -- a robin can raise two or three broods a
## season. Verified by test_growth_rate_is_faster_than_herbivore_baseline.
const GROWTH_RATE_PER_DAY := 0.4
const MIGRATION_RATE_PER_DAY := 0.5

## How many robins one worm burrow can sustain. A robin's foraging territory
## spans many burrows -- real robin territories run to a third of a hectare
## or more, far bigger than the ground a single burrow occupies -- so it
## takes several worm cells to sustain one bird, the avian mirror of
## HerbivorePopulationModel.HERBIVORES_PER_VEGETATION_UNIT. Verified
## indirectly by test_carrying_capacity_increases_with_worm_density.
const ROBINS_PER_WORM_CELL := 0.2

var _population_model := PopulationModel.new(GROWTH_RATE_PER_DAY)


func carrying_capacity(worm_cell_count: float) -> float:
	return maxf(0.0, worm_cell_count) * ROBINS_PER_WORM_CELL


func step(population: float, carrying_capacity: float, delta_days: float) -> float:
	return _population_model.step(population, carrying_capacity, delta_days)


func migrate(populations: Dictionary, capacities: Dictionary, delta_days: float) -> Dictionary:
	return _population_model.migrate(populations, capacities, MIGRATION_RATE_PER_DAY, delta_days)
