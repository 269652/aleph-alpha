extends RefCounted

## One SETTLEMENT's real local food stock (docs/concept/npc.md "Local trade
## is NPC-to-NPC, not just player-to-shop"): a producer villager's real
## gathered surplus (see NpcProduction) becomes real stock here, and any
## hungry villager (see NpcEconomy) can buy a meal's worth of it with real
## gold from their own Wallet, at a village-local price.
##
## Deliberately distinct from shop.gd's CATALOG: that is ONE fixed, global,
## player-facing catalog every merchant sells from; this is a real per-
## VILLAGE stock, keyed by real food item id (ItemCatalog), fed by actual
## production rather than an infinite fixed list. One VillageMarket instance
## is shared by every NpcMarker of the same settlement (see
## VillageRenderer.spawn_village) -- NPC-only per docs/concept/npc.md's own
## framing ("non-producer occupations... eat by buying it... from whichever
## village producer has stock"); the doc never extends this to the player, so
## the player keeps using shop.gd's existing merchant-catalog purchase path,
## not this market.

## How much food one meal costs to satisfy one NpcNeeds.is_hungry() ->
## feed() cycle -- a meal is one whole unit, matching how feed() resolves
## hunger in one shot rather than a fractional nibble.
const FOOD_UNITS_PER_MEAL := 1.0

## Gold price of one meal's worth of village-local food. Deliberately below
## shop.gd's CATALOG["cooked_meat"] (4 gold, a prepared/cooked item sold at
## the player-facing fixed catalog) -- this is raw, informal villager-to-
## villager trade, priced under that prepared-food benchmark rather than
## matching or exceeding it. Verified by
## test_village_local_price_is_below_shops_cooked_meat_price so the two
## catalogs never drift into contradiction.
const VILLAGE_LOCAL_FOOD_PRICE := 2

## item_id -> float count of that food currently in stock.
var stock: Dictionary = {}


func add_stock(item_id: String, amount: float) -> void:
	if amount <= 0.0:
		return
	stock[item_id] = stock.get(item_id, 0.0) + amount


## Withdraws `amount` of item_id -- the real draw-down docs/concept/
## timber_construction.md's "Settlement construction ledger" section needs
## ("VillageMarket.stock... it holds lumber the same way [as food]"), e.g.
## the Sagewerk/Storage beam and plank stock a real ConstructionProject
## reserves against on start. All-or-nothing, mirroring
## StructureStock.remove_stock's own contract exactly: fails (false, no
## mutation) if less than `amount` is present, rather than silently
## withdrawing a partial amount.
func remove_stock(item_id: String, amount: float) -> bool:
	if stock.get(item_id, 0.0) < amount:
		return false
	stock[item_id] = stock.get(item_id, 0.0) - amount
	return true


func total_stock() -> float:
	var total := 0.0
	for item_id in stock:
		total += stock[item_id]
	return total


func can_buy_meal() -> bool:
	for item_id in stock:
		if stock[item_id] >= FOOD_UNITS_PER_MEAL:
			return true
	return false


## Buys one meal's worth of whatever real village food is available -- a
## hungry villager takes whichever stock exists, not a specific item.
## Deterministic pick (first item_id, in insertion/iteration order, holding a
## whole unit) rather than random, so the same market state always resolves
## the same purchase. Returns the item_id bought, or "" if the purchase
## failed (no item has a whole unit, or the wallet can't afford
## VILLAGE_LOCAL_FOOD_PRICE) -- wallet and stock are both left unchanged on
## failure (see Wallet.spend's own no-op-on-failure contract).
func buy_meal(wallet) -> String:
	for item_id in stock:
		if stock[item_id] >= FOOD_UNITS_PER_MEAL:
			if not wallet.spend(VILLAGE_LOCAL_FOOD_PRICE):
				return ""
			stock[item_id] -= FOOD_UNITS_PER_MEAL
			return item_id
	return ""
