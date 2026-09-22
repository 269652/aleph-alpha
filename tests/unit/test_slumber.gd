extends GutTest

## docs/concept/sleep.md: putting the night behind you.
##
## survival.md's first paragraph has always said a character must "eat,
## drink, and sleep". Eating and drinking are real; sleep has never existed
## -- `SurvivalMeters.rest(amount)` is an arithmetic helper that adds to the
## stamina bar, with no resting state, nothing that can interrupt one, and
## no way to put a night behind you. That gap is what blocks the Alp
## (monsters.md entry 3), whose whole behaviour is "approaches only while
## you rest".

const Slumber = preload("res://src/gameplay/slumber.gd")
const DawnClause = preload("res://src/gameplay/dawn_clause.gd")
const Answerback = preload("res://src/gameplay/answerback.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


# -- the rate is derived, not picked -------------------------------------

## The worst night any rest can face is half a clock face, and the HUD's own
## MAX_CARD_SECONDS is its statement of the longest thing it will ask a
## player to sit through. The rate is one divided by the other.
func test_the_rate_is_the_worst_night_over_the_longest_watchable_span():
	assert_almost_eq(
		Slumber.HOURS_PER_REAL_SECOND,
		DawnClause.MAX_OFFSET_HOURS / Answerback.MAX_CARD_SECONDS,
		0.0001
	)


## The property that makes it honest: skipping a night must not itself cost
## a night.
func test_the_longest_possible_night_passes_inside_the_longest_card():
	var real_seconds := DawnClause.MAX_OFFSET_HOURS / Slumber.HOURS_PER_REAL_SECOND
	assert_lte(
		real_seconds, Answerback.MAX_CARD_SECONDS,
		"a rest that takes longer than reading a card is not skipping anything"
	)


## And not so fast that the night is a cut rather than a passage.
func test_a_rest_is_a_passage_rather_than_a_cut():
	assert_gt(
		DawnClause.MAX_OFFSET_HOURS / Slumber.HOURS_PER_REAL_SECOND, 2.0,
		"the sky has to be seen to move"
	)


## The world age it advances is the world's own clock, not a second one.
func test_the_world_age_advance_is_the_seasons_own_clock():
	var one_second: float = Slumber.world_age_seconds_for(1.0)
	var one_in_game_hour: float = SeasonCycle.SECONDS_PER_DAY / 24.0
	assert_almost_eq(
		one_second, one_in_game_hour * Slumber.HOURS_PER_REAL_SECOND, 0.001
	)


func test_a_zero_or_negative_frame_advances_nothing():
	assert_eq(Slumber.world_age_seconds_for(0.0), 0.0)
	assert_eq(Slumber.world_age_seconds_for(-1.0), 0.0)


func test_the_advance_scales_with_the_frame():
	assert_almost_eq(
		Slumber.world_age_seconds_for(2.0), Slumber.world_age_seconds_for(1.0) * 2.0, 0.001
	)


# -- a rest runs to first light ------------------------------------------

## The hour a character wakes and the hour a new character opens their eyes
## are one fact (docs/concept/arrival.md), stated once.
func test_a_rest_ends_at_the_dawn_clauses_own_first_light():
	assert_almost_eq(
		Slumber.hours_until_first_light(DawnClause.FIRST_LIGHT_HOUR), 0.0, 0.0001
	)


func test_resting_at_midnight_runs_until_dawn():
	assert_almost_eq(
		Slumber.hours_until_first_light(0.0), DawnClause.FIRST_LIGHT_HOUR, 0.0001
	)


## The clock face wraps: an evening rest crosses midnight.
func test_an_evening_rest_crosses_midnight():
	var hours := Slumber.hours_until_first_light(22.0)
	assert_almost_eq(hours, 24.0 - 22.0 + DawnClause.FIRST_LIGHT_HOUR, 0.0001)
	assert_gt(hours, 0.0, "a rest always has somewhere to run to")


## A nap in daylight is allowed -- the world does not forbid one, it simply
## runs nearly a whole day.
func test_a_daylight_nap_is_allowed_and_runs_nearly_a_day():
	var hours := Slumber.hours_until_first_light(6.0)
	assert_gt(hours, 20.0)
	assert_lt(hours, 24.0)


func test_the_wait_is_always_a_real_clock_face():
	for hour_index in 240:
		var hour := float(hour_index) / 10.0
		var hours := Slumber.hours_until_first_light(hour)
		assert_true(hours >= 0.0 and hours < 24.0, "%f is not a wait" % hours)


# -- completion ----------------------------------------------------------

func test_a_rest_is_complete_when_first_light_arrives():
	assert_true(Slumber.is_complete(0.0))
	assert_true(Slumber.is_complete(-0.1), "overshooting a frame still counts")
	assert_false(Slumber.is_complete(0.5))


# -- refusals are sentences ----------------------------------------------

func test_an_ordinary_night_refuses_nothing():
	assert_eq(Slumber.refusal_for({}), "")


## Pillar 5 says no refusal keeps a player SAFE while asleep. This one is
## not about safety after the fact -- you cannot lie down while something is
## already coming for you.
func test_you_cannot_lie_down_while_something_is_hunting_you():
	var refusal := Slumber.refusal_for({"hunted": true})
	assert_ne(refusal, "")
	assert_true(refusal.to_lower().contains("hunt"), "and it says why: %s" % refusal)


func test_you_cannot_sleep_in_the_water():
	assert_ne(Slumber.refusal_for({"in_water": true}), "")


func test_you_cannot_begin_a_rest_you_are_already_having():
	assert_ne(Slumber.refusal_for({"already_resting": true}), "")


func test_every_refusal_is_a_sentence():
	for facts in [{"hunted": true}, {"in_water": true}, {"already_resting": true}]:
		var refusal := Slumber.refusal_for(facts)
		assert_true(refusal.ends_with("."), "%s is not a sentence" % refusal)
		assert_false(refusal.contains("_"), "%s reached a player as an id" % refusal)


# -- and what you are told on waking -------------------------------------

func test_a_completed_rest_says_so():
	var line := Slumber.wake_report(7.5, true)
	assert_true(line.to_lower().contains("first light"))


## The cost of waking early is the rest you lose, so the line has to name
## what you actually got.
func test_an_interrupted_rest_names_the_hours_that_really_passed():
	var line := Slumber.wake_report(2.0, false)
	assert_false(line.to_lower().contains("first light"), "you did not get there")
	assert_true(line.contains("2"), "it names what really passed: %s" % line)


func test_a_rest_that_barely_began_still_reads_as_a_sentence():
	var line := Slumber.wake_report(0.0, false)
	assert_false(line.is_empty())
	assert_true(line.ends_with("."))
