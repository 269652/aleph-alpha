extends GutTest

## Fish wake timing (see FishMarker._step_water_ripple).
##
## Every fish used a constant interval and started its accumulator at zero, so
## a whole shoal fired its rings on the SAME tick, forever -- a pond full of
## fish pulsing in unison, which reads as a mechanism rather than as wildlife
## (reported: "fish are producing a ring at the exact same time which looks
## unnatural ... also the interval should vary so it appears more random and
## less ticked").
##
## Both the phase offset and each successive interval are now derived from the
## fish's own seed, so the tuning is a tested function rather than an
## eyeballed constant.

const FishMarker = preload("res://src/rendering/fish_marker.gd")


func test_each_fish_starts_its_ripple_cycle_at_a_different_phase():
	var phases := {}
	for seed_value in 30:
		phases[snappedf(FishMarker.ripple_phase_offset(seed_value), 0.001)] = true
	assert_gt(phases.size(), 5, "a shoal must not all start on the same tick")


func test_a_phase_offset_never_exceeds_one_full_interval():
	for seed_value in 30:
		assert_between(FishMarker.ripple_phase_offset(seed_value), 0.0, FishMarker.RIPPLE_INTERVAL_MAX)


func test_successive_intervals_of_one_fish_vary():
	var intervals := {}
	for index in 20:
		intervals[snappedf(FishMarker.ripple_interval(4242, index), 0.001)] = true
	assert_gt(intervals.size(), 5, "one fish's own rhythm should not be metronomic")


func test_every_interval_stays_within_its_declared_bounds():
	for seed_value in 8:
		for index in 8:
			assert_between(
				FishMarker.ripple_interval(seed_value, index),
				FishMarker.RIPPLE_INTERVAL_MIN,
				FishMarker.RIPPLE_INTERVAL_MAX
			)


func test_two_fish_do_not_share_a_rhythm():
	var a: Array[float] = []
	var b: Array[float] = []
	for index in 6:
		a.append(FishMarker.ripple_interval(1, index))
		b.append(FishMarker.ripple_interval(2, index))
	assert_ne(a, b)


func test_timing_is_deterministic():
	assert_eq(FishMarker.ripple_interval(9, 3), FishMarker.ripple_interval(9, 3))
	assert_eq(FishMarker.ripple_phase_offset(9), FishMarker.ripple_phase_offset(9))


## A fish glides; it should not churn the surface, and it is the biggest
## consumer of the shared fixed-size disturbance buffer.
func test_fish_stay_unhurried_enough_not_to_flood_the_ripple_buffer():
	assert_gte(FishMarker.RIPPLE_INTERVAL_MIN, 1.0)
	assert_gt(FishMarker.RIPPLE_INTERVAL_MAX, FishMarker.RIPPLE_INTERVAL_MIN)
