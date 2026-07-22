extends RefCounted

## Regional/aggregate predator population: same shape as
## HerbivorePopulationModel, but tracking prey (herbivore) density instead of
## vegetation density (Phase 1 roadmap). Thin domain wrapper around the
## resource-agnostic PopulationModel.

const PopulationModel = preload("res://src/world/population_model.gd")

const GROWTH_RATE_PER_DAY := 0.15  # predators reproduce slower than their prey
const MIGRATION_RATE_PER_DAY := 0.5

## Trophic pyramid: an ecosystem sustains far fewer predators than prey.
## Verified by test_carrying_capacity_is_a_small_fraction_of_prey_population.
const PREDATORS_PER_PREY_UNIT := 0.08

var _population_model := PopulationModel.new(GROWTH_RATE_PER_DAY)


func carrying_capacity(prey_population: float) -> float:
	return prey_population * PREDATORS_PER_PREY_UNIT


func step(population: float, carrying_capacity: float, delta_days: float) -> float:
	return _population_model.step(population, carrying_capacity, delta_days)


func migrate(populations: Dictionary, capacities: Dictionary, delta_days: float) -> Dictionary:
	return _population_model.migrate(populations, capacities, MIGRATION_RATE_PER_DAY, delta_days)
