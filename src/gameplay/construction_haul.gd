extends RefCounted

## What a builder has in his arms on each leg of the round between the
## village store and the site he is raising (docs/concept/building.md, "And
## he carries the material"). Asked for directly: *"the builders should
## carry materials to the site"*.
##
## The pure half of that round: ConstructionWorkerMarker walks the legs and
## owns WHERE the store is; this owns WHAT is being carried and WHEN there
## is nothing left to fetch -- the same split LogisticsMarker and
## LogisticsBehavior already keep, and for the same reason: a decision with
## no scene tree in it is a decision that can be tested on its own.
##
## Every number here is read off a real project rather than authored. A
## project's `reserved_material` is material that has ALREADY left
## VillageMarket.stock (SettlementConstruction.try_start draws the recipe's
## inputs down the moment the project starts) -- so this is not a second
## ledger deciding what a building costs, it is the pile that purchase
## already made, being moved from where the settlement keeps it to where
## the building is going up.

## How much one man carries in one trip. Not a number somebody liked: it is
## what makes a real cottage a handful of journeys rather than one (in
## which case the material may as well teleport with a walk attached) or
## fifty (in which case he never lifts the mallet). Pinned against the REAL
## catalog costs by test_a_real_cottage_is_a_handful_of_trips, so a
## rebalance of what a cottage costs is caught there rather than quietly
## changing how a village looks.
##
## A hand-cart's own load (LogisticsMarker.CARRY_CAPACITY) is the same size
## by coincidence of arithmetic, not by sharing: a porter's wagon and a
## builder's arms are different facts and are free to drift apart.
const CARRY_LOAD := 4.0

## Below this, a remainder is not worth a journey -- it is float dust left
## by repeated subtraction, not material.
const CARRIED_EPSILON := 0.0001


## item_id -> how much of it is still at the store, for every item that has
## any left. Reserved minus delivered, floored at nothing.
static func outstanding(reserved_material: Dictionary, delivered: Dictionary) -> Dictionary:
	var left := {}
	for item_id in reserved_material:
		var remaining := float(reserved_material[item_id]) - float(delivered.get(item_id, 0.0))
		if remaining > CARRIED_EPSILON:
			left[str(item_id)] = remaining
	return left


## The next load as {"item_id": String, "count": float}, or {} when
## everything the project reserved is already standing on the site.
##
## The item with the most still outstanding goes first -- the bulk of the
## pile moves first, the way a real site is stocked -- and the last trip
## for an item carries only the remainder rather than rounding a load up
## out of nothing. Ties break on the item id so that two equal piles are
## fetched in the same order on every reload, the same determinism every
## other seeded thing in this project is held to.
static func next_load(reserved_material: Dictionary, delivered: Dictionary) -> Dictionary:
	var left := outstanding(reserved_material, delivered)
	if left.is_empty():
		return {}
	var item_ids: Array = left.keys()
	item_ids.sort()
	var chosen: String = item_ids[0]
	for item_id in item_ids:
		if float(left[item_id]) > float(left[chosen]):
			chosen = item_id
	return {"item_id": chosen, "count": minf(CARRY_LOAD, float(left[chosen]))}


## How many journeys the whole reservation is worth. Order-independent:
## every trip empties one item by a whole CARRY_LOAD or by whatever is
## left, so the total is the same however the piles interleave.
static func trips_required(reserved_material: Dictionary) -> int:
	var trips := 0
	for item_id in reserved_material:
		var amount := float(reserved_material[item_id])
		if amount > CARRIED_EPSILON:
			trips += int(ceil(amount / CARRY_LOAD))
	return trips
