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


# -- a trip walks a ROUTE, not just a straight line ------------------------
#
# Asked for after every other walking marker had a building gate: *"fix the
# caravan and cart markers too"*.
#
# A caravan could not be given that gate, and the reason is worth writing
# down rather than working around: its position is a pure closed-form
# function of elapsed time, and `is_arrived`, `raid_triggered` and the
# route's own PathScarring wear are all defined off the same progress.
# Deflecting the MARKER would leave the marker and the trip disagreeing
# about where the caravan is -- it would hug a wall, then pop through as
# the pure position moved on, and be freed on arrival somewhere it was not.
#
# So the route bends instead of the walker. Waypoints make it a polyline
# and position_at walks it by arc length; everything else is unchanged,
# because everything else was already written in terms of progress.
#
# Measured before this existed (a 360-direction sweep over 60 real village
# layouts, tools/probe_carts_and_caravans.gd): 30.2% of the directions a
# caravan can leave a well in cross one of its own village's buildings.

const _WALK := CaravanTrip.WALK_SPEED_PX_PER_SEC


func _trip_via(waypoints: Array, origin := Vector2.ZERO, destination := Vector2(100, 0)) -> CaravanTrip:
	var trip := CaravanTrip.new(
		"settlement:1_1", "settlement:2_2", "grain", 5,
		origin, destination, 0.0, 1, false, 1.0
	)
	trip.waypoints = waypoints
	return trip


## A trip with no waypoints is exactly the straight line it always was.
func test_a_trip_with_no_waypoints_is_the_straight_line_it_always_was():
	var trip := _trip_via([])
	assert_almost_eq(trip.travel_seconds(), 100.0 / _WALK, 0.0001)
	assert_almost_eq(trip.position_at(trip.travel_seconds() * 0.5).x, 50.0, 0.0001)
	assert_almost_eq(trip.position_at(trip.travel_seconds() * 0.5).y, 0.0, 0.0001)


## A dog-leg is walked, not cut across: half way through the trip the
## caravan is half way along the ROUTE, which is the corner itself.
func test_a_dog_leg_is_walked_corner_and_all():
	var trip := _trip_via([Vector2(0, 100)], Vector2.ZERO, Vector2(100, 100))
	assert_almost_eq(trip.travel_seconds(), 200.0 / _WALK, 0.0001, "both legs, not the hypotenuse")
	var half := trip.position_at(trip.travel_seconds() * 0.5)
	assert_almost_eq(half.x, 0.0, 0.0001, "half way is the corner")
	assert_almost_eq(half.y, 100.0, 0.0001)
	var quarter := trip.position_at(trip.travel_seconds() * 0.25)
	assert_almost_eq(quarter.y, 50.0, 0.0001, "and a quarter is half way up the first leg")


## It still ENDS where it was sent, and still counts as arrived exactly
## then -- the two things the rest of the system reads off a trip.
func test_a_detoured_trip_still_arrives_exactly_at_its_destination():
	var trip := _trip_via([Vector2(0, 60), Vector2(-40, 60)], Vector2.ZERO, Vector2(100, 100))
	var end := trip.position_at(trip.travel_seconds())
	assert_almost_eq(end.x, 100.0, 0.0001)
	assert_almost_eq(end.y, 100.0, 0.0001)
	assert_true(trip.is_arrived(trip.travel_seconds()))
	assert_false(trip.is_arrived(trip.travel_seconds() * 0.99))


## ...and it takes LONGER, which is the honest cost of walking round a
## village rather than through it -- not a free teleport along a bent line.
func test_a_detour_costs_real_walking_time():
	var straight := _trip_via([])
	var bent := _trip_via([Vector2(0, 100)])
	assert_gt(bent.travel_seconds(), straight.travel_seconds())


## A raid still lands at its own fraction OF THE ROUTE, so a trip that
## detours is robbed further along the road rather than at the same
## straight-line point it would have been.
func test_a_raid_still_lands_at_its_fraction_of_the_route():
	var trip := _trip_via([Vector2(0, 100)], Vector2.ZERO, Vector2(100, 100))
	trip.raided = true
	trip.raid_fraction = 0.5
	assert_false(trip.raid_triggered(trip.travel_seconds() * 0.49))
	assert_true(trip.raid_triggered(trip.travel_seconds() * 0.5))


## A waypoint that repeats a point cannot make the route zero-length or the
## pace infinite -- a degenerate route still reads as arrived rather than
## dividing by zero, the same guard travel_seconds already had.
func test_a_degenerate_route_reads_as_arrived_rather_than_dividing_by_zero():
	var trip := _trip_via([Vector2.ZERO, Vector2.ZERO], Vector2.ZERO, Vector2.ZERO)
	assert_almost_eq(trip.progress_at(0.0), 1.0, 0.0001)
	assert_eq(trip.position_at(0.0), Vector2.ZERO)
