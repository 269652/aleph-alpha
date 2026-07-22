extends GutTest

const FestivalTrigger = preload("res://src/gameplay/festival_trigger.gd")

var trigger: FestivalTrigger


func before_each():
	trigger = FestivalTrigger.new()


func test_harvest_festival_eligible_true_above_threshold():
	assert_true(trigger.harvest_festival_eligible(150.0, 100.0))


func test_harvest_festival_eligible_true_at_exact_boundary():
	assert_true(trigger.harvest_festival_eligible(100.0, 100.0))


func test_harvest_festival_eligible_false_below_threshold():
	assert_false(trigger.harvest_festival_eligible(50.0, 100.0))


func test_seasonal_festival_for_day_spring_equinox_is_non_empty():
	assert_ne(trigger.seasonal_festival_for_day(80), "")


func test_seasonal_festival_for_day_summer_solstice_is_non_empty():
	assert_ne(trigger.seasonal_festival_for_day(172), "")


func test_seasonal_festival_for_day_autumn_equinox_is_non_empty():
	assert_ne(trigger.seasonal_festival_for_day(266), "")


func test_seasonal_festival_for_day_winter_solstice_is_non_empty():
	assert_ne(trigger.seasonal_festival_for_day(355), "")


func test_seasonal_festival_for_day_ordinary_day_is_empty():
	assert_eq(trigger.seasonal_festival_for_day(100), "")


func test_seasonal_festivals_have_distinct_names():
	var spring: String = trigger.seasonal_festival_for_day(80)
	var summer: String = trigger.seasonal_festival_for_day(172)
	var autumn: String = trigger.seasonal_festival_for_day(266)
	var winter: String = trigger.seasonal_festival_for_day(355)
	assert_ne(spring, summer)
	assert_ne(summer, autumn)
	assert_ne(autumn, winter)
	assert_ne(winter, spring)


func test_days_until_next_seasonal_festival_is_zero_on_festival_day():
	assert_eq(trigger.days_until_next_seasonal_festival(172), 0)


func test_days_until_next_seasonal_festival_counts_down_approaching_festival():
	assert_eq(trigger.days_until_next_seasonal_festival(170), 2)


func test_days_until_next_seasonal_festival_wraps_around_year_end():
	# Day 360 is after winter solstice (355), the year's last festival, so the
	# next festival is spring equinox (day 80) of the following year.
	assert_eq(trigger.days_until_next_seasonal_festival(360), 5 + 80)


func test_days_until_next_seasonal_festival_at_last_day_of_year_wraps_and_is_never_negative():
	var result: int = trigger.days_until_next_seasonal_festival(365)
	assert_gte(result, 0)
	assert_eq(result, 80)
