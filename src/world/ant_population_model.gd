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

## Every mound's population at the instant it is (re)seeded (see
## `AntColony._seed_initial_mounds`) -- an abstract colony-strength
## number, not a literal worker headcount, the same abstraction level
## fish_population/herbivore_population already sit at.
##
## 1.0 (a seeded-RANGE floor) -> flat 15.0 (2026-09-06, "start at 15 ants
## at the beginning," taken literally rather than folded back into a
## range): every mound is not freshly founded the instant a chunk loads --
## most have already existed in this simulated world for real, if
## unmodeled, time before being loaded for the first time, the same
## "map-generated content starts already established" convention every
## other patch-sim in this game already follows (TallGrass/WildCropPatch/
## every tree all start mature, never as seedlings/saplings). The
## previous pass's own seeded-RANGE fix (1.0..BASE_CAPACITY) was itself a
## correction for exactly this same problem at the old scale; given a
## specific number directly this time, every mound now founds at exactly
## it, matching BASE_CAPACITY below so a fresh colony reads as
## established without already being AT its own unfed ceiling.
const STARTING_POPULATION := 15.0

## What an average mound supports with no particular feeding advantage --
## deliberately kept equal to STARTING_POPULATION (see that constant's own
## doc comment): a freshly-seeded mound must never read as already ABOVE
## its own unobserved capacity ceiling, or PopulationModel.step would read
## it as overcrowded and start shrinking it back down before a player ever
## sees it settle -- the identical safety the previous 1.0/4.0-scale pass
## already established, preserved at the new scale rather than
## reintroducing the bug it fixed.
##
## 4.0 -> 15.0 (2026-09-06, matching the new starting population).
## FOOD_CAPACITY_BONUS/WATER_CAPACITY_BONUS stay at their existing ratio
## to this base, so MAX_REFERENCE_POPULATION (below) rises proportionally.
const BASE_CAPACITY := 15.0

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

## ## A real food economy: storage, upkeep, and a real growth constraint
##
## See docs/concept/soil_fauna.md's "A real food economy" section.
## Everything above this point is "how well a colony's LUCK has been
## running lately" (an EMA of recent forage/moisture outcomes); this is
## the real, depleting/accumulating stockpile those outcomes actually
## fill and a growing population actually draws from -- reported directly:
## "food then becomes driver and constraint of population growth."

## How much a single ant draws from its own mound's stored food reserve
## per simulated day (see AntColony.advance/food_stored_at). Defined as
## exactly 1.0 so "one food unit" IS "one ant's daily ration" -- the
## simplest possible unit choice, needing no separate justification for
## what the number itself means.
const FOOD_PER_ANT_PER_DAY := 1.0

## How many days of reserve, at the CURRENT population's own upkeep rate,
## counts as "secure" -- AntColony.food_availability_fraction reads 1.0
## (capacity() is used exactly as recent forage-success/moisture already
## say it should be, unconstrained) once food_stored_at reaches this many
## days' worth of upkeep, and something less than 1.0 below it. A modest
## few-day buffer: real enough to ride out an ordinary short dry spell,
## not a hoard so large the constraint this whole mechanism exists for
## could never actually bite.
const FOOD_BUFFER_DAYS := 3.0

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
