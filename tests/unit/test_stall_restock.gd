extends GutTest

## StallRestock: the leg that was missing from the food chain.
##
## docs/concept/milling_and_baking.md has carried this as open work in its
## own words -- *"Three food containers, one eater. A villager now eats from
## the stall, the persisted Market and the shelves alike, but nothing ever
## moves food between them."*
##
## Measured (tools/probe_food_containers.gd) on a real village, every
## container printed separately over a 600-second watch:
##
##     seconds farmhouse warehouse    STALL  ledger  hands  carts
##           0         0         0        0       0      0      0
##         100         5         0        0       0      0     12
##         200        15        12        9       0      0      2
##         300         3        16        0       0      0      2
##         400        23        13        0       0      0      2
##         500        22         9        0       0      0      8
##
## The chain works right up to the store: a farmhouse fills, a carter's
## round empties it onto a cart, the cart empties into the warehouse. And
## the STALL -- the thing VillageMarket.buy_meal actually sells from -- is
## empty at every sample but one.
##
## Pure and static, numbers in and numbers out, the same shape
## SettlementSurplus and MerchantVisit already keep: the caller moves the
## goods.

const StallRestock = preload("res://src/emergence/stall_restock.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")

const FOOD_IDS := ["bread", "herb"]


## A stall holds a DAY'S TRADE, derived rather than picked:
## SettlementState.FOOD_PER_HOUSEHOLD is what one household really eats in
## a day, and it is already pinned to the hunger clock by its own test.
func test_a_stall_holds_one_days_eating_for_the_village():
	assert_almost_eq(
		StallRestock.target_units(10), 10.0 * SettlementState.FOOD_PER_HOUSEHOLD, 0.0001
	)


func test_a_village_with_nobody_in_it_wants_no_stall_at_all():
	assert_eq(StallRestock.target_units(0), 0.0)


## An empty stall in a stocked village draws a day's food off the shelf.
func test_an_empty_stall_is_filled_from_the_store():
	var drawn: Dictionary = StallRestock.draw(0.0, 10, {"bread": 100.0}, FOOD_IDS)
	var moved := 0.0
	for item_id in drawn:
		moved += float(drawn[item_id])
	assert_almost_eq(moved, StallRestock.target_units(10), 0.0001)


## ...and a stall that already holds its day's trade draws nothing. A shop
## window is topped up, not refilled from scratch.
func test_a_stocked_stall_draws_nothing():
	var drawn: Dictionary = StallRestock.draw(
		StallRestock.target_units(10), 10, {"bread": 100.0}, FOOD_IDS
	)
	assert_eq(drawn, {}, "the stall is already holding its day")


## Only the shortfall, never the whole target again -- or a stall would
## pull the store empty one step at a time.
func test_a_half_empty_stall_draws_only_what_it_is_short():
	var target := StallRestock.target_units(10)
	var drawn: Dictionary = StallRestock.draw(target - 3.0, 10, {"bread": 100.0}, FOOD_IDS)
	var moved := 0.0
	for item_id in drawn:
		moved += float(drawn[item_id])
	assert_almost_eq(moved, 3.0, 0.0001)


## NOTHING IS CONJURED: a store that holds two units sends two, not a day's
## worth. Every unit on the stall left the shelf it came from.
func test_a_stall_never_draws_food_the_store_does_not_have():
	var drawn: Dictionary = StallRestock.draw(0.0, 10, {"bread": 2.0}, FOOD_IDS)
	assert_almost_eq(float(drawn.get("bread", 0.0)), 2.0, 0.0001)
	var moved := 0.0
	for item_id in drawn:
		moved += float(drawn[item_id])
	assert_almost_eq(moved, 2.0, 0.0001, "a village cannot sell what it never grew")


## A store of timber stocks no stall. Nobody eats a plank.
func test_a_store_holding_no_food_fills_no_stall():
	assert_eq(StallRestock.draw(0.0, 10, {"plank": 50.0, "stone": 9.0}, FOOD_IDS), {})


## Spread across what the store really has, in sorted id order so two
## identical villages restock identically rather than by Dictionary order.
func test_the_draw_is_spread_across_the_food_the_store_really_holds():
	var drawn: Dictionary = StallRestock.draw(0.0, 10, {"herb": 100.0, "bread": 4.0}, FOOD_IDS)
	assert_almost_eq(float(drawn.get("bread", 0.0)), 4.0, 0.0001, "all of the bread first")
	var moved := 0.0
	for item_id in drawn:
		moved += float(drawn[item_id])
	assert_almost_eq(moved, StallRestock.target_units(10), 0.0001, "and the rest in herb")


# -- and the delivery that was counted twice ------------------------------
#
# village_warehouse.md's Mechanism 7 states the rule this broke: *"The
# carter's arrival at the store is what credits the village's sellable
# stock. ONE credit, at the moment the goods really get there -- so nothing
# is counted twice, and the market's numbers describe a pile that exists."*
#
# It is counted twice now, for two reasons that landed after it was
# written. `_unload_the_cart` puts the load on the store's shelf AND calls
# `record_delivered_goods`; the shelf was invisible to every food reading
# when that was written, and milling_and_baking.md's "Food that counts"
# taught SettlementFood to count shelves. Then hauling was switched on, so
# `_stock` routes that second credit into the carter's own HANDS, which
# `deliver_load` later empties onto the stall.
#
# So N units delivered became N on the shelf plus N on the stall. That is
# the brief 9 in the measurement above: not the chain working, but food
# being invented.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")


## The function's CODE, with its comment lines dropped -- the question is
## what it calls, not what it talks about, and the comment explaining a
## removed call would otherwise read as the call itself.
func _body(function_name: String, path: String) -> String:
	var source := FileAccess.get_file_as_string(path)
	var start := source.find("func %s" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var whole := source.substr(start, source.find("\nfunc ", start + 1) - start)
	var code: Array = []
	for line in whole.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		code.append(line)
	return "\n".join(code)


## The goods go on the shelf, and are not credited a second time anywhere.
func test_the_carters_arrival_credits_the_shelf_and_nothing_else():
	var body := _body("_unload_the_cart", "res://src/rendering/npc_marker.gd")
	assert_true(
		body.contains("deposit_to_structure_at"),
		"the premise: the load still reaches the store: %s" % body
	)
	assert_false(
		body.contains("record_delivered_goods"),
		"the same units were put on the shelf AND credited again: %s" % body
	)


## ...and the second credit has no way back in: a function that stocks a
## village for goods already standing in its own store is the bug, not a
## helper the bug used.
func test_nothing_stocks_a_village_for_goods_its_store_already_holds():
	var source := FileAccess.get_file_as_string("res://src/world/npc_economy.gd")
	assert_false(
		source.contains("func record_delivered_goods"),
		"the double credit is gone, not merely unused"
	)


## And the stall really is restocked from the store, on the settlement step.
func test_the_settlement_step_keeps_the_stall_stocked():
	var source := FileAccess.get_file_as_string("res://src/world/earth_chunk_manager.gd")
	assert_true(
		source.contains("StallRestock.draw("),
		"nothing moves food from the store to the stall"
	)
