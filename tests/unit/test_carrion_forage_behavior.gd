extends GutTest

## Pure state machine for a ground decomposer (ant, carrion bug) working a
## carcass or guts pile -- see docs/concept/carrion.md. Simpler than
## GroundForageBehavior/PiscivoreBirdBehavior: no flight, so there is no
## separate "descend" phase -- approaching IS the walk, ending on arrival.
## seek -> approach -> feed -> seek.

const CarrionForageBehavior = preload("res://src/gameplay/carrion_forage_behavior.gd")

var behavior: CarrionForageBehavior


func before_each():
	behavior = CarrionForageBehavior.new()


func test_starts_seeking():
	assert_eq(behavior.phase, CarrionForageBehavior.Phase.SEEKING)


func test_cannot_commit_before_the_rehunt_interval_elapses():
	assert_false(behavior.can_commit())


func test_can_commit_once_the_rehunt_interval_elapses():
	behavior.advance(CarrionForageBehavior.REHUNT_SECONDS)
	assert_true(behavior.can_commit())


func test_begin_approach_fails_before_the_rehunt_interval():
	assert_false(behavior.begin_approach())
	assert_eq(behavior.phase, CarrionForageBehavior.Phase.SEEKING)


func test_begin_approach_succeeds_once_committable():
	behavior.advance(CarrionForageBehavior.REHUNT_SECONDS)
	assert_true(behavior.begin_approach())
	assert_eq(behavior.phase, CarrionForageBehavior.Phase.APPROACHING)


func test_arrive_moves_to_feeding():
	behavior.advance(CarrionForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	assert_true(behavior.arrive())
	assert_eq(behavior.phase, CarrionForageBehavior.Phase.FEEDING)


func test_arrive_fails_outside_the_approaching_phase():
	assert_false(behavior.arrive())


func test_abort_returns_to_seeking_from_any_phase():
	behavior.advance(CarrionForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.abort()
	assert_eq(behavior.phase, CarrionForageBehavior.Phase.SEEKING)


## A fresh rehunt clock after abort -- a decomposer that loses its target
## doesn't instantly re-commit to a new one, same "run between bites"
## reasoning GroundForageBehavior's own REHUNT_SECONDS documents.
func test_abort_resets_the_rehunt_clock():
	behavior.advance(CarrionForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.abort()
	assert_false(behavior.can_commit())


func test_advance_returns_false_outside_feeding():
	assert_false(behavior.advance(1000.0))


func test_advance_bites_on_the_configured_interval_while_feeding():
	behavior.advance(CarrionForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive()
	assert_false(behavior.advance(CarrionForageBehavior.BITE_INTERVAL * 0.5))
	assert_true(behavior.advance(CarrionForageBehavior.BITE_INTERVAL * 0.5))


func test_advance_bites_repeatedly_across_multiple_intervals():
	behavior.advance(CarrionForageBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive()
	var bites := 0
	for i in 5:
		if behavior.advance(CarrionForageBehavior.BITE_INTERVAL):
			bites += 1
	assert_eq(bites, 5)
