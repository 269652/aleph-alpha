extends RefCounted

## Local supply/demand-driven stock and pricing (see
## docs/emergence/03-contracts-property-economy.md "Markets": "local
## buyer/seller matching systems. Prices respond to supply, demand,
## stockpiles... Do not use one global price").
##
## Production itself is NOT reinvented here -- CraftingRecipeBook already has
## real, tested recipes grounded in this project's real item ids (wood, rock,
## stick, ...). `produce` runs an existing recipe against THIS market's stock
## the same way `Player.craft` already runs one against a player's inventory
## (both ultimately call CraftingRecipeBook.craft against a plain
## item_id -> count Dictionary); a market is just a different Dictionary to
## run it against.

## Elasticity is uniform across every item rather than a per-item base price
## table: there is no real currency/value system wired to NPCs yet (see
## docs/roadmap.md's Emergence Phase 5 note), so a per-item base price would
## be an invented number with nothing grounding it. REFERENCE_STOCK is the
## "healthy" stock level at which price reads as the neutral 1.0 -- below it,
## scarcer is pricier; above it, oversupply is cheaper. Chosen as a plausible
## settlement-scale stockpile size, exercised by the tests that pin its
## monotonic behaviour rather than any specific number.
const REFERENCE_STOCK := 20

## Floor under the stock used in the price division, so zero stock is the
## most expensive finite state rather than a divide-by-zero crash -- scarcity
## has a ceiling, it does not blow up to infinity.
const MIN_STOCK_FOR_PRICING := 1

var stock: Dictionary = {}   # item_id -> int


func stock_of(item_id: String) -> int:
	return stock.get(item_id, 0)


func add_stock(item_id: String, count: int) -> void:
	stock[item_id] = stock_of(item_id) + count


## Price relative to the neutral REFERENCE_STOCK level: 1.0 at reference,
## rising as stock falls below it, falling as stock rises above it -- the
## same real number every buyer and every producer sees, so a shortage that
## raises the price IS the same shortage that can block production below
## (see produce), not two independently-tuned effects that happen to agree.
func price_for(item_id: String) -> float:
	return float(REFERENCE_STOCK) / float(maxi(stock_of(item_id), MIN_STOCK_FOR_PRICING))


## Runs `recipe_id` from `recipe_book` against this market's own stock:
## consumes the recipe's inputs and adds its output, exactly as
## CraftingRecipeBook.craft already does against any item_id -> count
## Dictionary. Fails (recipe_book.craft's own "success": false) when stock is
## short of what the recipe needs -- a real production failure caused by a
## real shortage, not a scripted event.
func produce(recipe_book, recipe_id: String) -> Dictionary:
	var result: Dictionary = recipe_book.craft(recipe_id, stock)
	stock = result.remaining_counts
	if result.success:
		add_stock(result.output_item_id, result.output_count)
	return result


func to_dict() -> Dictionary:
	return {"stock": stock}


static func from_dict(d: Dictionary) -> RefCounted:
	var market = new()
	var restored_stock: Dictionary = d.get("stock", {})
	for item_id in restored_stock:
		market.stock[str(item_id)] = int(restored_stock[item_id])
	return market
