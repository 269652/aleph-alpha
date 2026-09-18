extends RefCounted

## What a village is SAVING FOR, and what that stops it spending. See
## docs/concept/village_growth.md's "What a village is saving for".
##
## A village that owes itself a building is saving for it, and nothing else
## in the village may spend that material first. One rule, two callers: the
## traveling merchant may not BUY it (MerchantVisit.purchase), and the
## village's own production step may not SAW it (EarthChunkManager.
## _step_settlement_production).
##
## Without it the growth ladder cannot be climbed at all.
## SettlementGathering is the only thing in the game that puts wood, stone
## or plant fibre into a settlement's market, and both of those callers took
## it away again before the ladder ever saw it -- the merchant because
## `wood` is on his buy list, the sawyer because `log_to_balken` turns 3
## wood into 1 beam the moment a village has three. Measured on a real
## loaded village (tools/probe_village_growth.gd): its stone climbed past 50
## while its wood never once got past 2, and a village that grew from 10
## households to 31 built not one house for any of them.
##
## The reserve itself is never decided here: the caller reads it off the
## same VillageGrowth.next_building the ladder walks and the same recipe
## that building is priced in. This module only answers what that reserve
## permits.
##
## Pure, static-function module, the same shape SettlementSpareCapacity and
## ConstructionStartHysteresis already use -- no stored state, explicit
## dependencies in.


## What is really spare of `item_id`: whole units held, less whatever the
## village is saving for. Never negative -- a village short of what it needs
## has no surplus, it does not owe anybody units.
static func surplus_of(stock: Dictionary, reserved: Dictionary, item_id: String) -> int:
	var held := int(floor(float(stock.get(item_id, 0.0))))
	return maxi(held - int(reserved.get(item_id, 0)), 0)


## Whether every one of `inputs` (a CraftingRecipeBook.recipe_inputs list:
## [{item_id, count}, ...]) can be paid for out of what is really spare.
##
## Every input has to clear: a recipe blocked on one of its materials is
## blocked, however much of the others the village has -- the same
## all-or-nothing reading SettlementConstruction.try_start already takes of
## a project's own inputs.
static func can_spend(inputs: Array, stock: Dictionary, reserved: Dictionary) -> bool:
	for input in inputs:
		if surplus_of(stock, reserved, String(input["item_id"])) < int(input["count"]):
			return false
	return true
