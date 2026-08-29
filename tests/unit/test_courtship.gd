extends GutTest

## Courtship: two animals of the same kind noticing each other, dancing, and
## sometimes mating (see docs/concept/ecosystem_dynamics.md).
##
## Pure and engine-free like the rest of the behaviour modules, so the whole
## meeting-to-mating cycle is testable headlessly.

const Courtship = preload("res://src/gameplay/courtship.gd")
const LifeCycle = preload("res://src/gameplay/life_cycle.gd")


# -- who will court whom -----------------------------------------------------

func test_two_of_the_same_kind_will_court():
	assert_true(Courtship.can_court("monarch", "monarch"))


func test_different_species_do_not_court():
	assert_false(Courtship.can_court("monarch", "swallowtail"))
	assert_false(Courtship.can_court("horse", "deer"))


## An animal cannot court itself -- the caller passes candidates from a group
## scan that includes itself, and a self-pairing would be a partner that is
## always available and always in range.
func test_an_animal_does_not_court_itself():
	assert_false(Courtship.can_pair(7, 7))
	assert_true(Courtship.can_pair(7, 8))


## Exactly one of a pair leads the dance, decided the same way by both, so two
## animals never both try to lead or both try to follow.
func test_a_pair_agrees_on_which_of_them_leads():
	assert_ne(Courtship.leads(3, 9), Courtship.leads(9, 3))
	assert_eq(Courtship.leads(3, 9), Courtship.leads(3, 9))


# -- the dance ---------------------------------------------------------------
#
# The dance is entered from wherever the two animals actually met and draws in
# from there (see dance_offset) -- it used to snap both partners onto a fixed
# DANCE_RADIUS_PX circle on the frame it began, a jump of up to 14.9 px against
# the 0.267 px a butterfly flies in a frame. So every call below hands it a
# real start offset and a real convergence, exactly as AmbientFlyerMarker does.

## Two animals meeting a body-length or so apart, which is what the dance is
## entered from in practice. Deliberately not exactly DANCE_RADIUS_PX -- a
## start offset that was already on the orbit would hide anything the
## convergence gets wrong.
const A_MEETING_OFFSET := Vector2(14.0, 0.0)
const A_MEETING_CLOSE := 0.4


func test_the_dance_is_a_circling_motion_around_the_partner():
	var offsets := []
	for step in 8:
		offsets.append(
			Courtship.dance_offset(
				float(step) * Courtship.DANCE_SECONDS / 8.0, 1, A_MEETING_OFFSET, A_MEETING_CLOSE
			)
		)
	var angles := {}
	for offset in offsets:
		angles[snappedf(offset.angle(), 0.2)] = true
	assert_gt(angles.size(), 4, "the pair should circle, not sit beside each other")


## Partners orbit opposite each other rather than on top of one another --
## that is what reads as two butterflies dancing rather than one sprite.
##
## Nothing tells either of them which one it is any more: their two start
## offsets are opposite by construction, because the dance's centre IS the
## midpoint between them, and the figure is a rigid rotation of that offset.
func test_partners_stay_on_opposite_sides_of_the_dance():
	for step in 40:
		var t := float(step) * Courtship.DANCE_SECONDS / 40.0
		var one := Courtship.dance_offset(t, 1, A_MEETING_OFFSET, A_MEETING_CLOSE)
		var other := Courtship.dance_offset(t, 1, -A_MEETING_OFFSET, A_MEETING_CLOSE)
		assert_lt(
			one.normalized().dot(other.normalized()), -0.9999,
			"the two must stay across the axis from each other, with nothing said"
		)
		assert_almost_eq(one.length(), other.length(), 0.0001, "and on the same radius")


## The whole point of the start offset: at elapsed 0 the animal is exactly
## where it already was, so beginning a dance moves nothing at all.
func test_a_dance_begins_exactly_where_the_animal_already_is():
	assert_eq(Courtship.dance_offset(0.0, 1, A_MEETING_OFFSET, A_MEETING_CLOSE), A_MEETING_OFFSET)


## ...and it does not stay out there: the convergence is what makes the
## approach finish, and after it the pair are on the dance's own radius.
func test_and_draws_in_onto_the_dances_own_radius():
	var band := Courtship.DANCE_RADIUS_PX / (1.0 - Courtship.DANCE_RADIUS_SWING)
	var settled := Courtship.dance_offset(
		A_MEETING_CLOSE * 2.0, 1, A_MEETING_OFFSET, A_MEETING_CLOSE
	)
	assert_lte(settled.length(), band + 0.01, "the convergence has to actually close")


## The orbit wanders rather than tracing one circle (see DANCE_RADIUS_SWING),
## so this is a BAND -- but the band still has to keep the two reading as one
## interacting pair rather than as two unrelated sprites.
## Sampled from AFTER the convergence has closed, since the approach is
## deliberately outside the band -- that is what an approach is (the entry
## itself is pinned by test_a_dance_begins_exactly_where_the_animal_already_is
## and test_and_draws_in_onto_the_dances_own_radius above).
func test_the_dance_stays_close_enough_to_read_as_one_pair():
	var swing := Courtship.DANCE_RADIUS_SWING
	var widest := 0.0
	var tightest := INF
	for step in 200:
		var offset := Courtship.dance_offset(
			A_MEETING_CLOSE + float(step) * 0.043, 5, A_MEETING_OFFSET, A_MEETING_CLOSE
		)
		widest = maxf(widest, offset.length())
		tightest = minf(tightest, offset.length())
	assert_lte(widest, Courtship.DANCE_RADIUS_PX / (1.0 - swing) + 0.01)
	assert_gte(tightest, Courtship.DANCE_RADIUS_PX / (1.0 + swing) - 0.01)
	assert_lte(
		widest, Courtship.NOTICE_RADIUS_PX * 0.5,
		"however it wanders, the pair must still read as one pair"
	)


