extends GutTest

## A fly's life: egg, maggot, pupa, adult (see docs/concept/flies.md).
##
## The loop is the feature: rot draws a fly, the fly lays, the maggots eat the
## rot, the maggots become flies, those flies lay. It is the one population a
## player can create on purpose by leaving food out -- and the one that will
## eat the world if it is not bounded at every step.

const FlyLifeCycle = preload("res://src/gameplay/fly_life_cycle.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


# -- the stages --------------------------------------------------------------

func test_a_fly_starts_as_an_egg():
	assert_eq(FlyLifeCycle.stage_at(0.0), FlyLifeCycle.STAGE_EGG)


func test_it_passes_through_every_stage_in_order():
	var seen: Array[String] = []
	for step in 400:
		var age := float(step) / 399.0 * FlyLifeCycle.ADULT_AT_SECONDS * 1.2
		var stage := FlyLifeCycle.stage_at(age)
		if seen.is_empty() or seen[-1] != stage:
			seen.append(stage)
	assert_eq(
		seen,
		[
			FlyLifeCycle.STAGE_EGG,
			FlyLifeCycle.STAGE_MAGGOT,
			FlyLifeCycle.STAGE_PUPA,
			FlyLifeCycle.STAGE_ADULT,
		],
		"a fly should go egg, maggot, pupa, adult -- in that order and no other"
	)


## The maggot is the stage that EATS. Nothing else in the life cycle touches
## the rot it hatched on.
func test_only_a_maggot_eats():
	assert_true(FlyLifeCycle.eats(FlyLifeCycle.STAGE_MAGGOT))
	for stage in [FlyLifeCycle.STAGE_EGG, FlyLifeCycle.STAGE_PUPA, FlyLifeCycle.STAGE_ADULT]:
		assert_false(FlyLifeCycle.eats(stage), stage)


## Only an adult flies -- an egg or a pupa that drifted around would be a
## rendering bug with a life cycle attached.
func test_only_an_adult_flies():
	assert_true(FlyLifeCycle.flies(FlyLifeCycle.STAGE_ADULT))
	for stage in [FlyLifeCycle.STAGE_EGG, FlyLifeCycle.STAGE_MAGGOT, FlyLifeCycle.STAGE_PUPA]:
		assert_false(FlyLifeCycle.flies(stage), stage)


## The pupa is real and takes real time. Without it maggots would turn into
## flies where they stand, and the loop would run several days faster -- which
## is the difference between a swarm and an explosion.
func test_the_pupa_takes_real_time():
	assert_gt(FlyLifeCycle.ADULT_AT_SECONDS - FlyLifeCycle.PUPA_AT_SECONDS, 0.0)


## A whole life is days, not minutes: fast enough that a player leaving fruit
## out sees the consequence, slow enough to watch it happen.
func test_a_whole_life_takes_days():
	var days := FlyLifeCycle.ADULT_AT_SECONDS / SeasonCycle.SECONDS_PER_DAY
	assert_between(days, 3.0, 20.0)


# -- laying ------------------------------------------------------------------

## Eggs go on rot, because there is nothing on a fresh apple for a maggot to
## eat.
func test_eggs_go_on_rot_not_on_fresh_fruit():
	assert_true(FlyLifeCycle.can_lay_on(Olfaction.fruit_mixture("apple", 0.05)))
	assert_false(FlyLifeCycle.can_lay_on(Olfaction.fruit_mixture("apple", 1.0)))


## Only a mated female lays.
func test_only_a_mated_female_lays():
	assert_true(FlyLifeCycle.can_lay(FlyLifeCycle.STAGE_ADULT, true, 0))
	assert_false(FlyLifeCycle.can_lay(FlyLifeCycle.STAGE_ADULT, false, 0))
	assert_false(FlyLifeCycle.can_lay(FlyLifeCycle.STAGE_MAGGOT, true, 0))


## She lays several times, then stops -- an endlessly laying female is an
## endlessly growing swarm.
func test_a_female_lays_a_limited_number_of_times():
	assert_true(FlyLifeCycle.can_lay(FlyLifeCycle.STAGE_ADULT, true, 0))
	assert_false(
		FlyLifeCycle.can_lay(FlyLifeCycle.STAGE_ADULT, true, FlyLifeCycle.MAX_CLUTCHES)
	)


func test_a_clutch_is_several_eggs_but_not_a_hundred():
	assert_gt(FlyLifeCycle.CLUTCH_SIZE, 1, "one egg at a time is not a fly")
	assert_lte(FlyLifeCycle.CLUTCH_SIZE, 8, "a hundred nodes per clutch is a plague")


# -- the loop must be bounded ------------------------------------------------

## Every level is capped. A breeding population with no ceiling is the
## tree-spread bug again, and worse: flies breed in days rather than years.
func test_a_single_source_cannot_support_unlimited_flies():
	assert_gt(FlyLifeCycle.MAX_PER_SOURCE, 0)
	assert_lte(FlyLifeCycle.MAX_PER_SOURCE, 12)


func test_the_world_has_a_ceiling_on_flies():
	assert_gt(FlyLifeCycle.MAX_FLIES_IN_WORLD, FlyLifeCycle.MAX_PER_SOURCE)
	assert_lte(FlyLifeCycle.MAX_FLIES_IN_WORLD, 80)


## The ceiling actually stops laying, rather than being a number nobody reads.
func test_laying_stops_at_the_source_ceiling():
	assert_false(
		FlyLifeCycle.may_add_to_source(FlyLifeCycle.MAX_PER_SOURCE),
		"a full source should take no more eggs"
	)
	assert_true(FlyLifeCycle.may_add_to_source(0))


## One generation must not be able to multiply the population without limit:
## a clutch is smaller than what a source can hold, so a full source is reached
## rather than overshot in one lay.
func test_a_clutch_cannot_overshoot_a_source_by_itself():
	assert_lte(FlyLifeCycle.CLUTCH_SIZE, FlyLifeCycle.MAX_PER_SOURCE)
