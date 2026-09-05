extends GutTest

const SeasonCycle = preload("res://src/world/season_cycle.gd")

var seasons := SeasonCycle.new()


func test_cycles_through_all_four_seasons_over_a_year():
	var seen := {}
	var year := SeasonCycle.SECONDS_PER_YEAR
	for i in 8:
		seen[seasons.season_at(year * i / 8.0)] = true
	for name in ["spring", "summer", "autumn", "winter"]:
		assert_true(seen.has(name), "expected to pass through %s over a year" % name)


func test_season_is_periodic_across_years():
	var year := SeasonCycle.SECONDS_PER_YEAR
	assert_eq(seasons.season_at(123.0), seasons.season_at(123.0 + year))


func test_first_season_of_the_year_is_spring():
	assert_eq(seasons.season_at(0.0), "spring")


func test_warmth_modifier_stays_in_range():
	var year := SeasonCycle.SECONDS_PER_YEAR
	for i in 20:
		var w := seasons.warmth_modifier(year * i / 20.0)
		assert_between(w, 0.0, 1.0)


func test_summer_is_warmer_than_winter():
	# Summer sits around 3/8 of the year (after spring), winter around 7/8.
	var year := SeasonCycle.SECONDS_PER_YEAR
	var summer := seasons.warmth_modifier(year * 0.375)
	var winter := seasons.warmth_modifier(year * 0.875)
	assert_gt(summer, winter, "mid-summer should be warmer than mid-winter")


func test_growth_modifier_stays_in_range_and_peaks_warm():
	var year := SeasonCycle.SECONDS_PER_YEAR
	for i in 20:
		assert_between(seasons.growth_modifier(year * i / 20.0), 0.0, 1.0)
	var spring_summer := seasons.growth_modifier(year * 0.3)
	var winter := seasons.growth_modifier(year * 0.875)
	assert_gt(spring_summer, winter, "plants grow more in the warm half of the year")


func test_is_deterministic():
	assert_eq(seasons.warmth_modifier(4242.0), seasons.warmth_modifier(4242.0))


# -- jumping to a season (/season) -------------------------------------------

## `/season <name>` skips the world forward to the start of that season.
##
## FORWARD only, and that is the whole design. Season is a pure function of
## elapsed world time, so the obvious implementation is to set the clock to the
## season you want -- but every other system measures itself against that same
## clock. A tree records `planted_at`; fruiting records `_last_fruiting_time`.
## Winding the clock BACK gives a tree a negative age and hands `fallen_between`
## a span that runs backwards. Skipping forward is the only move that leaves
## every other clock consistent.
func test_jumping_to_a_season_lands_at_the_start_of_it():
	for name in SeasonCycle.SEASONS:
		var now := SeasonCycle.SECONDS_PER_YEAR * 0.1
		var skip: float = seasons.seconds_until_season(now, name)
		assert_eq(seasons.season_at(now + skip), name, "should land in %s" % name)


## Never backwards, from anywhere in the year.
func test_a_jump_is_always_forward():
	for step in 12:
		var now := SeasonCycle.SECONDS_PER_YEAR * float(step) / 12.0
		for name in SeasonCycle.SEASONS:
			assert_gte(
				seasons.seconds_until_season(now, name), 0.0,
				"jumping to %s from %.2f went backwards" % [name, now]
			)


## And it lands at the START of the season, not somewhere inside it -- so
## `/season winter` gives you the whole of winter to look at rather than
## dropping you into the last minute of it.
func test_a_jump_lands_at_the_beginning_not_the_middle():
	var now := SeasonCycle.SECONDS_PER_YEAR * 0.1
	var landed: float = now + seasons.seconds_until_season(now, "autumn")
	# Autumn is the third quarter, so the year fraction on arrival is 0.5.
	assert_almost_eq(seasons.year_fraction(landed), 0.5, 0.0001)


## Asking for the season you are already in gives you the NEXT one a year out,
## not a no-op -- you asked to see it start.
func test_asking_for_the_current_season_waits_for_it_to_come_round():
	var now := SeasonCycle.SECONDS_PER_YEAR * 0.1  # spring
	assert_eq(seasons.season_at(now), "spring", "precondition")
	var skip: float = seasons.seconds_until_season(now, "spring")
	assert_gt(skip, 0.0)
	assert_eq(seasons.season_at(now + skip), "spring")


## A season never costs more than a year to reach.
func test_no_jump_is_longer_than_a_year():
	for step in 12:
		var now := SeasonCycle.SECONDS_PER_YEAR * float(step) / 12.0
		for name in SeasonCycle.SEASONS:
			assert_lte(
				seasons.seconds_until_season(now, name),
				SeasonCycle.SECONDS_PER_YEAR + 0.001
			)


