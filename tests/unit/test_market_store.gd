extends GutTest

## MarketStore: one Market per settlement -- "local buyer/seller matching
## systems... do not use one global price" (docs/emergence/03), so markets
## are keyed by settlement the same way HouseholdStore/ContractStore are
## keyed by whatever real entity they belong to.

const MarketStore = preload("res://src/emergence/market_store.gd")
const Market = preload("res://src/emergence/market.gd")

var store: MarketStore


func before_each():
	store = MarketStore.new()


func test_market_for_creates_one_on_first_access():
	var market := store.market_for("settlement:0_0")
	assert_not_null(market)
	assert_eq(market.stock_of("wood"), 0)


## Idempotent, the same shape HouseholdStore.form_household already uses --
## asking twice for the same settlement returns the SAME market, not a fresh
## empty one that would silently discard whatever stock it held.
func test_market_for_returns_the_same_market_on_repeat_access():
	var first := store.market_for("settlement:0_0")
	first.add_stock("wood", 5)
	var second := store.market_for("settlement:0_0")
	assert_eq(second.stock_of("wood"), 5)


func test_different_settlements_get_different_markets():
	store.market_for("settlement:0_0").add_stock("wood", 5)
	assert_eq(store.market_for("settlement:1_1").stock_of("wood"), 0)


# -- persistence round trip (pure, no FileAccess) -----------------------------

func test_to_dicts_and_from_dicts_round_trip_every_market():
	store.market_for("settlement:0_0").add_stock("wood", 5)
	store.market_for("settlement:1_1").add_stock("rock", 3)

	var restored := MarketStore.from_dicts(store.to_dicts())

	assert_eq(restored.market_for("settlement:0_0").stock_of("wood"), 5)
	assert_eq(restored.market_for("settlement:1_1").stock_of("rock"), 3)
