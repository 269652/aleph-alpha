extends GutTest

## Butterflies FLAP-GLIDE (see FlapGlide), and songbirds flap-bound. Both
## alternate bursts of beating with phases where the wings are not driving,
## which is why their flight does not look metronomic. A bee's does not: it
## has asynchronous flight muscle and hums continuously.
##
## Reported: "can you add more random bounces and flaps?" -- the wing
## animation stepped frames at a fixed rate and the bob was a clean sinusoid
## at a fixed frequency, which is exactly what reads as mechanical.

const FlapGlide = preload("res://src/rendering/flap_glide.gd")
const WingbeatBounce = preload("res://src/rendering/wingbeat_bounce.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")

const CYCLE := 0.09 * 4.0  # one animation wing-beat, as AmbientFlyerMarker drives it


# -- who alternates at all, and why it needs no species list -----------------


## Structural, not a branch. Asynchronous flight muscle is what lets a wing
## beat faster than the nervous system can fire, and it is the whole reason a
## bee can do a couple of hundred beats a second where a butterfly does ten.
## An animal beating that fast is not alternating with anything -- it hums --
## and the frequency it beats at is the thing that says so.
func test_the_high_frequency_fliers_never_glide_and_no_list_says_so():
	for species in ["bee", "fly"]:
		assert_false(
			FlapGlide.glides(species),
			"%s has asynchronous flight muscle -- it hums, it does not flap-glide" % species
		)
	for species in AmbientFlyerRenderer.TRUE_BUTTERFLY_SPECIES_POOL:
		assert_true(FlapGlide.glides(species), "%s flap-glides" % species)
	for species in ["sparrow", "robin", "kingfisher"]:
		assert_true(FlapGlide.glides(species), "%s alternates too (flap-bounding)" % species)


func test_the_threshold_is_the_real_muscle_boundary_not_a_gap_in_this_table():
	for species in WingbeatBounce.FLIGHT.keys():
		var hz: float = float(WingbeatBounce.FLIGHT[species]["wingbeat_hz"])
		assert_eq(
			FlapGlide.glides(species), hz < FlapGlide.ASYNCHRONOUS_MUSCLE_HZ,
			"whether %s alternates must be decided by its beat, not by a roster" % species
		)


# -- how much of the time, and where that number comes from ------------------


## DERIVED, not chosen. In level flight the mean lift over a whole gait cycle
## has to equal body weight. During the non-driving phase the wings supply
## none of it, so the flapping phase has to supply all of it, and the most a
## wing can make is the ceiling WingbeatBounce already derives (a wing cannot
## pull the body DOWN through its stroke, so peak lift is at most twice
## weight). Flapping at that ceiling for a fraction (1-f) of the time and
## making nothing for f of it gives (1-f) x 2W = W, so f = 1/2.
func test_the_glide_share_is_what_level_flight_demands():
	var ceiling := 1.0 + WingbeatBounce.MAX_LIFT_SWING
	assert_almost_eq(
		FlapGlide.GLIDE_FRACTION, 1.0 - 1.0 / ceiling, 0.000001,
		"the share not flapping is fixed by level flight, not picked"
	)
	assert_between(FlapGlide.GLIDE_FRACTION, 0.2, 0.8, "and it lands somewhere watchable")


## A bout has to be a BURST. One beat then a pause is a stutter, not a gait.
func test_a_bout_is_a_burst_of_beats_not_a_single_flap():
	assert_gte(FlapGlide.BOUT_BEATS, 2)
	var gait := FlapGlide.gait_seconds("monarch", CYCLE)
	assert_gte(
		gait * (1.0 - FlapGlide.GLIDE_FRACTION), CYCLE * 2.0 - 0.0001,
		"the flapping half of the gait must be at least two visible beats"
	)
	assert_lt(gait, 2.0, "and the whole thing has to repeat while a player is watching")


