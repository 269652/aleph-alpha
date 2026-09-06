extends RefCounted

## Regional/aggregate ant-colony population: a queen's egg-laying, bounded
## by how much food her workers actually bring home -- see
## docs/concept/soil_fauna.md#a-queen-and-where-a-colonys-size-comes-from.
## Thin domain wrapper around the resource-agnostic PopulationModel, the
## ant sibling of HerbivorePopulationModel/PredatorPopulationModel/
## AquaticPopulationModel/etc.
##
## Unlike those, this is tracked PER MOUND, not per chunk: AntColony
## already owns several independent mounds (colonies) per chunk, each with
## its own queen, so there is no single per-chunk population number for
## every mound to share the way every other species' aggregate does.
##
## No migrate() here, unlike its siblings -- mounds are sessile, fixed
## placements (see AntColony's own doc comment); a colony does not exchange
## workers with a neighbouring one, so there is nothing for population to
## migrate between. Named explicitly rather than a silent omission.

const PopulationModel = preload("res://src/world/population_model.gd")

## Real ant colonies mature over YEARS, far slower than the seasonal
## reproduction of the land mammals/fish/birds this game already tracks --
## the slowest-growing population this game models. Pinned below
## PredatorPopulationModel's own 0.15 (the previous slowest), not just
## asserted, mirroring how AntColony.MOUND_CHANCE is already pinned FASTER
## than EarthwormPatch.SEED_CHANCE for the same "ordering, not an
## eyeballed number" reason.
const GROWTH_RATE_PER_DAY := 0.05

## The FLOOR of the real range `AntColony` seeds a mound's initial
## population across (see `AntColony._seed_initial_mounds`) -- an abstract
## colony-strength number, not a literal worker headcount, the same
## abstraction level fish_population/herbivore_population already sit at.
##
## Not every mound a player ever finds is freshly founded this instant --
## most have already existed in this simulated world for real, if
## unmodeled, time before being loaded for the first time, the same
## "map-generated content starts already established" convention every
## other patch-sim in this game already follows (TallGrass/WildCropPatch/
## every tree all start mature, never as seedlings/saplings). A colony
## seeded exactly at this floor is a real, currently-young-or-struggling
## one, not an error -- it is the low end of the range, not the only
## value in it.
const STARTING_POPULATION := 1.0

## What an average mound supports with no particular feeding advantage.
const BASE_CAPACITY := 4.0

## How much extra capacity a consistently well-fed colony can support, as
## a multiple of BASE_CAPACITY, at recent_forage_success == 1.0 (an
## unbroken recent run of successful forages). A colony that keeps finding
## food genuinely supports a bigger population than one that keeps coming
## home empty -- the real mechanism the grounding above names, not an
## invented one.
const FOOD_CAPACITY_BONUS := 1.0

## How much extra capacity a colony sitting on consistently damp ground
## can support, at recent_moisture == 1.0 -- see docs/concept/soil_fauna.md
## "Water, not just food: a second real growth driver". Pinned EQUAL to
## FOOD_CAPACITY_BONUS: both are real, independently-acting inputs to the
## same real mechanism (how much of a colony a mound can support), and
## nothing in the grounding argues either should structurally dominate.
## Tested directly (test_water_bonus_is_pinned_equal_to_food_bonus) rather
## than left to coincidentally match.
const WATER_CAPACITY_BONUS := 1.0

## The ceiling capacity() can ever produce -- both bonuses simultaneously
## maxed out. What AntColony.growth_fraction_at (and so a mound's own
## visual size, see ProceduralAntMoundSprite.world_width_for) normalizes
## population against, computed from the same constants capacity() itself
## uses rather than a second, independently-chosen number that could
## silently drift from the real ceiling (cross-checked by
## test_max_reference_population_matches_capacity_at_full_food_and_water).
const MAX_REFERENCE_POPULATION := BASE_CAPACITY * (1.0 + FOOD_CAPACITY_BONUS + WATER_CAPACITY_BONUS)

var _population_model := PopulationModel.new(GROWTH_RATE_PER_DAY)


## `recent_forage_success`/`recent_moisture` are each a [0, 1] fraction
## (see AntColony.record_forage_result/record_moisture) -- 0 for a colony
## that keeps coming home empty / sits on parched ground, 1 for one that
## keeps finding food / stays consistently damp. Out-of-range input is
## clamped rather than trusted, since the caller's own EMA math could in
## principle drift a hair outside [0, 1] through floating-point
## accumulation.
func capacity(recent_forage_success: float, recent_moisture: float) -> float:
	return BASE_CAPACITY * (
		1.0
		+ FOOD_CAPACITY_BONUS * clampf(recent_forage_success, 0.0, 1.0)
		+ WATER_CAPACITY_BONUS * clampf(recent_moisture, 0.0, 1.0)
	)


func step(population: float, carrying_capacity: float, delta_days: float) -> float:
	return _population_model.step(population, carrying_capacity, delta_days)
