extends GutTest

## ChargeMeter: the "strengthometer" for the hold-E-to-charge-then-release
## throw (see docs/concept/stone.md). A classic charge-meter minigame value
## that bounces back and forth between a min and a max repeatedly while held
## -- NOT a monotonically-filling bar -- so release power depends on exact
## TIMING, not just how long E was held. Pure function of elapsed time: no
## state of its own (the caller tracks "how long has E been held").

const ChargeMeter = preload("res://src/gameplay/charge_meter.gd")


func test_fraction_at_zero_elapsed_is_at_the_minimum():
	assert_almost_eq(ChargeMeter.fraction_at(0.0), ChargeMeter.MIN_FRACTION, 0.001)


func test_fraction_at_half_a_period_is_at_the_maximum():
	assert_almost_eq(
		ChargeMeter.fraction_at(ChargeMeter.BOUNCE_PERIOD_SECONDS / 2.0), ChargeMeter.MAX_FRACTION, 0.001
	)


func test_fraction_returns_to_the_minimum_after_a_full_period():
	assert_almost_eq(ChargeMeter.fraction_at(ChargeMeter.BOUNCE_PERIOD_SECONDS), ChargeMeter.MIN_FRACTION, 0.001)


## The whole point: it BOUNCES rather than climbing forever -- elapsed times
## well past several periods must still land back at the minimum on a period
## boundary, not saturate at the maximum forever.
func test_fraction_keeps_bouncing_across_many_periods_rather_than_saturating():
	for cycles in [1, 2, 5, 10]:
		var elapsed := ChargeMeter.BOUNCE_PERIOD_SECONDS * float(cycles)
		assert_almost_eq(
			ChargeMeter.fraction_at(elapsed), ChargeMeter.MIN_FRACTION, 0.001,
			"cycle %d should be back at the minimum" % cycles
		)


func test_fraction_always_stays_within_its_own_bounds():
	var t := 0.0
	while t <= ChargeMeter.BOUNCE_PERIOD_SECONDS * 4.0:
		var value := ChargeMeter.fraction_at(t)
		assert_between(value, ChargeMeter.MIN_FRACTION, ChargeMeter.MAX_FRACTION)
		t += 0.05


## Rising then falling -- a quarter and three-quarters through a period
## should read as (roughly) the same intermediate value, mirrored around the
## midpoint peak, not a sawtooth that snaps back down.
func test_fraction_rises_then_falls_symmetrically_within_one_period():
	var quarter := ChargeMeter.fraction_at(ChargeMeter.BOUNCE_PERIOD_SECONDS * 0.25)
	var three_quarters := ChargeMeter.fraction_at(ChargeMeter.BOUNCE_PERIOD_SECONDS * 0.75)
	assert_almost_eq(quarter, three_quarters, 0.001)
	assert_gt(quarter, ChargeMeter.MIN_FRACTION)
	assert_lt(quarter, ChargeMeter.MAX_FRACTION)


func test_fraction_is_deterministic():
	assert_eq(ChargeMeter.fraction_at(1.234), ChargeMeter.fraction_at(1.234))