func test_a_hummer_has_no_gait_at_all():
	assert_false(FlapGlide.is_gliding("bee", 0.31, CYCLE, 7))
	for step in 100:
		assert_false(
			FlapGlide.is_gliding("bee", float(step) * 0.017, CYCLE, 7),
			"a bee never stops beating"
		)


# -- the gait itself ---------------------------------------------------------


func test_a_butterfly_really_does_spend_that_share_gliding():
	var gliding := 0
	var samples := 4000
	for step in samples:
		if FlapGlide.is_gliding("monarch", float(step) * 0.004, CYCLE, 4242):
			gliding += 1
	assert_almost_eq(
		float(gliding) / float(samples), FlapGlide.GLIDE_FRACTION, 0.02,
		"measured over many gaits, the share must be the one it was derived to be"
	)


func test_two_butterflies_do_not_flap_in_unison():
	var differed := false
	for step in 400:
		var t := float(step) * 0.01
		if FlapGlide.is_gliding("monarch", t, CYCLE, 1) != FlapGlide.is_gliding("monarch", t, CYCLE, 2):
			differed = true
			break
	assert_true(differed, "a meadow full of butterflies must not beat as one")


## The wings only advance while they are BEATING. A gliding butterfly holds
## its wings out; it does not keep cycling the flap frames with nothing
## driving them.
func test_the_wings_hold_still_through_a_glide_and_carry_on_after():
	var last := FlapGlide.wing_cycles("monarch", 0.0, CYCLE, 4242)
	var froze := false
	var resumed := false
	for step in 1200:
		var t := float(step) * 0.005
		var here := FlapGlide.wing_cycles("monarch", t, CYCLE, 4242)
		assert_gte(here, last - 0.0001, "the wing clock must never run backwards")
		if FlapGlide.is_gliding("monarch", t, CYCLE, 4242):
			if absf(here - last) < 0.0001:
				froze = true
		elif froze and here > last + 0.0001:
			resumed = true
		last = here
	assert_true(froze, "the wings must actually pause")
	assert_true(resumed, "...and actually start again")


## Within a bout the beat is not metronomic either. Real wingbeats are
## irregular -- a bout builds and tails off -- and the rate swing is derived
## rather than picked: quasi-steady lift goes as the square of the flapping
## speed, so a lift that can swing by e corresponds to a rate that swings by
## sqrt(1+e) - 1.
func test_the_beat_rate_swings_by_what_the_lift_swing_implies():
	assert_almost_eq(
		FlapGlide.RATE_SWING, sqrt(1.0 + WingbeatBounce.MAX_LIFT_SWING) - 1.0, 0.000001
	)
	assert_lt(FlapGlide.RATE_SWING, 1.0, "or the wing clock could run backwards")


func test_the_beat_within_a_bout_is_not_a_fixed_rate():
	var fastest := 0.0
	var slowest := INF
	var dt := 0.002
	for step in 600:
		var t := float(step) * dt
		if FlapGlide.is_gliding("monarch", t, CYCLE, 4242):
			continue
		if FlapGlide.is_gliding("monarch", t + dt, CYCLE, 4242):
			continue
		var rate := (
			FlapGlide.wing_cycles("monarch", t + dt, CYCLE, 4242)
			- FlapGlide.wing_cycles("monarch", t, CYCLE, 4242)
		) / dt
		fastest = maxf(fastest, rate)
		slowest = minf(slowest, rate)
	assert_gt(fastest - slowest, 0.1, "the wingbeat must genuinely vary, not tick")


func test_a_hummers_wings_never_pause_and_beat_at_the_plain_rate():
	for step in 200:
		var t := float(step) * 0.01
		assert_almost_eq(
			FlapGlide.wing_cycles("bee", t, CYCLE, 7), t / CYCLE, 0.0001,
			"nothing may modulate a continuous hum"
		)


# -- what the BODY does under that gait --------------------------------------

