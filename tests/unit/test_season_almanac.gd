extends GutTest

## SeasonAlmanac: reads season_cycle.gd's real day/season clock forward (see
## docs/concept/wayfinding.md's Star chart / seasonal almanac section) --
## next_season is a pure lookup in SeasonCycle.SEASONS, and
## days_until_next_season is SeasonCycle's own real
## seconds_until_season/SECONDS_PER_DAY, no invented constant.

const SeasonAlmanac = preload("res://src/world/season_almanac.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


# -- next_season: the season after current_season in SEASONS, wrapping -----

func test_next_season_after_spring_is_summer():
	assert_eq(SeasonAlmanac.next_season("spring"), "summer")


func test_next_season_after_summer_is_autumn():
	assert_eq(SeasonAlmanac.next_season("summer"), "autumn")


func test_next_season_after_autumn_is_winter():
	assert_eq(SeasonAlmanac.next_season("autumn"), "winter")


func test_next_season_after_winter_wraps_to_spring():
	assert_eq(SeasonAlmanac.next_season("winter"), "spring")


# -- days_until_next_season: real SeasonCycle math, hand-computed here -----
#
# SeasonCycle.SECONDS_PER_DAY = 14400.0, SECONDS_PER_YEAR = 691200.0, and the
# year is 4 equal quarters -- so each season is exactly
# 691200.0 / 4 / 14400.0 = 12.0 real days long. Confirmed against a real
# SeasonCycle instance before writing these assertions.

func test_days_until_next_season_at_the_very_start_of_a_season():
	var cycle := SeasonCycle.new()
	# elapsed_seconds=0.0 is the exact start of spring -- a full season
	# (12.0 days) remains until summer.
	assert_eq(cycle.season_at(0.0), "spring")
	assert_almost_eq(SeasonAlmanac.days_until_next_season(0.0), 12.0, 0.001)


func test_days_until_next_season_at_the_start_of_summer():
	var cycle := SeasonCycle.new()
	var elapsed := SeasonCycle.SECONDS_PER_YEAR / 4.0  # 172800.0
	assert_eq(cycle.season_at(elapsed), "summer")
	assert_almost_eq(SeasonAlmanac.days_until_next_season(elapsed), 12.0, 0.001)


func test_days_until_next_season_partway_through_winter():
	var cycle := SeasonCycle.new()
	# 604800.0 seconds = 42.0 days into the year: winter is the last
	# quarter (days 36-48), so this is 6.0 days into winter, leaving
	# 12.0 - 6.0 = 6.0 days until spring.
	var elapsed := 604800.0
	assert_eq(elapsed / SeasonCycle.SECONDS_PER_DAY, 42.0)
	assert_eq(cycle.season_at(elapsed), "winter")
	assert_almost_eq(SeasonAlmanac.days_until_next_season(elapsed), 6.0, 0.001)
