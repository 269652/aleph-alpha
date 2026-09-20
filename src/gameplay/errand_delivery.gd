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


## The give button, read straight off the dialogue frame DialogueContext
## already builds (docs/concept/errands.md, "The verb, at the villager's
## door"). The villager who says "I could use three more rock"
## (DialogueTopic's household_ask beat, from this same frame's
## shortfall_missing) and the button that hands them over therefore read
## the same state -- they cannot disagree.
##
## Returns {available, label, reason, given, household_id, settlement_id}.
## `available` false always carries a `reason` that names who needs what,
## because a refusal in this game is a sentence about the world and not a
## dead button (the same rule docs/concept/hud.md states for prompts).
##
## A frame with no settlement id is refused rather than half-performed:
## there is no market to add the stock to, and taking the goods anyway
## would be exactly the half-delivery pillar 2 forbids.
static func offer_from_frame(frame: Dictionary) -> Dictionary:
	var missing: Array = frame.get("shortfall_missing", [])
	var carried: Dictionary = frame.get("player_carrying", {})
	var who := String(frame.get("npc_name", "They"))
	var household_id := String(frame.get("household_id", ""))
	var settlement_id := String(frame.get("settlement_id", ""))
	var offer := {
		"available": false,
		"label": "",
		"reason": "",
		"given": [],
		"household_id": household_id,
		"settlement_id": settlement_id,
	}
	if missing.is_empty():
		offer["reason"] = "%s needs nothing you are carrying." % who
		return offer

	var given := deliverable_for(missing, carried)
	if given.is_empty():
		offer["reason"] = "%s needs %s; you carry none." % [who, _needed_phrase(missing)]
		return offer
	if settlement_id == "" or household_id == "":
		offer["reason"] = "%s keeps no household stores here." % who
		return offer

	offer["available"] = true
	offer["given"] = given
	offer["label"] = "Give %s" % _given_phrase(given)
	return offer


## "3 rock" / "3 rock and 1 wood" / "3 rock, 1 wood and 2 clay" -- the
## count first, because the count is what the player is deciding about.
static func _given_phrase(given: Array) -> String:
	var parts: Array[String] = []
	for entry in given:
		parts.append("%d %s" % [int(entry["count"]), _item_word(String(entry["item_id"]))])
	return _join_plainly(parts)


## What the household is short of, for a refusal that names it.
static func _needed_phrase(missing: Array) -> String:
	var parts: Array[String] = []
	for entry in missing:
		parts.append("%d %s" % [int(entry.get("need", 0)), _item_word(String(entry.get("item_id", "")))])
	return _join_plainly(parts)


static func _join_plainly(parts: Array[String]) -> String:
	if parts.is_empty():
		return ""
	if parts.size() == 1:
		return parts[0]
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[-1]]


## An item id as a villager would say it: "plant_fibre" -> "plant fibre".
## Deliberately NOT an ItemCatalog lookup -- this module stays pure, and a
## shortfall names recipe inputs that are catalog ids by construction.
static func _item_word(item_id: String) -> String:
	return item_id.replace("_", " ")


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
