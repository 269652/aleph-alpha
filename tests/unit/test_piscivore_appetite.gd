extends GutTest

## What a fish-eating bird wants, and what it does when it wants nothing (see
## docs/concept/ecosystem_dynamics.md).
##
## The kingfisher hunted continuously: it struck, waited out an eight-second
## cooldown, and struck again, forever. Nothing in it was ever full, so a bird
## would work a pond until there was nothing left in it. A predator that
## strips its own larder is not a simulation of a predator.

const PiscivoreAppetite = preload("res://src/gameplay/piscivore_appetite.gd")


# -- appetite ----------------------------------------------------------------

func test_a_bird_starts_out_wanting_a_meal():
	assert_true(PiscivoreAppetite.is_hungry(PiscivoreAppetite.STARTING_HUNGER))


func test_eating_takes_the_edge_off():
	var fed := PiscivoreAppetite.hunger_after_meal(1.0)
	assert_lt(fed, 1.0)
	assert_false(PiscivoreAppetite.is_hungry(fed), "a bird that just ate is not still hungry")


func test_hunger_returns_on_its_own():
	var fed := PiscivoreAppetite.hunger_after_meal(1.0)
	var hungry_again := PiscivoreAppetite.hunger_after(fed, PiscivoreAppetite.SECONDS_PER_MEAL)
	assert_true(PiscivoreAppetite.is_hungry(hungry_again))


func test_hunger_does_not_run_away_past_starving():
	assert_lte(PiscivoreAppetite.hunger_after(1.0, 100000.0), 1.0)


func test_eating_repeatedly_cannot_drive_hunger_below_nothing():
	var hunger := 0.0
	for _i in 20:
		hunger = PiscivoreAppetite.hunger_after_meal(hunger)
	assert_gte(hunger, 0.0)


## The rate the design asks for: a couple of fish across an in-game day, not a
## fish every few seconds.
func test_a_bird_eats_about_two_fish_a_day():
	var meals := 0
	var hunger: float = PiscivoreAppetite.STARTING_HUNGER
	var step := 0.5
	var elapsed := 0.0
	while elapsed < PiscivoreAppetite.SECONDS_PER_IN_GAME_DAY:
		hunger = PiscivoreAppetite.hunger_after(hunger, step)
		elapsed += step
		if PiscivoreAppetite.is_hungry(hunger):
			hunger = PiscivoreAppetite.hunger_after_meal(hunger)
			meals += 1
	assert_between(meals, 1, 3, "a couple of fish a day, not a fish every few seconds")


# -- leaving a worked-out pond alone -----------------------------------------

## The rule that actually stops a pond being emptied. A real predator gives up
## on a patch that has stopped paying and goes elsewhere; without it, appetite
## alone only slows the stripping down.
func test_a_hungry_bird_leaves_a_depleted_pond_alone():
	assert_false(
		PiscivoreAppetite.will_hunt(1.0, 0.5, 10.0),
		"a nearly-empty pond is not worth working"
	)


func test_a_hungry_bird_will_hunt_a_healthy_pond():
	assert_true(PiscivoreAppetite.will_hunt(1.0, 9.0, 10.0))


func test_a_full_bird_does_not_hunt_even_a_full_pond():
	assert_false(PiscivoreAppetite.will_hunt(0.0, 10.0, 10.0))


func test_water_with_nothing_in_it_is_never_hunted():
	assert_false(PiscivoreAppetite.will_hunt(1.0, 0.0, 0.0))


# -- what a bird does when it is not hungry ----------------------------------

## A sated bird is not an idle bird: it should be visibly doing something
## else, which is the other half of what was asked for.
func test_a_full_bird_finds_something_else_to_do():
	var activity := PiscivoreAppetite.activity_for(0.0, 1)
	assert_ne(activity, PiscivoreAppetite.ACTIVITY_HUNT)


func test_a_hungry_bird_is_hunting_and_nothing_else():
	assert_eq(PiscivoreAppetite.activity_for(1.0, 1), PiscivoreAppetite.ACTIVITY_HUNT)


## Different birds are doing different things at any moment, rather than the
## whole species patrolling in unison.
func test_sated_birds_do_not_all_do_the_same_thing():
	var seen := {}
	for seed_value in 40:
		seen[PiscivoreAppetite.activity_for(0.0, seed_value)] = true
	assert_gt(seen.size(), 1, "a river should not look choreographed")


func test_every_activity_is_one_of_the_known_ones():
	for seed_value in 40:
		assert_true(
			PiscivoreAppetite.ACTIVITIES.has(PiscivoreAppetite.activity_for(0.0, seed_value))
		)
