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


# -- a larder is not a warehouse ------------------------------------------
#
# The fix for a village that starved next to its own full farmhouses
# narrowed _settlement_structure_stocks to STRUCTURE_MEAL_SOURCE_IDS, which
# is right for what a village can EAT and wrong for what a merchant can
# BUY. They are different questions about the same shelves: a farmhouse is
# not a place anybody eats, and it is exactly the container the carter's
# round fills and the merchant walks the circuit for.
#
# Measured after that narrowing (tools/probe_village_famine.gd) on a real
# village at t=1200 with 99 units on the stall and 117 on the shelves:
#
#     villagers' purse 0.0 gold | merchant's purse 0.0 gold
#     8 of 8 villagers broke
#
# No gold existed anywhere in the village, because the merchant is the only
# faucet and his view had been narrowed to the larder.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const MerchantVisit = preload("res://src/emergence/merchant_visit.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord := Vector2i(0, 0)
var _store := Vector2i(10, 6)


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	manager._load_chunk(_chunk_coord)


func after_each():
	remove_child(tile_map_layer)
	remove_child(entities_parent)
	manager.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _a_stocked(structure_id: String, item_id: String, count: int) -> void:
	assert_true(
		manager.build_at_global(_store.x, _store.y, structure_id),
		"precondition: the %s stands" % structure_id
	)
	manager.deposit_to_structure_at(_store.x, _store.y, item_id, count)


## Exactly the views _step_merchant_visits builds, added up the way it does.
func _what_the_merchant_is_shown() -> Dictionary:
	var settlement_id: String = manager.EntityRef.for_settlement(_chunk_coord)
	var views: Array = []
	for shelf in manager._settlement_structure_stocks(settlement_id):
		views.append(shelf.stock)
	return SettlementSurplus.combined(views)


## The regression itself, in one line: a hide in the farmhouse is a hide
## the merchant will pay for -- and a hide is not food, so no meal list
## covers it.
func test_the_merchant_is_shown_the_farmhouse_the_larder_leaves_out():
	_a_stocked("farmhouse", "hide", 12)
	assert_eq(
		int(_what_the_merchant_is_shown().get("hide", 0)), 12,
		"the only gold faucet in the game cannot see the village's goods"
	)


## And it really turns into money: goods he cannot see are goods nobody is
## ever paid for, which is a village with no income at all.
func test_goods_in_a_farmhouse_are_worth_gold():
	_a_stocked("farmhouse", "hide", 12)
	var sale: Dictionary = MerchantVisit.purchase(_what_the_merchant_is_shown())
	assert_eq(int(sale["paid"]), 12 * MerchantVisit.price_of("hide"))


## The narrowing stays right where it belongs: a SAWMILL holds sawn timber
## and nobody eats off one, so the village must not count its stock as
## food. (A farmhouse used to be the example here; it was measured onto
## STRUCTURE_MEAL_SOURCE_IDS since -- 97 units of a village's own crop that
## its own people could not eat while they starved around it -- which is
## why the two lists are kept apart rather than merged: what a village can
## SELL and what it can EAT are different questions whose answers happen to
## overlap today.)
func test_the_larder_still_leaves_out_a_shelf_nobody_eats_off():
	_a_stocked("sawmill", "cooked_meat", 50)
	var ItemCatalog = load("res://src/gameplay/item_catalog.gd")
	var catalog = ItemCatalog.new()
	var larder := 0
	for stock in manager._settlement_larder_stocks(manager.EntityRef.for_settlement(_chunk_coord)):
		for item_id in stock.stock:
			if catalog.kind_of(String(item_id)) == "food":
				larder += int(stock.stock[item_id])
	assert_eq(larder, 0, "nobody takes their dinner off a sawmill")


## ...and the merchant is still shown it, which is the whole point of the
## split: a sawmill's timber is a village's income.
func test_the_merchant_is_still_shown_that_shelf():
	_a_stocked("sawmill", "plank", 9)
	assert_eq(int(_what_the_merchant_is_shown().get("plank", 0)), 9)


## ...and a visit really pays. Measured (tools/probe_village_purse.gd) on a
## real village after 5000 simulated seconds, with the buy list derived and
## the purse bound: 811 sellable units, a visit's carry at 0.373 -- which
## is 1.373 less the one visit that fired -- and the purse still reading
## 0.0 with 22 of 22 villagers broke. A sale happened and no gold arrived,
## so something between `purchase` and the deposit is dropping it.
func test_a_visit_really_pays_gold_into_the_settlements_purse():
	var settlement_id: String = manager.EntityRef.for_settlement(_chunk_coord)
	_a_stocked("farmhouse", "hide", 12)
	var market = manager._market_store.market_for(settlement_id)
	# One tick short of a visit, so THIS step is the visit.
	manager._settlement_merchant_carry[settlement_id] = 0.999

	manager._step_merchant_visits(settlement_id, market)

	assert_gt(
		NpcEconomy.purse_of(manager._market_store.market_for(settlement_id)), 0.0,
		"the cart came, took the goods, and paid nobody"
	)


## Nothing conjured and nothing vanished: what he took really left the
## shelf he took it from.
func test_what_he_paid_for_really_leaves_the_shelf():
	var settlement_id: String = manager.EntityRef.for_settlement(_chunk_coord)
	_a_stocked("farmhouse", "hide", 12)
	manager._settlement_merchant_carry[settlement_id] = 0.999

	manager._step_merchant_visits(settlement_id, manager._market_store.market_for(settlement_id))

	assert_lt(
		manager.structure_stock_at(_store.x, _store.y, "hide"), 12,
		"he paid for hides and left them on the shelf"
	)



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
