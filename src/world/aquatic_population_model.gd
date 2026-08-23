extends RefCounted

## Regional/aggregate fish population: reproduction/migration/death as a
## function of local water area and temperature suitability (see
## docs/concept/fishing.md#aquatic-population-model). Thin domain wrapper
## around the resource-agnostic PopulationModel, the aquatic sibling of
## HerbivorePopulationModel/PredatorPopulationModel.

const PopulationModel = preload("res://src/world/population_model.gd")

## Fish are more r-selected than land herbivores (high fecundity, high
## juvenile mortality) -- a real fish stock's intrinsic growth rate is
## plausibly higher than HerbivorePopulationModel.GROWTH_RATE_PER_DAY's 0.3.
## Verified by test_growth_rate_is_faster_than_herbivore_baseline.
const GROWTH_RATE_PER_DAY := 0.5
const MIGRATION_RATE_PER_DAY := 0.5

## How many fish one interior-water cell at ideal temperature can sustain.
## Verified indirectly by test_carrying_capacity_increases_with_water_area.
const FISH_PER_WATER_CELL := 2.0

## Bell-curve temperature suitability: 1.0 at OPTIMAL_TEMPERATURE, falling
## off toward 0.0 at the edges of TEMPERATURE_TOLERANCE -- most fish species
## have a real thermal comfort band, most productive in a middle range and
## less so toward both poles and the equator. mean_water_temperature is
## expected normalized [0.0, 1.0], the same convention as Chunk.temperature.
const OPTIMAL_TEMPERATURE := 0.55
const TEMPERATURE_TOLERANCE := 0.45

var _population_model := PopulationModel.new(GROWTH_RATE_PER_DAY)


## water_area_cells is an absolute interior-water cell count (not a
## fraction -- see fishing.md's "Water area -> carrying capacity"); the
## bigger a body of water, the more fish it can sustain, independent of
## whether the chunk is *mostly* water.
func carrying_capacity(water_area_cells: float, mean_water_temperature: float) -> float:
	return water_area_cells * FISH_PER_WATER_CELL * temperature_suitability(mean_water_temperature)


## Bell-shaped suitability multiplier in [0.0, 1.0], peaking at
## OPTIMAL_TEMPERATURE and falling linearly to 0.0 by TEMPERATURE_TOLERANCE
## away from it in either direction.
func temperature_suitability(mean_water_temperature: float) -> float:
	var distance := absf(mean_water_temperature - OPTIMAL_TEMPERATURE)
	return clampf(1.0 - distance / TEMPERATURE_TOLERANCE, 0.0, 1.0)


func step(population: float, carrying_capacity: float, delta_days: float) -> float:
	return _population_model.step(population, carrying_capacity, delta_days)


func migrate(populations: Dictionary, capacities: Dictionary, delta_days: float) -> Dictionary:
	return _population_model.migrate(populations, capacities, MIGRATION_RATE_PER_DAY, delta_days)
