extends GutTest

## Pure state machine for a bird that feeds off the ground (see
## docs/concept/soil_fauna.md's "Ground foraging behaviour"): seek -> descend
## -> peck -> resume. Same separation as PiscivoreBirdBehavior -- this decides
## WHEN things happen and WHETHER the strike lands; actually removing the worm
## from the world is the marker's job.
##
## No engine dependencies at all, so the whole feeding cycle is testable
## headlessly without a scene.

const GroundForageBehavior = preload("res://src/gameplay/ground_forage_behavior.gd")

var behavior: GroundForageBehavior


func before_each():
	behavior = GroundForageBehavior.new()


## Advances past the airborne re-hunt interval so the bird is willing to
## commit to a worm.
func _become_hungry() -> void:
	behavior.advance(GroundForageBehavior.REHUNT_SECONDS)


## Runs the whole cycle up to the tick the strike resolves, returning true if
## it actually resolved.
func _peck_until_strike() -> bool:
	_become_hungry()
	behavior.begin_descent()
	behavior.arrive()
	for i in 200:
		if behavior.advance(0.05):
			return true
	return false


# -- phases -----------------------------------------------------------------

func test_starts_airborne_and_seeking():
	assert_eq(behavior.phase, GroundForageBehavior.Phase.SEEKING)
	assert_false(behavior.is_grounded(), "a seeking bird is in the air")


## A robin runs, stops, pecks, runs again -- it does not chain strikes back to
## back. The interval is the running part.
func test_will_not_commit_until_the_rehunt_interval_has_passed():
	assert_false(behavior.can_commit(), "a bird that just ate does not immediately re-commit")
	behavior.advance(GroundForageBehavior.REHUNT_SECONDS * 0.5)
	assert_false(behavior.can_commit())
	behavior.advance(GroundForageBehavior.REHUNT_SECONDS)
	assert_true(behavior.can_commit())


func test_committing_starts_a_descent():
	_become_hungry()
	assert_true(behavior.begin_descent())
	assert_eq(behavior.phase, GroundForageBehavior.Phase.DESCENDING)


func test_cannot_commit_before_the_interval():
	assert_false(behavior.begin_descent())
	assert_eq(behavior.phase, GroundForageBehavior.Phase.SEEKING)


func test_cannot_commit_twice():
	_become_hungry()
	behavior.begin_descent()
	assert_false(behavior.begin_descent(), "already on its way down")


## The descent ends on ARRIVAL, not on a timer: how long the flight takes
## depends on how far the worm is.
func test_arriving_starts_the_peck():
	_become_hungry()
	behavior.begin_descent()
	assert_true(behavior.arrive())
	assert_eq(behavior.phase, GroundForageBehavior.Phase.PECKING)


func test_arriving_while_not_descending_does_nothing():
	assert_false(behavior.arrive())
	assert_eq(behavior.phase, GroundForageBehavior.Phase.SEEKING)


func test_the_bird_is_on_the_ground_while_pecking_and_resuming():
	_become_hungry()
	behavior.begin_descent()
	assert_false(behavior.is_grounded(), "still flying down")
	behavior.arrive()
	assert_true(behavior.is_grounded(), "pecking happens sitting on the ground")
	behavior.advance(GroundForageBehavior.PECK_SECONDS)
	assert_eq(behavior.phase, GroundForageBehavior.Phase.RESUMING)
	assert_true(behavior.is_grounded(), "it swallows and looks around before taking off")


func test_it_returns_to_seeking_and_the_air_after_resuming():
	_peck_until_strike()
	behavior.advance(GroundForageBehavior.PECK_SECONDS + GroundForageBehavior.RESUME_SECONDS)
	assert_eq(behavior.phase, GroundForageBehavior.Phase.SEEKING)
	assert_false(behavior.is_grounded(), "back in the air")


## Having just eaten, it must fly around again before the next worm.
func test_it_cannot_immediately_commit_again_after_a_meal():
	_peck_until_strike()
	behavior.advance(GroundForageBehavior.PECK_SECONDS + GroundForageBehavior.RESUME_SECONDS)
	assert_eq(behavior.phase, GroundForageBehavior.Phase.SEEKING)
	assert_false(behavior.can_commit())


func test_the_full_cycle_returns_to_a_committable_seek():
	_peck_until_strike()
	for i in 400:
		behavior.advance(0.1)
		if behavior.can_commit():
			break
	assert_eq(behavior.phase, GroundForageBehavior.Phase.SEEKING)
	assert_true(behavior.can_commit(), "the cycle must actually close")


# -- the strike -------------------------------------------------------------

