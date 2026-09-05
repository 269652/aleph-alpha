extends GutTest

## Pure state machine for one ant-colony forager's real round trip: mound ->
## a known food location -> mound again. See docs/concept/soil_fauna.md
## "Real foraging: a round trip, not an instant resolve".
##
## Simpler than CarrionForageBehavior/GroundForageBehavior: there is no
## SEEKING phase here, because the COLONY already found a real, reachable
## food candidate before dispatching a forager at all (see
## EarthChunkManager._forage_seed_near_mound) -- this state machine owns
## only the walk-there-and-back, and whether the food was actually still
## there when the ant arrived.

const AntForageBehavior = preload("res://src/gameplay/ant_forage_behavior.gd")

var behavior: AntForageBehavior


func before_each():
	behavior = AntForageBehavior.new()


func test_starts_approaching():
	assert_eq(behavior.phase, AntForageBehavior.Phase.APPROACHING)


func test_arriving_with_food_moves_to_returning_and_remembers_success():
	behavior.arrive_at_food(true)
	assert_eq(behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_true(behavior.found_food)


## A real forager does not just vanish if something else got there first --
## it still walks home, simply with nothing to cache once it does.
func test_arriving_with_nothing_still_moves_to_returning_but_remembers_failure():
	behavior.arrive_at_food(false)
	assert_eq(behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_false(behavior.found_food)


func test_found_food_defaults_to_false_before_arrival():
	assert_false(behavior.found_food)
