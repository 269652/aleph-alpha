extends GutTest

## One placed structure's own item stock (a Storage building's inventory --
## see docs/concept/timber_construction.md's "Storage, logistics, and the
## autonomous dependency chain" section). Same item_id -> int shape as
## Market (src/emergence/market.gd), just at building scale instead of
## settlement scale, per that section's own explicit instruction to reuse
## the shape rather than invent a third container design.

const StructureStock = preload("res://src/emergence/structure_stock.gd")

var stock: StructureStock


func before_each():
	stock = StructureStock.new()


func test_starts_empty():
	assert_eq(stock.stock_of("plank"), 0)


func test_add_stock_increases_the_count():
	stock.add_stock("plank", 5)
	assert_eq(stock.stock_of("plank"), 5)


func test_add_stock_accumulates_across_calls():
	stock.add_stock("plank", 5)
	stock.add_stock("plank", 3)
	assert_eq(stock.stock_of("plank"), 8)


func test_add_stock_tracks_items_independently():
	stock.add_stock("plank", 5)
	stock.add_stock("beam", 2)
	assert_eq(stock.stock_of("plank"), 5)
	assert_eq(stock.stock_of("beam"), 2)


func test_remove_stock_succeeds_and_deducts_when_enough_is_present():
	stock.add_stock("plank", 5)
	assert_true(stock.remove_stock("plank", 3))
	assert_eq(stock.stock_of("plank"), 2)


func test_remove_stock_fails_and_leaves_stock_untouched_when_short():
	stock.add_stock("plank", 2)
	assert_false(stock.remove_stock("plank", 3))
	assert_eq(stock.stock_of("plank"), 2)


func test_remove_stock_fails_for_an_item_never_stocked():
	assert_false(stock.remove_stock("plank", 1))


func test_remove_stock_exact_amount_succeeds_and_zeroes_it():
	stock.add_stock("plank", 4)
	assert_true(stock.remove_stock("plank", 4))
	assert_eq(stock.stock_of("plank"), 0)


# -- persistence round trip (pure, no FileAccess -- mirrors test_market.gd) --

func test_to_dict_and_from_dict_round_trip_the_stock():
	stock.add_stock("plank", 5)
	stock.add_stock("beam", 2)

	var restored := StructureStock.from_dict(stock.to_dict())

	assert_eq(restored.stock_of("plank"), 5)
	assert_eq(restored.stock_of("beam"), 2)


func test_from_dict_on_an_empty_dict_is_a_fresh_empty_stock():
	var restored := StructureStock.from_dict({})
	assert_eq(restored.stock_of("plank"), 0)
