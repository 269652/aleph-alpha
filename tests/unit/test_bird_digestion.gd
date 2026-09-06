extends GutTest

## A bird's gut: why it eats, and what comes out (see
## docs/concept/seed_dispersal.md).
##
## Birds already carried a swallowed seed and planted it further on. What they
## did not have was a REASON to eat -- they foraged constantly whether or not
## they needed to -- or anything to show for the other end of it. A dropping is
## the visible half of dispersal: the player sees where a seed came from.

const BirdDigestion = preload("res://src/gameplay/bird_digestion.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


# -- a reason to eat ---------------------------------------------------------

func test_a_bird_starts_out_hungry():
	assert_true(BirdDigestion.is_hungry(BirdDigestion.STARTING_FULLNESS))


func test_eating_fills_it_up():
	var full := BirdDigestion.fullness_after_meal(0.0)
	assert_gt(full, 0.0)
	assert_false(BirdDigestion.is_hungry(full), "a bird that just ate is not hungry")


func test_hunger_returns_on_its_own():
	var full := BirdDigestion.fullness_after_meal(0.0)
	var later := BirdDigestion.fullness_after(full, BirdDigestion.DIGEST_SECONDS * 2.0)
	assert_true(BirdDigestion.is_hungry(later))


func test_a_full_bird_does_not_keep_eating():
	assert_false(BirdDigestion.is_hungry(1.0))


func test_fullness_never_runs_past_its_ends():
	assert_lte(BirdDigestion.fullness_after_meal(1.0), 1.0)
	assert_gte(BirdDigestion.fullness_after(0.0, 100000.0), 0.0)


## A bird eats a few times a day, not constantly and not once a week.
##
## Upper bound raised 40 -> 60 (2026-09-06): reported live, twice now (see
## docs/progress.md), that a robin standing right next to visible worms
## reads as "not eating" -- confirmed working (a real strike takes a
## hungry bird, a bird is hungry roughly every ~18 real minutes at the
## previous DIGEST_SECONDS) but genuinely too rare to actually catch.
## Asked directly whether to speed it up: yes. 60 gives the same real
## bracketing intent ("through the day, not constant") at the new,
## faster cadence -- see test_a_bird_forages_four_times_as_often below for
## the tuned ratio itself.
func test_a_bird_eats_several_times_a_day():
	var meals := 0
	var fullness: float = BirdDigestion.STARTING_FULLNESS
	var step := 30.0
	var elapsed := 0.0
	while elapsed < SeasonCycle.SECONDS_PER_DAY:
		fullness = BirdDigestion.fullness_after(fullness, step)
		elapsed += step
		if BirdDigestion.is_hungry(fullness):
			fullness = BirdDigestion.fullness_after_meal(fullness)
			meals += 1
	assert_between(meals, 3, 60, "a songbird should feed through the day, not once")


## Same reasoning as this session's other tuning ratio tests (Snowfall's
## covering speed, the camera zoom): pin the RATIO against the previous
## tuning, not just the new literal, so "meaningfully faster" survives
## independently of the exact numbers on either side.
func test_a_bird_forages_four_times_as_often():
	var previous_digest_seconds := SeasonCycle.SECONDS_PER_DAY / 8.0
	assert_almost_eq(
		previous_digest_seconds / BirdDigestion.DIGEST_SECONDS, 4.0, 0.0001,
		"a bird should get hungry (and so forage) 4x as often as before"
	)


# -- one clock, not two ------------------------------------------------------

## There is deliberately NO passage timer here.
##
## SeedEndozoochory already models passage as a DISTANCE the bird carries the
## seed, which is better than a time: a faster bird carries it proportionally
## further. Adding a passage timer on top gave two clocks for one thing at
## wildly different scales -- the carry is seconds of game time and a real gut
## passage is minutes -- so the timer never elapsed and dispersal stopped
## happening at all. Every seed a bird swallowed simply stayed in it.
##
## Caught by the flyer's own tests, which asserted that a swallowed seed
## eventually gets planted. This pins the lesson so it does not come back.
func test_digestion_does_not_own_a_second_passage_clock():
	for name in ["PASS_SECONDS", "plants_on_drop", "has_passed", "grows_from"]:
		assert_false(
			name in BirdDigestion,
			"%s is a second clock for something SeedEndozoochory already owns" % name
		)


# -- one drive vector underneath (docs/concept/ethogram.md §5, slice 3) --------

const Ethogram = preload("res://src/gameplay/ethogram.gd")


## Fullness is one minus the bird body plan's hunger drive; the numbers are
## the ethogram record.
func test_the_numbers_are_the_ethograms_bird_profile():
	var profile := Ethogram.drive_profile("", "bird")
	assert_almost_eq(BirdDigestion.DIGEST_SECONDS, profile["hunger"]["rise_seconds"], 0.0001)
	assert_almost_eq(BirdDigestion.HUNGRY_BELOW, 1.0 - profile["hunger"]["threshold"], 0.0001)
	assert_almost_eq(BirdDigestion.MEAL_FULLNESS, profile["hunger"]["meal"], 0.0001)
	assert_almost_eq(BirdDigestion.STARTING_FULLNESS, 1.0 - profile["hunger"]["start"], 0.0001)
