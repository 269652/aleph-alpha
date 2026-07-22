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
