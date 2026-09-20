extends GutTest

## That the merchant really is shown every container (docs/concept/
## traveling_merchants.md, "A merchant buys the whole village, not one of
## its cupboards").
##
## What the combining and the drawing DO is tested for real in
## test_settlement_surplus.gd; what is pinned here is that the visit asks
## them, which is a source-contract question -- the boundary this repo
## already draws for EarthChunkManager wiring.

const SettlementSurplus = preload("res://src/emergence/settlement_surplus.gd")


func _body(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://src/world/earth_chunk_manager.gd")
	var start := source.find("func %s" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


## The fault itself: the merchant priced `market.stock` alone, while the
## food readout counted the shelves too.
func test_the_visit_prices_every_container_not_just_the_market():
	var body := _body("_step_merchant_visits")
	assert_true(
		body.contains("_settlement_structure_stocks("),
		"the warehouse shelves are part of what he sees: %s" % body
	)
	assert_true(
		body.contains("SettlementSurplus.combined("),
		"and they are priced as one stock"
	)


## And the goods really leave the containers they were in -- a merchant who
## pays for warehouse fish and takes them out of the market would be
## inventing goods in one place and destroying them in another.
func test_the_sale_is_drawn_back_out_of_the_real_containers():
	var body := _body("_step_merchant_visits")
	assert_true(body.contains("SettlementSurplus.allocate("), body)
	assert_true(
		body.contains("remove_stock("),
		"the plan is actually carried out"
	)


## The market is offered first, so the shelf a player can walk up to and
## open is the last thing emptied.
func test_the_market_is_drawn_from_before_the_shelves():
	var body := _body("_step_merchant_visits")
	var market_at := body.find("market.stock")
	var shelves_at := body.find("_settlement_structure_stocks(")
	assert_gt(market_at, -1, "the premise: the market is still a view")
	assert_gt(shelves_at, -1, "the premise: the shelves are too")
	assert_lt(market_at, shelves_at, "the market heads the view list")


## Still one purse. The gold a merchant pays has one destination, and a
## second one would be a second treasury.
func test_the_gold_still_lands_in_the_one_purse():
	assert_true(_body("_step_merchant_visits").contains("deposit_to_purse("))


## MEASURED (tools/probe_village_famine.gd, purse column): purse 0.0 at
## every sample of a 1200-second watch, in a village holding 38 sellable
## food in its market and 187 across its shelves, with the merchant offered
## that stock on every settlement step.
##
## step_settlements hands him `_market_store.market_for(settlement_id)` --
## the persisted emergence Market, whose own neighbouring comment says
## "live play essentially never stocks that one". The purse is metadata ON
## THAT OBJECT (NpcEconomy._set_purse), while every villager reads the
## purse off their live VillageMarket. So the gold a merchant paid landed
## in a purse nobody reads, and the wage could never be drawn.
##
## This is the same "two unrelated things called the market" trap
## SettlementFood's own header was written about.
func test_the_visit_sees_the_market_the_villagers_actually_trade_from():
	var body := _body("_step_merchant_visits")
	assert_true(
		body.contains("village_market"),
		"the live market is one of the containers he is shown: %s" % body
	)


## And the gold lands where the wage is drawn from, or it may as well not
## have been paid.
func test_the_gold_lands_in_the_purse_the_wage_is_drawn_from():
	var body := _body("_step_merchant_visits")
	var deposit_at := body.find("deposit_to_purse(")
	assert_gt(deposit_at, -1, "the premise: he still pays")
	var call := body.substr(deposit_at, 60)
	assert_true(
		call.contains("village_market") or call.contains("purse_market"),
		"paid into the market villagers read, not the persisted ledger: %s" % call
	)
