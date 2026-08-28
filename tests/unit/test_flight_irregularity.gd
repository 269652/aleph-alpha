extends GutTest

## The one place this game says "a butterfly's path never repeats the same arc
## twice" (see FlightIrregularity).
##
## Reported: the two butterfly interactions are "overly dramatic and only a
## circle". Real spiral and courtship flights are chaotic ascending chases --
## irregular, jagged, never a clean ellipse -- and that irregularity is not
## decoration: erratic, unpredictable ("protean") flight is a real
## anti-predator adaptation, which is a large part of why butterflies fly the
## way they do.
##
## This module holds that irregularity ONCE. It was already in the game, in
## PollinatorForaging.tumbled_heading's two-frequency swing; a second,
## slightly different wobble for the dances would be the same statement made
## twice with two sets of numbers to keep in step.

const FlightIrregularity = preload("res://src/gameplay/flight_irregularity.gd")
const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")


func test_the_wobble_stays_inside_plus_or_minus_one():
	for step in 400:
		var w := FlightIrregularity.wobble(float(step) * 0.017, 12345)
		assert_between(w, -1.0, 1.0, "callers scale this, so it has to be normalised")


## The point of the whole module: it must not be a sine. A single frequency
## reads as a regular slalom, where a real butterfly's path never traces the
## same arc twice.
func test_the_wobble_is_not_a_single_sine():
	# A pure sine is exactly antisymmetric about its own half period. Sampling
	# both halves of one period of the FAST component and comparing tells the
	# two apart without asserting any particular waveform.
	var fast_period := TAU / FlightIrregularity.FAST_RADIANS_PER_SECOND
	var worst := 0.0
	for step in 60:
		var t := float(step) * fast_period / 60.0
		worst = maxf(
			worst,
			absf(
				FlightIrregularity.wobble(t, 7)
				+ FlightIrregularity.wobble(t + fast_period * 0.5, 7)
			)
		)
	assert_gt(worst, 0.1, "a pure sine would cancel here; this must not")


func test_two_individuals_wobble_differently():
	var apart := 0.0
	for step in 200:
		var t := float(step) * 0.021
		apart = maxf(apart, absf(FlightIrregularity.wobble(t, 1) - FlightIrregularity.wobble(t, 2)))
	assert_gt(apart, 0.3, "no two butterflies may trace the same figure")


func test_the_same_individual_is_deterministic():
	assert_eq(FlightIrregularity.wobble(1.234, 99), FlightIrregularity.wobble(1.234, 99))


## The integral is what makes a BREATHING ORBIT physically exact rather than
## approximate: a flyer holding a constant airspeed on a radius that varies
## turns at w = v/r, and the angle it has swept is the integral of that. The
## integral of this wobble is closed-form (it is a sum of sines), so no caller
## has to accumulate state to get it right.
func test_the_integral_really_is_the_integral_of_the_wobble():
	var seed_value := 4242
	var dt := 0.0005
	var running := 0.0
	var t := 0.0
	for step in 2000:
		# Midpoint rule, so this converges fast enough to assert tightly.
		running += FlightIrregularity.wobble(t + dt * 0.5, seed_value) * dt
		t += dt
		if step % 400 == 399:
			assert_almost_eq(
				FlightIrregularity.wobble_integral(t, seed_value), running, 0.0005,
				"the closed form must agree with numerical integration"
			)


func test_the_integral_starts_at_zero_so_nothing_jumps_at_t_zero():
	for seed_value in [0, 1, 7, 4242, -13]:
		assert_almost_eq(
			FlightIrregularity.wobble_integral(0.0, seed_value), 0.0, 0.000001,
			"an orbit must begin exactly where the flyer already is"
		)


## The irregularity a butterfly's FLIGHT PATH already had, and the one the
## dances now get, must be the same statement -- one spectrum, not two.
func test_the_tumble_and_the_dances_share_one_spectrum():
	assert_almost_eq(
		FlightIrregularity.FAST_RADIANS_PER_SECOND,
		PollinatorForaging.TUMBLE_FREQUENCY,
		0.000001,
		"the flutter's own frequency IS this module's, not a second copy of it"
	)
