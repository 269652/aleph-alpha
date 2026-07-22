extends RefCounted

## Regional/aggregate herbivore population: reproduction/migration/death as a
## function of local vegetation density and water access (Phase 1 roadmap).
## Thin domain wrapper around the resource-agnostic PopulationModel.

const PopulationModel = preload("res://src/world/population_model.gd")

const GROWTH_RATE_PER_DAY := 0.3
const MIGRATION_RATE_PER_DAY := 0.5

## How many herbivores a full-density (1.0) vegetated region can sustain.
## Verified indirectly by test_carrying_capacity_increases_with_vegetation_density.
const HERBIVORES_PER_VEGETATION_UNIT := 20.0

## A region far from water still sustains this fraction of its vegetation-only
## capacity (herbivores travel to drink); water access only softens capacity,
## it doesn't gate it the way zero vegetation (no food at all) does. Verified
## by test_carrying_capacity_is_still_positive_far_from_water.
const WATER_ACCESS_MIN_MULTIPLIER := 0.3

var _population_model := PopulationModel.new(GROWTH_RATE_PER_DAY)


## vegetation_density and water_access are both expected in [0.0, 1.0].
func carrying_capacity(vegetation_density: float, water_access: float) -> float:
	var water_multiplier := lerpf(
		WATER_ACCESS_MIN_MULTIPLIER, 1.0, clampf(water_access, 0.0, 1.0)
	)
	return vegetation_density * HERBIVORES_PER_VEGETATION_UNIT * water_multiplier


func step(population: float, carrying_capacity: float, delta_days: float) -> float:
	return _population_model.step(population, carrying_capacity, delta_days)


func migrate(populations: Dictionary, capacities: Dictionary, delta_days: float) -> Dictionary:
	return _population_model.migrate(populations, capacities, MIGRATION_RATE_PER_DAY, delta_days)