func test_the_strike_resolves_exactly_once_per_peck():
	_become_hungry()
	behavior.begin_descent()
	behavior.arrive()
	var resolutions := 0
	for i in 200:
		if behavior.advance(0.05):
			resolutions += 1
	assert_eq(resolutions, 1, "one worm per peck, reported on exactly one tick")


func test_no_strike_is_reported_while_merely_seeking():
	for i in 200:
		assert_false(behavior.advance(0.05), "a bird in the air is not taking worms")


func test_no_strike_is_reported_during_the_descent():
	_become_hungry()
	behavior.begin_descent()
	for i in 10:
		assert_false(behavior.advance(0.05))


## The strike lands PART WAY through the peck, not at its end -- so the peck
## animation keeps playing after the worm is taken, the same "resolve once,
## keep animating" split PiscivoreBirdBehavior uses for its dive.
func test_the_strike_lands_before_the_peck_is_over():
	_become_hungry()
	behavior.begin_descent()
	behavior.arrive()
	var elapsed := 0.0
	while elapsed < GroundForageBehavior.PECK_SECONDS * 2.0:
		if behavior.advance(0.05):
			break
		elapsed += 0.05
	assert_lt(elapsed, GroundForageBehavior.PECK_SECONDS, "the strike is mid-peck")
	assert_eq(behavior.phase, GroundForageBehavior.Phase.PECKING)


# -- the visible peck -------------------------------------------------------
#
# The bird dips its head several times across the peck phase, so the moment
# reads as pecking rather than as a bird freezing on the grass.

func test_the_head_dips_several_times_across_a_peck():
	_become_hungry()
	behavior.begin_descent()
	behavior.arrive()
	var dips := 0
	var was_down := behavior.is_beak_down()
	var elapsed := 0.0
	while elapsed < GroundForageBehavior.PECK_SECONDS:
		behavior.advance(0.02)
		elapsed += 0.02
		var down := behavior.is_beak_down()
		if down and not was_down:
			dips += 1
		was_down = down
	assert_eq(dips, GroundForageBehavior.PECK_COUNT, "the head should dip once per peck")


func test_the_peck_starts_with_the_head_up():
	_become_hungry()
	behavior.begin_descent()
	behavior.arrive()
	assert_false(behavior.is_beak_down(), "it lands, then dips -- not the other way round")


## The worm has to vanish while the beak is actually in the grass, or the
## animation and the simulation disagree on screen.
func test_the_beak_is_down_at_the_moment_the_strike_resolves():
	_become_hungry()
	behavior.begin_descent()
	behavior.arrive()
	for i in 200:
		if behavior.advance(0.02):
			assert_true(behavior.is_beak_down(), "the worm is taken with the beak in the grass")
			return
	fail_test("the strike never resolved")


func test_the_beak_is_never_down_off_the_ground():
	_become_hungry()
	for i in 40:
		behavior.advance(0.1)
		assert_false(behavior.is_beak_down())
	assert_true(behavior.begin_descent())
	for i in 10:
		behavior.advance(0.05)
		assert_false(behavior.is_beak_down(), "not while still flying down")


## Stepped straight to the phase boundary rather than continuing on from the
## strike: a transition carries its remainder forward (see advance), so
## resuming from mid-peck would overshoot RESUME_SECONDS and land back in
## SEEKING.
func test_the_beak_is_up_again_while_resuming():
	_become_hungry()
	behavior.begin_descent()
	behavior.arrive()
	behavior.advance(GroundForageBehavior.PECK_SECONDS)
	assert_eq(behavior.phase, GroundForageBehavior.Phase.RESUMING)
	assert_false(behavior.is_beak_down(), "head up while it swallows")


# -- giving up --------------------------------------------------------------

func test_an_unreachable_target_is_abandoned_rather_than_chased_forever():
	_become_hungry()
	behavior.begin_descent()
	behavior.advance(GroundForageBehavior.DESCENT_TIMEOUT + 0.1)
	assert_eq(
		behavior.phase, GroundForageBehavior.Phase.SEEKING,
		"a descent that never arrives must not strand the bird"
	)


func test_aborting_a_descent_returns_it_to_the_air():
	_become_hungry()
	behavior.begin_descent()
	behavior.abort()
	assert_eq(behavior.phase, GroundForageBehavior.Phase.SEEKING)
	assert_false(behavior.is_grounded())


## A worm eaten by another robin between committing and arriving: the bird
## must give up cleanly rather than sitting on empty grass.
func test_aborting_makes_it_fly_around_before_committing_again():
	_become_hungry()
	behavior.begin_descent()
	behavior.abort()
	assert_false(behavior.can_commit())
