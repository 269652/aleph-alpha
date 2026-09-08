extends RefCounted

## Regional/aggregate honeybee-colony population: a queen's egg-laying,
## bounded by how much nectar/pollen her workers actually bring home --
## see docs/concept/bees.md's "Honeybee colony economy" section. Thin
## domain wrapper around the resource-agnostic PopulationModel, the bee
## sibling of AntPopulationModel/HerbivorePopulationModel/etc.
##
## Unlike AntPopulationModel, capacity is bounded by forage success
## ALONE -- no separate moisture/water bonus. A real colony's growth
## ceiling is nectar/pollen availability; there is no comparably central
## "does this site have water nearby" driver for bees the way there
## genuinely is for digging, larvae-humidity-dependent ants. Winter
## dormancy (BeeColony.dormancy_multiplier_at) covers the seasonal half
## water/warmth jointly covered for ants.
##
## Tracked PER HIVE, not per chunk, the same reason AntPopulationModel is
## tracked per mound: BeeColony owns several independent hives per chunk,
## each with its own queen.
##
## No migrate() here either, for the identical reason AntPopulationModel
## has none: hives are sessile between real moves -- and a hive's own
## relocation (swarming, absconding) is BeeColony's own mechanism, not
## population migrating between fixed regions.

const PopulationModel = preload("res://src/world/population_model.gd")

## Real honeybee colonies build up across a single growing season,
## considerably faster than an ant colony's multi-year maturation --
## pinned ABOVE AntPopulationModel.GROWTH_RATE_PER_DAY (0.05), an
## ordering, not an eyeballed number. Matches PredatorPopulationModel's
## own rate: a comparably fast-building population, without claiming to
## be among the very fastest this game tracks (small birds/fish
## reproduce many times a season in large broods -- even a fast-building
## superorganism colony is not that).
const GROWTH_RATE_PER_DAY := 0.15

## Every hive's population at the instant it is (re)seeded, or the moment
## it re-establishes after a swarm or an absconding move -- an abstract
## colony-strength number, not a literal bee headcount, the same
## abstraction level AntColony._population already sits at.
##
## Doubled from 20 to 40 (requested live: "minimum / starting beehive size
## should be double of current") -- a bigger, more established-looking
## colony from the moment a hive is first founded or re-founded.
const STARTING_POPULATION := 40.0

## Kept equal to STARTING_POPULATION for the identical reason
## AntPopulationModel.BASE_CAPACITY is: a freshly-founded hive must never
## read as already above its own unobserved capacity ceiling, or
## PopulationModel.step would read it as overcrowded and start shrinking
## it back down before a player ever sees it settle.
const BASE_CAPACITY := 40.0

## How much extra capacity a consistently well-fed hive can support, as a
## multiple of BASE_CAPACITY, at recent_forage_success == 1.0 (an
## unbroken recent run of successful nectar trips). A hive that keeps
## finding forage genuinely supports more bees than one that keeps
## coming home empty -- the real mechanism the grounding names, not an
## invented one.
const FOOD_CAPACITY_BONUS := 1.0

## The ceiling capacity() can ever produce -- FOOD_CAPACITY_BONUS maxed
## out. What BeeColony.growth_fraction_at (and so a hive's own
## growth-stage art frame) normalizes population against, computed from
## the same constant capacity() itself uses rather than a second,
## independently-chosen number that could silently drift from the real
## ceiling.
const MAX_REFERENCE_POPULATION := BASE_CAPACITY * (1.0 + FOOD_CAPACITY_BONUS)

## How much a single bee draws from its own hive's stored honey reserve
## per simulated day (see BeeColony.advance/honey_stored_at). Defined as
## exactly 1.0 so "one honey unit" IS "one bee's daily ration" -- the
## identical unit choice AntPopulationModel.FOOD_PER_ANT_PER_DAY already
## makes for ants.
const HONEY_PER_BEE_PER_DAY := 1.0

## Days of reserve, at the CURRENT population's own upkeep rate, that
## counts as "secure" -- BeeColony.honey_availability_fraction reads 1.0
## once honey_stored_at reaches this many days' worth of upkeep. Mirrors
## AntPopulationModel.FOOD_BUFFER_DAYS exactly: a modest few-day buffer,
## real enough to ride out an ordinary short dry spell, not a hoard so
## large the constraint this whole mechanism exists for could never
## actually bite.
const HONEY_BUFFER_DAYS := 3.0

var _population_model := PopulationModel.new(GROWTH_RATE_PER_DAY)


## `recent_forage_success` is a [0, 1] fraction (see
## BeeColony.record_forage_result) -- 0 for a hive that keeps coming home
## empty, 1 for one that keeps finding nectar. Out-of-range input is
## clamped rather than trusted, since the caller's own EMA math could in
## principle drift a hair outside [0, 1] through floating-point
## accumulation.
func capacity(recent_forage_success: float) -> float:
	return BASE_CAPACITY * (1.0 + FOOD_CAPACITY_BONUS * clampf(recent_forage_success, 0.0, 1.0))


func step(population: float, carrying_capacity: float, delta_days: float) -> float:
	return _population_model.step(population, carrying_capacity, delta_days)