## ...and it must genuinely wander. A fixed ellipse is still a closed figure
## traced identically every time round, which is what "only a circle" meant.
func test_the_dance_is_not_one_repeating_figure():
	var widest := 0.0
	var tightest := INF
	for step in 200:
		var offset := Courtship.dance_offset(
			A_MEETING_CLOSE + float(step) * 0.043, 5, A_MEETING_OFFSET, A_MEETING_CLOSE
		)
		widest = maxf(widest, offset.length())
		tightest = minf(tightest, offset.length())
	assert_gt(
		widest - tightest, Courtship.DANCE_RADIUS_PX * 0.15,
		"the orbit has to breathe, not trace one circle"
	)


## Two pairs must not trace the same dance. Two things now make them differ,
## and both are checked, because they are separately losable:
##
## - the SEED, which shapes the breathing radius and the swept angle. Checked
##   with the two pairs handed identical meeting geometry, so the seed is the
##   only thing left that can separate them.
## - WHERE THEY MET, which now sets the dance's phase (it used to be a hash of
##   the pair seed -- see dance_offset). Two pairs that met facing different
##   ways trace figures that are further apart still.
func test_no_two_pairs_dance_the_same_figure():
	var apart := 0.0
	for step in 200:
		var t := A_MEETING_CLOSE + float(step) * 0.023
		apart = maxf(
			apart,
			Courtship.dance_offset(t, 1, A_MEETING_OFFSET, A_MEETING_CLOSE).distance_to(
				Courtship.dance_offset(t, 2, A_MEETING_OFFSET, A_MEETING_CLOSE)
			)
		)
	assert_gt(
		apart, 0.5 * Courtship.DANCE_RADIUS_PX,
		"the seed alone must still separate two dances (%.2f px)" % apart
	)


func test_and_two_pairs_that_met_facing_different_ways_differ_further_still():
	var elsewhere := A_MEETING_OFFSET.rotated(PI * 0.5)
	var apart := 0.0
	for step in 200:
		var t := A_MEETING_CLOSE + float(step) * 0.023
		apart = maxf(
			apart,
			Courtship.dance_offset(t, 1, A_MEETING_OFFSET, A_MEETING_CLOSE).distance_to(
				Courtship.dance_offset(t, 2, elsewhere, A_MEETING_CLOSE)
			)
		)
	assert_gt(apart, Courtship.DANCE_RADIUS_PX, "two pairs must not trace the same dance")


## Derived, not chosen: a display flight is flown at a cruising speed, and the
## turn rate is that speed divided by the circumference actually being flown.
## The old 0.85 implied 3.8 m/s -- three quarters of a monarch's absolute burst
## -- for a manoeuvre this module calls a slow wide orbit.
func test_the_dance_rate_is_a_real_cruising_flight_speed():
	assert_almost_eq(
		TAU * Courtship.DANCE_RADIUS_M * Courtship.DANCE_TURNS_PER_SECOND,
		Courtship.CRUISE_SPEED_MPS,
		0.0001,
		"turns per second must BE cruise speed / circumference"
	)
	assert_between(
		Courtship.CRUISE_SPEED_MPS, 1.0, 3.0, "a monarch's ordinary flight is about 2 m/s"
	)


# -- mating ------------------------------------------------------------------

## Occasionally, not every meeting: two butterflies crossing paths mostly just
## cross paths.
func test_only_some_dances_end_in_mating():
	var mated := 0
	for pair in 400:
		if Courtship.mates(pair * 31 + 7):
			mated += 1
	var rate := float(mated) / 400.0
	assert_gt(rate, 0.05, "mating has to actually happen sometimes")
	assert_lt(rate, 0.6, "...but a meeting is not a pregnancy")


func test_whether_a_given_pairing_mates_is_deterministic():
	assert_eq(Courtship.mates(12345), Courtship.mates(12345))


## A pair that has just courted does not court again for a REAL DAY.
##
## The cooldown was 40 seconds, which measured as a butterfly added every few
## seconds. The brief puts this on wall-clock time -- "1+ real day to mate" --
## so the dance stays a common sight and what follows it does not.
func test_courting_is_followed_by_a_cooldown():
	assert_gt(Courtship.COOLDOWN_SECONDS, Courtship.DANCE_SECONDS)
	assert_gte(
		Courtship.COOLDOWN_SECONDS, LifeCycle.MATE_SECONDS,
		"a pair must not court again inside a real day"
	)


## The dance itself is still seconds long: it is the thing the player is meant
## to SEE, and a courtship flight that took a day would never be witnessed.
func test_the_dance_itself_stays_watchable_even_though_breeding_does_not():
	assert_lt(Courtship.DANCE_SECONDS, 60.0)


func test_the_dance_lasts_long_enough_to_be_seen():
	assert_gt(Courtship.DANCE_SECONDS, 1.0, "a dance the player cannot notice is not a dance")
	assert_lt(Courtship.DANCE_SECONDS, 20.0, "...but they are not courting all day either")


## Only pollinators dance. A bird performing a butterfly's tight spiralling
## courtship flight reads as a bird glitching in place -- reported as birds
## stalling and jittering on the spot.
func test_birds_do_not_perform_the_butterfly_dance():
	assert_false(Courtship.can_court("sparrow", "sparrow"))
	assert_false(Courtship.can_court("robin", "robin"))
	assert_false(Courtship.dances("sparrow"))


func test_pollinators_still_dance():
	for species in ["monarch", "swallowtail", "blue_morpho", "bee"]:
		assert_true(Courtship.can_court(species, species), "%s should dance" % species)