const FRAMES := 4
const PER_FRAME := 0.09
const BODY_PX := 20.0


func _body(t: float, seed_value: int = 4242) -> float:
	return FlapGlide.body_offset("monarch", t, PER_FRAME, FRAMES, BODY_PX, seed_value)


## The bounce follows whatever the WINGS are doing. When they stop, the bob
## stops with them -- a gliding butterfly does not go on bobbing as though
## something were still pulsing lift into it.
func test_the_bob_stops_when_the_wings_do():
	var while_gliding := []
	for step in 2000:
		var t := float(step) * 0.004
		if FlapGlide.is_gliding("monarch", t, CYCLE, 4242):
			while_gliding.append(_body(t))
	assert_gt(while_gliding.size(), 50, "precondition: it glides at all")
	# Through a glide the body only ever descends -- no oscillation left.
	var reversals := 0
	for i in range(1, while_gliding.size()):
		if while_gliding[i] < while_gliding[i - 1] - 0.0001:
			reversals += 1
	assert_lt(
		float(reversals) / float(while_gliding.size()), 0.15,
		"a glide is a sink, not a bob (some samples straddle a gait boundary)"
	)


## ...and it SINKS while it does. Screen-up is -Y, so sinking is positive.
func test_the_body_sinks_through_a_glide_and_climbs_back_through_the_bout():
	var lowest := -INF
	var highest := INF
	for step in 2000:
		var here := _body(float(step) * 0.004)
		lowest = maxf(lowest, here)
		highest = minf(highest, here)
	assert_gt(lowest, 0.5, "it must genuinely sink")
	assert_lt(highest, -0.5, "and genuinely rise")


## LEVEL FLIGHT: the sag a glide costs is exactly what the next bout gains, so
## over whole gaits the body has no net drift. A bounce that drifted would
## walk the sprite off its own body.
func test_a_whole_gait_leaves_the_body_where_it_started():
	var gait := FlapGlide.gait_seconds("monarch", CYCLE)
	for beat in 6:
		assert_almost_eq(
			_body(gait * float(beat)), _body(0.0), 0.001,
			"a flap-glide gait is a sawtooth with no net drift"
		)


## It still has to stay inside the animal. The ceiling is now the bob plus the
## sag rather than the bob alone -- both are real, and both are a fraction of
## the same body.
func test_the_bounce_never_leaves_the_body():
	var ceiling := WingbeatBounce.amplitude_bodies("monarch") * BODY_PX * 2.0
	for step in 3000:
		assert_lte(absf(_body(float(step) * 0.0031)), ceiling + 0.0001)


func test_two_butterflies_do_not_bounce_in_unison():
	var apart := 0.0
	for step in 400:
		var t := float(step) * 0.01
		apart = maxf(apart, absf(_body(t, 1) - _body(t, 2)))
	assert_gt(apart, 1.0, "no two of them may bob together")


## A flyer whose sprite generator gave it no frames has no beat to lock to --
## the same fallback WingbeatBounce has, for the same reason.
func test_a_flyer_with_no_wing_beat_does_not_bounce():
	assert_eq(FlapGlide.body_offset("monarch", 1.0, PER_FRAME, 0, BODY_PX, 7), 0.0)
	assert_eq(FlapGlide.body_offset("monarch", 1.0, 0.0, FRAMES, BODY_PX, 7), 0.0)


## A hummer has no gait, so its body does exactly what WingbeatBounce says and
## nothing else -- which for a bee is an amplitude nothing can draw anyway.
func test_a_hummers_body_is_still_just_the_plain_bob():
	for step in 50:
		var t := float(step) * 0.013
		assert_almost_eq(
			FlapGlide.body_offset("bee", t, PER_FRAME, FRAMES, BODY_PX, 7),
			WingbeatBounce.bounce_offset("bee", t, PER_FRAME, FRAMES, BODY_PX),
			0.0001
		)
