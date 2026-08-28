extends RefCounted

## One settlement's REAL food stock, summed across BOTH of the two unrelated
## things this project calls "the market".
##
## There are two, and they have never been added up. The persisted emergence
## Market (see market.gd/MarketStore) is what SettlementState.food_stock
## reads -- but in live play essentially nothing ever stocks it, so
## carrying_capacity comes out 0 and status_for classifies EVERY settlement
## DECLINING forever (see EarthChunkManager.step_settlements, and Governance,
## which reads that same status as legitimacy). Meanwhile the live
## VillageMarket (see village_market.gd) is where villagers really do put
## real gathered food every day (NpcProduction), really do buy their meals
## from (NpcEconomy/VillageMarket.buy_meal), and where the player really can
## sell food (Player.sell_food_to_village). That food exists; the
## classification just could not see it.
##
## So this module is the food-stock/capacity source callers should use, and
## SettlementState is deliberately left EXACTLY as it is: its food_stock
## keeps its current "the emergence Market's food" meaning for everything
## already built on it, and the two real constants it owns -- FOOD_PER_
## HOUSEHOLD and the GROWING/STABLE/DECLINING classification in status_for --
## stay the single definition of what a capacity number MEANS. Nothing about
## the rule is re-tuned or re-copied here; only the stock feeding it gets
## honest.
##
## Pure, static-function module, the same shape SettlementState and
## SettlementSpareCapacity already use -- no stored state, explicit
## dependencies in.

const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")


## Combined food-typed stock of `market` (an emergence Market, whose stock is
## whole integer units) and `village_market` (a live VillageMarket, whose
## stock is float). Either may be null -- a settlement whose chunk is not
## currently loaded has no live VillageMarket at all, and a settlement that
## has never traded may have no emergence Market entry; both are ordinary
## states, not errors, and contribute nothing rather than crashing.
##
## Both sides are filtered through the SAME real ItemCatalog category
## SettlementState.food_stock already filters on, rather than a second
## hand-maintained "which items are food" list -- a VillageMarket also holds
## construction lumber (see its own remove_stock doc comment), and beams must
## not feed anyone.
static func food_stock(market, village_market, catalog = null) -> int:
	var item_catalog = catalog if catalog != null else ItemCatalog.new()
	var total := 0
	if market != null:
		total += SettlementState.food_stock(market, item_catalog)
	if village_market != null:
		total += _village_food_stock(village_market, item_catalog)
	return total


## The village side, in the SAME whole-units currency as the emergence
## market's integer stock. A VillageMarket counts food in floats, but
## VillageMarket.buy_meal only ever draws from an item already holding a
## whole FOOD_UNITS_PER_MEAL -- so half a fruit is not half a household's
## food, it is nobody's, and two half-units of two different foods still feed
## nobody. Counting whole meals per item (rather than summing raw floats via
## total_stock) is therefore not a rounding convention invented here: it is
## the market's own real purchase rule, read off its own constant.
static func _village_food_stock(village_market, item_catalog) -> int:
	var total := 0
	for item_id in village_market.stock:
		if item_catalog.kind_of(item_id) != "food":
			continue
		total += int(float(village_market.stock[item_id]) / VillageMarket.FOOD_UNITS_PER_MEAL)
	return total


## How many households the combined stock can carry -- SettlementState's own
## FOOD_PER_HOUSEHOLD, applied to a food number that is finally complete.
## Pair it with SettlementState.status_for exactly as before; only the
## capacity argument changes.
static func carrying_capacity(market, village_market, catalog = null) -> int:
	return int(food_stock(market, village_market, catalog) / float(SettlementState.FOOD_PER_HOUSEHOLD))


## The live VillageMarket belonging to `settlement_id`, or null if that
## settlement's chunk is not currently loaded (an unloaded settlement is
## still assessed -- see EarthChunkManager.step_settlements' "every
## settlement that has ever been founded" -- so "no live market right now" is
## the normal case for most of the world, not a failure).
##
## `loaded_villages` is the chunk_coord -> Array of spawned village nodes
## shape EarthChunkManager already keeps (see _loaded_villages, filled by
## VillageRenderer.spawn_village); this module invents no second registry, it
## only reads that one. A settlement's key IS its chunk coordinate (see
## EntityRef.for_settlement), so the settlement is matched by rebuilding that
## same id rather than by parsing one apart.
##
## The market itself is reached duck-typed through `node.economy.market` --
## the one VillageMarket instance every NpcMarker of a settlement shares (see
## NpcMarker.setup_economy) -- so the landmarks and props spawn_village
## returns in the same Array are skipped rather than crashed on, the same
## fail-open shape VillageRenderer's own `world == null` guards use. Any
## villager will do: it is deliberately one shared instance per settlement.
static func village_market_for(settlement_id: String, loaded_villages: Dictionary):
	for chunk_coord in loaded_villages:
		if EntityRef.for_settlement(chunk_coord) != settlement_id:
			continue
		for node in loaded_villages[chunk_coord]:
			if node == null or not ("economy" in node):
				continue
			var economy = node.economy
			if economy == null or not ("market" in economy):
				continue
			if economy.market != null:
				return economy.market
	return null
