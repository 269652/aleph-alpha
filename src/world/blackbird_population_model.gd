extends RefCounted

## Regional/aggregate blackbird population: reproduction/migration/death as a
## function of local worm density (see EarthwormPatch.worm_cells and
## docs/concept/seasonal_behavior.md, "Blackbird: new species, real
## population, real diet shift"). Thin domain wrapper around the
## resource-agnostic PopulationModel, mirroring Robin/SparrowPopulationModel's
## exact shape.
##
## Real blackbirds (Turdus merula) are thrushes -- the same real ecological
## role as the robin this project already models (both are worm-hunting
## lawn/garden birds), not the seed-bulk-feeding sparrow -- so worm density
## is the real, closest-available capacity signal reused directly, rather
## than inventing a new "fruit density" per-chunk metric this game has no
## existing plumbing for.

const PopulationModel = preload("res://src/world/population_model.gd")
const RobinPopulationModel = preload("res://src/world/robin_population_model.gd")

## Blackbirds and robins are both thrushes with a genuinely similar real
## breeding rate -- there is no real basis to invent a different rate for
## the closest available real ecological analog. Verified by
## test_growth_rate_matches_its_closest_real_ecological_analog.
const GROWTH_RATE_PER_DAY := RobinPopulationModel.GROWTH_RATE_PER_DAY
const MIGRATION_RATE_PER_DAY := 0.5

## How many blackbirds one worm cell can sustain. A real blackbird's diet
## leans on fruit more than a robin's does (see FlyerDiet's own real fruit
## list for each, and this species' own winter diet-shift), so the same
## worm density should support proportionally FEWER blackbirds than
## robins -- a real, derived ratio (3/4 of RobinPopulationModel.ROBINS_
## PER_WORM_CELL), not an eyeballed number. Verified by
## test_supports_fewer_blackbirds_per_worm_cell_than_robins.
const BLACKBIRDS_PER_WORM_CELL := RobinPopulationModel.ROBINS_PER_WORM_CELL * 0.75

var _population_model := PopulationModel.new(GROWTH_RATE_PER_DAY)


func carrying_capacity(worm_cell_count: float) -> float:
	return maxf(0.0, worm_cell_count) * BLACKBIRDS_PER_WORM_CELL


func step(population: float, carrying_capacity: float, delta_days: float) -> float:
	return _population_model.step(population, carrying_capacity, delta_days)


func migrate(populations: Dictionary, capacities: Dictionary, delta_days: float) -> Dictionary:
	return _population_model.migrate(populations, capacities, MIGRATION_RATE_PER_DAY, delta_days)
