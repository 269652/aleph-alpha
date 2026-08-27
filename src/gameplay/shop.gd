extends RefCounted

## A merchant's goods for sale (docs/concept/npc.md's villages,
## docs/concept/economy.md's "Selling to the market" currency faucet).
##
## Phase 1 simplification: one fixed catalog every merchant NPC sells from,
## not a per-NPC inventory/stock -- see docs/progress.md's NPC section. A
## real per-settlement/per-NPC market (varying stock, buying the player's own
## goods, price haggling by relationship -- see npc.md's hiring trust model)
## is future work this can grow into.

const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const Market = preload("res://src/emergence/market.gd")

## item_id -> gold price. A small, deliberately affordable starter selection
## spanning tool/weapon/armor/food so a new player has something to spend
## early gold on.
const CATALOG := {
	"fishing_rod": 15,
	"torch": 5,
	"cooked_meat": 4,
	"leather_helm": 25,
	"iron_sword": 60,
}


func known_item_ids() -> Array:
	return CATALOG.keys()


## Gives a settlement's market the goods its merchant actually sells, at the
## neutral stock level.
##
## Needed because MarketStore.market_for creates a fresh EMPTY market on first
## access, and an empty market prices at REFERENCE_STOCK / 1 = 20x. Wiring the
## shop to the market without this would not add scarcity pricing, it would
## multiply every price in the game by twenty. Seeding AT REFERENCE_STOCK is
## what makes a newly founded village charge exactly the old flat catalog
## price, so this whole change starts from where the game already was and only
## moves when something in the world moves it.
##
## Idempotent, like the form_*/record_*_if_new family: an item already in
## stock is left alone, so re-running founding logic cannot quietly double a
## merchant's goods and halve the town's prices.
func stock_initial_goods(market) -> void:
	for item_id in CATALOG:
		if market.stock_of(item_id) <= 0:
			market.add_stock(item_id, Market.REFERENCE_STOCK)


## The gold price of item_id, or 0 for an item this shop doesn't sell.
func price_of(item_id: String) -> int:
	return CATALOG.get(item_id, 0)


## What item_id actually costs HERE, in this settlement, right now.
##
## CATALOG is the base price in absolute gold; Market.price_for is a
## dimensionless scarcity multiplier that is exactly 1.0 at
## Market.REFERENCE_STOCK. So this is one multiplication and it invents no new
## number: a village holding a healthy stock charges precisely what the flat
## catalog charged before this existed, and every deviation from that is a real
## shortage or a real glut the NPC economy produced (Market.produce runs real
## CraftingRecipeBook recipes against real stock).
##
## This is docs/emergence/03-contracts-property-economy.md's "Do not use one
## global price", of which the flat catalog was the last violation. A null
## market -- a merchant with no settlement behind them -- falls back to the
## catalog rather than to free goods.
func market_price_of(item_id: String, market) -> int:
	if not CATALOG.has(item_id):
		return 0
	if market == null:
		return CATALOG[item_id]
	return roundi(float(CATALOG[item_id]) * market.price_for(item_id))


func can_afford(wallet_balance: int, item_id: String, market = null) -> bool:
	return CATALOG.has(item_id) and wallet_balance >= market_price_of(item_id, market)


## Attempts to buy one unit of item_id: on success, spends its price from
## wallet and adds it to inventory. False (no-op, nothing changed) for an
## unknown item or an unaffordable one.
##
## `market`: the local settlement's real market, when there is one. Two things
## then change, and both come from docs/emergence/03's invariant 4, "Money does
## not create physical goods". The price is the LOCAL price (see
## market_price_of), and the purchase takes the item out of that market's
## stock -- so buying the last sword really does leave the next customer
## without one, and a sold-out village is a real reason to travel rather than a
## message. Omitting the market keeps the old flat-catalog behaviour exactly.
func buy(wallet, inventory, item_catalog: ItemCatalog, item_id: String, market = null) -> bool:
	if not CATALOG.has(item_id):
		return false
	# You cannot buy what is not there, at any price.
	if market != null and market.stock_of(item_id) <= 0:
		return false
	if not wallet.spend(market_price_of(item_id, market)):
		return false
	if market != null:
		market.add_stock(item_id, -1)
	inventory.add(item_catalog.make(item_id), 1)
	return true
