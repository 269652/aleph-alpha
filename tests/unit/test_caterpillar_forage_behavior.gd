extends GutTest

## Pure state machine for a caterpillar working a food source -- either a
## real, in-season fallen leaf on the ground, or a real nearby tree
## currently in leaf (see CaterpillarMarker). Requested live: "wire
## caterpillars which live on trees and on the ground around them; they
## should also do groundforaging and eat green leaves (spring, summer
## only)". Mirrors CarrionForageBehavior's own SEEKING -> APPROACHING ->
## (feeding) -> SEEKING shape closely -- no flight, so there is no separate
## "descend" phase, approaching IS the walk and ends on arrival -- but
## departs from it in one deliberate way: a tree never runs out the way a
## carcass does, so EATING must end on its OWN clock (EAT_SECONDS) rather
## than staying committed "until it's gone". Ground litter, which DOES get
## consumed in one visit, is handled by the caller simply not re-offering
## an already-eaten leaf, the same way CarrionForageBehavior's own fruit/nut
## case (a single-visit item) already works without needing its own timeout.

const CaterpillarForageBehavior = preload("res://src/gameplay/caterpillar_forage_behavior.gd")

var behavior: CaterpillarForageBehavior


func before_each():
	behavior = CaterpillarForageBehavior.new()


func test_starts_seeking():
	assert_eq(behavior.phase, CaterpillarForageBehavior.Phase.SEEKING)


func test_cannot_commit_before_the_rehunt_interval_elapses():
	assert_false(behavior.can_commit())


func test_can_commit_once_the_rehunt_interval_elapses():
	behavior.advance(CaterpillarForageBehavior.REHUNT_SECONDS)
	assert_true(behavior.can_commit())


func test_begin_approach_fails_before_the_rehunt_interval():
	assert_false(behavior.begin_approach())
	assert_eq(behavior.phase, CaterpillarForageBehavior.Phase.SEEKING)


func test_begin_approach_succeeds_once_committable():
	behavior.advance(CaterpillarForageBehavior.REHUNT_SECONDS)
	assert_true(behavior.begin_approach())
	assert_eq(behavior.phase, CaterpillarForageBehavior.Phase.APPROACHING)


func test_arrive_moves_to_eating():
	behavior.advance(CaterpillarForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	assert_true(behavior.arrive())
	assert_eq(behavior.phase, CaterpillarForageBehavior.Phase.EATING)


func test_arrive_fails_outside_the_approaching_phase():
	assert_false(behavior.arrive())


func test_abort_returns_to_seeking_from_any_phase():
	behavior.advance(CaterpillarForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.abort()
	assert_eq(behavior.phase, CaterpillarForageBehavior.Phase.SEEKING)


## A fresh rehunt clock after abort -- a caterpillar that loses its target
## doesn't instantly re-commit to a new one, same reasoning
## GroundForageBehavior/CarrionForageBehavior's own REHUNT_SECONDS document.
func test_abort_resets_the_rehunt_clock():
	behavior.advance(CaterpillarForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.abort()
	assert_false(behavior.can_commit())


func test_advance_returns_false_outside_eating():
	assert_false(behavior.advance(1000.0))


func test_advance_bites_on_the_configured_interval_while_eating():
	behavior.advance(CaterpillarForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive()
	assert_false(behavior.advance(CaterpillarForageBehavior.BITE_INTERVAL * 0.5))
	assert_true(behavior.advance(CaterpillarForageBehavior.BITE_INTERVAL * 0.5))


func test_advance_bites_repeatedly_across_multiple_intervals():
	behavior.advance(CaterpillarForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive()
	var bites := 0
	for i in 3:
		if behavior.advance(CaterpillarForageBehavior.BITE_INTERVAL):
			bites += 1
	assert_eq(bites, 3)


## The one real departure from CarrionForageBehavior's own shape: a tree
## never runs out the way a carcass does, so a caterpillar must not just
## sit in it forever once it arrives -- EATING has to end on its own clock,
## which is also what actually gives "groundforaging" somewhere to happen:
## without this, a caterpillar that found a tree first would never be seen
## on the ground at all.
func test_eating_automatically_returns_to_seeking_after_eat_seconds():
	behavior.advance(CaterpillarForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive()
	behavior.advance(CaterpillarForageBehavior.EAT_SECONDS)
	assert_eq(behavior.phase, CaterpillarForageBehavior.Phase.SEEKING)


## And the rehunt clock is genuinely fresh afterward -- a caterpillar
## doesn't immediately re-commit to the very tree it just climbed down
## from, same as an aborted approach.
func test_a_fresh_rehunt_clock_starts_after_eating_ends_naturally():
	behavior.advance(CaterpillarForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive()
	behavior.advance(CaterpillarForageBehavior.EAT_SECONDS)
	assert_false(behavior.can_commit())


## A single large delta that crosses the whole EAT_SECONDS span in one call
## must not lose a bite that should have landed right at the boundary, and
## must not carry EATING's own elapsed clock into the fresh SEEKING phase.
func test_a_large_delta_crossing_the_eat_window_still_returns_to_seeking_cleanly():
	behavior.advance(CaterpillarForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive()
	behavior.advance(CaterpillarForageBehavior.EAT_SECONDS * 10.0)
	assert_eq(behavior.phase, CaterpillarForageBehavior.Phase.SEEKING)
	assert_false(behavior.can_commit())
