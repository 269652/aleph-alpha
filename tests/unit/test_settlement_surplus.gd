extends GutTest

## Every container a settlement really keeps goods in, as ONE stock a
## merchant can price (docs/concept/traveling_merchants.md, "A merchant buys
## the whole village, not one of its cupboards").
##
## Reported with the town panel open: *"The village produces way too much
## food and the NPCs don't have an income"* -- Food feeds 387 of 16, Gold 1,
## worst need income. One fault, not two: the goods were in the warehouse
## and the only buyer could see the market.

const SettlementSurplus = preload("res://src/emergence/settlement_surplus.gd")


func test_the_containers_are_added_up_for_pricing():
	var views: Array = [{"fish": 3.0}, {"fish": 2, "meat": 5}]
	assert_eq(SettlementSurplus.combined(views), {"fish": 5.0, "meat": 5.0})


func test_one_container_reads_exactly_as_itself():
	assert_eq(SettlementSurplus.combined([{"wood": 7}]), {"wood": 7.0})


func test_nothing_anywhere_is_an_empty_stock_rather_than_a_crash():
	assert_eq(SettlementSurplus.combined([]), {})
	assert_eq(SettlementSurplus.combined([{}, {}]), {})


## A container holding a negative or zero count contributes nothing rather
## than subtracting from another container's real goods.
func test_an_empty_or_negative_shelf_never_eats_another_shelfs_goods():
	assert_eq(SettlementSurplus.combined([{"fish": 4}, {"fish": -2}]), {"fish": 4.0})
	assert_eq(SettlementSurplus.combined([{"fish": 0}]), {})


# -- taking the sale back out of the real containers ----------------------

func test_a_sale_is_drawn_from_the_first_container_that_has_it():
	var views: Array = [{"fish": 5.0}, {"fish": 5}]
	var plan := SettlementSurplus.allocate({"fish": 3}, views)
	assert_eq(plan, [{"fish": 3.0}, {}])


## Goods spread across two shelves are taken from both, in view order.
func test_a_sale_bigger_than_one_container_spills_into_the_next():
	var views: Array = [{"fish": 2.0}, {"fish": 10}]
	var plan := SettlementSurplus.allocate({"fish": 7}, views)
	assert_eq(plan, [{"fish": 2.0}, {"fish": 5.0}])


## The whole point: what is taken adds up to exactly what was bought, so a
## merchant never pays for goods that stay on the shelf.
func test_what_is_taken_adds_up_to_what_was_bought():
	var views: Array = [{"fish": 2, "meat": 1}, {"fish": 4, "meat": 9}]
	var bought := {"fish": 5, "meat": 6}
	var plan := SettlementSurplus.allocate(bought, views)
	for item_id in bought:
		var taken := 0.0
		for view in plan:
			taken += float(view.get(item_id, 0.0))
		assert_eq(taken, float(bought[item_id]), "%s" % item_id)


## No container is ever drawn below empty -- the caller removes exactly what
## the plan says, and a shelf that cannot cover it must not be asked to.
func test_no_container_is_ever_drawn_below_empty():
	var views: Array = [{"fish": 2.0}, {"fish": 1.0}]
	var plan := SettlementSurplus.allocate({"fish": 99}, views)
	assert_eq(plan, [{"fish": 2.0}, {"fish": 1.0}], "it takes what is there and no more")


func test_buying_nothing_touches_nothing():
	var views: Array = [{"fish": 5.0}, {"meat": 5}]
	assert_eq(SettlementSurplus.allocate({}, views), [{}, {}])


func test_a_good_no_container_holds_is_simply_not_taken():
	assert_eq(SettlementSurplus.allocate({"gold_bar": 4}, [{"fish": 5}]), [{}])


## One plan entry per view, in the same order, so the caller can map each
## back to the container it came from without a second key.
func test_the_plan_has_one_entry_per_container_in_order():
	var views: Array = [{"fish": 1}, {}, {"meat": 2}]
	var plan := SettlementSurplus.allocate({"meat": 2}, views)
	assert_eq(plan.size(), views.size())
	assert_eq(plan[2], {"meat": 2.0}, "the third container is the one that had it")
	assert_eq(plan[0], {})
	assert_eq(plan[1], {})


func test_the_plan_is_deterministic():
	var views: Array = [{"fish": 3, "meat": 3}, {"fish": 3, "meat": 3}]
	var first := SettlementSurplus.allocate({"fish": 4, "meat": 2}, views)
	for _i in 4:
		assert_eq(SettlementSurplus.allocate({"fish": 4, "meat": 2}, views), first)


## Pure: pricing and planning never touch the containers they were shown,
## so a sale that cannot be completed has changed nothing.
func test_neither_reading_nor_planning_disturbs_the_containers():
	var market := {"fish": 5.0}
	var shelf := {"fish": 5}
	var views: Array = [market, shelf]
	SettlementSurplus.combined(views)
	SettlementSurplus.allocate({"fish": 8}, views)
	assert_eq(market, {"fish": 5.0}, "the market is untouched")
	assert_eq(shelf, {"fish": 5}, "and so is the shelf")
