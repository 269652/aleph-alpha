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


## The gold price of item_id, or 0 for an item this shop doesn't sell.
func price_of(item_id: String) -> int:
	return CATALOG.get(item_id, 0)


func can_afford(wallet_balance: int, item_id: String) -> bool:
	return CATALOG.has(item_id) and wallet_balance >= CATALOG[item_id]


## Attempts to buy one unit of item_id: on success, spends its price from
## wallet and adds it to inventory. False (no-op, nothing changed) for an
## unknown item or an unaffordable one.
func buy(wallet, inventory, item_catalog: ItemCatalog, item_id: String) -> bool:
	if not CATALOG.has(item_id):
		return false
	if not wallet.spend(CATALOG[item_id]):
		return false
	inventory.add(item_catalog.make(item_id), 1)
	return true
