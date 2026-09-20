extends RefCounted

## docs/concept/village_growth.md mechanism 2: the ONE building a village
## owes itself next.
##
## The whole Anno-like shape of this system is here in one function. A
## village's real household count (EarthChunkManager.household_count_for_
## settlement, read back out of the persisted event graph and
## HouseholdStore -- no second population counter is introduced anywhere)
## is the ONE number the ladder consults, and the answer is one building id
## or "".
##
## Priority, highest first:
##
## 1. **A house for every household that has none.** A village shelters its
##    people before it adorns itself, so an unhoused household outranks
##    every civic and production rung however entitled the village is to
##    them. Which house is the catalog's own business (BuildingCatalog.
##    choose_house_id, keyed to the arriving villager); this module names
##    the FIRST house id so a caller with no villager in hand still gets a
##    real answer.
## 2. **The next unbuilt rung whose household threshold is met**, in LADDER
##    order -- sawmill, city hall, farmhouse, blacksmith,
##    brewery. Skipped, never re-ordered: a rung already standing is passed
##    over and the walk continues, so a village that acquired its hall out
##    of order (a player built one) still grows into the rest.
## 3. Otherwise "" -- nothing owed. A village that has everything its size
##    entitles it to simply lives.
##
## Deliberately NOT decided here: whether the village can actually build
## the thing. Hands (SettlementSpareCapacity) and material
## (SettlementConstruction.try_start's own stock hysteresis) stay exactly
## where they are, the same division CivicBuildDecision already draws for
## the hall -- this module names the target and nothing else.
##
## Static-function module with no stored state, the same shape
## SettlementTier/SettlementSpareCapacity already use. Thresholds are pinned
## by test_village_growth.gd against the ORDER they produce (a bigger
## village is entitled to strictly more), not against any one "correct"
## population -- there is no real demographic data to derive one from, the
## same honesty SettlementTier.TOWN_HOUSEHOLDS' own doc comment states.

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const CivicBuildDecision = preload("res://src/emergence/civic_build_decision.gd")

## Rung 1. Timber is the input every later rung is made of, so even a
## village of one owes itself a sawmill -- and it is the one rung sited
## away from the street, at the forest (VillageLayout.industry_plot).
const SAWMILL_MIN_HOUSEHOLDS := 1
## The warehouse used to be rung 3 here, gated at four households. It is not
## a rung any more: every village is FOUNDED with its store already standing
## (docs/concept/village_warehouse.md -- VillageLayout reserves the plot
## beside the square and VillageRenderer raises it), so there is nothing for
## a village to grow into.
##
## Removed rather than lowered to one. A threshold that is always met is a
## gate that lies to the next reader, and the rung itself would be satisfied
## before this ladder is ever consulted -- so next_building would go on
## naming a target the village already has, which is the exact bug
## present_building_ids exists to prevent.
## Rung 3. Food production: the works that let the population keep growing
## at all, and the first thing a village builds once it has a hall. (It used
## to be rung 4, behind the store; the store is founded with the village
## now, so its harvest already has a roof waiting for it.)
## The rungs below are spaced in FOUNDING ROSTERS (SettlementGenerator.
## POPULATION), not in absolute households, and that is why they moved when
## the roster did.
##
## A threshold at or below the founding roster is met the moment a village
## exists, which makes it a gate that lies to the next reader -- the exact
## reasoning that took the warehouse off this ladder entirely (see above).
## So the rungs a village needs to LIVE sit at or under one roster, and the
## specialists it grows INTO sit above it. These were spaced against a
## roster of five (5 / 7 / 9); the roster is ten, so they are spaced against
## ten. The relationship, not the numbers, is what is pinned
## (test_village_growth.gd) -- there is no real demographic data to derive a
## "correct" population per rung from, the same honesty SettlementTier.
## TOWN_HOUSEHOLDS' own doc comment states.
##
## One roster: a village feeds itself from the day it is founded.
const FARMHOUSE_MIN_HOUSEHOLDS := 10
## Rung 4. Tools, and the first rung needing stone in real quantity -- a
## village supports a full-time smith only once it is past subsistence,
## which is now past its own founding size.
const BLACKSMITH_MIN_HOUSEHOLDS := 14
## Rung 5. The one rung raised for comfort rather than survival; a village
## only builds this once everything it actually needs already stands.
const BREWERY_MIN_HOUSEHOLDS := 18

