extends RefCounted

## Regional/aggregate kingfisher population: same shape as
## PredatorPopulationModel, but tracking the EXISTING aquatic fish population
## as its prey signal instead of a new food-density model -- a kingfisher's
## food source is exactly the fish EcosystemSimulation already tracks (see
## docs/concept/ecosystem_dynamics.md's Open questions: "a real 'more fish
## support more birds' feedback ... is a natural, grounded follow-up"). Thin
## domain wrapper around the resource-agnostic PopulationModel.

const PopulationModel = preload("res://src/world/population_model.gd")
const AquaticPopulationModel = preload("res://src/world/aquatic_population_model.gd")

## Predators reproduce slower than their prey (mirrors
## PredatorPopulationModel's own GROWTH_RATE_PER_DAY being under
## HerbivorePopulationModel's) -- kingfishers raise about one brood of a
## handful of chicks a year, nowhere near a fish stock's high fecundity.
## Verified by test_growth_rate_is_slower_than_fish_baseline.
const GROWTH_RATE_PER_DAY := 0.2
const MIGRATION_RATE_PER_DAY := 0.5

## Trophic pyramid: a real kingfisher pair patrols a long stretch of bank for
## its fish, so far fewer kingfishers than fish can share a given water body
## -- smaller even than PredatorPopulationModel.PREDATORS_PER_PREY_UNIT,
## reflecting a specialist piscivore's wider individual range. Verified by
## test_carrying_capacity_is_a_small_fraction_of_fish_population.
const KINGFISHERS_PER_FISH_UNIT := 0.03

var _population_model := PopulationModel.new(GROWTH_RATE_PER_DAY)


func carrying_capacity(fish_population: float) -> float:
	return maxf(0.0, fish_population) * KINGFISHERS_PER_FISH_UNIT


func step(population: float, carrying_capacity: float, delta_days: float) -> float:
	return _population_model.step(population, carrying_capacity, delta_days)


func migrate(populations: Dictionary, capacities: Dictionary, delta_days: float) -> Dictionary:
	return _population_model.migrate(populations, capacities, MIGRATION_RATE_PER_DAY, delta_days)
