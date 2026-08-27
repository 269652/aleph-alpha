extends GutTest

## SettlementSpareCapacity: docs/concept/timber_construction.md's "Deciding
## what to build, and who builds it" section's own "Spare capacity: a real
## derived number, the same style SettlementState.carrying_capacity already
## uses" paragraph -- household_count_for_settlement (already real) minus
## however many of those households are currently needed for a real survival
## occupation (farmer/hunter/fisher -- the subset of NpcProduction.
## PRODUCER_ITEM_BY_OCCUPATION that feeds the settlement's own food stock).
## Zero or negative clamps to zero -- construction is a genuine luxury of a
## settlement with room to grow, never a competing priority against the
## survival occupations carrying_capacity itself depends on.

const SettlementSpareCapacity = preload("res://src/emergence/settlement_spare_capacity.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")


# -- the formula itself -------------------------------------------------------

func test_spare_capacity_is_household_count_minus_survival_occupation_households():
	var household_occupations := {
		"household:1": "farmer",
		"household:2": "guard",
		"household:3": "merchant",
	}
	# 3 households total, 1 of them (the farmer) is a survival occupation ->
	# 2 spare.
	assert_eq(SettlementSpareCapacity.for_settlement(3, household_occupations), 2)


func test_every_survival_occupation_household_is_subtracted():
	var household_occupations := {
		"household:1": "farmer",
		"household:2": "hunter",
		"household:3": "fisher",
	}
	assert_eq(SettlementSpareCapacity.for_settlement(3, household_occupations), 0)


func test_a_household_with_no_occupation_entry_is_not_treated_as_survival():
	# household_occupations mirrors _occupation_of_household/production_
	# shortfall_quests_for_settlement's own shape: it may omit a household
	# whose occupation is unknown/"" -- household_count (the total) still
	# counts it as a real household with no bearing on the survival subtraction.
	var household_occupations := {"household:1": "guard"}
	assert_eq(SettlementSpareCapacity.for_settlement(2, household_occupations), 2)


# -- clamped at zero, never negative -----------------------------------------

func test_spare_capacity_never_goes_negative():
	var household_occupations := {"household:1": "farmer", "household:2": "hunter"}
	# household_count undercounts relative to the survival occupations map
	# (should not happen in real play, but the clamp must hold regardless).
	assert_eq(SettlementSpareCapacity.for_settlement(1, household_occupations), 0)


func test_spare_capacity_is_zero_for_an_empty_settlement():
	assert_eq(SettlementSpareCapacity.for_settlement(0, {}), 0)


# -- pinned against the REAL PRODUCER_ITEM_BY_OCCUPATION survival subset -----

## The exact real occupation id strings read from NpcProduction's own const
## -- not guessed/duplicated here -- so a future change to which occupations
## are "survival" (e.g. a new producer role) is picked up automatically
## rather than silently drifting from this module's own hardcoded subset.
func test_survival_occupations_are_read_from_the_real_producer_item_map():
	for occupation in NpcProduction.PRODUCER_ITEM_BY_OCCUPATION.keys():
		var household_occupations := {"household:1": occupation}
		assert_eq(
			SettlementSpareCapacity.for_settlement(1, household_occupations), 0,
			"%s should be counted as a real survival occupation" % occupation
		)


## A non-producer occupation (e.g. "guard", "merchant", "blacksmith",
## "herbalist", "nurse") is NOT survival -- it does not feed the settlement's
## own food stock, so it is never subtracted from spare capacity.
func test_non_producer_occupations_are_not_counted_as_survival():
	var household_occupations := {"household:1": "guard"}
	assert_eq(SettlementSpareCapacity.for_settlement(1, household_occupations), 1)
