extends GutTest

## See docs/concept/player_trade.md's "Trade Route (autotrading)" -- a
## saved Hauling Contract TEMPLATE that decides WHEN to redispatch, the
## same "cheap due-check every tick, real work only when due" shape
## ConstructionPriority's own settlement-build gating already uses. No
## separate route simulation -- is_due just gates dispatching a fresh,
## ordinary HaulingContract.

const TradeRoute = preload("res://src/gameplay/trade_route.gd")
const HaulingContract = preload("res://src/gameplay/hauling_contract.gd")

var route: TradeRoute


func before_each():
	route = TradeRoute.new(
		Vector2(0, 0), "settlement:1", "wood", 10,
		HaulingContract.Direction.SELL, 60.0
	)


func test_a_freshly_created_route_has_never_dispatched():
	assert_lt(route.last_dispatched_age, 0.0)


func test_a_never_dispatched_route_is_due_immediately():
	assert_true(route.is_due(0.0))


func test_a_route_is_not_due_before_its_interval_elapses():
	route.mark_dispatched(100.0)
	assert_false(route.is_due(150.0))


func test_a_route_becomes_due_once_its_interval_elapses():
	route.mark_dispatched(100.0)
	assert_true(route.is_due(160.0))


func test_a_route_is_due_exactly_at_the_interval_boundary():
	route.mark_dispatched(100.0)
	assert_true(route.is_due(160.0))  # interval_seconds == 60.0


func test_mark_dispatched_updates_last_dispatched_age():
	route.mark_dispatched(250.0)
	assert_eq(route.last_dispatched_age, 250.0)


func test_build_contract_produces_a_hauling_contract_with_the_routes_terms():
	var contract: HaulingContract = route.build_contract(
		Vector2(300, 0), 0.85, 500.0, false, 0.0
	)
	assert_eq(contract.warehouse_position, Vector2(0, 0))
	assert_eq(contract.settlement_id, "settlement:1")
	assert_eq(contract.settlement_position, Vector2(300, 0))
	assert_eq(contract.item_id, "wood")
	assert_eq(contract.count, 10)
	assert_eq(contract.direction, HaulingContract.Direction.SELL)
	assert_almost_eq(contract.unit_price, 0.85, 0.0001)
	assert_eq(contract.departure_age, 500.0)


func test_build_contract_carries_raid_terms_through():
	var contract: HaulingContract = route.build_contract(
		Vector2(300, 0), 0.85, 500.0, true, 0.4
	)
	assert_true(contract.raided)
	assert_almost_eq(contract.raid_fraction, 0.4, 0.0001)
