extends GutTest

## The shop's prices are per-settlement (Shop.market_price_of,
## docs/emergence/03-contracts-property-economy.md's "Do not use one global
## price") -- but only if the CALL SITE actually passes a market. Shop's own
## unit tests cannot see that: they pass a market because the test wrote one,
## and would stay green forever while the running game quietly bought
## everything at the flat catalog price from a market it never consulted.
##
## That is the exact failure mode this project keeps finding in its own
## audits: a complete, tested module with no production caller. So this pins
## the wiring itself, read straight from source.
##
## Kept as its own tiny file (it preloads nothing but reads two files) so it
## runs in about a second, rather than living in test_earth_chunk_manager.gd,
## which takes ten-plus minutes. Same reasoning, and same shape, as
## test_world_backup_paths.gd.

const Shop = preload("res://src/gameplay/shop.gd")
const Market = preload("res://src/emergence/market.gd")


## The body of Player._attempt_a_purchase, read straight from source -- the
## authority on what the trade key actually does.
func _purchase_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	var start := source.find("func _attempt_a_purchase()")
	assert_gt(start, -1, "Player._attempt_a_purchase should still exist")
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	return source.substr(start, end - start)


func test_the_purchase_path_asks_for_the_local_market():
	assert_string_contains(_purchase_body(), "merchant_market_near")


## Passing the market to buy() is what makes the purchase draw the item out of
## that village's stock. Without it the price could be local while the goods
## were still conjured from nothing -- docs/emergence/03's invariant 4,
## "Money does not create physical goods", half-applied.
func test_the_purchase_passes_the_market_to_buy():
	var body := _purchase_body()
	var call_start := body.find("_shop.buy(")
	assert_gt(call_start, -1, "the purchase path should still call _shop.buy")
	var call_end := body.find(")", call_start)
	assert_string_contains(body.substr(call_start, call_end - call_start), "market")


## The banner has to quote what was actually paid. Reading the price back out
## of the market AFTER the purchase would report the next customer's price,
## because the purchase itself moved the stock.
func test_the_reported_price_is_read_before_the_purchase():
	var body := _purchase_body()
	var price_read := body.find("market_price_of")
	var purchase := body.find("_shop.buy(")
	assert_gt(price_read, -1, "the purchase path should quote a market price")
	assert_lt(price_read, purchase, "the price must be read before buy() moves the stock")


## EarthChunkManager.merchant_market_near stocks the market it hands back, and
## this is why: MarketStore.market_for creates a fresh EMPTY market, and an
## empty market prices at REFERENCE_STOCK/1. Without the stocking, wiring the
## shop to the market would multiply every price in the game by twenty rather
## than making prices local.
func test_a_stocked_market_prices_at_the_catalog_and_an_empty_one_does_not():
	var shop := Shop.new()
	var empty := Market.new()
	var stocked := Market.new()
	shop.stock_initial_goods(stocked)
	for item_id in shop.known_item_ids():
		assert_eq(shop.market_price_of(item_id, stocked), shop.price_of(item_id))
		assert_gt(shop.market_price_of(item_id, empty), shop.price_of(item_id))


func test_the_manager_stocks_the_market_it_hands_out():
	var source := FileAccess.get_file_as_string("res://src/world/earth_chunk_manager.gd")
	var start := source.find("func merchant_market_near(")
	assert_gt(start, -1, "EarthChunkManager.merchant_market_near should still exist")
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	assert_string_contains(source.substr(start, end - start), "stock_initial_goods")
