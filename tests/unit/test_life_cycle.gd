extends GutTest

## How long it takes an animal to be conceived, hatch and grow up, in REAL
## time (see docs/concept/ecosystem_dynamics.md).
##
## Specified directly: "reproduction + growth should take 7 real days for a
## newborn child to mature... butterflies [need to be watched] 1+ real day to
## mate, 2+ lay eggs, 3+ to hatch and 4-7 days to mature".
##
## These are wall-clock durations, not in-game ones, and they are far longer
## than any play session. That is the point: individual, watched reproduction
## is a thing a player can catch a glimpse of, never a thing they can farm.
## The population work happens off screen in the aggregate model.

const LifeCycle = preload("res://src/gameplay/life_cycle.gd")

const DAY := 86400.0


# -- the timescale the design asks for ---------------------------------------

func test_a_newborn_takes_a_week_to_mature():
	assert_almost_eq(LifeCycle.MATURE_SECONDS, 7.0 * DAY, 1.0)


func test_the_stages_arrive_in_the_order_specified():
	assert_lt(LifeCycle.MATE_SECONDS, LifeCycle.EGG_SECONDS)
	assert_lt(LifeCycle.EGG_SECONDS, LifeCycle.HATCH_SECONDS)
	assert_lt(LifeCycle.HATCH_SECONDS, LifeCycle.MATURE_SECONDS)


func test_each_stage_lands_on_the_day_it_was_asked_for():
	assert_almost_eq(LifeCycle.MATE_SECONDS, 1.0 * DAY, 1.0)
	assert_almost_eq(LifeCycle.EGG_SECONDS, 2.0 * DAY, 1.0)
	assert_almost_eq(LifeCycle.HATCH_SECONDS, 3.0 * DAY, 1.0)


# -- what stage a given age is in --------------------------------------------

func test_a_fresh_pairing_is_still_courting():
	assert_eq(LifeCycle.stage_at(0.0), LifeCycle.STAGE_COURTING)
	assert_eq(LifeCycle.stage_at(LifeCycle.MATE_SECONDS - 1.0), LifeCycle.STAGE_COURTING)


func test_a_day_in_the_pair_has_mated():
	assert_eq(LifeCycle.stage_at(LifeCycle.MATE_SECONDS), LifeCycle.STAGE_MATED)


func test_two_days_in_there_are_eggs():
	assert_eq(LifeCycle.stage_at(LifeCycle.EGG_SECONDS), LifeCycle.STAGE_EGG)


func test_three_days_in_the_eggs_have_hatched():
	assert_eq(LifeCycle.stage_at(LifeCycle.HATCH_SECONDS), LifeCycle.STAGE_JUVENILE)


func test_a_week_in_it_is_an_adult():
	assert_eq(LifeCycle.stage_at(LifeCycle.MATURE_SECONDS), LifeCycle.STAGE_ADULT)
	assert_eq(LifeCycle.stage_at(LifeCycle.MATURE_SECONDS * 10.0), LifeCycle.STAGE_ADULT)


## Monotonic: an animal never goes backwards through its own life.
func test_an_animal_never_gets_younger():
	var previous := -1
	for step in 200:
		var stage := LifeCycle.stage_at(float(step) * DAY / 20.0)
		assert_gte(stage, previous, "stages must only ever advance")
		previous = stage


# -- growth ------------------------------------------------------------------

## A juvenile is visibly smaller than an adult, growing into its full size --
## that is what makes "it grew up" something the player can see rather than a
## number.
func test_a_juvenile_is_smaller_than_an_adult():
	assert_lt(LifeCycle.size_scale_at(LifeCycle.HATCH_SECONDS), 1.0)
	assert_almost_eq(LifeCycle.size_scale_at(LifeCycle.MATURE_SECONDS), 1.0, 0.001)


func test_a_juvenile_grows_steadily_rather_than_popping_to_full_size():
	var previous := 0.0
	for step in 50:
		var age := lerpf(LifeCycle.HATCH_SECONDS, LifeCycle.MATURE_SECONDS, float(step) / 49.0)
		var scale := LifeCycle.size_scale_at(age)
		assert_gte(scale, previous, "growth must not go backwards")
		previous = scale


func test_a_hatchling_is_still_big_enough_to_see():
	assert_gt(LifeCycle.size_scale_at(LifeCycle.HATCH_SECONDS), 0.25)


# -- who may breed -----------------------------------------------------------

## The rule that stops the population running away: only adults court.
func test_only_an_adult_can_court():
	assert_false(LifeCycle.can_court_at(LifeCycle.HATCH_SECONDS))
	assert_false(LifeCycle.can_court_at(LifeCycle.MATURE_SECONDS - 1.0))
	assert_true(LifeCycle.can_court_at(LifeCycle.MATURE_SECONDS))
