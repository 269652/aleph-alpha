extends RefCounted
## Handing a villager the thing their household is actually short of
## (docs/concept/errands.md) -- the one transfer that turns every
## production-shortfall projection in this game into something a player can
## act on.
##
## Pure: no market object, no player, no world. Its inputs are the
## projection's OWN `missing` array (exactly what
## Quest.production_shortfall_quests_for puts in a quest's "missing" field,
## [{"item_id": String, "need": int}, ...]), a plain {item_id: count} of
## what the player carries, the household purse's balance, and a price
## lookup Callable. Its output is the WHOLE transaction, decided before
## anything mutates -- the same shape village_wages.gd's payout planning
## takes, and for the same reason: a half-delivery that takes the rock and
## pays nothing is the kind of bug that makes a player stop trusting a verb
## for ever.
##
## The caller (World, at the villager's door) then performs exactly what
## this describes: Inventory.remove, Market.add_stock on the SAME market
## object Quest reads, Wallet transfer, a witnessed Event. Nothing here
## knows about any of that.

## The floor a unit of help is worth, in whole coins, however cheap the
## good. Without it a village that has plenty of straw values four straw
## at nothing and the player is paid zero for a real delivery -- which
## reads as the verb being broken rather than as the straw being cheap.
## Test-pinned (docs/concept/errands.md, "what it is worth"), never an
## eyeballed comment.
const MIN_COIN_PER_UNIT := 1


## Per missing input, the units the player could really hand over:
## min(need, carried). An input the player carries none of is DROPPED
## rather than listed as a zero, so an empty result is the verb's own
## availability test -- "nothing to give here" -- and the give button can
## say why instead of standing dead.
##
## Order follows `missing`, which follows the recipe's own input order, so
## the same shortfall always reads the same way to the player.
static func deliverable_for(missing: Array, carried: Dictionary) -> Array:
	var given: Array = []
	for entry in missing:
		var item_id := String(entry.get("item_id", ""))
		var need := int(entry.get("need", 0))
		var count: int = mini(need, int(carried.get(item_id, 0)))
		if count > 0:
			given.append({"item_id": item_id, "count": count})
	return given


## The whole transaction: what moves, what it is worth, what the household
## can actually pay for it, what it still owes, and whether the shortage is
## over afterwards.
##
## `purse_balance` is the household's own real Wallet balance -- the same
## finite purse wages come out of (docs/concept/village_economy_balance.md),
## so a village that cannot pay does NOT refuse the goods and does NOT
## conjure coins: it takes the delivery, pays every coin it holds, and
## carries the remainder as a debt the dialogue can speak to. Value is
## always conserved: paid + debt == value.
##
## `price_for` is the settlement's own scarcity price
## (Market.price_for) -- the only price model here, so supplying something
## a village is desperate for pays better with nothing invented for the
## player.
static func settle(
	missing: Array, carried: Dictionary, purse_balance: int, price_for: Callable
) -> Dictionary:
	var given := deliverable_for(missing, carried)
	var units := 0
	var value := 0
	for entry in given:
		var count := int(entry["count"])
		units += count
		value += count * _coin_value_of(String(entry["item_id"]), price_for)
	var paid: int = clampi(mini(value, purse_balance), 0, value)
	return {
		"given": given,
		"units": units,
		"value": value,
		"paid": paid,
		"debt": value - paid,
		"clears": _covers(missing, carried),
	}


## What one unit of `item_id` is worth in whole coins at this village's own
## price, never below the pinned floor.
static func _coin_value_of(item_id: String, price_for: Callable) -> int:
	var price := 0.0
	if price_for.is_valid():
		price = float(price_for.call(item_id))
	return maxi(MIN_COIN_PER_UNIT, int(round(price)))


## Whether this delivery really ends the shortage: EVERY missing input
## fully covered by what the player carries. Partial help is still help
## (the goods move and are paid for), but the projection will still report
## the shortfall afterwards -- because it is still short, which is the
## honest answer and the one Quest's own re-run will give.
static func _covers(missing: Array, carried: Dictionary) -> bool:
	for entry in missing:
		var need := int(entry.get("need", 0))
		if int(carried.get(String(entry.get("item_id", "")), 0)) < need:
			return false
	return true
