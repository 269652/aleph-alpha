extends RefCounted

## The player's buy/sell price against a real settlement Market (see
## docs/concept/player_trade.md's "Getting a real price"). No new price
## table -- Market.price_for's own uniform-elasticity reference-stock math
## is the ONLY price signal; this only adds the real buy/sell spread
## around it, the same "the house takes a cut" every real market has, so
## a player can't round-trip buy-low-sell-high a single settlement for
## free profit within one visit (see test_buy_price_always_exceeds_
## sell_price_at_the_same_stock).
##
## Pure functions only, no state of its own -- takes a real Market
## instance as an argument rather than owning one, the same shape every
## other reader of a shared store (SignatureRing reading embedded keys,
## CraftingRecipeBook reading a stock Dictionary) already uses.

const Market = preload("res://src/emergence/market.gd")

## Tuned, tested constants (see CLAUDE.md: never an eyeballed comment) --
## the player receives 85% of the neutral price selling in, and pays 115%
## buying out. Exercised exactly (not just "less/greater than") by
## test_sell_price_applies_the_exact_pinned_markup_factor and its buy
## counterpart.
const SELL_MARKUP_FACTOR := 0.85
const BUY_MARKUP_FACTOR := 1.15


static func sell_price_for(market: Market, item_id: String) -> float:
	return market.price_for(item_id) * SELL_MARKUP_FACTOR


static func buy_price_for(market: Market, item_id: String) -> float:
	return market.price_for(item_id) * BUY_MARKUP_FACTOR


static func can_sell(market: Market, item_id: String, count: int) -> bool:
	return count > 0


## False if the settlement's own real stock can't cover `count` -- the
## player can't buy out goods that structurally don't exist there yet,
## the same "no phantom output" discipline StructureStock.remove_stock
## already enforces.
static func can_buy(market: Market, item_id: String, count: int) -> bool:
	return count > 0 and market.stock_of(item_id) >= count
