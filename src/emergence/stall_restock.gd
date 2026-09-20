extends RefCounted

## The leg that was missing from a village's food chain: the STORE keeps
## the STALL stocked.
##
## docs/concept/milling_and_baking.md carried this as open work in its own
## words -- *"Three food containers, one eater. A villager now eats from
## the stall, the persisted Market and the shelves alike, but nothing ever
## moves food between them."* Measured (tools/probe_food_containers.gd) on
## a real village, every container printed separately:
##
##     seconds farmhouse warehouse    STALL  ledger  hands  carts
##         100         5         0        0       0      0     12
##         200        15        12        9       0      0      2
##         400        23        13        0       0      0      2
##         500        22         9        0       0      0      8
##
## The chain works right up to the store -- a farmhouse fills, a carter's
## round empties it onto a cart, the cart empties into the warehouse -- and
## the stall, the thing `VillageMarket.buy_meal` actually sells from, is
## empty at every sample but one. (That one was not the chain working: it
## was a delivery being credited twice, which is fixed alongside this.)
##
## Real-world grounding: a market stall is not a warehouse. It is the shop
## window of one, filled each morning from the store behind it and holding
## about a day's trade -- which is exactly why a village can look "out of
## bread" at the stall while its granary is full.
##
## Pure and static, numbers in and numbers out, the same shape
## SettlementSurplus and MerchantVisit already keep: the caller moves the
## goods, so a restock that cannot be completed has changed nothing.

const SettlementState = preload("res://src/emergence/settlement_state.gd")


## What a village's stall should be holding: ONE DAY'S EATING for its
## households.
##
## Derived rather than picked. `SettlementState.FOOD_PER_HOUSEHOLD` is what
## one household really eats in a day and is already pinned to the hunger
## clock by its own test, so a stall holds a day's trade by construction and
## retuning what people eat retunes the stall with it.
static func target_units(household_count: int) -> float:
	if household_count <= 0:
		return 0.0
	return float(household_count) * SettlementState.FOOD_PER_HOUSEHOLD


## What to move off the store's shelf and onto the stall: `{item_id ->
## units}`, empty when the stall is already holding its day.
##
## Only the SHORTFALL, never the whole target again -- a stall that drew a
## full day on every step would pull the store empty one step at a time.
##
## Never more of an id than the shelf really holds, and never more in total
## than is owed: every unit that reaches the stall LEFT the store, which is
## the same "nothing is conjured and nothing vanishes" rule the merchant's
## own sale keeps. `food_ids` is supplied by the caller, which is the only
## side that knows the live item catalog -- the same division that keeps
## MerchantVisit free of it.
##
## Sorted id order, so two identical villages restock identically rather
## than by Dictionary iteration.
static func draw(
	stall_food: float, household_count: int, shelf: Dictionary, food_ids: Array
) -> Dictionary:
	var owed := target_units(household_count) - maxf(stall_food, 0.0)
	if owed <= 0.0:
		return {}
	var ids: Array = []
	for item_id in food_ids:
		ids.append(String(item_id))
	ids.sort()
	var drawn := {}
	for item_id in ids:
		if owed <= 0.0:
			break
		var held := float(shelf.get(item_id, 0.0))
		if held <= 0.0:
			continue
		var take := minf(held, owed)
		drawn[item_id] = take
		owed -= take
	return drawn
