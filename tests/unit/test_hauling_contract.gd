extends GutTest

## See docs/concept/player_trade.md's "Hauling Contract" -- a real,
## player-dispatched shipment between a Warehouse and a discovered
## settlement, deliberately mirroring CaravanTrip's own pure travel math
## (same WALK_SPEED_PX_PER_SEC, same progress_at/position_at/is_arrived/
## raid_triggered shape) plus the trade terms (item, count, direction,
## price) a settlement-to-settlement CaravanTrip never needed.

const HaulingContract = preload("res://src/gameplay/hauling_contract.gd")

var contract: HaulingContract


func before_each():
	contract = HaulingContract.new(
		Vector2(0, 0), "settlement:1", Vector2(200, 0), "wood", 10,
		HaulingContract.Direction.SELL, 0.85, 0.0, false, 0.0
	)


func test_travel_seconds_is_distance_over_walk_speed():
	assert_almost_eq(
		contract.travel_seconds(),
		200.0 / HaulingContract.WALK_SPEED_PX_PER_SEC,
		0.0001
	)


func test_progress_is_zero_at_departure():
	assert_almost_eq(contract.progress_at(0.0), 0.0, 0.0001)


func test_progress_is_one_once_travel_time_has_fully_elapsed():
	assert_almost_eq(contract.progress_at(contract.travel_seconds()), 1.0, 0.0001)


func test_progress_is_clamped_to_one_long_after_arrival():
	assert_almost_eq(contract.progress_at(contract.travel_seconds() * 10.0), 1.0, 0.0001)


func test_position_at_departure_is_the_warehouse():
	assert_eq(contract.position_at(0.0), Vector2(0, 0))


func test_position_at_arrival_is_the_settlement():
	assert_eq(contract.position_at(contract.travel_seconds()), Vector2(200, 0))


func test_position_halfway_is_the_midpoint():
	var halfway := contract.position_at(contract.travel_seconds() / 2.0)
	assert_almost_eq(halfway.x, 100.0, 0.01)


func test_is_arrived_false_before_travel_time_elapses():
	assert_false(contract.is_arrived(0.0))


func test_is_arrived_true_once_travel_time_elapses():
	assert_true(contract.is_arrived(contract.travel_seconds()))


func test_a_same_position_contract_counts_as_already_arrived():
	var same_spot := HaulingContract.new(
		Vector2(50, 50), "settlement:1", Vector2(50, 50), "wood", 5,
		HaulingContract.Direction.SELL, 1.0, 0.0, false, 0.0
	)
	assert_true(same_spot.is_arrived(0.0))


func test_raid_triggered_false_when_not_raided():
	assert_false(contract.raid_triggered(contract.travel_seconds()))


func test_raid_triggered_true_once_progress_reaches_the_raid_fraction():
	var raided_contract := HaulingContract.new(
		Vector2(0, 0), "settlement:1", Vector2(200, 0), "wood", 10,
		HaulingContract.Direction.SELL, 0.85, 0.0, true, 0.5
	)
	var halfway_time := raided_contract.travel_seconds() * 0.5
	assert_true(raided_contract.raid_triggered(halfway_time))


func test_raid_triggered_false_before_the_raid_fraction_is_reached():
	var raided_contract := HaulingContract.new(
		Vector2(0, 0), "settlement:1", Vector2(200, 0), "wood", 10,
		HaulingContract.Direction.SELL, 0.85, 0.0, true, 0.5
	)
	var quarter_time := raided_contract.travel_seconds() * 0.25
	assert_false(raided_contract.raid_triggered(quarter_time))


func test_total_price_is_count_times_unit_price():
	assert_almost_eq(contract.total_price(), 10 * 0.85, 0.0001)


func test_stores_the_trade_terms_verbatim():
	assert_eq(contract.settlement_id, "settlement:1")
	assert_eq(contract.item_id, "wood")
	assert_eq(contract.count, 10)
	assert_eq(contract.direction, HaulingContract.Direction.SELL)
	assert_almost_eq(contract.unit_price, 0.85, 0.0001)
