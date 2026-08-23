extends GutTest

## Pure state machine for a fish-eating bird (kingfisher) diving to catch
## fish -- see docs/concept/ecosystem_dynamics.md's "fish-eating birds" (A
## new aerial tier): cruise -> dive -> grab-or-miss -> ascend -> cooldown ->
## cruise. This module only decides WHEN a dive happens and WHETHER it
## succeeds -- applying a successful grab to the real aquatic population
## (EcosystemSimulation.record_catch) is the caller's job (see
## PiscivoreBirdMarker).

const PiscivoreBirdBehavior = preload("res://src/gameplay/piscivore_bird_behavior.gd")

var behavior: PiscivoreBirdBehavior


func before_each():
	behavior = PiscivoreBirdBehavior.new()


func test_starts_in_cruise():
	assert_eq(behavior.phase, PiscivoreBirdBehavior.Phase.CRUISE)


func test_try_start_dive_fails_when_no_fish_are_present():
	assert_false(behavior.try_start_dive(0.0, 1))
	assert_eq(behavior.phase, PiscivoreBirdBehavior.Phase.CRUISE)


func test_try_start_dive_succeeds_when_fish_are_present():
	assert_true(behavior.try_start_dive(5.0, 1))
	assert_eq(behavior.phase, PiscivoreBirdBehavior.Phase.DIVING)


func test_try_start_dive_is_a_no_op_while_already_diving():
	behavior.try_start_dive(5.0, 1)
	assert_false(behavior.try_start_dive(5.0, 2))


func test_advance_resolves_a_grab_outcome_partway_through_the_dive():
	behavior.try_start_dive(5.0, 1)
	var resolved := false
	for i in 20:
		if behavior.advance(0.1):
			resolved = true
			break
	assert_true(resolved, "grab outcome should resolve partway through the dive")


func test_advance_eventually_returns_to_cruise_after_ascend_and_cooldown():
	behavior.try_start_dive(5.0, 1)
	for i in 200:
		behavior.advance(0.1)
	assert_eq(behavior.phase, PiscivoreBirdBehavior.Phase.CRUISE)


func test_dive_progress_is_zero_outside_a_dive_or_ascend():
	assert_eq(behavior.dive_progress(), 0.0)


func test_dive_progress_increases_during_the_dive():
	behavior.try_start_dive(5.0, 1)
	var early := behavior.dive_progress()
	behavior.advance(0.1)
	var later := behavior.dive_progress()
	assert_gt(later, early)


## Real herons/ospreys/kingfishers miss most strikes -- a dive must not be a
## guaranteed catch, nor an impossible one.
func test_grab_outcome_varies_with_seed():
	var successes := 0
	for seed_value in range(50):
		var b := PiscivoreBirdBehavior.new()
		b.try_start_dive(5.0, seed_value)
		for i in 10:
			if b.advance(0.1):
				break
		if b.did_last_grab_succeed():
			successes += 1
	assert_gt(successes, 0, "some dives should succeed across many seeds")
	assert_lt(successes, 50, "not every dive should succeed")


func test_deterministic_for_the_same_seed():
	var a := PiscivoreBirdBehavior.new()
	a.try_start_dive(5.0, 42)
	for i in 10:
		a.advance(0.1)

	var b := PiscivoreBirdBehavior.new()
	b.try_start_dive(5.0, 42)
	for i in 10:
		b.advance(0.1)

	assert_eq(a.did_last_grab_succeed(), b.did_last_grab_succeed())
	assert_eq(a.phase, b.phase)


# -- hunting: hover before the strike, carry after it ------------------------
#
# The kingfisher only dived when its RANDOM WANDER happened to carry it over
# water with fish in it, and then held its horizontal position through a dive,
# an ascent and an eight-second cooldown. A bird whose home was inland
# essentially never fished at all (reported: "the kingfisher is mostly stuck
# in one place without fishing anything").
#
# It now hunts: it goes to the fish, hovers over it the way a real kingfisher
# does, and only then strikes.

func test_a_bird_hovers_before_it_strikes():
	var bird = PiscivoreBirdBehavior.new()
	assert_true(bird.begin_hover(1))
	assert_eq(bird.phase, PiscivoreBirdBehavior.Phase.HOVERING)
	assert_false(bird.begin_hover(1), "already hovering")


func test_hovering_leads_into_a_dive_on_its_own():
	var bird = PiscivoreBirdBehavior.new()
	bird.begin_hover(1)
	bird.advance(PiscivoreBirdBehavior.HOVER_DURATION + 0.01)
	assert_eq(bird.phase, PiscivoreBirdBehavior.Phase.DIVING)


## The hover is what makes the strike readable: without it a kingfisher just
## appears at the water.
func test_the_hover_lasts_long_enough_to_read():
	assert_gt(PiscivoreBirdBehavior.HOVER_DURATION, 0.5)
	assert_lt(PiscivoreBirdBehavior.HOVER_DURATION, 5.0)


## A bird already committed must not restart its hover.
func test_hovering_only_starts_from_cruising():
	var bird = PiscivoreBirdBehavior.new()
	bird.begin_hover(1)
	bird.advance(PiscivoreBirdBehavior.HOVER_DURATION + 0.01)  # now diving
	assert_false(bird.begin_hover(1))


# -- what happens after the strike -------------------------------------------

## A successful strike is followed by the bird CARRYING its catch, which is
## the whole visible payoff: the player sees a fish leave the water.
func test_a_successful_strike_leads_to_carrying_the_fish():
	var bird = _bird_after_strike(true)
	assert_eq(bird.phase, PiscivoreBirdBehavior.Phase.CARRYING)


## A miss does not: the bird pulls up empty and the fish is gone.
func test_a_missed_strike_goes_straight_to_pulling_up():
	var bird = _bird_after_strike(false)
	assert_eq(bird.phase, PiscivoreBirdBehavior.Phase.ASCENDING)


func test_carrying_ends_with_the_fish_eaten():
	var bird = _bird_after_strike(true)
	bird.advance(PiscivoreBirdBehavior.CARRY_DURATION + 0.01)
	assert_ne(bird.phase, PiscivoreBirdBehavior.Phase.CARRYING, "the fish gets eaten")


## Most strikes miss -- a kingfisher is not a guaranteed predator, and the
## fish gets a say.
func test_most_strikes_miss():
	var caught := 0
	for seed_value in 200:
		if _run_strike(seed_value).did_last_grab_succeed():
			caught += 1
	var rate := float(caught) / 200.0
	assert_gt(rate, 0.1, "it has to catch something sometimes")
	assert_lt(rate, 0.6, "...but a strike is not a certainty")


func _run_strike(seed_value: int):
	var bird = PiscivoreBirdBehavior.new()
	bird.begin_hover(seed_value)
	bird.advance(PiscivoreBirdBehavior.HOVER_DURATION + 0.01)
	var guard := 0
	while bird.phase == PiscivoreBirdBehavior.Phase.DIVING and guard < 100:
		bird.advance(0.05)
		guard += 1
	return bird


## A bird just past a strike that went the wanted way. Searches for a seed
## rather than forcing the outcome, so the test exercises the real roll.
func _bird_after_strike(succeed: bool):
	for seed_value in 500:
		var bird = _run_strike(seed_value)
		if bird.did_last_grab_succeed() == succeed:
			return bird
	fail_test("no seed produced the wanted outcome")
	return PiscivoreBirdBehavior.new()
