extends RefCounted

## docs/concept/timber_construction.md's "Deciding what to build, and who
## builds it" section's own "Spare capacity: a real derived number, the same
## style SettlementState.carrying_capacity already uses" paragraph.
##
## `household_count_for_settlement(settlement_id)` (already real, see
## EarthChunkManager) minus however many of those households are currently
## needed for a real survival occupation -- farmer/hunter/fisher, the
## subset of NpcProduction.PRODUCER_ITEM_BY_OCCUPATION that feeds the
## settlement's own food stock, which SettlementState.carrying_capacity
## itself already reads -- is the real spare count. Zero or negative spare
## capacity means no Builder exists right now: construction is a genuine
## luxury of a settlement with room to grow, never a competing priority
## against the survival occupations carrying_capacity itself depends on.
##
## `household_occupations` is the SAME household_id -> occupation shape
## EarthChunkManager._occupation_of_household/production_shortfall_quests_
## for_settlement already build (a household with no real/known occupation
## is simply absent from this Dictionary, per that shape's own convention)
## -- this module invents no second shape, it only counts against it.
## `household_count` is passed separately (rather than re-derived from
## household_occupations.size()) because that Dictionary may omit a real
## household whose occupation is unknown/unmapped; the total household
## count is still real and still counts toward capacity, it is simply never
## subtracted as survival-occupied.
##
## Pure, static-function module, the same shape ConstructionStartHysteresis/
## SettlementState already use -- no stored state, explicit dependencies in.

const NpcProduction = preload("res://src/world/npc_production.gd")


## `household_occupations`: household_id -> occupation (the real subset that
## HAS a known occupation -- see this file's own doc comment). Reads the
## REAL survival subset straight off NpcProduction.PRODUCER_ITEM_BY_
## OCCUPATION's own keys rather than a second, hand-maintained
## ["farmer", "hunter", "fisher"] list that could silently drift from it.
static func for_settlement(household_count: int, household_occupations: Dictionary) -> int:
	var survival_count := 0
	for household_id in household_occupations:
		var occupation: String = household_occupations[household_id]
		if NpcProduction.PRODUCER_ITEM_BY_OCCUPATION.has(occupation):
			survival_count += 1
	return maxi(0, household_count - survival_count)
