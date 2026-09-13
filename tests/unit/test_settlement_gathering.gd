extends GutTest

## SettlementGathering (docs/concept/milling_and_baking.md, "Where the wood
## and stone come from"): a settlement's spare hands gather building
## material into its own persisted Market over time -- the construction
## analogue of SettlementGranary's food gathering, and the reason a village
## can afford to raise a Farm at all (nothing else ever puts wood, stone or
## fibre into the emergence Market in live play). Pure: a rate per spare
## household per day, a sub-unit carry between steps, whole units out.

const SettlementGathering = preload("res://src/emergence/settlement_gathering.gd")
const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")


func test_one_spare_household_gathers_exactly_the_pinned_daily_amounts_over_a_day():
	var result: Dictionary = SettlementGathering.material_delta(1, ConstructionCatchup.SECONDS_PER_DAY, {})
	var delta: Dictionary = result["stock_delta"]
	assert_eq(delta["wood"], int(SettlementGathering.WOOD_PER_SPARE_HOUSEHOLD_PER_DAY))
	assert_eq(delta["stone"], int(SettlementGathering.STONE_PER_SPARE_HOUSEHOLD_PER_DAY))
	assert_eq(delta["plant_fibre"], int(SettlementGathering.PLANT_FIBRE_PER_SPARE_HOUSEHOLD_PER_DAY))


func test_the_daily_rates_are_whole_positive_units_with_wood_the_most_plentiful():
	assert_gt(SettlementGathering.WOOD_PER_SPARE_HOUSEHOLD_PER_DAY, SettlementGathering.STONE_PER_SPARE_HOUSEHOLD_PER_DAY,
		"firewood is split by the armful; fieldstone is picked one at a time")
	assert_gt(SettlementGathering.STONE_PER_SPARE_HOUSEHOLD_PER_DAY, 0.0)
	assert_gt(SettlementGathering.PLANT_FIBRE_PER_SPARE_HOUSEHOLD_PER_DAY, 0.0)


func test_no_spare_hands_gather_nothing():
	var result: Dictionary = SettlementGathering.material_delta(0, ConstructionCatchup.SECONDS_PER_DAY, {})
	assert_eq(result["stock_delta"], {})


func test_sub_unit_gathering_is_carried_into_the_next_step_not_lost():
	# A short step gathers less than one whole unit of anything.
	var short_step := ConstructionCatchup.SECONDS_PER_DAY / 100.0
	var first: Dictionary = SettlementGathering.material_delta(1, short_step, {})
	assert_eq(first["stock_delta"], {}, "nothing whole yet")
	var carry: Dictionary = first["carry"]
	assert_gt(carry.get("wood", 0.0), 0.0, "...but the work done is carried")

	# Enough short steps add up to the same whole units one long step gives.
	var total := 0
	for i in 100:
		var step: Dictionary = SettlementGathering.material_delta(1, short_step, carry)
		carry = step["carry"]
		total += step["stock_delta"].get("wood", 0)
	assert_eq(total + first["stock_delta"].get("wood", 0), int(SettlementGathering.WOOD_PER_SPARE_HOUSEHOLD_PER_DAY))


func test_more_spare_households_gather_proportionally_more():
	var one: Dictionary = SettlementGathering.material_delta(1, ConstructionCatchup.SECONDS_PER_DAY, {})
	var three: Dictionary = SettlementGathering.material_delta(3, ConstructionCatchup.SECONDS_PER_DAY, {})
	assert_eq(three["stock_delta"]["wood"], 3 * one["stock_delta"]["wood"])


func test_material_delta_never_mutates_the_carry_it_was_given():
	var carry := {"wood": 0.5}
	SettlementGathering.material_delta(1, ConstructionCatchup.SECONDS_PER_DAY, carry)
	assert_eq(carry, {"wood": 0.5})
