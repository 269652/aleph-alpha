extends GutTest

## Pure state machine for one bee forager's real round trip: hive -> (scout
## for) a real flower with nectar -> hive again. Mirrors
## test_ant_forage_behavior.gd exactly -- see docs/concept/bees.md's own
## "What's reused verbatim, what's a deliberate new duplicate, and why":
## a small, pure, independently-tunable duplicate of AntForageBehavior
## rather than a shared import, the same "three similar things beats a
## premature abstraction" preference this project already states.

const BeeForageBehavior = preload("res://src/gameplay/bee_forage_behavior.gd")

var behavior: BeeForageBehavior


func before_each():
	behavior = BeeForageBehavior.new()


func test_default_phase_is_approaching():
	assert_eq(behavior.phase, BeeForageBehavior.Phase.APPROACHING)


func test_default_found_food_is_false():
	assert_false(behavior.found_food)


func test_begin_scouting_moves_to_scouting():
	behavior.begin_scouting()
	assert_eq(behavior.phase, BeeForageBehavior.Phase.SCOUTING)


func test_commit_to_food_moves_to_approaching():
	behavior.begin_scouting()
	behavior.commit_to_food()
	assert_eq(behavior.phase, BeeForageBehavior.Phase.APPROACHING)


func test_arrive_at_food_with_success_moves_to_returning_and_remembers_it():
	behavior.arrive_at_food(true)
	assert_eq(behavior.phase, BeeForageBehavior.Phase.RETURNING)
	assert_true(behavior.found_food)


func test_arrive_at_food_without_success_moves_to_returning_empty_handed():
	behavior.arrive_at_food(false)
	assert_eq(behavior.phase, BeeForageBehavior.Phase.RETURNING)
	assert_false(behavior.found_food)


func test_arrival_still_resolves_normally_after_committing_from_scouting():
	behavior.begin_scouting()
	behavior.commit_to_food()
	behavior.arrive_at_food(true)
	assert_eq(behavior.phase, BeeForageBehavior.Phase.RETURNING)
	assert_true(behavior.found_food)


func test_give_up_scouting_moves_to_returning_empty_handed():
	behavior.begin_scouting()
	behavior.give_up_scouting()
	assert_eq(behavior.phase, BeeForageBehavior.Phase.RETURNING)
	assert_false(behavior.found_food)
