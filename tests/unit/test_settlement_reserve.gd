extends GutTest

## What a village is SAVING FOR, and what that stops it spending (see
## docs/concept/village_growth.md, "What a village is saving for").
##
## One rule, two callers: the traveling merchant may not buy it, and the
## village's own production step may not saw it. Pure -- stock and reserve
## are passed in, so nothing here needs a settlement or a market.

const SettlementReserve = preload("res://src/emergence/settlement_reserve.gd")


func test_stock_above_the_reserve_is_surplus():
	assert_eq(SettlementReserve.surplus_of({"wood": 20.0}, {"wood": 12}, "wood"), 8)


func test_stock_at_the_reserve_is_not_surplus():
	assert_eq(SettlementReserve.surplus_of({"wood": 12.0}, {"wood": 12}, "wood"), 0)


## A village short of what it needs has no surplus -- it does not owe
## anybody units.
func test_being_short_is_never_a_negative_surplus():
	assert_eq(SettlementReserve.surplus_of({"wood": 3.0}, {"wood": 12}, "wood"), 0)


func test_a_good_nobody_is_saving_for_is_all_surplus():
	assert_eq(SettlementReserve.surplus_of({"stone": 40.0}, {"wood": 12}, "stone"), 40)


# -- what it stops being spent ----------------------------------------------

## The sawyer's own recipe: 3 wood to a beam. A village saving twelve wood
## for its next house may not saw three of them off the pile.
func test_a_recipe_may_not_eat_what_the_village_is_saving_for():
	var inputs: Array = [{"item_id": "wood", "count": 3}]
	assert_false(SettlementReserve.can_spend(inputs, {"wood": 10.0}, {"wood": 12}))


func test_a_recipe_may_run_on_what_is_really_spare():
	var inputs: Array = [{"item_id": "wood", "count": 3}]
	assert_true(SettlementReserve.can_spend(inputs, {"wood": 20.0}, {"wood": 12}))


## Exactly enough spare is enough: the reserve is what is kept, not a
## cushion on top of it.
func test_exactly_enough_spare_is_enough():
	var inputs: Array = [{"item_id": "wood", "count": 3}]
	assert_true(SettlementReserve.can_spend(inputs, {"wood": 15.0}, {"wood": 12}))


## Every input has to clear: a recipe blocked on one of its materials is
## blocked, however much of the others the village has.
func test_one_reserved_input_blocks_the_whole_recipe():
	var inputs: Array = [{"item_id": "wood", "count": 3}, {"item_id": "stone", "count": 1}]
	assert_false(SettlementReserve.can_spend(inputs, {"wood": 10.0, "stone": 40.0}, {"wood": 12}))


func test_a_village_saving_for_nothing_may_spend_anything():
	var inputs: Array = [{"item_id": "wood", "count": 3}]
	assert_true(SettlementReserve.can_spend(inputs, {"wood": 3.0}, {}))


func test_a_recipe_with_no_inputs_is_always_affordable():
	assert_true(SettlementReserve.can_spend([], {}, {"wood": 12}))
