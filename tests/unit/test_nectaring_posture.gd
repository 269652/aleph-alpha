extends GutTest

## What a butterfly does while it stands on a bloom and drinks -- the WINGS
## (shut over the back, opened only occasionally to bask) and the FEET
## (shuffling around the flower head, working different florets).
##
## Every number here is pinned by the property that grounds it, never by the
## literal: the cycle is slower than the flight beat by an order of magnitude,
## the wings are shut for most of it, one stop shows at most one opening, and
## the shuffle never carries the insect off the bloom it is standing on.

const NectaringPosture = preload("res://src/rendering/nectaring_posture.gd")
const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")
const AmbientFlyerMarker = preload("res://src/rendering/ambient_flyer_marker.gd")
const ProceduralButterflySprite = preload("res://src/rendering/procedural_butterfly_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const FishRenderer = preload("res://src/rendering/fish_renderer.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const FlightTransition = preload("res://src/rendering/flight_transition.gd")

const SEED := 4242


# -- the wings --------------------------------------------------------------


## THE headline number. A butterfly's flight stroke in this game runs a whole
## wing-beat in AmbientFlyerMarker.FLAP_SECONDS_PER_FRAME x
## ProceduralButterflySprite.FLAP_FRAME_COUNT = 0.36 s (about 2.8 beats a
## second). Nectaring wing movement is not a slower flap -- it is a different
## behaviour on a different timescale: the wings sit shut and open once every
## few SECONDS. An order of magnitude is the weakest form of that statement
## and the one worth pinning.
func test_the_settled_cycle_is_an_order_of_magnitude_slower_than_the_flight_beat():
	var beat := (
		AmbientFlyerMarker.FLAP_SECONDS_PER_FRAME
		* float(ProceduralButterflySprite.FLAP_FRAME_COUNT)
	)
	assert_gt(
		NectaringPosture.SECONDS_PER_CYCLE / beat, 10.0,
		"a feeding butterfly's wings must move on a wholly different timescale"
			+ " from its flight stroke (%.2fs cycle vs %.2fs beat)"
				% [NectaringPosture.SECONDS_PER_CYCLE, beat]
	)


## "Opened only slowly and occasionally": within ONE stop the wings may open
## at most once. That is what makes it read as basking rather than as a slow
## rhythm, and it is exactly why the cycle is longer than a whole drink.
func test_the_wings_open_at_most_once_during_a_single_drink():
	for start in 40:
		var t0 := float(start) * NectaringPosture.SECONDS_PER_CYCLE / 40.0
		var openings := 0
		var was_shut := true
		var steps := 240
		for i in steps:
			var t := t0 + PollinatorForaging.DRINK_SECONDS * float(i) / float(steps)
			var open := NectaringPosture.openness_fraction(t, SEED) > 0.0
			if open and was_shut:
				openings += 1
			was_shut = not open
		assert_lte(
			openings, 1,
			"a butterfly on one bloom must not open and shut repeatedly (t0=%.2f, %d openings)"
				% [t0, openings]
		)


## The dominant pose is SHUT. A nectaring butterfly holds the wings closed
## over its back and the opening is the exception, so most of the cycle must
## be spent fully shut -- not half, not a smooth sine that is only briefly at
## either extreme.
func test_the_wings_are_shut_for_most_of_the_cycle():
	var shut := 0
	var samples := 2000
	for i in samples:
		var t := NectaringPosture.SECONDS_PER_CYCLE * float(i) / float(samples)
		if NectaringPosture.openness_fraction(t, SEED) <= 0.0:
			shut += 1
	var fraction := float(shut) / float(samples)
	assert_gt(
		fraction, 0.5,
		"the wings must be shut for the majority of a feeding stop (shut %.0f%% of the time)"
			% [fraction * 100.0]
	)
	assert_almost_eq(
		fraction, NectaringPosture.closed_duty(), 0.02,
		"and that majority must be exactly the duty the opening duration implies"
	)


## The opening itself is a real, observable swing of about half a second each
## way -- not an instant snap (which would pop at any frame rate) and not a
## drawn-out morph.
func test_one_opening_takes_about_half_a_second_each_way():
	assert_between(
		NectaringPosture.OPENING_SECONDS, 0.3, 1.0,
		"a basking wing swings open in a fraction of a second, not instantly and not for ages"
	)
	# ...and the excursion in the cycle really does last twice that: open, shut.
	var duty := NectaringPosture.closed_duty()
	assert_almost_eq(
		(1.0 - duty) * NectaringPosture.SECONDS_PER_CYCLE,
		2.0 * NectaringPosture.OPENING_SECONDS,
		0.001,
		"the shut duty must be DERIVED from the swing duration, not a second free number"
	)


func test_the_wings_do_actually_reach_fully_open():
	var widest := 0.0
	var samples := 2000
	for i in samples:
		var t := NectaringPosture.SECONDS_PER_CYCLE * float(i) / float(samples)
		widest = maxf(widest, NectaringPosture.openness_fraction(t, SEED))
	assert_almost_eq(widest, 1.0, 0.01, "a basking butterfly opens all the way, not part way")


func test_openness_never_leaves_zero_to_one():
	for i in 5000:
		var t := float(i) * 0.013
		var openness := NectaringPosture.openness_fraction(t, SEED)
		assert_between(openness, 0.0, 1.0, "openness is a fraction at t=%.3f" % t)


## Two butterflies on neighbouring blooms must not bask in unison -- the same
## per-individual phase every other flyer behaviour in this codebase uses (see
## FlightIrregularity.phase), rather than a shared global clock.
func test_two_butterflies_do_not_open_their_wings_in_unison():
	var differed := false
	for i in 400:
		var t := float(i) * 0.02
		if not is_equal_approx(
			NectaringPosture.openness_fraction(t, 1), NectaringPosture.openness_fraction(t, 77)
		):
			differed = true
			break
	assert_true(differed, "two individuals must not share one basking clock")


func test_the_frame_index_stays_inside_the_frame_array():
	for count in [1, 2, 3, 4, 7]:
		for i in 900:
			var index := NectaringPosture.frame_index(float(i) * 0.017, count, SEED)
			assert_between(index, 0, count - 1, "index must address a real frame (count %d)" % count)


func test_the_frame_index_holds_the_fully_shut_frame_for_most_of_the_cycle():
	var shut := 0
	var samples := 2000
	for i in samples:
		var t := NectaringPosture.SECONDS_PER_CYCLE * float(i) / float(samples)
		if NectaringPosture.frame_index(t, 4, SEED) == 0:
			shut += 1
	assert_gt(
		float(shut) / float(samples), 0.5,
		"frame 0 is the wings-shut pose and it is the one a feeding butterfly mostly holds"
	)


func test_an_empty_frame_set_does_not_index_out_of_bounds():
	assert_eq(NectaringPosture.frame_index(1.0, 0, SEED), 0)


# -- the feet ---------------------------------------------------------------


## A real flower head is a couple of centimetres across and the insect walks
## around it, so the excursion is bounded by the HEAD, not by anything about
## the meadow. Bounded absolutely -- this is an offset from a fixed anchor,
## never an accumulating step, which is the only reason it cannot drift.
func test_the_shuffle_never_leaves_the_flower_head():
	var reach := NectaringPosture.shuffle_reach_px(10.0)
	for i in 4000:
		var offset := NectaringPosture.shuffle_offset(float(i) * 0.011, 10.0, SEED)
		assert_lte(
			offset.length(), reach + 0.0001,
			"the insect must stay on the bloom it is standing on (t=%.3f)" % [float(i) * 0.011]
		)


func test_the_shuffle_actually_moves_it_rather_than_freezing_it():
	var seen: Array[Vector2] = []
	for i in 60:
		seen.append(NectaringPosture.shuffle_offset(float(i) * 0.1, 10.0, SEED))
	var spread := 0.0
	for a in seen:
		for b in seen:
			spread = maxf(spread, a.distance_to(b))
	assert_gt(
		spread, 0.5 * NectaringPosture.shuffle_reach_px(10.0),
		"a feeding butterfly works different florets -- it is never a frozen pixel"
	)


## The bloom is a POINT to the forage rule (PollinatorForaging.LANDING_
## DISTANCE is how close counts as landed), so the shuffle has to stay well
## inside that or "landed on this flower" and "standing on this flower" stop
## meaning the same thing. Measured on the real drawn monarch, not on a
## convenient number.
func test_a_real_monarchs_shuffle_stays_well_inside_the_landing_distance():
	var body_px := (
		float(ProceduralButterflySprite.SIZE.y)
		* ArtResolution.SPRITE_SCALE
		* FishRenderer.FISH_WORLD_SCALE
		* float(AmbientFlyerRenderer.FLYER_WORLD_SCALE["monarch"])
	)
	var reach := NectaringPosture.shuffle_reach_px(body_px)
	assert_gt(reach, 0.0, "precondition: a drawn monarch has a real body to scale against")
	assert_lt(
		reach, PollinatorForaging.LANDING_DISTANCE,
		"a shuffle wider than the landing distance would stop reading as ON the bloom"
			+ " (reach %.3f px, landing distance %.1f px)"
				% [reach, PollinatorForaging.LANDING_DISTANCE]
	)


func test_a_flyer_with_no_drawn_body_yet_simply_does_not_shuffle():
	assert_eq(NectaringPosture.shuffle_offset(1.0, 0.0, SEED), Vector2.ZERO)


# -- alighting: land, never teleport ----------------------------------------


## The snap this replaced was `position = _forage_target`, a hard jump of up
## to LANDING_DISTANCE. The settle is as long as covering that last gap takes
## at the flyer's OWN airspeed -- derived, so a bee (faster) sets down quicker
## than a monarch without a second tuned number existing.
##
## It was `LANDING_DISTANCE / airspeed` exactly, and that was half a right
## answer: that is the AVERAGE rate, and the settle is smoothstepped, so the
## insect flew FlightTransition.EASE_PEAK_RATE times its own airspeed halfway
## through the very move that exists to stop it teleporting (measured on a
## monarch: 0.467 px on a frame that carries it 0.267). The crossing is now
## stretched by exactly that factor, so the PEAK is the airspeed.
func test_the_alighting_takes_the_last_gap_at_the_flyers_own_airspeed():
	assert_almost_eq(
		NectaringPosture.alighting_seconds(16.0),
		FlightTransition.EASE_PEAK_RATE * PollinatorForaging.LANDING_DISTANCE / 16.0,
		0.0001,
		"the settle is the last gap flown, not an invented duration"
	)
	assert_lt(
		NectaringPosture.alighting_seconds(32.0),
		NectaringPosture.alighting_seconds(16.0),
		"a faster flyer sets down quicker"
	)


func test_the_alighting_is_short_enough_to_leave_a_real_drink_behind_it():
	assert_lt(
		NectaringPosture.alighting_seconds(16.0),
		0.5 * PollinatorForaging.DRINK_SECONDS,
		"landing must be a moment at the start of the stop, not most of the stop"
	)


func test_a_motionless_flyer_does_not_divide_by_its_own_airspeed():
	assert_eq(NectaringPosture.alighting_seconds(0.0), 0.0)


func test_the_alighting_ease_runs_from_nought_to_one_without_overshoot():
	assert_eq(NectaringPosture.alighting_ease(0.0, 0.25), 0.0, "starts where it touched down")
	assert_eq(NectaringPosture.alighting_ease(0.25, 0.25), 1.0, "ends on the bloom")
	assert_eq(NectaringPosture.alighting_ease(9.0, 0.25), 1.0, "and stays there")
	for i in 200:
		var eased := NectaringPosture.alighting_ease(float(i) * 0.002, 0.25)
		assert_between(eased, 0.0, 1.0, "no overshoot on the way in")


func test_the_alighting_ease_is_smooth_at_both_ends():
	# A linear settle arrives at full speed and stops dead; a smoothstep eases
	# out. Pinned as: the last tenth of the settle covers less ground than the
	# middle tenth does.
	var last := (
		NectaringPosture.alighting_ease(1.0, 1.0) - NectaringPosture.alighting_ease(0.9, 1.0)
	)
	var middle := (
		NectaringPosture.alighting_ease(0.55, 1.0) - NectaringPosture.alighting_ease(0.45, 1.0)
	)
	assert_lt(last, middle, "the flyer must ease onto the bloom, not arrive at full speed")


func test_a_zero_length_settle_is_simply_already_landed():
	assert_eq(NectaringPosture.alighting_ease(0.0, 0.0), 1.0)


# -- the feet, at a walking pace ---------------------------------------------
#
# The shuffle is a WALK around a flower head, and it was read straight off
# FlightIrregularity -- a FLYING insect's wobble, about one veer a second. On a
# real drawn monarch that carried it 0.338 px per frame, against the 0.267 px
# its own airspeed carries it: a butterfly standing on a flower was outrunning
# a butterfly in flight, which on screen is a vibration rather than an insect
# working a bloom. It now runs on the settled clock instead (see
# SHUFFLE_TIME_SCALE), which is the same clock the wings bask on.

const FlightIrregularity = preload("res://src/gameplay/flight_irregularity.gd")

const A_BUTTERFLY_AIRSPEED := 16.0


func _drawn_monarch_body_px() -> float:
	return (
		float(ProceduralButterflySprite.SIZE.y)
		* ArtResolution.SPRITE_SCALE
		* FishRenderer.FISH_WORLD_SCALE
		* float(AmbientFlyerRenderer.FLYER_WORLD_SCALE["monarch"])
	)


func _fastest_shuffle_px_per_second(body_px: float, seed_value: int) -> float:
	var step := 1.0 / 600.0
	var fastest := 0.0
	var previous := NectaringPosture.shuffle_offset(0.0, body_px, seed_value)
	for i in 24000:
		var now := NectaringPosture.shuffle_offset(float(i + 1) * step, body_px, seed_value)
		fastest = maxf(fastest, previous.distance_to(now) / step)
		previous = now
	return fastest


func test_the_shuffle_is_a_walk_not_a_flight():
	assert_lt(
		NectaringPosture.SHUFFLE_TIME_SCALE, 1.0,
		"a standing insect works the head slower than a flying one veers"
	)


## The bug, at the site it was measured: a real drawn monarch on a real flower.
func test_a_real_monarch_shuffles_slower_than_it_flies():
	var body := _drawn_monarch_body_px()
	assert_lt(
		_fastest_shuffle_px_per_second(body, SEED), A_BUTTERFLY_AIRSPEED,
		"a butterfly standing on a flower must not outrun one in flight"
	)


func test_and_its_stated_peak_bounds_what_it_actually_does():
	var body := _drawn_monarch_body_px()
	assert_lte(
		_fastest_shuffle_px_per_second(body, SEED),
		NectaringPosture.shuffle_peak_px_per_second(body),
		"the budget the alighting is sized against has to actually bound the walk"
	)


## ...and still MOVES. The whole reason the shuffle exists is that a butterfly
## motionless on one pixel for 2.4 seconds is what "stuck in front of a flower"
## described, so slowing it must not have frozen it again.
func test_a_slower_shuffle_still_works_the_whole_flower_head():
	var body := _drawn_monarch_body_px()
	var seen: Array[Vector2] = []
	for i in 60:
		seen.append(NectaringPosture.shuffle_offset(float(i) * 0.04, body, SEED))
	var spread := 0.0
	for a in seen:
		for b in seen:
			spread = maxf(spread, a.distance_to(b))
	assert_gt(
		spread, 0.5 * NectaringPosture.shuffle_reach_px(body),
		"within one drink it must still work different florets (%.3f px)" % spread
	)


## The alighting has to pay for the walk it fades in, or the two spend the same
## airspeed twice -- which is exactly what put a settling butterfly at 0.469 px
## on a frame that carries it 0.267.
func test_the_alighting_is_sized_for_the_walk_it_fades_in_as_well():
	var body := _drawn_monarch_body_px()
	assert_gt(
		NectaringPosture.alighting_seconds(A_BUTTERFLY_AIRSPEED, body),
		NectaringPosture.alighting_seconds(A_BUTTERFLY_AIRSPEED),
		"a settle that also brings a shuffle in has further to go and less to go on"
	)


func test_and_it_is_still_a_moment_at_the_start_of_the_stop():
	assert_lt(
		NectaringPosture.alighting_seconds(A_BUTTERFLY_AIRSPEED, _drawn_monarch_body_px()),
		0.5 * PollinatorForaging.DRINK_SECONDS,
		"landing must not eat the drink it is the start of"
	)


## Neither the settle NOR the walk on top of it may outrun the animal. This is
## the module-level half of the marker's own invariant test.
func test_the_settle_and_the_walk_together_never_outrun_the_flyer():
	var body := _drawn_monarch_body_px()
	var span := NectaringPosture.alighting_seconds(A_BUTTERFLY_AIRSPEED, body)
	var anchor := Vector2(PollinatorForaging.LANDING_DISTANCE, 0.0)
	var step := 1.0 / 600.0
	var fastest := 0.0
	var previous := Vector2.ZERO
	for i in 6000:
		var t := float(i + 1) * step
		var settled := NectaringPosture.alighting_ease(t, span)
		var now := (
			Vector2.ZERO.lerp(anchor, settled)
			+ NectaringPosture.shuffle_offset(t, body, SEED) * settled
		)
		fastest = maxf(fastest, previous.distance_to(now) / step)
		previous = now
	assert_lte(
		fastest, A_BUTTERFLY_AIRSPEED,
		"the alighting plus the shuffle it fades in reached %.3f px/s" % fastest
	)
