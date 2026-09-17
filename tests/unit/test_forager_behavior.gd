extends GutTest

## ForagerBehavior: the pure phase machine behind a villager who hunts or
## fishes real quarry (docs/concept/npc.md, "Work against the real world,
## not against a number").
##
## The exact split LumberjackBehavior already uses -- this decides WHEN
## things happen, the marker owns the world effect (finding a real
## CreatureMarker or FishMarker, walking to it, striking it). No engine
## dependency, so the whole cycle is unit-testable headlessly.

const ForagerBehavior = preload("res://src/gameplay/forager_behavior.gd")
const LumberjackBehavior = preload("res://src/gameplay/lumberjack_behavior.gd")

var forager: ForagerBehavior


func before_each():
	forager = ForagerBehavior.new()


func test_a_forager_starts_out_looking_for_quarry():
	assert_eq(forager.phase, ForagerBehavior.Phase.SEEKING)


func test_it_will_not_commit_before_its_look_around_interval_has_passed():
	assert_false(forager.can_commit(), "a villager does not sprint at the first thing they see")
	assert_false(forager.begin_approach(), "offering a target early is a no-op, not an error")
	assert_eq(forager.phase, ForagerBehavior.Phase.SEEKING)


func test_it_commits_once_it_has_looked_around():
	forager.advance(ForagerBehavior.REHUNT_SECONDS)
	assert_true(forager.can_commit())
	assert_true(forager.begin_approach())
	assert_eq(forager.phase, ForagerBehavior.Phase.APPROACHING)


## Arrival is the caller's call, by real distance -- how long the walk takes
## depends on how far the quarry was, exactly as for a tree.
func test_arriving_starts_the_taking():
	forager.advance(ForagerBehavior.REHUNT_SECONDS)
	forager.begin_approach()
	assert_true(forager.arrive())
	assert_eq(forager.phase, ForagerBehavior.Phase.TAKING)


func test_arriving_without_having_set_out_is_a_no_op():
	assert_false(forager.arrive())
	assert_eq(forager.phase, ForagerBehavior.Phase.SEEKING)


## Quarry runs away, dies to something else, or its chunk unloads.
func test_giving_up_returns_to_seeking_with_a_fresh_clock():
	forager.advance(ForagerBehavior.REHUNT_SECONDS)
	forager.begin_approach()

	forager.abort()

	assert_eq(forager.phase, ForagerBehavior.Phase.SEEKING)
	assert_false(forager.can_commit(), "and it looks around again before committing to the next one")


# -- striking ---------------------------------------------------------------

func test_no_strike_lands_before_its_interval_elapses():
	forager.advance(ForagerBehavior.REHUNT_SECONDS)
	forager.begin_approach()
	forager.arrive()
	assert_false(forager.advance(ForagerBehavior.STRIKE_INTERVAL * 0.5))


func test_a_strike_lands_once_the_interval_elapses():
	forager.advance(ForagerBehavior.REHUNT_SECONDS)
	forager.begin_approach()
	forager.arrive()
	assert_true(forager.advance(ForagerBehavior.STRIKE_INTERVAL), "this is the tick that hits")


func test_strikes_keep_landing_at_a_steady_pace():
	forager.advance(ForagerBehavior.REHUNT_SECONDS)
	forager.begin_approach()
	forager.arrive()
	var landed := 0
	for i in 40:
		if forager.advance(ForagerBehavior.STRIKE_INTERVAL * 0.25):
			landed += 1
	assert_eq(landed, 10, "four quarter-intervals to a strike, forty ticks, ten strikes")


func test_nothing_strikes_while_still_walking():
	forager.advance(ForagerBehavior.REHUNT_SECONDS)
	forager.begin_approach()
	for i in 20:
		assert_false(forager.advance(ForagerBehavior.STRIKE_INTERVAL), "a villager does not swing at thin air")


## Taking the quarry sends them back out, after a beat -- a hunter does not
## instantly lock onto the next deer over the body of the last.
func test_taking_the_quarry_returns_to_seeking():
	forager.advance(ForagerBehavior.REHUNT_SECONDS)
	forager.begin_approach()
	forager.arrive()

	forager.finish_take()

	assert_eq(forager.phase, ForagerBehavior.Phase.SEEKING)
	assert_false(forager.can_commit())


func test_finishing_a_take_that_never_started_is_harmless():
	forager.finish_take()
	assert_eq(forager.phase, ForagerBehavior.Phase.SEEKING)


## The whole loop runs round and round without wedging.
func test_the_cycle_repeats():
	for round_index in 3:
		forager.advance(ForagerBehavior.REHUNT_SECONDS)
		assert_true(forager.begin_approach(), "round %d: commits" % round_index)
		assert_true(forager.arrive(), "round %d: arrives" % round_index)
		assert_true(forager.advance(ForagerBehavior.STRIKE_INTERVAL), "round %d: strikes" % round_index)
		forager.finish_take()
	assert_eq(forager.phase, ForagerBehavior.Phase.SEEKING)


## It is the same mechanic as felling with a different caller, so it keeps
## the same pacing rather than inventing its own.
func test_it_keeps_the_lumberjacks_own_pacing_rather_than_a_new_guess():
	assert_eq(ForagerBehavior.REHUNT_SECONDS, LumberjackBehavior.REHUNT_SECONDS)
	assert_eq(ForagerBehavior.STRIKE_INTERVAL, LumberjackBehavior.SWING_INTERVAL)
