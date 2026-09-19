extends RefCounted

## The Bollerwagen's own load -- see docs/concept/village_warehouse.md,
## Mechanism 5.
##
## Asked directly: *"it should be so that the ressources are actually loaded
## inside the wagon which has an inventory; so if the worker leaves it
## somewhere it's actually full of ressources"*. That is the whole design:
## the goods are a real item_id -> count store that lives on the CART, not
## bookkeeping held on the person pulling it. A cart standing in a field is a
## cart with the timber still in it.
##
## Pure, static-function module, the same shape SettlementReserve and
## SettlementSpareCapacity already use: the load goes in, a NEW load comes
## back, and nothing here mutates what it was shown.

const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")

## How much a cart holds, in whole units.
##
## Six of the porter's own armfuls (LogisticsMarker.CARRY_CAPACITY). Neither
## the six nor the total is the claim -- there is no real cartwright's
## measure to derive one from, the same honesty SettlementTier.
## TOWN_HOUSEHOLDS' own doc comment states. What IS pinned
## (test_cart_load.gd) are two relationships against real quantities this
## game already holds: a cart carries strictly more than a porter's arms do,
## or the round trip is not worth making; and it carries at least the 12
## wood the growth ladder's cheapest rung costs, because a cart that could
## not bring home a whole small house's timber in one trip would not be
## worth pulling.
const CAPACITY := LogisticsMarker.CARRY_CAPACITY * 6


## Everything on the cart, in whole units.
static func total(stock: Dictionary) -> int:
	var carried := 0
	for item_id in stock:
		carried += int(stock[item_id])
	return carried


## How much more this cart will take.
static func room_left(stock: Dictionary) -> int:
	return maxi(CAPACITY - total(stock), 0)


## Loads up to `count` of `item_id`: `{"loaded": what really went on,
## "stock": the cart's new load}`.
##
## What will not fit is LEFT, never destroyed -- the caller has only moved
## `loaded` many units off the shelf, so a full cart leaves the rest waiting
## rather than swallowing it.
static func load_into(stock: Dictionary, item_id: String, count: int) -> Dictionary:
	var loaded: int = mini(maxi(count, 0), room_left(stock))
	if item_id == "" or loaded <= 0:
		return {"loaded": 0, "stock": stock.duplicate()}
	var next := stock.duplicate()
	next[item_id] = int(next.get(item_id, 0)) + loaded
	return {"loaded": loaded, "stock": next}
