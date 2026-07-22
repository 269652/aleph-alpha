extends GutTest

const WorldClock = preload("res://src/world/world_clock.gd")

var clock: WorldClock


func before_each():
	clock = WorldClock.new()


func test_starts_at_midnight_on_day_zero():
	assert_eq(clock.time_of_day, 0.0)
	assert_eq(clock.day, 0)


func test_advance_moves_time_of_day_forward_within_the_same_day():
	clock.advance(clock.DAY_LENGTH_SECONDS * 0.25)
	assert_almost_eq(clock.time_of_day, 0.25, 0.001)
	assert_eq(clock.day, 0)


func test_advance_past_a_full_day_wraps_time_of_day_and_increments_day():
	clock.advance(clock.DAY_LENGTH_SECONDS * 1.5)
	assert_almost_eq(clock.time_of_day, 0.5, 0.001)
	assert_eq(clock.day, 1)


func test_repeated_advances_accumulate_across_multiple_day_boundaries():
	clock.advance(clock.DAY_LENGTH_SECONDS * 0.7)
	clock.advance(clock.DAY_LENGTH_SECONDS * 0.7)
	assert_almost_eq(clock.time_of_day, 0.4, 0.001)
	assert_eq(clock.day, 1)
