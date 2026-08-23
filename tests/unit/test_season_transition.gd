extends GutTest

## Seasons arriving GRADUALLY rather than all at once (see
## docs/concept/flora.md#illustrated-trees).
##
## A canopy that swaps frames on a single frame boundary reads as a bug: the
## whole forest changes colour between one step and the next. A wood should
## turn over days, branch by branch, and be fully turned by the time the season
## it is turning into actually starts.

const SeasonTransition = preload("res://src/world/season_transition.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


# -- most of a season is not a transition ------------------------------------

func test_the_middle_of_a_season_is_not_transitioning():
	var state := SeasonTransition.state_at(0.125)  # mid-spring
	assert_eq(state.from, "spring")
	assert_eq(state.to, "spring")
	assert_eq(state.progress, 0.0)


func test_a_settled_season_reports_itself_as_both_ends():
	for year_fraction in [0.05, 0.3, 0.55, 0.8]:
		var state := SeasonTransition.state_at(year_fraction)
		if state.progress == 0.0:
			assert_eq(state.from, state.to, "a settled season is not between two")


# -- the turn ----------------------------------------------------------------

## By the time the new season starts, the change is complete -- "when spring
## happens it is saturated and 100% transitioned".
func test_the_change_is_complete_when_the_new_season_starts():
	var season_span := 1.0 / float(SeasonCycle.SEASONS.size())
	for index in SeasonCycle.SEASONS.size():
		var boundary := float(index) * season_span
		var just_before := SeasonTransition.state_at(boundary - 0.0005)
		assert_almost_eq(
			float(just_before.progress), 1.0, 0.05,
			"the turn should be finished as the season arrives"
		)


func test_the_turn_heads_for_the_season_that_is_coming():
	var season_span := 1.0 / float(SeasonCycle.SEASONS.size())
	# Late spring is turning into summer.
	var state := SeasonTransition.state_at(season_span - 0.005)
	assert_eq(state.from, "spring")
	assert_eq(state.to, "summer")


func test_the_turn_gets_further_along_as_it_goes():
	var season_span := 1.0 / float(SeasonCycle.SEASONS.size())
	var previous := -1.0
	var steps := 40
	for step in steps:
		var at := season_span - SeasonTransition.TURN_FRACTION * season_span \
			+ float(step) / float(steps) * SeasonTransition.TURN_FRACTION * season_span
		var progress: float = SeasonTransition.state_at(at).progress
		assert_gte(progress, previous, "the turn went backwards")
		previous = progress
	assert_gt(previous, 0.5, "the turn barely started")


## Winter turns into spring: the year wraps.
func test_winter_turns_into_spring():
	var state := SeasonTransition.state_at(0.999)
	assert_eq(state.from, "winter")
	assert_eq(state.to, "spring")


# -- it has to be watchable --------------------------------------------------

## Long enough to see. A turn that happens in the last half-percent of a season
## is a swap with extra steps.
func test_the_turn_lasts_long_enough_to_watch():
	assert_gt(SeasonTransition.TURN_FRACTION, 0.1, "a turn nobody can see is a swap")
	assert_lt(SeasonTransition.TURN_FRACTION, 0.6, "a season should have a settled middle")


## Progress is quantised, because every distinct value is a tree picture that
## has to be built (see ProceduralTreeSprite's cache). Enough steps to read as
## gradual, few enough to afford.
func test_progress_comes_in_a_small_number_of_steps():
	var values := {}
	for step in 400:
		values[SeasonTransition.state_at(float(step) / 400.0).progress] = true
	assert_lte(values.size(), SeasonTransition.TURN_STEPS + 1)
	assert_gte(values.size(), 4, "too few steps to read as gradual")
