extends RefCounted

## Every container a settlement really keeps goods in, as ONE stock
## (docs/concept/traveling_merchants.md, "A merchant buys the whole village,
## not one of its cupboards").
##
## Reported with the town panel open: *"The village produces way too much
## food and the NPCs don't have an income"* -- Food feeds 387 of 16, Gold 1,
## worst need income. That is ONE fault, not two. A settlement keeps goods
## in more than one place -- VillageMarket.stock, and every structure's own
## StructureStock -- and the merchant, the only thing that turns goods into
## gold, could see only the first. SettlementFood was taught to count the
## shelves; the merchant never was. So a village hauls its whole harvest
## into the warehouse, which is exactly what the carter's round is for, and
## thereby puts it beyond the reach of its own income.
##
## Pure and static: dictionaries in, dictionaries out, never a mutation of
## what it was shown. The caller moves the goods -- the same division
## MerchantVisit itself keeps, so a sale that cannot be completed has
## changed nothing.

## Every view added up, item_id -> units, for something that needs to price
## a settlement's whole holding.
##
## A view is any `item_id -> units` mapping: VillageMarket.stock (floats) or
## a StructureStock.stock (ints) alike. Counts at or below zero contribute
## nothing rather than subtracting from another container's real goods -- an
## empty shelf must never eat the market's fish.
static func combined(views: Array) -> Dictionary:
	var total: Dictionary = {}
	for view in views:
		for item_id in (view as Dictionary):
			var units := float((view as Dictionary)[item_id])
			if units <= 0.0:
				continue
			total[item_id] = float(total.get(item_id, 0.0)) + units
	return total


## How much of `bought` to take out of each view: one entry per view, in the
## same order, so a caller maps each back to the container it came from
## without needing a second key.
##
## Drawn in VIEW ORDER, and the caller passes the market first on purpose:
## it is the abstract ledger a village trades out of anyway, while a
## warehouse shelf is a real building the player can walk up to and open, so
## emptying the ledger before the shelf means what the player can SEE is the
## last thing to go.
##
## Never draws a container below empty. A sale bigger than the village holds
## takes what is there and no more -- the caller removes exactly what the
## plan says, and a shelf that cannot cover it must not be asked to.
static func allocate(bought: Dictionary, views: Array) -> Array:
	var plan: Array = []
	for _view in views:
		plan.append({})
	# Item order is the caller's `bought`, which MerchantVisit already builds
	# deterministically (dearest first, then item id), so the plan inherits
	# that determinism rather than adding a sort of its own.
	for item_id in bought:
		var owed := float(bought[item_id])
		if owed <= 0.0:
			continue
		for index in views.size():
			if owed <= 0.0:
				break
			var held := float((views[index] as Dictionary).get(item_id, 0.0))
			if held <= 0.0:
				continue
			var take := minf(held, owed)
			(plan[index] as Dictionary)[item_id] = take
			owed -= take
	return plan


## What the village keeps for itself: `units` of food held back across
## whatever food it actually has, item_id -> whole units.
##
## traveling_merchants.md already states this rule -- "a merchant buys a
## village's SURPLUS; he does not buy the timber it cut for its own next
## house" -- and MerchantVisit's `reserved` already implements it for
## CONSTRUCTION material. Nobody was reserving what the PEOPLE eat.
##
## MEASURED (tools/probe_village_famine.gd, once the purse was finally
## being funded): purse climbing 21 -> 24 -> 25 gold with market food 0 at
## every single sample, and the village dead by t=900. The faucet worked
## perfectly; the merchant was carrying off the larder.
##
## Spread across whatever food is there rather than naming a crop, so the
## reserve does not depend on a village holding one particular thing --
## and never more of a good than really exists, so this can only ever hold
## back food that is present.
static func larder_reserve(views: Array, food_ids: Array, units: int) -> Dictionary:
	var reserve: Dictionary = {}
	if units <= 0:
		return reserve
	var available := combined(views)
	var remaining := units
	for item_id in food_ids:
		if remaining <= 0:
			break
		var held := int(floor(float(available.get(item_id, 0.0))))
		if held <= 0:
			continue
		var keep := mini(held, remaining)
		reserve[item_id] = keep
		remaining -= keep
	return reserve