## The ladder, in the order a village walks it. The hall's own threshold is
## CivicBuildDecision's, not a second copy -- that decision is still the
## live owner of the hall, and two numbers for one rung could drift.
const LADDER_BUILDING_IDS: Array[String] = [
	"sawmill", "city_hall", "farmhouse", "blacksmith", "brewery",
]

const _MIN_HOUSEHOLDS_BY_BUILDING := {
	"sawmill": SAWMILL_MIN_HOUSEHOLDS,
	"city_hall": CivicBuildDecision.CITY_HALL_MIN_HOUSEHOLDS,
	"farmhouse": FARMHOUSE_MIN_HOUSEHOLDS,
	"blacksmith": BLACKSMITH_MIN_HOUSEHOLDS,
	"brewery": BREWERY_MIN_HOUSEHOLDS,
}


## How many households a village needs before it is entitled to
## `building_id`; 0 for anything that is not a rung of this ladder.
static func min_households_for(building_id: String) -> int:
	return _MIN_HOUSEHOLDS_BY_BUILDING.get(building_id, 0)


## The one building this village owes itself next, or "". See this file's
## own header for the full priority order. `present_building_ids` is the
## settlement's real "what already stands here" list (EarthChunkManager.
## _present_structure_ids_for_settlement_chunk) -- anything not in it is
## treated as unbuilt, which is exactly the right reading for a rung that
## burned down or was never raised.
## `spare_house_capacity` is how many places stand empty in houses that are
## already built. It defaults to 1 -- "there is already room" -- so a caller
## that does not know or care gets exactly the ladder it always got, rather
## than the lowest rung firing for everybody.
static func next_building(
	household_count: int, housed_count: int, present_building_ids: Array,
	spare_house_capacity: int = 1
) -> String:
	if household_count <= 0:
		return ""
	if housed_count < household_count:
		return BuildingCatalog.BUILDING_IDS[0]
	for building_id in LADDER_BUILDING_IDS:
		if present_building_ids.has(building_id):
			continue
		if household_count >= min_households_for(building_id):
			return building_id
	# The lowest rung: a house for nobody in particular.
	#
	# A household only moves in where a real empty house already stands
	# (VillageImmigration.arrivals), and priority 1 above only ever fires for
	# somebody who is ALREADY here with nowhere to live. So a village whose
	# people are all housed would owe itself nothing, build nothing, and
	# never have the spare roof an arrival needs -- it would stop growing for
	# good the moment it caught up with itself. Room is made first and moved
	# into afterwards.
	#
	# Below the civic and production rungs on purpose: a village finishes
	# what it already owes itself before it makes room for strangers.
	if spare_house_capacity <= 0:
		return BuildingCatalog.BUILDING_IDS[0]
	return ""


## How many DISTINCT rungs of this ladder actually stand -- the real input
## behind HouseholdWellbeing's "community" need (a village with a hall and
## a brewery is a better place to live than a bare hamlet). Counts each
## rung once however many times it appears, and ignores everything that is
## not a rung (a house, a legacy single-tile placeable).
static func standing_rungs(present_building_ids: Array) -> int:
	var seen := {}
	for building_id in present_building_ids:
		if LADDER_BUILDING_IDS.has(building_id):
			seen[building_id] = true
	return seen.size()


## standing_rungs as a share in [0, 1] -- 0 for a village with none of its
## ladder up, 1 for one with all of it.
static func ladder_share(present_building_ids: Array) -> float:
	return float(standing_rungs(present_building_ids)) / float(LADDER_BUILDING_IDS.size())
