extends GutTest

## StructureStockStore: one StructureStock per placed structure instance,
## keyed by its own position string -- mirrors MarketStore's "one Market per
## settlement" shape (src/emergence/market_store.gd) exactly, just keyed by
## structure position instead of settlement id. Deliberately position-keyed
## rather than structure-type-keyed: two Storage buildings in the same world
## must never share one stock, the same way two settlements' markets don't.

const StructureStockStore = preload("res://src/emergence/structure_stock_store.gd")
const StructureStock = preload("res://src/emergence/structure_stock.gd")

var store: StructureStockStore


func before_each():
	store = StructureStockStore.new()


func test_stock_for_creates_one_on_first_access():
	var stock := store.stock_for("10_20")
	assert_not_null(stock)
	assert_eq(stock.stock_of("plank"), 0)


## Idempotent -- asking twice for the same instance returns the SAME stock,
## the same shape MarketStore.market_for already proves, so a second lookup
## never silently discards what the first already holds.
func test_stock_for_returns_the_same_stock_on_repeat_access():
	var first := store.stock_for("10_20")
	first.add_stock("plank", 5)
	var second := store.stock_for("10_20")
	assert_eq(second.stock_of("plank"), 5)


func test_different_instances_get_different_stocks():
	store.stock_for("10_20").add_stock("plank", 5)
	assert_eq(store.stock_for("30_40").stock_of("plank"), 0)


# -- persistence round trip (pure, no FileAccess) -----------------------------

func test_to_dicts_and_from_dicts_round_trip_every_stock():
	store.stock_for("10_20").add_stock("plank", 5)
	store.stock_for("30_40").add_stock("beam", 3)

	var restored := StructureStockStore.from_dicts(store.to_dicts())

	assert_eq(restored.stock_for("10_20").stock_of("plank"), 5)
	assert_eq(restored.stock_for("30_40").stock_of("beam"), 3)