func test_an_unknown_season_moves_nothing():
	assert_eq(seasons.seconds_until_season(1234.0, "harvest"), 0.0)


# -- landing partway into a season (/season name progress) -------------------
# Reported: "make /season command so it accepts a float between 0 and 1 for
# how far it has progressed into the season" -- 0.0 keeps today's exact
# "lands at the start" behavior (the default), 1.0 lands exactly at the next
# season's own start (the two boundaries share a point by construction).

func test_omitting_progress_matches_landing_at_the_very_start():
	var now := SeasonCycle.SECONDS_PER_YEAR * 0.1
	for name in SeasonCycle.SEASONS:
		assert_eq(
			seasons.seconds_until_season(now, name),
			seasons.seconds_until_season(now, name, 0.0),
			"omitting progress should be identical to progress 0.0 for %s" % name
		)


func test_progress_lands_partway_through_the_named_season():
	var now := SeasonCycle.SECONDS_PER_YEAR * 0.1  # spring
	var skip: float = seasons.seconds_until_season(now, "autumn", 0.5)
	# Autumn is the third quarter (year_fraction 0.5-0.75); its own midpoint
	# is 0.625.
	assert_almost_eq(seasons.year_fraction(now + skip), 0.625, 0.0001)


func test_progress_one_lands_at_the_next_seasons_own_start():
	var now := SeasonCycle.SECONDS_PER_YEAR * 0.1
	var full_spring: float = seasons.seconds_until_season(now, "spring", 1.0)
	var start_of_summer: float = seasons.seconds_until_season(now, "summer", 0.0)
	assert_almost_eq(full_spring, start_of_summer, 0.0001)


func test_a_jump_with_progress_is_still_always_forward():
	for step in 12:
		var now := SeasonCycle.SECONDS_PER_YEAR * float(step) / 12.0
		for name in SeasonCycle.SEASONS:
			assert_gte(
				seasons.seconds_until_season(now, name, 0.5), 0.0,
				"jumping to %s at 50%% from %.2f went backwards" % [name, now]
			)


func test_out_of_range_progress_is_clamped_into_the_season_itself():
	var now := 0.0
	var over: float = seasons.seconds_until_season(now, "spring", 1.5)
	var one: float = seasons.seconds_until_season(now, "spring", 1.0)
	assert_almost_eq(over, one, 0.0001, "progress above 1 should clamp to 1")

	var under: float = seasons.seconds_until_season(now, "spring", -0.5)
	var zero: float = seasons.seconds_until_season(now, "spring", 0.0)
	assert_almost_eq(under, zero, 0.0001, "progress below 0 should clamp to 0")


# -- progress_through_season: a raw, unquantised 0..1 signal ------------------
#
# Reported directly: leaf litter should be "constant and continuous and
# increasing in autumn" -- TreePhenology/SeasonTransition's own "turn
# progress" reads exactly 0.0 for a season's whole settled span (see
# TreePhenology.canopy_state_at, TURN_FRACTION) and only ramps in its final
# 34%, which cannot drive a signal that rises across the WHOLE season. This
# exposes the raw fraction `season_at` itself already resolves an index
# from, directly, so a caller can rise smoothly from a season's first
# instant instead of waiting for its turn to begin.

func test_progress_through_season_starts_at_zero_at_the_seasons_own_start():
	assert_almost_eq(seasons.progress_through_season(0.0), 0.0, 0.0001)


func test_progress_through_season_approaches_one_near_the_seasons_own_end():
	var quarter := SeasonCycle.SECONDS_PER_YEAR / 4.0
	assert_almost_eq(seasons.progress_through_season(quarter - 1.0), 1.0, 0.001)


func test_progress_through_season_resets_at_a_season_boundary():
	var quarter := SeasonCycle.SECONDS_PER_YEAR / 4.0
	assert_almost_eq(seasons.progress_through_season(quarter), 0.0, 0.0001)


func test_progress_through_season_increases_monotonically_within_a_season():
	var quarter := SeasonCycle.SECONDS_PER_YEAR / 4.0
	var previous := -1.0
	for i in 10:
		var current: float = seasons.progress_through_season(quarter * 2.0 + quarter * i / 10.0)
		assert_gt(current, previous, "progress must rise monotonically across the season")
		previous = current


func test_progress_through_season_is_periodic_across_years():
	var year := SeasonCycle.SECONDS_PER_YEAR
	assert_almost_eq(
		seasons.progress_through_season(456.0),
		seasons.progress_through_season(456.0 + year),
		0.0001
	)
