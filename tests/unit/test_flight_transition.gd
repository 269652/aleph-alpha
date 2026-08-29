extends GutTest

## How a flyer gets from one thing it is doing to the next without teleporting
## (see FlightTransition). The duration model is a DIVISION -- the gap over the
## flyer's own airspeed -- so there is no tuned number here to pin, only the
## relations between the pieces.

const FlightTransition = preload("res://src/rendering/flight_transition.gd")
const FlyerPersonality = preload("res://src/gameplay/flyer_personality.gd")
const SpiralFlight = preload("res://src/gameplay/spiral_flight.gd")
const Courtship = preload("res://src/gameplay/courtship.gd")
const NectaringPosture = preload("res://src/rendering/nectaring_posture.gd")
const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")


# -- the duration is derived, never picked -----------------------------------


func test_crossing_a_gap_takes_the_gap_divided_by_the_flyers_own_airspeed():
	assert_almost_eq(FlightTransition.crossing_seconds(8.0, 16.0), 0.5, 0.0001)


func test_a_faster_flyer_crosses_the_same_gap_sooner():
	assert_lt(
		FlightTransition.crossing_seconds(8.0, 32.0),
		FlightTransition.crossing_seconds(8.0, 16.0),
		"a bee sets down quicker than a monarch, with no second number for it"
	)


func test_a_motionless_flyer_does_not_divide_by_its_own_airspeed():
	assert_eq(FlightTransition.crossing_seconds(8.0, 0.0), 0.0)
	assert_eq(FlightTransition.settling_seconds(8.0, 0.0), 0.0)


func test_a_gap_that_is_already_closed_takes_no_time():
	assert_eq(FlightTransition.crossing_seconds(0.0, 16.0), 0.0)
	assert_eq(FlightTransition.crossing_seconds(-3.0, 16.0), 0.0)


# -- the ease --------------------------------------------------------------


func test_the_ease_runs_from_nought_to_one_without_overshoot():
	assert_eq(FlightTransition.eased_progress(0.0, 0.25), 0.0, "starts where it left")
	assert_eq(FlightTransition.eased_progress(0.25, 0.25), 1.0, "ends where it is going")
	assert_eq(FlightTransition.eased_progress(9.0, 0.25), 1.0, "and stays there")
	for i in 200:
		assert_between(FlightTransition.eased_progress(float(i) * 0.002, 0.25), 0.0, 1.0)


func test_a_zero_length_transition_is_simply_already_over():
	assert_eq(FlightTransition.eased_progress(0.0, 0.0), 1.0)


func test_the_ease_is_smooth_at_both_ends():
	var last := FlightTransition.eased_progress(1.0, 1.0) - FlightTransition.eased_progress(0.9, 1.0)
	var middle := FlightTransition.eased_progress(0.55, 1.0) - FlightTransition.eased_progress(0.45, 1.0)
	var first := FlightTransition.eased_progress(0.1, 1.0) - FlightTransition.eased_progress(0.0, 1.0)
	assert_lt(last, middle, "it must ease OUT rather than stop dead")
	assert_lt(first, middle, "and ease IN rather than start at full speed")


## The bug the whole module exists to prevent, in the one place it could still
## have hidden: an eased crossing is not moving at its average rate. It peaks
## at EASE_PEAK_RATE times that halfway through, so a settle sized as
## `gap / airspeed` outflies the animal by half again exactly where the eye is.
func test_the_peak_of_a_smoothstepped_settle_is_exactly_the_flyers_airspeed():
	var airspeed := 16.0
	var gap := 4.0
	var span := FlightTransition.settling_seconds(gap, airspeed)
	var step := span / 400.0
	var fastest := 0.0
	for i in 400:
		var a := FlightTransition.eased_progress(float(i) * step, span)
		var b := FlightTransition.eased_progress(float(i + 1) * step, span)
		fastest = maxf(fastest, (b - a) * gap / step)
	assert_almost_eq(
		fastest, airspeed, airspeed * 0.02,
		"nothing may move faster than the flyer's own airspeed, not even mid-settle"
	)


func test_the_peak_rate_is_the_derivative_of_the_ease_not_a_number_somebody_liked():
	# max of d/dt t*t*(3 - 2t) = 6t(1 - t) is 1.5, at t = 0.5.
	assert_almost_eq(FlightTransition.EASE_PEAK_RATE, 6.0 * 0.5 * 0.5, 0.0001)


func test_an_eased_crossing_is_stretched_by_exactly_that():
	assert_almost_eq(
		FlightTransition.settling_seconds(8.0, 16.0),
		FlightTransition.EASE_PEAK_RATE * FlightTransition.crossing_seconds(8.0, 16.0),
		0.0001
	)


func test_the_eased_position_starts_where_it_left_and_ends_where_it_is_going():
	var from := Vector2(3.0, -4.0)
	var to := Vector2(20.0, 11.0)
	assert_eq(FlightTransition.eased_position(from, to, 0.0, 0.5), from)
	assert_eq(FlightTransition.eased_position(from, to, 0.5, 0.5), to)
	assert_eq(FlightTransition.eased_position(from, to, 5.0, 0.5), to)


# -- the ceiling -------------------------------------------------------------


## Not a new number: the burst multiple is already
## FlyerPersonality.ESCAPE_SPEED_MULTIPLIER, which is itself
## SpiralFlight.BURST_SPEED_MPS over Courtship.CRUISE_SPEED_MPS.
func test_the_burst_is_the_burst_this_game_already_derived():
	assert_almost_eq(
		FlightTransition.burst_px_per_second(16.0),
		16.0 * SpiralFlight.BURST_SPEED_MPS / Courtship.CRUISE_SPEED_MPS,
		0.0001
	)
	assert_almost_eq(
		FlightTransition.burst_px_per_second(16.0),
		16.0 * FlyerPersonality.ESCAPE_SPEED_MULTIPLIER,
		0.0001
	)


func test_the_step_ceiling_is_simply_how_far_that_airspeed_carries_it():
	assert_almost_eq(FlightTransition.step_ceiling_px(16.0, 1.0 / 60.0), 16.0 / 60.0, 0.0001)
	assert_eq(FlightTransition.step_ceiling_px(16.0, 0.0), 0.0)


# -- the site that was already right, now sharing the same one implementation -


## NectaringPosture derived its landing this way first (see its own
## alighting_seconds). It now delegates, so there is one implementation of
## "how long does covering that gap take" rather than two that can drift.
func test_the_nectaring_landing_is_this_module_specialised_to_the_last_gap():
	assert_almost_eq(
		NectaringPosture.alighting_seconds(16.0),
		FlightTransition.settling_seconds(PollinatorForaging.LANDING_DISTANCE, 16.0),
		0.0001
	)
	assert_almost_eq(
		NectaringPosture.alighting_ease(0.3, 1.0), FlightTransition.eased_progress(0.3, 1.0), 0.0001
	)
