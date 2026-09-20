extends GutTest

## Starvation: docs/concept/village_mortality.md mechanism 1 -- what the
## hunger drive does when it is left at the top.
##
## The window is measured in HUNGER CYCLES, never in days, and that is the
## whole point of the module. There are two day-lengths in this codebase
## (SeasonCycle.SECONDS_PER_DAY is 14400s of material economy;
## EarthChunkManager.SECONDS_PER_SIMULATED_DAY is the 60s a player feels),
## and a mortality clock written against the wrong one either kills
## instantly or never kills at all. Reading the drive's own cycle means
## starvation cannot drift onto a different clock than the hunger it is
## measuring.

const Starvation = preload("res://src/emergence/starvation.gd")
const NpcNeeds = preload("res://src/world/npc_needs.gd")


# -- starving is not the same as hungry ------------------------------------

func test_starving_is_worse_than_merely_hungry():
	assert_gt(
		Starvation.STARVING_LEVEL, NpcNeeds.HUNGRY_THRESHOLD,
		"looking for food and dying for want of it must not be the same state"
	)


func test_a_hungry_villager_is_not_yet_dying():
	assert_eq(Starvation.advance(0.0, NpcNeeds.HUNGRY_THRESHOLD, NpcNeeds.HUNGRY_THRESHOLD, 1000.0), 0.0)


func test_an_empty_villager_is_starving():
	assert_gt(Starvation.advance(0.0, 1.0, 1.0, 10.0), 0.0)


# -- the clock ---------------------------------------------------------------

func test_starving_accumulates_the_time_it_lasted():
	assert_almost_eq(Starvation.advance(0.0, 1.0, 1.0, 10.0), 10.0, 0.0001)
	assert_almost_eq(Starvation.advance(10.0, 1.0, 1.0, 5.0), 15.0, 0.0001)


## A villager who gets a meal is not still dying from last week.
func test_a_meal_clears_the_clock_outright():
	assert_eq(Starvation.advance(Starvation.seconds_to_die() * 0.9, 0.0, 0.0, 1.0), 0.0)


func test_dropping_back_to_merely_hungry_clears_it_too():
	assert_eq(Starvation.advance(50.0, NpcNeeds.HUNGRY_THRESHOLD, NpcNeeds.HUNGRY_THRESHOLD, 1.0), 0.0)


func test_the_clock_never_runs_backwards():
	assert_gte(Starvation.advance(10.0, 1.0, 1.0, -5.0), 10.0)


func test_they_die_only_after_the_whole_window():
	assert_false(Starvation.is_dead(Starvation.seconds_to_die() * 0.99))
	assert_true(Starvation.is_dead(Starvation.seconds_to_die()))


func test_nobody_starts_out_dead():
	assert_false(Starvation.is_dead(0.0))


# -- the window is the mechanic ---------------------------------------------
#
# Pillar 3: "the intervention window is the mechanic". Both bounds are
# real design claims, so both are pinned rather than left as comments.

## One missed meal is not fatal. A villager who empties once and eats again
## must not be marked for death by it.
func test_nobody_dies_of_one_missed_meal():
	assert_gt(
		Starvation.seconds_to_die(), Starvation.hunger_cycle_seconds(),
		"emptying once was already fatal"
	)


## ...and there is time to do something about it: long enough for a player
## who notices to cross the village and come back with food, several times
## over.
func test_there_is_time_to_save_them():
	assert_gte(Starvation.cycles_to_die(), 2.0)


## ...but a village with nothing to eat really does lose people, rather
## than standing permanently at the brink.
func test_a_village_with_no_food_really_does_lose_people():
	assert_lte(
		Starvation.cycles_to_die(), 12.0,
		"starving this slowly is a status effect, not mortality"
	)


## The cycle read is the villager's OWN hunger drive, not a number copied
## beside it -- so retuning the ethogram retunes starvation with it.
func test_the_window_is_measured_against_the_villagers_own_hunger():
	assert_almost_eq(
		Starvation.seconds_to_die(),
		Starvation.cycles_to_die() * Starvation.hunger_cycle_seconds(),
		0.0001
	)
	assert_almost_eq(
		Starvation.hunger_cycle_seconds(), 1.0 / NpcNeeds.HUNGER_RATE_PER_SECOND, 0.0001
	)


# -- a coarse step must not over-bill ---------------------------------------
#
# Hunger is not always ticked a frame at a time: a settlement step is 30s,
# and a catch-up after a reload is longer still. Crediting the whole step
# at the level it ENDED on kills a villager who was only starving for the
# last instant of it -- found by test_npc_needs.gd's own
# test_a_meal_at_the_last_moment_saves_them, which had somebody dead
# before the meal could reach them.

func test_a_coarse_step_credits_only_the_part_spent_starving():
	var banked := Starvation.advance(0.0, 0.0, 1.0, 100.0)
	assert_lt(banked, 100.0, "the whole step was billed at the level it ended on")
	assert_gt(banked, 0.0, "the part really spent starving was dropped")


func test_a_step_spent_entirely_starving_is_billed_whole():
	assert_almost_eq(Starvation.advance(0.0, 1.0, 1.0, 10.0), 10.0, 0.0001)


## Half the climb above the line is half the step.
func test_the_part_billed_is_the_part_above_the_line():
	var span := 1.0 - Starvation.STARVING_LEVEL
	var banked := Starvation.advance(0.0, Starvation.STARVING_LEVEL - span, 1.0, 100.0)
	assert_almost_eq(banked, 50.0, 0.5)
