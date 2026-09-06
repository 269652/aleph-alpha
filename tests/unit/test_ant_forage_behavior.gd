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


# -- scouting: real search, not omniscient dispatch (see docs/concept/
# soil_fauna.md's section of that name) -- opt-in via begin_scouting()
# rather than a new default phase, so every trip dispatched the OLD way
# (a pre-known target, still real: a test constructing this behavior
# directly and calling arrive_at_food from APPROACHING) is completely
# unaffected. Real production dispatch now always calls begin_scouting()
# first (see AntForagerMarker.scout).

func test_begin_scouting_moves_to_the_scouting_phase():
	behavior.begin_scouting()
	assert_eq(behavior.phase, AntForageBehavior.Phase.SCOUTING)


func test_committing_to_food_moves_from_scouting_to_approaching():
	behavior.begin_scouting()
	behavior.commit_to_food()
	assert_eq(behavior.phase, AntForageBehavior.Phase.APPROACHING)


## A scout that commits to a real, sensed food item still has to walk the
## last short distance and re-check on real arrival, exactly like the
## non-scouting path always has -- committing is "I know where it is now",
## not "I already have it".
func test_after_committing_arrival_still_resolves_normally():
	behavior.begin_scouting()
	behavior.commit_to_food()
	behavior.arrive_at_food(true)
	assert_eq(behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_true(behavior.found_food)


## Wandered too long/far and found nothing -- a real scout does not just
## vanish, it walks home empty-handed, the same "still returns, just with
## nothing to show for it" contract an unsuccessful APPROACHING trip
## already has.
func test_giving_up_scouting_moves_to_returning_empty_handed():
	behavior.begin_scouting()
	behavior.give_up_scouting()
	assert_eq(behavior.phase, AntForageBehavior.Phase.RETURNING)
	assert_false(behavior.found_food)
