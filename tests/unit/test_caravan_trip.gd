extends GutTest

## CaravanTrip: pure state/math for one real in-flight regional-trade
## shipment (see docs/concept/trade.md, which builds on top of the already-
## real docs/concept/regional_trade.md nearest-supplier resupply). Whether
## a trip is raided is decided by the CALLER (see CaravanRaid) and handed
## in as plain raided/raid_fraction values -- this class only knows how to
## walk a straight real route and report when a raid point/arrival is
## reached, the same "behavior decides WHEN, doesn't own the chance math"
## split CarrionForageBehavior already keeps clean of its own callers.

const CaravanTrip = preload("res://src/emergence/caravan_trip.gd")


func _make_trip(
	departure_age: float = 0.0, raided: bool = false, raid_fraction: float = 1.0
) -> CaravanTrip:
	return CaravanTrip.new(
		"settlement:1_0", "settlement:0_0", "rock", 3,
		Vector2(100, 0), Vector2(200, 0), departure_age, 2, raided, raid_fraction
	)


# -- progress_at / position_at: a real lerp along the real route ----------

func test_progress_is_zero_at_the_moment_of_departure():
	var trip := _make_trip(10.0)
	assert_eq(trip.progress_at(10.0), 0.0)


func test_progress_is_complete_once_the_real_distance_has_been_walked():
	var trip := _make_trip(0.0)
	# distance 100px at WALK_SPEED_PX_PER_SEC -- exactly travel_seconds() later.
	assert_eq(trip.progress_at(trip.travel_seconds()), 1.0)


func test_progress_never_exceeds_one_long_after_arrival():
	var trip := _make_trip(0.0)
	assert_eq(trip.progress_at(trip.travel_seconds() * 10.0), 1.0)


func test_position_at_departure_is_the_origin():
	var trip := _make_trip(0.0)
	assert_eq(trip.position_at(0.0), Vector2(100, 0))


func test_position_halfway_is_the_route_midpoint():
	var trip := _make_trip(0.0)
	var halfway := trip.travel_seconds() * 0.5
	assert_eq(trip.position_at(halfway), Vector2(150, 0))


func test_position_on_arrival_is_the_destination():
	var trip := _make_trip(0.0)
	assert_eq(trip.position_at(trip.travel_seconds()), Vector2(200, 0))


# -- is_arrived -------------------------------------------------------------

func test_is_not_arrived_partway_through_the_route():
	var trip := _make_trip(0.0)
	assert_false(trip.is_arrived(trip.travel_seconds() * 0.5))


func test_is_arrived_once_travel_seconds_have_passed():
	var trip := _make_trip(0.0)
	assert_true(trip.is_arrived(trip.travel_seconds()))


# -- raid_triggered: only meaningful when raided ---------------------------

func test_an_unraided_trip_never_triggers_a_raid():
	var trip := _make_trip(0.0, false, 0.0)
	assert_false(trip.raid_triggered(trip.travel_seconds()))


func test_a_raided_trip_triggers_once_its_raid_fraction_of_the_route_is_reached():
	var trip := _make_trip(0.0, true, 0.4)
	var raid_age := trip.travel_seconds() * 0.4
	assert_true(trip.raid_triggered(raid_age))


func test_a_raided_trip_has_not_triggered_before_its_raid_fraction_is_reached():
	var trip := _make_trip(0.0, true, 0.4)
	var before_raid_age := trip.travel_seconds() * 0.2
	assert_false(trip.raid_triggered(before_raid_age))


# -- tile_at: real PathScarring wear-contribution input --------------------

func test_tile_at_departure_is_the_origins_tile():
	var trip := _make_trip(0.0)
	assert_eq(trip.tile_at(0.0, 16), Vector2i(100 / 16, 0))


func test_tile_at_progresses_toward_the_destination_as_world_age_advances():
	var trip := _make_trip(0.0)
	var early_tile := trip.tile_at(trip.travel_seconds() * 0.1, 16)
	var late_tile := trip.tile_at(trip.travel_seconds() * 0.9, 16)
	assert_gt(late_tile.x, early_tile.x)
